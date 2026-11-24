//
//  TUCNativeGesture.m
//  Touch Up Core
//
//  Ported from T650Native (SwipeTranslator.cs, DockSwipeBlock.cs, ExclusiveMode.cs). Pure logic: no OS calls.
//

#import "TUCNativeGesture.h"

static NSValue *TUCWrapSwipe(TUCNativeSwipeEvent e) {
    return [NSValue valueWithBytes:&e objCType:@encode(TUCNativeSwipeEvent)];
}

static TUCNativeSwipeEvent TUCMakeSwipe(uint32_t cgType, int64_t subtype, int64_t kind, int64_t phase, double progress) {
    TUCNativeSwipeEvent e = {0};
    e.cgType = cgType;
    e.subtype = subtype;
    e.kind = kind;
    e.phase = phase;
    e.progress = progress;
    return e;
}


#pragma mark - Swipe translator

@interface TUCSwipeTranslator ()
@property (strong) NSMutableArray<NSArray<NSNumber *> *> *samples;  // [t, progress]
@property BOOL flavorSent;
@property BOOL beganPending;
@property BOOL suppressed;
@property uint32_t routeType;
@property int64_t routeSubtype;
@property BOOL inFlight;
@property int64_t inFlightKind;
@property double inFlightProgress;
@end

@implementation TUCSwipeTranslator {
    // Tuned against the Casa Touch recording (see T650Native SwipeTranslator.cs).
    double _progressClamp;
    double _beginProgress;
    double _sampleKeepSeconds;
    double _velocityWindowSeconds;
    double _velocityMinSpanSeconds;
    double _commitFarProgress;
    double _commitFlickBackSpeed;
    double _commitNearProgress;
    double _commitFlickOnSpeed;
}

- (instancetype)init {
    if (self = [super init]) {
        // T650 device units (~22 per mm) converted to millimetres: 1500, 1100 and 600 units.
        _horizontalFull = 68;
        _verticalFull = 50;
        _pinchFull = 27;
        _settings = [TUCGestureSettings defaultSettings];
        _samples = [NSMutableArray new];

        _progressClamp = 1.5;
        _beginProgress = 0.02;
        _sampleKeepSeconds = 0.3;
        _velocityWindowSeconds = 0.15;
        _velocityMinSpanSeconds = 0.02;
        _commitFarProgress = 0.33;
        _commitFlickBackSpeed = 0.5;
        _commitNearProgress = 0.12;
        _commitFlickOnSpeed = 1.5;
    }
    return self;
}

