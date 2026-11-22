//
//  TUCGestureRecognizer.m
//  Touch Up Core
//
//  See the header. The two- and multi-finger logic follows T650Native's GestureRecognizer.cs; its comments explain
//  why each rule is there.
//

#import "TUCGestureRecognizer.h"

typedef NS_ENUM(NSInteger, TUCTwoMode) {
    TUCTwoModeUndecided,
    TUCTwoModeScroll,
    TUCTwoModePage,
    TUCTwoModePinch,
    TUCTwoModeRotate,
    TUCTwoModeEdge,
};

typedef NS_ENUM(NSInteger, TUCMultiMode) {
    TUCMultiModeUndecided,
    TUCMultiModeSwipe,
    TUCMultiModeIgnored,
};

typedef struct {
    double cx, cy, spread, t;
} TUCCentre;


static NSValue *TUCWrapEvent(TUCGestureEvent e) {
    return [NSValue valueWithBytes:&e objCType:@encode(TUCGestureEvent)];
}

static TUCGestureEvent TUCEvent(TUCGestureKind kind) {
    TUCGestureEvent e;
    memset(&e, 0, sizeof(e));
    e.kind = kind;
    return e;
}

static TUCGestureEvent TUCEventAt(TUCGestureKind kind, CGPoint point) {
    TUCGestureEvent e = TUCEvent(kind);
    e.point = point;
    return e;
}

static TUCGestureEvent TUCSwipeEvent(TUCGesturePhase phase, NSInteger fingers, TUCSwipeAxis axis, double travel, CGPoint point) {
    TUCGestureEvent e = TUCEventAt(TUCGestureKindSwipe, point);
    e.phase = phase;
    e.fingers = fingers;
    e.axis = axis;
    e.value = travel;
    return e;
}

static double TUCWrapAngle(double a) {
    while (a > M_PI) a -= 2 * M_PI;
    while (a <= -M_PI) a += 2 * M_PI;
    return a;
}

static double TUCDegrees(double radians) {
    return radians * 180.0 / M_PI;
}

static TUCCentre TUCCentreOf(const TUCContact *contacts, NSInteger count, double t) {
    TUCCentre c = { 0, 0, 0, t };
    if (count == 0) return c;
    for (NSInteger i = 0; i < count; i++) { c.cx += contacts[i].mm.x; c.cy += contacts[i].mm.y; }
    c.cx /= count;
    c.cy /= count;
    for (NSInteger i = 0; i < count; i++) c.spread += hypot(contacts[i].mm.x - c.cx, contacts[i].mm.y - c.cy);
    c.spread /= count;
    return c;
}

static CGPoint TUCCentroidPoint(const TUCContact *contacts, NSInteger count) {
    CGPoint p = CGPointZero;
    if (count == 0) return p;
    for (NSInteger i = 0; i < count; i++) { p.x += contacts[i].point.x; p.y += contacts[i].point.y; }
    return CGPointMake(p.x / count, p.y / count);
}


#pragma mark - Session

@interface TUCGestureSession : NSObject {
@public
    double startTime;
    NSInteger settledCount;
    NSInteger candidate;
    double candidateSince;
    BOOL candidateHasStart;
    TUCCentre candidateStart;          // where the fingers were when the current count first appeared
    NSInteger tapFingers;              // the largest settled count
    BOOL multiTouched;                 // 2+ fingers settled at some point
    double maxTravelMM;                // the furthest any finger got from where it landed
    CGPoint tapPoint;                  // where the first finger landed

    // One finger
    BOOL dragging;
    BOOL dragDone;                     // a drag ended this session: nothing else happens until all fingers lift
    NSInteger dragID;
    CGPoint lastDragPoint;

    // Two fingers
    TUCTwoMode twoMode;
    BOOL hasPairStart;
    double pairStartDist, pairStartMx, pairStartMy, pairStartAngle;
    CGPoint pairStartPoint;
    BOOL hasLastPair;
    double lastPairDist, lastPairAngle;
    CGPoint lastMidPoint;
    double edgeTravel;
    double pageTravel;

