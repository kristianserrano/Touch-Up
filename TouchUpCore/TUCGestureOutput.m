//
//  TUCGestureOutput.m
//  Touch Up Core
//

#import "TUCGestureOutput.h"
#import <ApplicationServices/ApplicationServices.h>

static const uint16_t TUCKeyD = 0x02;   // Control-Command-D: Look Up
static const uint16_t TUCKeyN = 0x2D;   // Fn-N: Notification Center, when the menu-bar clock cannot be pressed

static const double TUCMomentumTick = 1.0 / 120.0;
static const double TUCMinMomentumStep = 0.001;
static const double TUCMaxMomentumStep = 0.1;

/// The modifier keys physically held right now, so a command-tap or shift-drag is the click it would be with a mouse.
/// Only the four that change what a click means.
static CGEventFlags TUCHeldClickModifiers(void) {
    CGEventFlags flags = CGEventSourceFlagsState(kCGEventSourceStateHIDSystemState);
    return flags & (kCGEventFlagMaskShift | kCGEventFlagMaskControl | kCGEventFlagMaskAlternate | kCGEventFlagMaskCommand);
}


@interface TUCGestureOutput ()
@property (strong) TUCSwipeTranslator *swipes;
@property (strong) TUCClickCounter *clicks;
@property (strong) TUCScrollVelocity *velocity;
@property (strong) TUCScrollMomentum *momentum;
@property (strong, nullable) NSTimer *momentumTimer;
@end

@implementation TUCGestureOutput {
    BOOL _buttonDown;
    CGPoint _buttonPoint;
    int64_t _clickState;

    BOOL _fingerScrollBegan;
    BOOL _momentumBegun;
    double _lastMomentumTick;
    double _carryX, _carryY;

    BOOL _magnifying;
    BOOL _rotating;

    BOOL _secondaryPending;
    CGPoint _secondaryPoint;
    NSInteger _secondaryGeneration;

    double _lastSwipeProgress;
}

- (instancetype)init {
    if (self = [super init]) {
        _settings = [TUCGestureSettings defaultSettings];
        _swipes = [TUCSwipeTranslator new];
        _clicks = [TUCClickCounter new];
        _velocity = [TUCScrollVelocity new];
        _momentum = [TUCScrollMomentum new];
        _doubleClickTolerancePoints = 30;
        _edgeCommitMM = 20;
        _smartZoomWindowSeconds = 0.35;
        _clickState = 1;
    }
    return self;
}

- (void)setSettings:(TUCGestureSettings *)settings {
    _settings = [settings copy];
    self.swipes.settings = _settings;
}


#pragma mark - Dispatch

- (void)post:(TUCGestureEvent)e {
    // Anything the fingers do but lift ends a coasting scroll, as touching a trackpad does.
    if (self.momentum.active && e.kind != TUCGestureKindScrollEnd) {
        [self cancelMomentum];
    }

    switch (e.kind) {
        case TUCGestureKindTouchBegan:
            if (!_buttonDown) [self moveCursorTo:e.point];
            break;

        case TUCGestureKindDragBegan:
            [self pressAt:e.point followingTap:e.value > 0];
            break;

        case TUCGestureKindDragMoved:
            [self dragTo:e.point];
            break;

        case TUCGestureKindDragEnded:
            [self releaseAt:e.point];
            break;

        case TUCGestureKindTap:
            if (e.fingers == 1) {
                [self clickAt:e.point];
            } else if (e.fingers == 2) {
                [self twoFingerTapAt:e.point];
            } else if (e.fingers == 3 && self.settings.lookUp) {
                [self moveCursorTo:e.point];
                [self postKey:TUCKeyD flags:kCGEventFlagMaskCommand | kCGEventFlagMaskControl];
            }
            break;

        case TUCGestureKindScroll:
            [self scrollBy:e.delta at:e.point pointsPerMM:e.value];
            break;

        case TUCGestureKindScrollEnd:
            [self endScrollAllowingMomentum:YES];
            break;

        case TUCGestureKindPinch:
            if (self.settings.zoom) {
                if (!_magnifying) [self moveCursorTo:e.point];
                [self postRotateOrMagnify:TUCSubtypeMagnify active:&_magnifying amount:e.value - 1];
            }
            break;

        case TUCGestureKindPinchEnd:
            [self endGesture:TUCSubtypeMagnify active:&_magnifying];
            break;

        case TUCGestureKindRotate:
            // Positive degrees from the recognizer are clockwise; the native event is the opposite.
            if (self.settings.rotate) {
                if (!_rotating) [self moveCursorTo:e.point];
                [self postRotateOrMagnify:TUCSubtypeRotate active:&_rotating amount:-e.value];
            }
            break;

        case TUCGestureKindRotateEnd:
            [self endGesture:TUCSubtypeRotate active:&_rotating];
            break;

        case TUCGestureKindSwipe:
            if (e.phase == TUCGesturePhaseBegan && e.fingers == 2) {
                [self moveCursorTo:e.point];  // a page swipe acts on the window under the fingers
            }
            [self postSwipes:[self.swipes translatePhase:e.phase fingers:e.fingers axis:e.axis travel:e.value now:TUCUptimeSeconds()]];
            break;

        case TUCGestureKindEdgeSwipe:
            // macOS has no gesture event for this that can be posted, so a committed swipe toggles Notification Center.
            if (self.settings.notificationCenter && e.phase == TUCGesturePhaseEnded && e.value >= self.edgeCommitMM) {
                [self toggleNotificationCenter];
            }
            break;
    }
}