- (NSArray<NSValue *> *)translatePhase:(TUCGesturePhase)phase
                               fingers:(NSInteger)fingers
                                  axis:(TUCSwipeAxis)axis
                                travel:(double)travel
                                   now:(double)now {
    NSMutableArray<NSValue *> *result = [NSMutableArray new];

    int64_t kind;
    double full, sign;
    switch (axis) {
        case TUCSwipeAxisHorizontal: kind = TUCSwipeKindHorizontal; full = self.horizontalFull; sign = -1; break; // right = negative
        case TUCSwipeAxisVertical:   kind = TUCSwipeKindVertical;   full = self.verticalFull;   sign = 1;  break; // down = positive
        default:                     kind = TUCSwipeKindPinch;      full = self.pinchFull;      sign = -1; break; // spread out = negative
    }

    double progress = fmax(-_progressClamp, fmin(_progressClamp, sign * travel / full));

    switch (phase) {
        case TUCGesturePhaseBegan:
            // Not posted yet: the begin event must already carry the direction (see Changed).
            [self.samples removeAllObjects];
            [self.samples addObject:@[@(now), @0]];
            self.flavorSent = NO;
            self.beganPending = YES;
            self.suppressed = NO;
            break;

        case TUCGesturePhaseChanged: {
            if (self.beganPending) {
                // The direction is known now: is this a swipe the user has switched on?
                if (![self chooseRouteForFingers:fingers axis:axis progress:progress]) {
                    self.beganPending = NO;
                    self.suppressed = YES;
                }
            }

            if (self.suppressed) {
                break;
            }

            if (self.beganPending) {
                // The begin event's progress carries the sign of the whole gesture. A begin of 0 reads as the negative
                // direction, which is why a pinch-in never triggered Launchpad.
                self.beganPending = NO;
                [result addObject:TUCWrapSwipe(TUCMakeSwipe(self.routeType, self.routeSubtype, kind, TUCPhaseBegan,
                                                            progress >= 0 ? _beginProgress : -_beginProgress))];
            }

            [self.samples addObject:@[@(now), @(progress)]];
            NSIndexSet *old = [self.samples indexesOfObjectsPassingTest:^BOOL(NSArray<NSNumber *> *s, NSUInteger i, BOOL *stop) {
                return now - s[0].doubleValue > self->_sampleKeepSeconds;
            }];
            [self.samples removeObjectsAtIndexes:old];

            TUCNativeSwipeEvent e = TUCMakeSwipe(self.routeType, self.routeSubtype, kind, TUCPhaseChanged, progress);
            if (!self.flavorSent) {
                self.flavorSent = YES;
                e.hasFlavor = YES;
                switch (axis) {
                    case TUCSwipeAxisHorizontal: e.flavor = progress > 0 ? TUCFlavorLeft : TUCFlavorRight; break;
                    case TUCSwipeAxisVertical:   e.flavor = progress > 0 ? TUCFlavorDown : TUCFlavorUp; break;
                    default:                     e.flavor = progress > 0 ? TUCFlavorPinchIn : TUCFlavorPinchOut; break;
                }
            }

            self.inFlight = YES;
            self.inFlightKind = kind;
            self.inFlightProgress = progress;
            [result addObject:TUCWrapSwipe(e)];
            break;
        }

        default: { // Ended
            if (self.beganPending || self.suppressed) {
                self.beganPending = NO;   // never moved, or switched off: nothing was posted
                self.suppressed = NO;
                break;
            }

            // Cancelled swipes end with phase 8 and no velocity, committed ones with phase 4 and a velocity
            // (progress per second over the last ~150 ms before release).
            NSMutableArray<NSArray<NSNumber *> *> *recent = [NSMutableArray new];
            for (NSArray<NSNumber *> *s in self.samples) {
                if (now - s[0].doubleValue <= _velocityWindowSeconds) [recent addObject:s];
            }

            double v = 0;
            if (recent.count > 1 && recent.lastObject[0].doubleValue - recent.firstObject[0].doubleValue > _velocityMinSpanSeconds) {
                v = (recent.lastObject[1].doubleValue - recent.firstObject[1].doubleValue)
                  / (recent.lastObject[0].doubleValue - recent.firstObject[0].doubleValue);
            } else if (self.samples.count > 0 && now - self.samples.firstObject[0].doubleValue > _velocityMinSpanSeconds) {
                // A flick so quick it has no two samples apart: its average speed since it began is the speed.
                v = self.samples.lastObject[1].doubleValue / (now - self.samples.firstObject[0].doubleValue);
            }

            double p = self.samples.count > 0 ? self.samples.lastObject[1].doubleValue : progress;
            BOOL commit;
            if (fabs(p) >= _commitFarProgress) {
                commit = !(v * p < 0 && fabs(v) >= _commitFlickBackSpeed);  // far enough, unless flicked back
            } else if (fabs(p) >= _commitNearProgress) {
                commit = v * p > 0 && fabs(v) >= _commitFlickOnSpeed;       // short, but flicked onward
            } else {
                commit = NO;                                                // back near the start: cancel
            }

            TUCNativeSwipeEvent e = TUCMakeSwipe(self.routeType, self.routeSubtype, kind,
                                                 commit ? TUCPhaseEnded : TUCPhaseCancelled, p);
            if (commit) {
                e.hasVelocity = YES;
                e.velocity = v;
            }
            [result addObject:TUCWrapSwipe(e)];
            [self.samples removeAllObjects];
            self.inFlight = NO;
            break;
        }
    }

    return result;
}

- (NSArray<NSValue *> *)cancel {
    NSMutableArray<NSValue *> *result = [NSMutableArray new];
    if (self.inFlight) {
        [result addObject:TUCWrapSwipe(TUCMakeSwipe(self.routeType, self.routeSubtype, self.inFlightKind,
                                                    TUCPhaseCancelled, self.inFlightProgress))];
    }
    self.inFlight = NO;
    self.beganPending = NO;
    self.suppressed = NO;
    [self.samples removeAllObjects];
    return result;
}