    // Three or more fingers
    TUCMultiMode multiMode;
    TUCSwipeAxis multiAxis;
    BOOL hasMultiStart;
    TUCCentre multiStart;
    NSInteger multiFingers;
    double multiBeganAt;
    double multiTravel;
    BOOL multiDone;                    // a swipe already ended this session: ignore the rest
    BOOL gestureSeen;                  // a scroll, pinch, rotate or swipe was recognised: the session is not a tap
}
@property (strong) NSMutableDictionary<NSNumber *, NSValue *> *landed;     // id -> TUCContact where it landed
@property (strong) NSMutableDictionary<NSNumber *, NSNumber *> *landedAt;  // id -> time
@property (strong) NSMutableDictionary<NSNumber *, NSValue *> *last;       // id -> TUCContact in the previous frame
@end

@implementation TUCGestureSession
- (instancetype)init {
    if (self = [super init]) {
        _landed = [NSMutableDictionary new];
        _landedAt = [NSMutableDictionary new];
        _last = [NSMutableDictionary new];
    }
    return self;
}
@end


static TUCContact TUCContactFromValue(NSValue *v) {
    TUCContact c;
    [v getValue:&c size:sizeof(c)];
    return c;
}

static NSValue *TUCWrapContact(TUCContact c) {
    return [NSValue valueWithBytes:&c objCType:@encode(TUCContact)];
}


#pragma mark - Recognizer

@implementation TUCGestureRecognizer {
    TUCGestureSession *_session;
}

static const NSInteger TUCPinchFingers = 4;     // Launchpad and Show Desktop are four-finger pinches
static const NSInteger TUCMaxSwipeFingers = 4;  // more fingers than this do not swipe (five can still pinch)

- (instancetype)init {
    if (self = [super init]) {
        _settleSeconds = 0.03;
        _dragSlopMM = 3.0;
        _longPressSeconds = 0.5;
        _tapMaxDuration = 0.35;
        _tapMaxTravelMM = 4.0;
        _modeDecisionTravelMM = 3.0;
        _multiSwipeTravelMM = 5.0;
        _edgeMarginMM = 20.0;
        _pinchBias = 1.5;
        _rotateBias = 0.9;
        _multiPinchBias = 0.5;
        _dragUpgradeSeconds = 0.3;

        _pagesWithTwoFingers = YES;
        _threeFingerVertical = YES;
    }
    return self;
}

- (void)applySettings:(TUCGestureSettings *)s {
    self.pagesWithTwoFingers = s.swipeBetweenPages
        && (s.pagesTrigger == TUCPagesTriggerTwoFingerScroll || s.pagesTrigger == TUCPagesTriggerTwoOrThreeFingerSwipe);
    self.threeFingerVertical = (s.missionControl || s.appExpose) && s.missionControlFingers == 3;
}

- (void)reset {
    _session = nil;
}