- (void)reset {
    _secondaryGeneration++;
    _secondaryPending = NO;

    [self cancelMomentum];
    [self endScrollAllowingMomentum:NO];
    [self releaseHeldButton];
    [self endGesture:TUCSubtypeMagnify active:&_magnifying];
    [self endGesture:TUCSubtypeRotate active:&_rotating];
    [self postSwipes:[self.swipes cancel]];
}

- (void)releaseHeldButton {
    if (_buttonDown) [self releaseAt:[self cursorLocation]];
}

- (void)nudgeCursor {
    [self moveCursorTo:[self cursorLocation]];
}


#pragma mark - Mouse

- (CGPoint)cursorLocation {
    CGEventRef dummy = CGEventCreate(NULL);
    CGPoint location = CGEventGetLocation(dummy);
    CFRelease(dummy);
    return location;
}

- (void)postMouse:(CGEventType)type at:(CGPoint)p button:(CGMouseButton)button clickState:(int64_t)clickState {
    CGEventRef event = CGEventCreateMouseEvent(NULL, type, p, button);
    if (!event) return;
    CGEventSetFlags(event, TUCHeldClickModifiers());
    if (clickState > 0) {
        CGEventSetIntegerValueField(event, kCGMouseEventClickState, clickState);
    }
    CGEventPost(kCGHIDEventTap, event);
    CFRelease(event);
}

- (void)moveCursorTo:(CGPoint)p {
    [self postMouse:kCGEventMouseMoved at:p button:kCGMouseButtonLeft clickState:0];
}

- (void)clickAt:(CGPoint)p {
    self.clicks.radiusPoints = self.doubleClickTolerancePoints;
    self.clicks.intervalSeconds = [NSEvent doubleClickInterval];
    int64_t state = [self.clicks pressAt:p now:TUCUptimeSeconds()];

    [self moveCursorTo:p];
    [self postMouse:kCGEventLeftMouseDown at:p button:kCGMouseButtonLeft clickState:state];
    [self postMouse:kCGEventLeftMouseUp at:p button:kCGMouseButtonLeft clickState:state];
}

/// followingTap: double-tap and drag, so the press is the tap's next click (a double-click drag selects by word);
/// otherwise a press and hold, which starts a click count of its own.
- (void)pressAt:(CGPoint)p followingTap:(BOOL)followingTap {
    if (_buttonDown) return;  // a second press would take the first over and stick
    self.clicks.radiusPoints = self.doubleClickTolerancePoints;
    self.clicks.intervalSeconds = [NSEvent doubleClickInterval];
    double now = TUCUptimeSeconds();
    _clickState = followingTap ? [self.clicks pressAt:p now:now] : [self.clicks pressForDragAt:p now:now];
    _buttonDown = YES;
    _buttonPoint = p;
    [self moveCursorTo:p];
    [self postMouse:kCGEventLeftMouseDown at:p button:kCGMouseButtonLeft clickState:_clickState];
}

- (void)dragTo:(CGPoint)p {
    if (!_buttonDown) return;
    CGEventRef event = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDragged, p, kCGMouseButtonLeft);
    if (!event) return;
    CGEventSetFlags(event, TUCHeldClickModifiers());
    CGEventSetIntegerValueField(event, kCGMouseEventClickState, _clickState);
    // Some apps read the delta fields rather than the position during a drag.
    CGEventSetIntegerValueField(event, kCGMouseEventDeltaX, (int64_t)llround(p.x - _buttonPoint.x));
    CGEventSetIntegerValueField(event, kCGMouseEventDeltaY, (int64_t)llround(p.y - _buttonPoint.y));
    CGEventPost(kCGHIDEventTap, event);
    CFRelease(event);
    _buttonPoint = p;
}