/// Which native swipe this gesture becomes; NO if the user has it switched off. `progress` carries the direction:
/// horizontal + left, vertical + down (App Exposé) / - up (Mission Control), pinch + in (Launchpad) / - out (Show Desktop).
- (BOOL)chooseRouteForFingers:(NSInteger)fingers axis:(TUCSwipeAxis)axis progress:(double)progress {
    TUCGestureSettings *s = self.settings;
    switch (axis) {
        case TUCSwipeAxisHorizontal: {
            if (s.swipeBetweenFullScreenApps && fingers == s.fullScreenAppsFingers) {
                self.routeType = TUCEventTypeDockSwipe;
                self.routeSubtype = TUCSubtypeDockSwipe;
                return YES;
            }
            if ([s swipesBetweenPagesWithFingers:fingers]) {
                self.routeType = TUCEventTypeGesture;
                self.routeSubtype = TUCSubtypeNavigationSwipe;
                return YES;
            }
            return NO;
        }

        case TUCSwipeAxisVertical: {
            BOOL enabled = progress > 0 ? s.appExpose : s.missionControl;
            if (enabled && fingers == s.missionControlFingers) {
                self.routeType = TUCEventTypeDockSwipe;
                self.routeSubtype = TUCSubtypeDockSwipe;
                return YES;
            }
            return NO;
        }

        default: // Pinch: four fingers only
            if (fingers == 4 && (progress > 0 ? s.launchpad : s.showDesktop)) {
                self.routeType = TUCEventTypeDockSwipe;
                self.routeSubtype = TUCSubtypeDockSwipe;
                return YES;
            }
            return NO;
    }
}

@end


#pragma mark - Dock swipe HID block

// The block (little-endian 32-bit words): 0-1 timestamp; 6 how many events it holds (1, or 2 on the end, which adds a
// velocity child); 7 size 40; 8 type 23 (DockSwipe); byte 39 the phase; 11 and 12 the finger movement since the last
// event, x and y; byte 60 the axis, byte 62 always 3; 16 the progress, negated, fixed 16.16. The end's child: size 28,
// type 9 (velocity), word 3 = 1, then the velocity negated twice, fixed 16.16.

static const uint16_t TUCDockBlockTag = 0x106D;          // data entry (0x1000) for field 109 (0x6D)
static const uint16_t TUCDockBlockInsertBefore = 0x406E; // the Casa's events have the block right before field 110
static const double TUCMovementPerProgress = 30000;

static int32_t TUCClampInt32(double v) {
    double r = round(v);
    if (r > INT32_MAX) return INT32_MAX;
    if (r < INT32_MIN) return INT32_MIN;
    return (int32_t)r;
}

static void TUCWriteLE32(uint8_t *b, size_t at, int32_t v) {
    uint32_t u = (uint32_t)v;
    b[at] = u & 0xFF; b[at + 1] = (u >> 8) & 0xFF; b[at + 2] = (u >> 16) & 0xFF; b[at + 3] = (u >> 24) & 0xFF;
}

@implementation TUCDockSwipeBlock

+ (NSData *)buildWithTimestamp:(uint64_t)timestamp
                          kind:(int64_t)kind
                         phase:(int64_t)phase
                      progress:(double)progress
                 progressDelta:(double)progressDelta
                   hasVelocity:(BOOL)hasVelocity
                      velocity:(double)velocity {
    BOOL withVelocity = phase == TUCPhaseEnded;
    size_t size = withVelocity ? 96 : 68;
    uint8_t b[96] = {0};

    for (int i = 0; i < 8; i++) b[i] = (timestamp >> (8 * i)) & 0xFF;
    TUCWriteLE32(b, 24, withVelocity ? 2 : 1);
    TUCWriteLE32(b, 28, 40);
    TUCWriteLE32(b, 32, (int32_t)TUCSubtypeDockSwipe);
    b[39] = (uint8_t)phase;

    int32_t movement = TUCClampInt32(-progressDelta * TUCMovementPerProgress);
    if (kind == TUCSwipeKindHorizontal) {
        TUCWriteLE32(b, 44, movement);
    } else if (kind == TUCSwipeKindVertical) {
        TUCWriteLE32(b, 48, movement);
    }

    b[60] = (uint8_t)kind;
    b[62] = 3;
    TUCWriteLE32(b, 64, TUCClampInt32(-progress * 65536));

    if (withVelocity) {
        TUCWriteLE32(b, 68, 28);
        TUCWriteLE32(b, 72, 9);
        TUCWriteLE32(b, 80, 1);
        int32_t v = TUCClampInt32(-(hasVelocity ? velocity : 0) * 65536);
        TUCWriteLE32(b, 84, v);
        TUCWriteLE32(b, 88, v);
    }

    return [NSData dataWithBytes:b length:size];
}