- (NSArray<NSValue *> *)handleContacts:(const TUCContact *)contacts
                                 count:(NSInteger)rawCount
                                  time:(double)now
                         screenWidthMM:(double)screenWidthMM
                           pointsPerMM:(double)pointsPerMM {
    NSMutableArray<NSValue *> *events = [NSMutableArray new];

    if (rawCount == 0 || contacts == NULL) {
        if (_session) {
            [events addObjectsFromArray:[self endSession:_session now:now]];
        }
        _session = nil;
        return events;
    }

    TUCGestureSession *s = _session;
    if (s == nil) {
        s = [TUCGestureSession new];
        s->startTime = now;
        s->candidate = rawCount;
        s->candidateSince = now;
        s->tapPoint = contacts[0].point;
        _session = s;
        [events addObject:TUCWrapEvent(TUCEventAt(TUCGestureKindTouchBegan, contacts[0].point))];
    }

    // Where each finger landed, and how far any finger has got from there (for taps).
    for (NSInteger i = 0; i < rawCount; i++) {
        NSNumber *key = @(contacts[i].identifier);
        NSValue *landedValue = s.landed[key];
        if (landedValue == nil) {
            s.landed[key] = TUCWrapContact(contacts[i]);
            s.landedAt[key] = @(now);
        } else {
            TUCContact o = TUCContactFromValue(landedValue);
            s->maxTravelMM = fmax(s->maxTravelMM, hypot(contacts[i].mm.x - o.mm.x, contacts[i].mm.y - o.mm.y));
        }
    }

    if (s->dragging || s->dragDone) {
        [self followDrag:s contacts:contacts count:rawCount events:events];
    } else {
        [self settleCount:s contacts:contacts count:rawCount now:now events:events];

        // How many of this frame's fingers were also in the previous one.
        NSInteger tracked = 0;
        for (NSInteger i = 0; i < rawCount; i++) {
            if (s.last[@(contacts[i].identifier)] != nil) tracked++;
        }

        if (s->settledCount == 1 && rawCount == 1 && !s->multiTouched) {
            [self oneFinger:s contact:contacts[0] now:now events:events];
        } else if (s->settledCount == 2 && rawCount == 2 && tracked == 2) {
            [self twoFingers:s contacts:contacts now:now screenWidthMM:screenWidthMM pointsPerMM:pointsPerMM events:events];
        } else if (s->settledCount >= 3 && rawCount == s->settledCount && !s->multiDone) {
            [self multiFinger:s contacts:contacts count:rawCount now:now events:events];
        }
    }

    [s.last removeAllObjects];
    for (NSInteger i = 0; i < rawCount; i++) {
        s.last[@(contacts[i].identifier)] = TUCWrapContact(contacts[i]);
    }

    return events;
}


#pragma mark One finger

- (void)oneFinger:(TUCGestureSession *)s contact:(TUCContact)c now:(double)now events:(NSMutableArray<NSValue *> *)events {
    NSNumber *key = @(c.identifier);
    TUCContact o = TUCContactFromValue(s.landed[key]);
    double held = now - s.landedAt[key].doubleValue;
    double travel = hypot(c.mm.x - o.mm.x, c.mm.y - o.mm.y);

    if (travel >= self.dragSlopMM) {
        // The finger moved: press where it landed and catch up to where it is, so the drag starts on its target.
        s->dragging = YES;
        s->dragID = c.identifier;
        [events addObject:TUCWrapEvent(TUCEventAt(TUCGestureKindDragBegan, o.point))];
        [events addObject:TUCWrapEvent(TUCEventAt(TUCGestureKindDragMoved, c.point))];
        s->lastDragPoint = c.point;
    } else if (held >= self.longPressSeconds) {
        // Press and hold (a Dock icon's menu, a button that repeats while held).
        s->dragging = YES;
        s->dragID = c.identifier;
        [events addObject:TUCWrapEvent(TUCEventAt(TUCGestureKindDragBegan, o.point))];
        s->lastDragPoint = o.point;
    }
}

/// A one-finger drag follows the finger that began it, whatever other fingers do, until it lifts.
- (void)followDrag:(TUCGestureSession *)s contacts:(const TUCContact *)contacts count:(NSInteger)count events:(NSMutableArray<NSValue *> *)events {
    if (!s->dragging) return;

    for (NSInteger i = 0; i < count; i++) {
        if (contacts[i].identifier != s->dragID) continue;
        CGPoint p = contacts[i].point;
        if (!CGPointEqualToPoint(p, s->lastDragPoint)) {
            [events addObject:TUCWrapEvent(TUCEventAt(TUCGestureKindDragMoved, p))];
            s->lastDragPoint = p;
        }
        return;
    }

    // The dragging finger lifted while others stay down.
    [events addObject:TUCWrapEvent(TUCEventAt(TUCGestureKindDragEnded, s->lastDragPoint))];
    s->dragging = NO;
    s->dragDone = YES;
}