- (void)releaseAt:(CGPoint)p {
    if (!_buttonDown) return;  // nothing to end: do not post a mouse-up with no mouse-down
    _buttonDown = NO;
    [self postMouse:kCGEventLeftMouseUp at:p button:kCGMouseButtonLeft clickState:_clickState];
}

- (void)rightClickAt:(CGPoint)p {
    [self moveCursorTo:p];
    [self postMouse:kCGEventRightMouseDown at:p button:kCGMouseButtonRight clickState:1];
    [self postMouse:kCGEventRightMouseUp at:p button:kCGMouseButtonRight clickState:1];
}

/// A single two-finger tap is a secondary click, but a second one within the window is smart zoom.
- (void)twoFingerTapAt:(CGPoint)p {
    if (!self.settings.smartZoom) {
        if (self.settings.secondaryClick) [self rightClickAt:p];
        return;
    }

    if (_secondaryPending) {
        _secondaryGeneration++;
        _secondaryPending = NO;
        [self moveCursorTo:p];
        [self postGestureType:TUCEventTypeGesture integers:@[@[@(TUCFieldSubtype), @(TUCSubtypeSmartZoom)]] doubles:nil];
        return;
    }

    _secondaryPending = YES;
    _secondaryPoint = p;
    NSInteger generation = ++_secondaryGeneration;
    __weak TUCGestureOutput *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.smartZoomWindowSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        TUCGestureOutput *strongSelf = weakSelf;
        // A second tap (smart zoom) or a reset got there first: this callback is stale and must not right-click.
        if (strongSelf == nil || generation != strongSelf->_secondaryGeneration) return;
        strongSelf->_secondaryPending = NO;
        if (strongSelf.settings.secondaryClick) [strongSelf rightClickAt:strongSelf->_secondaryPoint];
    });
}


#pragma mark - Scrolling

- (void)postScrollWheel1:(int32_t)wheel1 wheel2:(int32_t)wheel2 scrollPhase:(int64_t)scrollPhase momentumPhase:(int64_t)momentumPhase {
    if (TUCRecordingEnabled()) printf("O %.4f wheel %d %d phase %lld momentum %lld\n", TUCUptimeSeconds(), wheel1, wheel2, scrollPhase, momentumPhase);
    CGEventRef event = CGEventCreateScrollWheelEvent2(NULL, kCGScrollEventUnitPixel, 2, wheel1, wheel2, 0);
    if (!event) return;
    CGEventSetFlags(event, 0);
    if (scrollPhase != 0) CGEventSetIntegerValueField(event, kCGScrollWheelEventScrollPhase, scrollPhase);
    if (momentumPhase != 0) CGEventSetIntegerValueField(event, kCGScrollWheelEventMomentumPhase, momentumPhase);
    CGEventPost(kCGHIDEventTap, event);
    CFRelease(event);
}

/// Finger movement (points) -> whole wheel pixels, carrying the fraction. Natural: the content follows the fingers.
/// The acceleration for how fast it is going (points per second) applies to the fingers and the coasting alike.
- (void)wheelsFor:(CGVector)d speed:(double)pointsPerSecond wheel1:(int32_t *)wheel1 wheel2:(int32_t *)wheel2 {
    double ppmm = self.momentum.pointsPerMM > 0 ? self.momentum.pointsPerMM : TUCFallbackPointsPerMM;
    double gain = TUCScrollBoost(pointsPerSecond / ppmm);
    _carryX += d.dx * gain;
    _carryY += d.dy * gain;
    *wheel2 = (int32_t)trunc(_carryX);
    *wheel1 = (int32_t)trunc(_carryY);
    _carryX -= *wheel2;
    _carryY -= *wheel1;
}