// CGEventCreateData's format: a 4-byte header, then entries of a big-endian 16-bit count, a 16-bit tag and the
// payload; the tag's top bits say the payload's unit.
+ (NSData *)insertBlock:(NSData *)block intoSerializedEvent:(NSData *)serialized {
    const uint8_t *s = serialized.bytes;
    NSUInteger length = serialized.length;
    if (length < 4) return nil;

    NSMutableData *output = [NSMutableData dataWithCapacity:length + block.length + 4];
    [output appendBytes:s length:4];

    void (^addBlock)(void) = ^{
        uint8_t header[4] = { (uint8_t)(block.length >> 8), (uint8_t)block.length, TUCDockBlockTag >> 8, TUCDockBlockTag & 0xFF };
        [output appendBytes:header length:4];
        [output appendData:block];
    };

    // First pass: validate the whole event, so garbage gives nil rather than a half-built copy.
    NSUInteger at = 4;
    while (at < length) {
        if (at + 4 > length) return nil;
        uint16_t count = (uint16_t)((s[at] << 8) | s[at + 1]);
        uint16_t tag = (uint16_t)((s[at + 2] << 8) | s[at + 3]);
        NSInteger unit;
        switch (tag & 0xF000) {
            case 0x4000: case 0xC000: unit = 4; break;
            case 0x1000: unit = 1; break;
            case 0x0000: unit = 8; break;
            default: return nil;
        }
        if (at + 4 + count * unit > length) return nil;
        at += 4 + count * unit;
    }

    BOOL inserted = NO;
    at = 4;
    while (at < length) {
        uint16_t count = (uint16_t)((s[at] << 8) | s[at + 1]);
        uint16_t tag = (uint16_t)((s[at + 2] << 8) | s[at + 3]);
        NSInteger unit = (tag & 0xF000) == 0x1000 ? 1 : ((tag & 0xF000) == 0x0000 ? 8 : 4);
        NSUInteger entryLength = 4 + count * unit;

        if (tag != TUCDockBlockTag) {
            if (!inserted && tag == TUCDockBlockInsertBefore) {
                addBlock();
                inserted = YES;
            }
            [output appendBytes:s + at length:entryLength];
        }
        at += entryLength;
    }

    if (!inserted) addBlock();
    return output;
}

@end


#pragma mark - Click counter

@implementation TUCClickCounter {
    BOOL _hasLast;
    double _lastT;
    CGPoint _lastPoint;
    int64_t _lastState;
}

- (instancetype)init {
    if (self = [super init]) {
        _intervalSeconds = 0.5;
        _radiusPoints = 8;
    }
    return self;
}

- (int64_t)pressAt:(CGPoint)p now:(double)now {
    int64_t state = 1;
    if (_hasLast && now - _lastT <= self.intervalSeconds
        && hypot(p.x - _lastPoint.x, p.y - _lastPoint.y) <= self.radiusPoints) {
        state = MIN(_lastState + 1, 3);
    }
    _hasLast = YES; _lastT = now; _lastPoint = p; _lastState = state;
    return state;
}

- (int64_t)pressForDragAt:(CGPoint)p now:(double)now {
    _hasLast = YES; _lastT = now; _lastPoint = p; _lastState = 1;
    return 1;
}

@end


#pragma mark - Recording

BOOL TUCRecordingEnabled(void) {
    static BOOL recording;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ recording = getenv("TOUCHUP_RECORD") != NULL; });
    return recording;
}


#pragma mark - Scroll velocity & momentum

/// `from` up to `slow` mm/s, `to` from `fast` mm/s, and a squared ramp between.
static double TUCSpeedRamp(double mmPerSecond, double slow, double fast, double from, double to) {
    double t = fmax(0, fmin(1, (mmPerSecond - slow) / (fast - slow)));
    return from + (to - from) * t * t;
}

double TUCScrollBoost(double mmPerSecond) {
    return TUCSpeedRamp(mmPerSecond, 100, 260, 1, 3);
}

double TUCLaunchBoost(double mmPerSecond) {
    return TUCSpeedRamp(mmPerSecond, 60, 280, 1.8, 5);
}

@implementation TUCScrollVelocity {
    NSMutableArray<NSArray<NSNumber *> *> *_samples; // [t, dx, dy]
}