#pragma mark Finger count

- (void)settleCount:(TUCGestureSession *)s contacts:(const TUCContact *)contacts count:(NSInteger)rawCount now:(double)now events:(NSMutableArray<NSValue *> *)events {
    if (rawCount != s->candidate) {
        s->candidate = rawCount;
        s->candidateSince = now;
        s->candidateHasStart = rawCount >= TUCPinchFingers;
        if (s->candidateHasStart) s->candidateStart = TUCCentreOf(contacts, rawCount, now);
    }

    if (now - s->candidateSince < self.settleSeconds || s->settledCount == rawCount) {
        return;
    }

    [self endTwoFinger:s events:events];

    // Three fingers land a moment before the fourth and are, for that moment, a three-finger swipe: when the fourth
    // arrives soon after it began, it is let go (cancelled) and the four fingers are a gesture of their own.
    BOOL upgrading = s->multiMode == TUCMultiModeSwipe && s->settledCount == 3 && rawCount >= TUCPinchFingers
        && now - s->multiBeganAt <= self.dragUpgradeSeconds;
    if (upgrading) {
        s->multiTravel = 0;
        [events addObject:TUCWrapEvent(TUCSwipeEvent(TUCGesturePhaseChanged, s->multiFingers, s->multiAxis, 0, CGPointZero))];
    }

    NSArray<NSValue *> *ended = [self endMulti:s];
    if (!upgrading && ended.count > 0) {
        s->multiDone = YES;  // fingers lifting one by one must not start another gesture
    }
    [events addObjectsFromArray:ended];

    s->settledCount = rawCount;
    s->tapFingers = MAX(s->tapFingers, rawCount);
    if (rawCount >= 2) s->multiTouched = YES;

    s->twoMode = TUCTwoModeUndecided;
    s->hasPairStart = NO;
    s->hasLastPair = NO;
    s->multiMode = TUCMultiModeUndecided;
    s->hasMultiStart = NO;
    s->multiTravel = 0;
}


#pragma mark Two fingers