- (void)scrollBy:(CGVector)d at:(CGPoint)p pointsPerMM:(double)pointsPerMM {
    if (!_fingerScrollBegan) {
        [self moveCursorTo:p];  // the scroll goes to the view under the fingers
    }
    if (pointsPerMM > 0) self.momentum.pointsPerMM = pointsPerMM;
    double now = TUCUptimeSeconds();
    [self.velocity addDx:d.dx dy:d.dy now:now];
    CGVector v = [self.velocity velocityAt:now];

    int32_t wheel1, wheel2;
    [self wheelsFor:d speed:hypot(v.dx, v.dy) wheel1:&wheel1 wheel2:&wheel2];
    if (wheel1 != 0 || wheel2 != 0) {
        // The fingers' scroll is a phased gesture, like a trackpad's: began, then changed, then ended.
        [self postScrollWheel1:wheel1 wheel2:wheel2 scrollPhase:_fingerScrollBegan ? kCGScrollPhaseChanged : kCGScrollPhaseBegan momentumPhase:0];
        _fingerScrollBegan = YES;
    }
}

- (void)fingersWentQuiet {
    if (TUCRecordingEnabled()) printf("O %.4f quiet scrolling=%d\n", TUCUptimeSeconds(), _fingerScrollBegan);
    if (_fingerScrollBegan) {
        [self endScrollAllowingMomentum:YES];
    }
}

- (void)endScrollAllowingMomentum:(BOOL)allowMomentum {
    // Already ended when the fingers went quiet, and coasting: the confirmed lift changes nothing.
    if (!_fingerScrollBegan && self.momentum.active) {
        return;
    }

    if (_fingerScrollBegan) {
        [self postScrollWheel1:0 wheel2:0 scrollPhase:kCGScrollPhaseEnded momentumPhase:0];
        _fingerScrollBegan = NO;
    }

    // As of the last report: a lift noticed late (no report, then a timeout) must not read as fingers that had stopped.
    double now = TUCUptimeSeconds();
    double measuredAt = self.lastReportTime > 0 ? fmin(now, self.lastReportTime) : now;
    CGVector v = [self.velocity velocityAt:measuredAt];
    [self.velocity reset];

    BOOL coasting = allowMomentum && self.settings.scrollMomentum && [self.momentum startWithVelocity:v];
    if (TUCRecordingEnabled()) printf("O %.4f end-scroll v=%.0f,%.0f pt/s measured %.0f ms before now, coast=%d\n", now, v.dx, v.dy, (now - measuredAt) * 1000, coasting);
    if (coasting) {
        _momentumBegun = NO;
        _lastMomentumTick = TUCUptimeSeconds();
        [self.momentumTimer invalidate];
        self.momentumTimer = [NSTimer timerWithTimeInterval:TUCMomentumTick target:self selector:@selector(momentumTick:) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:self.momentumTimer forMode:NSRunLoopCommonModes];
    } else {
        _carryX = 0;
        _carryY = 0;
    }
}

- (void)momentumTick:(NSTimer *)timer {
    if (!self.momentum.active) {
        [self finishMomentum];
        return;
    }

    double now = TUCUptimeSeconds();
    double dt = fmax(TUCMinMomentumStep, fmin(TUCMaxMomentumStep, now - _lastMomentumTick));
    _lastMomentumTick = now;

    BOOL last = NO;
    CGVector d = [self.momentum step:dt last:&last];
    int32_t wheel1, wheel2;
    [self wheelsFor:d speed:hypot(d.dx, d.dy) / dt wheel1:&wheel1 wheel2:&wheel2];
    if (wheel1 != 0 || wheel2 != 0) {
        [self postScrollWheel1:wheel1 wheel2:wheel2 scrollPhase:0 momentumPhase:_momentumBegun ? kCGMomentumScrollPhaseContinue : kCGMomentumScrollPhaseBegin];
        _momentumBegun = YES;
    }

    if (last) [self finishMomentum];
}

/// The coasting came to rest, or was stopped: end it cleanly so apps are not left waiting.
- (void)finishMomentum {
    [self.momentumTimer invalidate];
    self.momentumTimer = nil;
    if (_momentumBegun) {
        [self postScrollWheel1:0 wheel2:0 scrollPhase:0 momentumPhase:kCGMomentumScrollPhaseEnd];
    }
    _momentumBegun = NO;
    _carryX = 0;
    _carryY = 0;
}

- (void)cancelMomentum {
    if (TUCRecordingEnabled() && (self.momentum.active || self.momentumTimer != nil)) printf("O %.4f cancel-momentum\n", TUCUptimeSeconds());
    if (!self.momentum.active && self.momentumTimer == nil) return;
    [self.momentum cancel];
    [self finishMomentum];
}


#pragma mark - Native gestures