static const double TUCVelocityWindow = 0.10;  // the speed is the travel over (at most) the last 100 ms
static const double TUCVelocityStale = 0.06;   // no movement for this long before the lift: no speed
static const double TUCVelocityMinSpan = 0.02; // a single sample is taken as at least this long a movement

- (instancetype)init {
    if (self = [super init]) _samples = [NSMutableArray new];
    return self;
}

- (void)addDx:(double)dx dy:(double)dy now:(double)now {
    [_samples addObject:@[@(now), @(dx), @(dy)]];
    while (_samples.count > 0 && now - _samples.firstObject[0].doubleValue > TUCVelocityWindow) {
        [_samples removeObjectAtIndex:0];
    }
}

- (CGVector)velocityAt:(double)now {
    if (_samples.count == 0 || now - _samples.lastObject[0].doubleValue > TUCVelocityStale) {
        return CGVectorMake(0, 0);
    }
    double sx = 0, sy = 0, first = 0, last = 0;
    NSInteger n = 0;
    for (NSArray<NSNumber *> *s in _samples) {
        double t = s[0].doubleValue;
        if (now - t > TUCVelocityWindow) continue;
        if (n == 0) first = t;
        last = t;
        sx += s[1].doubleValue;
        sy += s[2].doubleValue;
        n++;
    }
    if (n == 0) return CGVectorMake(0, 0);

    // Over the time the samples really cover: each sample is the movement since the frame before it, so the span runs
    // from one frame before the first. Dividing by the whole window would read a 40 ms flick at 40% of its speed.
    double frame = n > 1 ? (last - first) / (n - 1) : TUCVelocityMinSpan;
    double span = fmax(TUCVelocityMinSpan, now - first + frame);
    return CGVectorMake(sx / span, sy / span);
}

- (void)reset {
    [_samples removeAllObjects];
}

@end


@implementation TUCScrollMomentum {
    double _speed;       // mm/s the content is moving, boosted
    CGVector _direction; // unit vector
}

// The time constant shrinks with the speed: tau = TimeConstant * (speed / ReferenceSpeed) ^ SpeedPower. A flick glides and the
// slow end stops quickly. (T650Native's ScrollMomentum; its 1000 px/s at 7 px per mm is 143 mm/s.)
static const double TUCMomentumTimeConstant = 0.22;   // seconds, at the reference speed
static const double TUCMomentumReferenceSpeed = 143;  // mm/s
static const double TUCMomentumSpeedPower = 0.2;      // 0 would be a plain exponential
static const double TUCMomentumStartSpeed = 27;       // mm/s the fingers need to start coasting
static const double TUCMomentumStopSpeed = 4.3;       // mm/s: below this it has come to rest

- (instancetype)init {
    if (self = [super init]) _pointsPerMM = TUCFallbackPointsPerMM;
    return self;
}

- (BOOL)startWithVelocity:(CGVector)v {
    double ppmm = self.pointsPerMM > 0 ? self.pointsPerMM : TUCFallbackPointsPerMM;
    double speedMM = hypot(v.dx, v.dy) / ppmm;
    if (speedMM < TUCMomentumStartSpeed) return NO;

    _speed = speedMM * TUCLaunchBoost(speedMM);
    _direction = CGVectorMake(v.dx / hypot(v.dx, v.dy), v.dy / hypot(v.dx, v.dy));
    _active = YES;
    return YES;
}

- (CGVector)step:(double)dt last:(BOOL *)last {
    if (!_active) {
        if (last) *last = YES;
        return CGVectorMake(0, 0);
    }
    // dv/dt = -v / tau(v), so v^p falls linearly with time; the distance is the integral of tau over the speed lost. Both are
    // exact, so the step size does not matter.
    double p = TUCMomentumSpeedPower;
    double scale = TUCMomentumTimeConstant / pow(TUCMomentumReferenceSpeed, p);
    double before = _speed;
    double after = pow(fmax(0, pow(before, p) - p * dt / scale), 1 / p);
    BOOL done = after < TUCMomentumStopSpeed;
    if (done) {
        after = fmin(before, TUCMomentumStopSpeed);
        _active = NO;
    }
    _speed = after;
    if (last) *last = done;

    double ppmm = self.pointsPerMM > 0 ? self.pointsPerMM : TUCFallbackPointsPerMM;
    double travel = scale * (pow(before, p + 1) - pow(after, p + 1)) / (p + 1) * ppmm;
    return CGVectorMake(_direction.dx * travel, _direction.dy * travel);
}

- (void)cancel {
    _active = NO;
    _speed = 0;
}

@end