// Scroll vs pinch vs rotate is decided once per settled two-finger period from the *net* change since it began:
// scrolling moves the midpoint and keeps the spacing; pinching changes the spacing and leaves the midpoint; rotating
// turns the pair. A per-frame test can't tell them apart (spacing wobbles during every scroll).
- (void)twoFingers:(TUCGestureSession *)s
          contacts:(const TUCContact *)contacts
               now:(double)now
     screenWidthMM:(double)screenWidthMM
       pointsPerMM:(double)pointsPerMM
            events:(NSMutableArray<NSValue *> *)events {
    // Order by finger id so the pair's angle doesn't flip when the report order does.
    TUCContact a = contacts[0], b = contacts[1];
    if (a.identifier > b.identifier) { TUCContact t = a; a = b; b = t; }

    double dist = hypot(a.mm.x - b.mm.x, a.mm.y - b.mm.y);
    double mx = (a.mm.x + b.mm.x) / 2.0;
    double my = (a.mm.y + b.mm.y) / 2.0;
    double angle = atan2(b.mm.y - a.mm.y, b.mm.x - a.mm.x);  // y points down, so this grows clockwise
    CGPoint mid = CGPointMake((a.point.x + b.point.x) / 2.0, (a.point.y + b.point.y) / 2.0);

    if (!s->hasPairStart) {
        s->hasPairStart = YES;
        s->pairStartDist = dist;
        s->pairStartMx = mx;
        s->pairStartMy = my;
        s->pairStartAngle = angle;
        s->pairStartPoint = mid;
    }

    double prevDist = s->hasLastPair ? s->lastPairDist : dist;
    double prevAngle = s->hasLastPair ? s->lastPairAngle : angle;
    CGPoint prevMid = s->hasLastPair ? s->lastMidPoint : mid;

    s->hasLastPair = YES;
    s->lastPairDist = dist;
    s->lastPairAngle = angle;
    s->lastMidPoint = mid;

    switch (s->twoMode) {
        case TUCTwoModeUndecided: {
            double tx = mx - s->pairStartMx;
            double ty = my - s->pairStartMy;
            double translation = hypot(tx, ty);
            double spread = fabs(dist - s->pairStartDist);
            double turned = TUCWrapAngle(angle - s->pairStartAngle);
            double arc = fabs(turned) * dist / 2;  // how far each finger travelled around the midpoint
            if (translation + spread + arc < self.modeDecisionTravelMM) {
                return;
            }

            // Two fingers entering from the right edge, moving inward: Notification Center.
            if (s->pairStartMx >= screenWidthMM - self.edgeMarginMM && tx < 0 && fabs(tx) > self.pinchBias * fabs(ty)
                && spread < translation && arc < translation) {
                s->twoMode = TUCTwoModeEdge;
                s->edgeTravel = -tx;
                TUCGestureEvent began = TUCEvent(TUCGestureKindEdgeSwipe);
                began.phase = TUCGesturePhaseBegan;
                TUCGestureEvent changed = TUCEvent(TUCGestureKindEdgeSwipe);
                changed.phase = TUCGesturePhaseChanged;
                changed.value = s->edgeTravel;
                [events addObject:TUCWrapEvent(began)];
                [events addObject:TUCWrapEvent(changed)];
                return;
            }

            // Turning the pair: the fingers travel around the midpoint and the spacing barely changes.
            if (arc > self.rotateBias * translation && arc > spread) {
                s->twoMode = TUCTwoModeRotate;
                TUCGestureEvent e = TUCEventAt(TUCGestureKindRotate, mid);
                e.value = TUCDegrees(turned);  // the turn so far, then incremental
                [events addObject:TUCWrapEvent(e)];
                return;
            }

            if (spread > self.pinchBias * translation) {
                s->twoMode = TUCTwoModePinch;
                if (s->pairStartDist > 0) {
                    TUCGestureEvent e = TUCEventAt(TUCGestureKindPinch, mid);
                    e.value = dist / s->pairStartDist;  // the pinch so far
                    [events addObject:TUCWrapEvent(e)];
                }
                return;
            }

            // A sideways stroke is a page swipe when that is switched on; anything else scrolls.
            if (self.pagesWithTwoFingers && fabs(tx) > self.pinchBias * fabs(ty)) {
                s->twoMode = TUCTwoModePage;
                s->pageTravel = tx;
                [events addObject:TUCWrapEvent(TUCSwipeEvent(TUCGesturePhaseBegan, 2, TUCSwipeAxisHorizontal, 0, mid))];
                [events addObject:TUCWrapEvent(TUCSwipeEvent(TUCGesturePhaseChanged, 2, TUCSwipeAxisHorizontal, tx, mid))];
                return;
            }

            // Scroll, catching up the travel spent deciding, so the content stays under the fingers.
            s->twoMode = TUCTwoModeScroll;
            TUCGestureEvent e = TUCEventAt(TUCGestureKindScroll, s->pairStartPoint);
            e.delta = CGVectorMake(mid.x - s->pairStartPoint.x, mid.y - s->pairStartPoint.y);
            e.value = pointsPerMM;
            [events addObject:TUCWrapEvent(e)];
            return;
        }

        case TUCTwoModeEdge: {
            s->edgeTravel = -(mx - s->pairStartMx);
            TUCGestureEvent e = TUCEvent(TUCGestureKindEdgeSwipe);
            e.phase = TUCGesturePhaseChanged;
            e.value = s->edgeTravel;
            [events addObject:TUCWrapEvent(e)];
            return;
        }

        case TUCTwoModeRotate: {
            double step = TUCWrapAngle(angle - prevAngle);
            if (step != 0) {
                TUCGestureEvent e = TUCEventAt(TUCGestureKindRotate, mid);
                e.value = TUCDegrees(step);
                [events addObject:TUCWrapEvent(e)];
            }
            return;
        }

        case TUCTwoModePinch:
            if (dist != prevDist && prevDist > 0) {
                TUCGestureEvent e = TUCEventAt(TUCGestureKindPinch, mid);
                e.value = dist / prevDist;
                [events addObject:TUCWrapEvent(e)];
            }
            return;

        case TUCTwoModePage:
            s->pageTravel = mx - s->pairStartMx;
            [events addObject:TUCWrapEvent(TUCSwipeEvent(TUCGesturePhaseChanged, 2, TUCSwipeAxisHorizontal, s->pageTravel, mid))];
            return;

        case TUCTwoModeScroll: {
            CGVector d = CGVectorMake(mid.x - prevMid.x, mid.y - prevMid.y);
            if (d.dx != 0 || d.dy != 0) {
                TUCGestureEvent e = TUCEventAt(TUCGestureKindScroll, mid);
                e.delta = d;
                e.value = pointsPerMM;
                [events addObject:TUCWrapEvent(e)];
            }
            return;
        }
    }
}