/// A bare gesture event (type 29 or 30) with the given fields and the flags recorded events carry.
/// integers / doubles: arrays of @[field, value].
- (void)postGestureType:(uint32_t)type
               integers:(NSArray<NSArray<NSNumber *> *> *)integers
                doubles:(nullable NSArray<NSArray<NSNumber *> *> *)doubles {
    [self postGestureType:type integers:integers doubles:doubles dockBlock:NO swipe:(TUCNativeSwipeEvent){0}];
}

- (void)postGestureType:(uint32_t)type
               integers:(NSArray<NSArray<NSNumber *> *> *)integers
                doubles:(nullable NSArray<NSArray<NSNumber *> *> *)doubles
              dockBlock:(BOOL)withBlock
                  swipe:(TUCNativeSwipeEvent)swipe {
    CGEventRef event = CGEventCreate(NULL);
    if (!event) return;

    CGEventSetType(event, type);
    CGEventSetFlags(event, TUCGestureFlags);
    for (NSArray<NSNumber *> *pair in integers) {
        CGEventSetIntegerValueField(event, pair[0].unsignedIntValue, pair[1].longLongValue);
    }
    for (NSArray<NSNumber *> *pair in doubles) {
        CGEventSetDoubleValueField(event, pair[0].unsignedIntValue, pair[1].doubleValue);
    }

    CGEventRef rebuilt = withBlock ? [self copyEvent:event withDockSwipeBlockFor:swipe] : NULL;
    CGEventPost(kCGHIDEventTap, rebuilt ?: event);
    if (rebuilt) CFRelease(rebuilt);
    CFRelease(event);
}

/// A copy of a Dock swipe event with the embedded HID block macOS 27 requires, or NULL if it cannot be made.
- (nullable CGEventRef)copyEvent:(CGEventRef)event withDockSwipeBlockFor:(TUCNativeSwipeEvent)n CF_RETURNS_RETAINED {
    uint64_t timestamp = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    CGEventSetTimestamp(event, timestamp);

    CFDataRef data = CGEventCreateData(NULL, event);
    if (!data) return NULL;

    double delta = n.phase == TUCPhaseBegan ? n.progress : n.progress - _lastSwipeProgress;
    _lastSwipeProgress = n.progress;

    NSData *block = [TUCDockSwipeBlock buildWithTimestamp:timestamp kind:n.kind phase:n.phase progress:n.progress
                                            progressDelta:delta hasVelocity:n.hasVelocity velocity:n.velocity];
    NSData *withBlock = [TUCDockSwipeBlock insertBlock:block intoSerializedEvent:(__bridge NSData *)data];
    CFRelease(data);
    if (!withBlock) return NULL;

    return CGEventCreateFromData(NULL, (__bridge CFDataRef)withBlock);
}

/// Magnify and rotate share one layout: the subtype, the phase (began, then changed, then ended) and a double amount.
- (void)postRotateOrMagnify:(int64_t)subtype active:(BOOL *)active amount:(double)amount {
    [self postGestureType:TUCEventTypeGesture
                 integers:@[@[@(TUCFieldSubtype), @(subtype)], @[@(TUCFieldPhase), @(*active ? TUCPhaseChanged : TUCPhaseBegan)]]
                  doubles:@[@[@(TUCFieldAmount), @(amount)]]];
    *active = YES;
}

- (void)endGesture:(int64_t)subtype active:(BOOL *)active {
    if (!*active) return;
    [self postGestureType:TUCEventTypeGesture
                 integers:@[@[@(TUCFieldSubtype), @(subtype)], @[@(TUCFieldPhase), @(TUCPhaseEnded)]]
                  doubles:nil];
    *active = NO;
}

- (void)postSwipes:(NSArray<NSValue *> *)swipes {
    for (NSValue *v in swipes) {
        TUCNativeSwipeEvent n;
        [v getValue:&n size:sizeof(n)];
        [self postSwipe:n];
    }
}

/// Native swipe layout (Dock swipe type 30 / navigation swipe type 29); see TUCSwipeTranslator.
- (void)postSwipe:(TUCNativeSwipeEvent)n {
    float progressFloat = (float)n.progress;
    uint32_t progressBits;
    memcpy(&progressBits, &progressFloat, sizeof(progressBits));

    // These read back as float32 values whose bit patterns are the kind and the phase.
    int32_t kindBits = (int32_t)n.kind, phaseBits = (int32_t)n.phase;
    float kindFloat, phaseFloat;
    memcpy(&kindFloat, &kindBits, sizeof(kindFloat));
    memcpy(&phaseFloat, &phaseBits, sizeof(phaseFloat));

    NSMutableArray<NSArray<NSNumber *> *> *integers = [@[
        @[@(TUCFieldSubtype), @(n.subtype)],
        @[@(TUCFieldSwipeKind), @(n.kind)],
        @[@(TUCFieldSwipeKindCopy), @(n.kind)],
        @[@(TUCFieldPhase), @(n.phase)],
        @[@(TUCFieldPhaseCopy), @(n.phase)],
        @[@(TUCFieldProgressBits), @((int64_t)progressBits)],
        @[@(TUCFieldConstant136), @1],
        @[@(TUCFieldConstant138), @3],
    ] mutableCopy];
    NSMutableArray<NSArray<NSNumber *> *> *doubles = [@[
        @[@(TUCFieldProgress), @(n.progress)],
        @[@(TUCFieldKindFloat), @(kindFloat)],
        @[@(TUCFieldKindFloatCopy), @(kindFloat)],
        @[@(TUCFieldPhaseFloat), @(phaseFloat)],
        @[@(TUCFieldPhaseFloatCopy), @(phaseFloat)],
    ] mutableCopy];

    if (n.hasFlavor) {
        [integers addObject:@[@(TUCFieldFlavor), @(n.flavor)]];
        [integers addObject:@[@(TUCFieldFlavorCopy), @(n.flavor)]];
        [integers addObject:@[@(TUCFieldFlavorCopy2), @(n.flavor)]];
    }
    if (n.hasVelocity) {
        [doubles addObject:@[@(TUCFieldVelocity), @(n.velocity)]];
        [doubles addObject:@[@(TUCFieldVelocityCopy), @(n.velocity)]];
    }

    [self postGestureType:n.cgType integers:integers doubles:doubles dockBlock:n.cgType == TUCEventTypeDockSwipe swipe:n];
}


#pragma mark - Keys and Notification Center

/// Key down carries the flags; key up carries none, so a modifier can't stay asserted.
- (void)postKey:(uint16_t)key flags:(CGEventFlags)flags {
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStatePrivate);
    for (int down = 1; down >= 0; down--) {
        CGEventRef event = CGEventCreateKeyboardEvent(source, key, down);
        if (!event) continue;
        CGEventSetFlags(event, down ? flags : 0);
        CGEventPost(kCGHIDEventTap, event);
        CFRelease(event);
    }
    if (source) CFRelease(source);
}

/// Presses the menu-bar clock, which opens (or closes) Notification Center; falls back to Fn-N.
- (void)toggleNotificationCenter {
    if ([self pressMenuBarClock]) return;
    [self postKey:TUCKeyN flags:kCGEventFlagMaskSecondaryFn];
}

- (BOOL)pressMenuBarClock {
    if (!AXIsProcessTrusted()) return NO;

    NSRunningApplication *controlCenter = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.controlcenter"].firstObject;
    if (controlCenter == nil) return NO;

    AXUIElementRef root = AXUIElementCreateApplication(controlCenter.processIdentifier);
    if (!root) return NO;

    BOOL pressed = NO;
    CFTypeRef bar = NULL, children = NULL;
    if (AXUIElementCopyAttributeValue(root, CFSTR("AXExtrasMenuBar"), &bar) == kAXErrorSuccess && bar
        && AXUIElementCopyAttributeValue((AXUIElementRef)bar, kAXChildrenAttribute, &children) == kAXErrorSuccess
        && children && CFGetTypeID(children) == CFArrayGetTypeID()) {
        for (CFIndex i = 0; i < CFArrayGetCount(children) && !pressed; i++) {
            AXUIElementRef item = (AXUIElementRef)CFArrayGetValueAtIndex(children, i);
            CFTypeRef identifier = NULL;
            if (AXUIElementCopyAttributeValue(item, kAXIdentifierAttribute, &identifier) == kAXErrorSuccess && identifier) {
                if (CFGetTypeID(identifier) == CFStringGetTypeID()
                    && [(__bridge NSString *)identifier isEqualToString:@"com.apple.menuextra.clock"]) {
                    pressed = AXUIElementPerformAction(item, kAXPressAction) == kAXErrorSuccess;
                }
                CFRelease(identifier);
            }
        }
    }

    if (children) CFRelease(children);
    if (bar) CFRelease(bar);
    CFRelease(root);
    return pressed;
}

@end