/// Close whatever a two-finger period had open.
- (void)endTwoFinger:(TUCGestureSession *)s events:(NSMutableArray<NSValue *> *)events {
    if (s->twoMode != TUCTwoModeUndecided) s->gestureSeen = YES;
    switch (s->twoMode) {
        case TUCTwoModePinch:
            [events addObject:TUCWrapEvent(TUCEvent(TUCGestureKindPinchEnd))];
            break;
        case TUCTwoModeRotate:
            [events addObject:TUCWrapEvent(TUCEvent(TUCGestureKindRotateEnd))];
            break;
        case TUCTwoModeScroll:
            [events addObject:TUCWrapEvent(TUCEvent(TUCGestureKindScrollEnd))];
            break;
        case TUCTwoModePage:
            [events addObject:TUCWrapEvent(TUCSwipeEvent(TUCGesturePhaseEnded, 2, TUCSwipeAxisHorizontal, s->pageTravel, s->lastMidPoint))];
            break;
        case TUCTwoModeEdge: {
            TUCGestureEvent e = TUCEvent(TUCGestureKindEdgeSwipe);
            e.phase = TUCGesturePhaseEnded;
            e.value = s->edgeTravel;
            [events addObject:TUCWrapEvent(e)];
            break;
        }
        case TUCTwoModeUndecided:
            break;
    }
    s->twoMode = TUCTwoModeUndecided;
}


#pragma mark Three or more fingers

// The mode is chosen once, from net movement of the centroid and of the fingers' mean distance from it:
// spread changed more than the centroid moved (four fingers): a pinch; otherwise horizontal or vertical by the
// dominant axis.
- (void)multiFinger:(TUCGestureSession *)s contacts:(const TUCContact *)contacts count:(NSInteger)count now:(double)now events:(NSMutableArray<NSValue *> *)events {
    TUCCentre c = TUCCentreOf(contacts, count, now);
    CGPoint centroid = TUCCentroidPoint(contacts, count);

    if (!s->hasMultiStart) {
        // Four or more fingers measure from where they landed, not from when the count settled: a quick flick has
        // already travelled part of its way by then.
        s->hasMultiStart = YES;
        s->multiStart = (s->settledCount >= TUCPinchFingers && s->candidateHasStart) ? s->candidateStart : c;
    }

    double tx = c.cx - s->multiStart.cx;
    double ty = c.cy - s->multiStart.cy;
    double ts = c.spread - s->multiStart.spread;
    double trans = hypot(tx, ty);

    switch (s->multiMode) {
        case TUCMultiModeUndecided: {
            if (trans + fabs(ts) < self.modeDecisionTravelMM) return;

            // Five fingers pinch and spread like four; they do not swipe.
            BOOL pinching = s->settledCount >= TUCPinchFingers && fabs(ts) > self.multiPinchBias * trans;
            if (s->settledCount >= TUCPinchFingers && !pinching) {
                if (s->settledCount > TUCMaxSwipeFingers || trans < self.multiSwipeTravelMM) return;
            }

            TUCSwipeAxis axis;
            if (pinching) {
                axis = TUCSwipeAxisPinch;
            } else if (fabs(tx) >= fabs(ty)) {
                axis = TUCSwipeAxisHorizontal;
            } else if (s->settledCount == 4 || (s->settledCount == 3 && self.threeFingerVertical)) {
                axis = TUCSwipeAxisVertical;
            } else {
                s->multiMode = TUCMultiModeIgnored;
                return;
            }

            s->multiMode = TUCMultiModeSwipe;
            s->multiBeganAt = now;
            s->multiAxis = axis;
            s->multiFingers = MIN(s->settledCount, TUCMaxSwipeFingers);  // a five-finger pinch is the four-finger one
            s->multiTravel = axis == TUCSwipeAxisHorizontal ? tx : (axis == TUCSwipeAxisVertical ? ty : ts);
            [events addObject:TUCWrapEvent(TUCSwipeEvent(TUCGesturePhaseBegan, s->multiFingers, axis, 0, centroid))];
            [events addObject:TUCWrapEvent(TUCSwipeEvent(TUCGesturePhaseChanged, s->multiFingers, axis, s->multiTravel, centroid))];
            return;
        }

        case TUCMultiModeSwipe:
            // The swipe follows the fingers both ways: pulled back, it goes back (the release decides whether it completes).
            s->multiTravel = s->multiAxis == TUCSwipeAxisHorizontal ? tx : (s->multiAxis == TUCSwipeAxisVertical ? ty : ts);
            [events addObject:TUCWrapEvent(TUCSwipeEvent(TUCGesturePhaseChanged, s->multiFingers, s->multiAxis, s->multiTravel, centroid))];
            return;

        case TUCMultiModeIgnored:
            return;
    }
}

- (NSArray<NSValue *> *)endMulti:(TUCGestureSession *)s {
    if (s->multiMode != TUCMultiModeUndecided) s->gestureSeen = YES;
    if (s->multiMode == TUCMultiModeSwipe) {
        s->multiMode = TUCMultiModeUndecided;
        return @[TUCWrapEvent(TUCSwipeEvent(TUCGesturePhaseEnded, s->multiFingers, s->multiAxis, s->multiTravel, CGPointZero))];
    }
    return @[];
}


#pragma mark Session end

- (NSArray<NSValue *> *)endSession:(TUCGestureSession *)s now:(double)now {
    NSMutableArray<NSValue *> *result = [NSMutableArray new];

    if (s->dragging) {
        [result addObject:TUCWrapEvent(TUCEventAt(TUCGestureKindDragEnded, s->lastDragPoint))];
        return result;
    }
    if (s->dragDone) {
        return result;
    }

    [result addObjectsFromArray:[self endMulti:s]];
    [self endTwoFinger:s events:result];
    if (result.count > 0 || s->multiDone || s->gestureSeen) {
        return result;  // it was a gesture, not a tap
    }

    double duration = now - s->startTime;
    NSInteger fingers = MAX(s->tapFingers, 1);
    if (fingers == 1) {
        // A lone finger that never moved past the slop or reached the long press: a click where it touched.
        if (!s->multiTouched) {
            TUCGestureEvent e = TUCEventAt(TUCGestureKindTap, s->tapPoint);
            e.fingers = 1;
            [result addObject:TUCWrapEvent(e)];
        }
    } else if (duration <= self.tapMaxDuration && s->maxTravelMM <= self.tapMaxTravelMM) {
        TUCGestureEvent e = TUCEventAt(TUCGestureKindTap, s->tapPoint);
        e.fingers = fingers;
        [result addObject:TUCWrapEvent(e)];
    }

    return result;
}

@end
