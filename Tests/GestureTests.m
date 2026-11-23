//
//  GestureTests.m
//  Touch Up Core tests
//
//  Tests for the pure gesture logic: TUCGestureRecognizer, TUCSwipeTranslator, TUCDockSwipeBlock, TUCClickCounter, scroll
//  velocity, momentum and boost, and TUCGestureSettings' defaults and routing.
//  Run with Tests/run-tests.sh. No XCTest target: these files have no OS dependencies, so plain clang is enough.
//

#import <Foundation/Foundation.h>
#import "TUCGestureRecognizer.h"

static int failures = 0;
static int checks = 0;
static NSString *currentTest = @"";

#define CHECK(cond, ...) do { \
    checks++; \
    if (!(cond)) { \
        failures++; \
        printf("FAIL [%s] %s:%d: %s — %s\n", currentTest.UTF8String, __FILE__, __LINE__, #cond, [NSString stringWithFormat:__VA_ARGS__].UTF8String); \
    } \
} while (0)

static const double kWidthMM = 300;
static const double kPPMM = 4;
static const double kFrame = 0.008;  // 125 Hz

#pragma mark - Helpers

/// Drives a recognizer with synthetic frames; finger positions in mm, points = mm * kPPMM.
@interface Driver : NSObject
@property TUCGestureRecognizer *recognizer;
@property double now;
@property NSMutableArray<NSValue *> *events;
@end

@implementation Driver
- (instancetype)init {
    if (self = [super init]) {
        _recognizer = [TUCGestureRecognizer new];
        _now = 100;
        _events = [NSMutableArray new];
    }
    return self;
}

/// fingers: array of @[id, x, y] in mm.
- (void)frame:(NSArray<NSArray<NSNumber *> *> *)fingers {
    TUCContact contacts[10];
    NSInteger n = 0;
    for (NSArray<NSNumber *> *f in fingers) {
        contacts[n].identifier = f[0].integerValue;
        contacts[n].mm = CGPointMake(f[1].doubleValue, f[2].doubleValue);
        contacts[n].point = CGPointMake(f[1].doubleValue * kPPMM, f[2].doubleValue * kPPMM);
        n++;
    }
    [self.events addObjectsFromArray:[self.recognizer handleContacts:(n ? contacts : NULL) count:n time:self.now screenWidthMM:kWidthMM pointsPerMM:kPPMM]];
    self.now += kFrame;
}

- (void)lift {
    [self frame:@[]];
}

/// Moves every finger from its start by (dx, dy) over `frames` frames. start: @[id, x, y].
- (void)move:(NSArray<NSArray<NSNumber *> *> *)start dx:(double)dx dy:(double)dy frames:(int)frames {
    for (int i = 1; i <= frames; i++) {
        double t = (double)i / frames;
        NSMutableArray *f = [NSMutableArray new];
        for (NSArray<NSNumber *> *c in start) {
            [f addObject:@[c[0], @(c[1].doubleValue + dx * t), @(c[2].doubleValue + dy * t)]];
        }
        [self frame:f];
    }
}

- (void)hold:(NSArray<NSArray<NSNumber *> *> *)fingers frames:(int)frames {
    for (int i = 0; i < frames; i++) [self frame:fingers];
}

- (NSArray<NSValue *> *)ofKind:(TUCGestureKind)kind {
    NSMutableArray *r = [NSMutableArray new];
    for (NSValue *v in self.events) if (TUCGestureEventFromValue(v).kind == kind) [r addObject:v];
    return r;
}

- (BOOL)has:(TUCGestureKind)kind {
    return [self ofKind:kind].count > 0;
}

- (TUCGestureEvent)first:(TUCGestureKind)kind {
    return TUCGestureEventFromValue([self ofKind:kind].firstObject);
}

- (TUCGestureEvent)last:(TUCGestureKind)kind {
    return TUCGestureEventFromValue([self ofKind:kind].lastObject);
}
@end


#pragma mark - One finger

static void testOneFingerTapClicksWhereItLanded(void) {
    currentTest = @"one finger tap";
    Driver *d = [Driver new];
    [d hold:@[@[@1, @50, @60]] frames:5];
    [d frame:@[@[@1, @51, @60]]];  // a little wobble, under the slop
    [d lift];

    CHECK([d has:TUCGestureKindTouchBegan], @"no TouchBegan");
    CHECK([d ofKind:TUCGestureKindTap].count == 1, @"taps: %lu", [d ofKind:TUCGestureKindTap].count);
    TUCGestureEvent tap = [d first:TUCGestureKindTap];
    CHECK(tap.fingers == 1, @"fingers %ld", tap.fingers);
    CHECK(tap.point.x == 200 && tap.point.y == 240, @"point %f,%f", tap.point.x, tap.point.y);
    CHECK(![d has:TUCGestureKindDragBegan], @"a tap must not drag");
}

static void testOneFingerMovePressesAtOriginAndDrags(void) {
    currentTest = @"one finger drag";
    Driver *d = [Driver new];
    NSArray *start = @[@[@1, @50, @60]];
    [d hold:start frames:5];
    [d move:start dx:20 dy:0 frames:10];
    [d lift];

    CHECK([d has:TUCGestureKindDragBegan], @"no DragBegan");
    TUCGestureEvent began = [d first:TUCGestureKindDragBegan];
    CHECK(began.point.x == 200 && began.point.y == 240, @"press should be where the finger landed, got %f,%f", began.point.x, began.point.y);
    TUCGestureEvent lastMove = [d last:TUCGestureKindDragMoved];
    CHECK(fabs(lastMove.point.x - 280) < 0.001, @"drag should follow the finger to x=280, got %f", lastMove.point.x);
    CHECK([d ofKind:TUCGestureKindDragEnded].count == 1, @"DragEnded count %lu", [d ofKind:TUCGestureKindDragEnded].count);
    CHECK(![d has:TUCGestureKindTap], @"a drag must not tap");
}

static void testOneFingerLongPressPressesTheButton(void) {
    currentTest = @"long press";
    Driver *d = [Driver new];
    [d hold:@[@[@1, @50, @60]] frames:70];  // 0.56 s
    CHECK([d has:TUCGestureKindDragBegan], @"no press after the long-press time");
    CHECK(![d has:TUCGestureKindDragEnded], @"button released too early");
    [d lift];
    CHECK([d has:TUCGestureKindDragEnded], @"no release on lift");
    CHECK(![d has:TUCGestureKindTap], @"a long press is not a tap too");
}

static void testDragFollowsItsFingerWhenASecondLands(void) {
    currentTest = @"drag ignores a second finger";
    Driver *d = [Driver new];
    NSArray *start = @[@[@1, @50, @60]];
    [d hold:start frames:5];
    [d move:start dx:10 dy:0 frames:5];
    [d hold:@[@[@1, @60, @60], @[@2, @100, @100]] frames:10];
    [d move:@[@[@1, @60, @60], @[@2, @100, @100]] dx:0 dy:10 frames:5];
    [d lift];

    CHECK(![d has:TUCGestureKindScroll], @"a second finger during a drag must not scroll");
    CHECK(fabs([d last:TUCGestureKindDragMoved].point.y - 280) < 0.001, @"drag should follow finger 1, got y=%f", [d last:TUCGestureKindDragMoved].point.y);
    CHECK([d ofKind:TUCGestureKindDragEnded].count == 1, @"one release");
}


#pragma mark - Two fingers

static void testTwoFingerTapIsATwoFingerTap(void) {
    currentTest = @"two finger tap";
    Driver *d = [Driver new];
    [d hold:@[@[@1, @50, @60], @[@2, @70, @60]] frames:10];
    [d lift];

    CHECK([d ofKind:TUCGestureKindTap].count == 1, @"taps %lu", [d ofKind:TUCGestureKindTap].count);
    CHECK([d first:TUCGestureKindTap].fingers == 2, @"fingers %ld", [d first:TUCGestureKindTap].fingers);
    CHECK(![d has:TUCGestureKindDragBegan], @"no drag");
}

static void testStaggeredLandingIsStillTwoFingers(void) {
    currentTest = @"staggered two finger landing";
    Driver *d = [Driver new];
    [d frame:@[@[@1, @50, @60]]];                         // second finger lands one frame later
    NSArray *pair = @[@[@1, @50, @60], @[@2, @70, @60]];
    [d hold:pair frames:5];
    [d move:pair dx:0 dy:30 frames:15];
    [d lift];

    CHECK(![d has:TUCGestureKindDragBegan], @"the first finger must not start a drag");
    CHECK([d has:TUCGestureKindScroll], @"should scroll");
    CHECK([d has:TUCGestureKindScrollEnd], @"should end the scroll");
    CHECK(![d has:TUCGestureKindTap], @"a scroll is not a tap");
}

static void testTwoFingerVerticalScrollFollowsTheFingers(void) {
    currentTest = @"two finger scroll";
    Driver *d = [Driver new];
    NSArray *pair = @[@[@1, @50, @60], @[@2, @70, @60]];
    [d hold:pair frames:5];
    [d move:pair dx:0 dy:30 frames:15];
    [d lift];

    double total = 0;
    for (NSValue *v in [d ofKind:TUCGestureKindScroll]) total += TUCGestureEventFromValue(v).delta.dy;
    // All the finger travel but the few mm spent deciding it is a scroll (not caught up in one jump).
    CHECK(total > (30 - 4) * kPPMM && total <= 30 * kPPMM + 0.001, @"scroll should follow the fingers after the decision, got %f", total);
    CHECK([d first:TUCGestureKindScroll].value == kPPMM, @"scroll carries points per mm");
    CHECK([d ofKind:TUCGestureKindScrollEnd].count == 1, @"one ScrollEnd");
}

static void testTwoFingerPinchOutZoomsIn(void) {
    currentTest = @"pinch";
    Driver *d = [Driver new];
    [d hold:@[@[@1, @100, @100], @[@2, @120, @100]] frames:5];
    for (int i = 1; i <= 15; i++) {
        [d frame:@[@[@1, @(100 - i), @100], @[@2, @(120 + i), @100]]];
    }
    [d lift];

    CHECK([d has:TUCGestureKindPinch], @"should pinch");
    double scale = 1;
    for (NSValue *v in [d ofKind:TUCGestureKindPinch]) scale *= TUCGestureEventFromValue(v).value;
    CHECK(fabs(scale - 50.0 / 20.0) < 0.01, @"scale should be 2.5, got %f", scale);
    CHECK([d has:TUCGestureKindPinchEnd], @"PinchEnd");
    CHECK(![d has:TUCGestureKindScroll], @"a pinch is not a scroll");
}

static void testTwoFingerRotate(void) {
    currentTest = @"rotate";
    Driver *d = [Driver new];
    // Two fingers 30 mm apart turning 45 degrees clockwise about their midpoint (100,100).
    for (int i = 0; i <= 20; i++) {
        double a = (i < 5 ? 0 : (i - 5) / 15.0) * M_PI / 4;
        [d frame:@[@[@1, @(100 - 15 * cos(a)), @(100 - 15 * sin(a))], @[@2, @(100 + 15 * cos(a)), @(100 + 15 * sin(a))]]];
    }
    [d lift];

    CHECK([d has:TUCGestureKindRotate], @"should rotate");
    double degrees = 0;
    for (NSValue *v in [d ofKind:TUCGestureKindRotate]) degrees += TUCGestureEventFromValue(v).value;
    CHECK(fabs(degrees - 45) < 1, @"should turn ~45 degrees clockwise, got %f", degrees);
    CHECK([d has:TUCGestureKindRotateEnd], @"RotateEnd");
}

static void testTwoFingerSidewaysIsAPageSwipeWhenOn(void) {
    currentTest = @"two finger page swipe";
    Driver *d = [Driver new];
    d.recognizer.pagesWithTwoFingers = YES;  // swipe between pages on the two-finger scroll (off by default)
    NSArray *pair = @[@[@1, @100, @60], @[@2, @100, @80]];
    [d hold:pair frames:5];
    [d move:pair dx:-40 dy:2 frames:15];
    [d lift];

    NSArray *swipes = [d ofKind:TUCGestureKindSwipe];
    CHECK(swipes.count > 2, @"should page-swipe");
    TUCGestureEvent first = TUCGestureEventFromValue(swipes.firstObject);
    TUCGestureEvent last = TUCGestureEventFromValue(swipes.lastObject);
    CHECK(first.phase == TUCGesturePhaseBegan && first.fingers == 2 && first.axis == TUCSwipeAxisHorizontal, @"began 2-finger horizontal");
    CHECK(last.phase == TUCGesturePhaseEnded && fabs(last.value + 40) < 0.001, @"ended at -40 mm, got %f", last.value);
    CHECK(![d has:TUCGestureKindScroll], @"not a scroll");

    currentTest = @"two finger sideways scroll when pages are off";
    Driver *off = [Driver new];
    off.recognizer.pagesWithTwoFingers = NO;
    [off hold:pair frames:5];
    [off move:pair dx:-40 dy:2 frames:15];
    [off lift];
    CHECK([off has:TUCGestureKindScroll], @"should scroll sideways");
    CHECK(![off has:TUCGestureKindSwipe], @"no page swipe");
}

static void testTwoFingersFromTheRightEdgeOpenNotificationCenter(void) {
    currentTest = @"edge swipe";
    Driver *d = [Driver new];
    NSArray *pair = @[@[@1, @295, @100], @[@2, @295, @120]];
    [d hold:pair frames:5];
    [d move:pair dx:-30 dy:1 frames:15];
    [d lift];

    CHECK([d has:TUCGestureKindEdgeSwipe], @"should edge-swipe");
    TUCGestureEvent end = [d last:TUCGestureKindEdgeSwipe];
    CHECK(end.phase == TUCGesturePhaseEnded && fabs(end.value - 30) < 0.001, @"ended with 30 mm inward, got %f", end.value);
    CHECK(![d has:TUCGestureKindSwipe], @"not a page swipe");
}


#pragma mark - Three and four fingers

static void testThreeFingerSwipeLeft(void) {
    currentTest = @"three finger horizontal swipe";
    Driver *d = [Driver new];
    NSArray *three = @[@[@1, @100, @100], @[@2, @120, @95], @[@3, @140, @100]];
    [d hold:three frames:5];
    [d move:three dx:-50 dy:3 frames:20];
    [d lift];

    NSArray *swipes = [d ofKind:TUCGestureKindSwipe];
    CHECK(swipes.count > 2, @"should swipe");
    TUCGestureEvent last = TUCGestureEventFromValue(swipes.lastObject);
    CHECK(last.fingers == 3 && last.axis == TUCSwipeAxisHorizontal && last.phase == TUCGesturePhaseEnded, @"3-finger horizontal end");
    CHECK(fabs(last.value + 50) < 0.001, @"travel -50, got %f", last.value);
    CHECK(![d has:TUCGestureKindTap], @"not a tap");
}

static void testFourFingerSwipeUp(void) {
    currentTest = @"four finger swipe up";
    Driver *d = [Driver new];
    NSArray *four = @[@[@1, @100, @100], @[@2, @120, @95], @[@3, @140, @95], @[@4, @160, @100]];
    [d hold:four frames:5];
    [d move:four dx:1 dy:-40 frames:20];
    [d lift];

    TUCGestureEvent last = [d last:TUCGestureKindSwipe];
    CHECK(last.fingers == 4 && last.axis == TUCSwipeAxisVertical, @"4-finger vertical, got fingers %ld axis %ld", last.fingers, last.axis);
    CHECK(fabs(last.value + 40) < 0.001, @"travel -40 (up), got %f", last.value);
}

static void testFourFingerPinchIn(void) {
    currentTest = @"four finger pinch";
    Driver *d = [Driver new];
    for (int i = 0; i <= 20; i++) {
        double k = i < 5 ? 1 : 1 - 0.5 * (i - 5) / 15.0;  // close to half the spread
        [d frame:@[@[@1, @(150 - 40 * k), @100], @[@2, @150, @(100 - 40 * k)], @[@3, @(150 + 40 * k), @100], @[@4, @150, @(100 + 40 * k)]]];
    }
    [d lift];

    TUCGestureEvent last = [d last:TUCGestureKindSwipe];
    CHECK(last.axis == TUCSwipeAxisPinch && last.fingers == 4, @"4-finger pinch, axis %ld fingers %ld", last.axis, last.fingers);
    CHECK(last.value < -15, @"spread should shrink ~20 mm, got %f", last.value);
}

static void testThreeThenFourFingersIsAFourFingerSwipe(void) {
    currentTest = @"3 -> 4 finger upgrade";
    Driver *d = [Driver new];
    NSArray *three = @[@[@1, @100, @100], @[@2, @120, @95], @[@3, @140, @100]];
    [d hold:three frames:5];
    [d move:three dx:-6 dy:0 frames:3];  // the three-finger swipe begins
    NSArray *four = @[@[@1, @94, @100], @[@2, @114, @95], @[@3, @134, @100], @[@4, @154, @105]];
    [d hold:four frames:5];
    [d move:four dx:-50 dy:0 frames:15];
    [d lift];

    NSArray *swipes = [d ofKind:TUCGestureKindSwipe];
    BOOL sawThreeEndAtZero = NO, sawFour = NO;
    for (NSValue *v in swipes) {
        TUCGestureEvent e = TUCGestureEventFromValue(v);
        if (e.fingers == 3 && e.phase == TUCGesturePhaseEnded && e.value == 0) sawThreeEndAtZero = YES;
        if (e.fingers == 4 && e.phase == TUCGesturePhaseEnded) sawFour = YES;
    }
    CHECK(sawThreeEndAtZero, @"the three-finger swipe should be taken back to 0 and ended");
    CHECK(sawFour, @"a four-finger swipe should follow");
}

static void testThreeFingerTap(void) {
    currentTest = @"three finger tap";
    Driver *d = [Driver new];
    [d hold:@[@[@1, @100, @100], @[@2, @120, @95], @[@3, @140, @100]] frames:10];
    [d lift];
    CHECK([d ofKind:TUCGestureKindTap].count == 1 && [d first:TUCGestureKindTap].fingers == 3, @"one 3-finger tap");
}


#pragma mark - Swipe translator

static NSArray<NSValue *> *Translate(TUCSwipeTranslator *t, TUCGesturePhase phase, NSInteger fingers, TUCSwipeAxis axis, double travel, double now) {
    return [t translatePhase:phase fingers:fingers axis:axis travel:travel now:now];
}

static TUCNativeSwipeEvent Native(NSValue *v) {
    TUCNativeSwipeEvent e;
    [v getValue:&e size:sizeof(e)];
    return e;
}

/// Settings with the swipes on the given finger counts, and pages on the given trigger.
static TUCGestureSettings *Swipes(NSInteger desktopsFingers, NSInteger missionControlFingers, BOOL pages, TUCPagesTrigger trigger) {
    TUCGestureSettings *s = [TUCGestureSettings defaultSettings];
    s.fullScreenAppsFingers = desktopsFingers;
    s.missionControlFingers = missionControlFingers;
    s.swipeBetweenPages = pages;
    s.pagesTrigger = trigger;
    return s;
}

static void testDefaultsAndRouting(void) {
    currentTest = @"framework defaults are the app's";
    TUCGestureSettings *d = [TUCGestureSettings defaultSettings];
    CHECK(!d.swipeBetweenPages && d.pagesTrigger == TUCPagesTriggerThreeFingerSwipe, @"pages off, three-finger trigger");
    CHECK(d.fullScreenAppsFingers == 4 && d.missionControlFingers == 4, @"full-screen apps and Mission Control on four fingers");
    CHECK(!d.lookUp && d.secondaryClick && d.zoom && d.smartZoom && d.rotate && d.notificationCenter, @"switches");

    currentTest = @"pages routing";
    CHECK(![d swipesBetweenPagesWithFingers:2] && ![d swipesBetweenPagesWithFingers:3], @"pages off: no finger count");
    TUCGestureSettings *two = Swipes(4, 4, YES, TUCPagesTriggerTwoFingerScroll);
    TUCGestureSettings *both = Swipes(4, 4, YES, TUCPagesTriggerTwoOrThreeFingerSwipe);
    TUCGestureSettings *three = Swipes(4, 4, YES, TUCPagesTriggerThreeFingerSwipe);
    CHECK([two swipesBetweenPagesWithFingers:2] && ![two swipesBetweenPagesWithFingers:3], @"two-finger scroll");
    CHECK([both swipesBetweenPagesWithFingers:2] && [both swipesBetweenPagesWithFingers:3], @"two or three");
    CHECK(![three swipesBetweenPagesWithFingers:2] && [three swipesBetweenPagesWithFingers:3], @"three-finger swipe");
    CHECK(![d usesThreeFingerVerticalSwipes] && [Swipes(4, 3, NO, TUCPagesTriggerThreeFingerSwipe) usesThreeFingerVerticalSwipes], @"three-finger vertical only on three");
}

static void testTranslatorCommitsALongSwipeUpAsMissionControl(void) {
    currentTest = @"translator mission control";
    TUCSwipeTranslator *t = [TUCSwipeTranslator new];  // defaults: Mission Control on four fingers
    double now = 0;
    NSMutableArray<NSValue *> *out = [NSMutableArray new];
    [out addObjectsFromArray:Translate(t, TUCGesturePhaseBegan, 4, TUCSwipeAxisVertical, 0, now)];
    for (int i = 1; i <= 20; i++) {
        now += 0.01;
        [out addObjectsFromArray:Translate(t, TUCGesturePhaseChanged, 4, TUCSwipeAxisVertical, -2.0 * i, now)];
    }
    [out addObjectsFromArray:Translate(t, TUCGesturePhaseEnded, 4, TUCSwipeAxisVertical, -40, now + 0.01)];

    TUCNativeSwipeEvent began = Native(out.firstObject);
    TUCNativeSwipeEvent end = Native(out.lastObject);
    CHECK(began.cgType == TUCEventTypeDockSwipe && began.phase == TUCPhaseBegan && began.progress < 0, @"Dock swipe begins upward (negative)");
    CHECK(Native(out[1]).hasFlavor && Native(out[1]).flavor == TUCFlavorUp, @"flavor up on the first change");
    CHECK(end.phase == TUCPhaseEnded && end.hasVelocity, @"commits with a velocity");
}

static void testTranslatorCancelsAShortSlowSwipe(void) {
    currentTest = @"translator cancel";
    TUCSwipeTranslator *t = [TUCSwipeTranslator new];  // defaults: full-screen apps on four fingers
    Translate(t, TUCGesturePhaseBegan, 4, TUCSwipeAxisHorizontal, 0, 0);
    Translate(t, TUCGesturePhaseChanged, 4, TUCSwipeAxisHorizontal, -3, 0.1);
    NSArray *end = Translate(t, TUCGesturePhaseEnded, 4, TUCSwipeAxisHorizontal, -3, 0.5);
    CHECK(Native(end.lastObject).phase == TUCPhaseCancelled, @"a 3 mm swipe is cancelled");
}

static void testTranslatorRoutesBySettings(void) {
    currentTest = @"translator routing";
    TUCSwipeTranslator *t = [TUCSwipeTranslator new];
    t.settings = Swipes(3, 3, YES, TUCPagesTriggerTwoFingerScroll);

    // Pages on two fingers: two-finger sideways = page swipe (navigation, type 29); full-screen apps on three fingers:
    // three-finger sideways = Dock swipe (type 30).
    Translate(t, TUCGesturePhaseBegan, 2, TUCSwipeAxisHorizontal, 0, 0);
    NSArray *pages = Translate(t, TUCGesturePhaseChanged, 2, TUCSwipeAxisHorizontal, 20, 0.05);
    CHECK(pages.count > 0 && Native(pages.firstObject).cgType == TUCEventTypeGesture && Native(pages.firstObject).subtype == TUCSubtypeNavigationSwipe, @"two-finger -> navigation swipe");
    Translate(t, TUCGesturePhaseEnded, 2, TUCSwipeAxisHorizontal, 20, 0.1);

    Translate(t, TUCGesturePhaseBegan, 3, TUCSwipeAxisHorizontal, 0, 1);
    NSArray *apps = Translate(t, TUCGesturePhaseChanged, 3, TUCSwipeAxisHorizontal, 20, 1.05);
    CHECK(apps.count > 0 && Native(apps.firstObject).cgType == TUCEventTypeDockSwipe, @"three-finger -> Dock swipe");
    Translate(t, TUCGesturePhaseEnded, 3, TUCSwipeAxisHorizontal, 20, 1.1);

    // Switched off: nothing is posted for the whole swipe.
    TUCGestureSettings *s = Swipes(3, 3, YES, TUCPagesTriggerTwoFingerScroll);
    s.missionControl = NO;
    t.settings = s;
    Translate(t, TUCGesturePhaseBegan, 3, TUCSwipeAxisVertical, 0, 2);
    NSArray *off = Translate(t, TUCGesturePhaseChanged, 3, TUCSwipeAxisVertical, -20, 2.05);
    NSArray *offEnd = Translate(t, TUCGesturePhaseEnded, 3, TUCSwipeAxisVertical, -20, 2.1);
    CHECK(off.count == 0 && offEnd.count == 0, @"Mission Control off: nothing posted");

    // Launchpad is a four-finger pinch in (progress positive).
    Translate(t, TUCGesturePhaseBegan, 4, TUCSwipeAxisPinch, 0, 3);
    NSArray *pinch = Translate(t, TUCGesturePhaseChanged, 4, TUCSwipeAxisPinch, -10, 3.05);
    CHECK(pinch.count == 2 && Native(pinch[0]).progress > 0 && Native(pinch[1]).flavor == TUCFlavorPinchIn, @"pinch in -> Launchpad direction");
    Translate(t, TUCGesturePhaseEnded, 4, TUCSwipeAxisPinch, -10, 3.1);

    // The defaults: a three-finger sideways swipe does nothing (pages off, full-screen apps on four).
    t.settings = [TUCGestureSettings defaultSettings];
    Translate(t, TUCGesturePhaseBegan, 3, TUCSwipeAxisHorizontal, 0, 4);
    CHECK(Translate(t, TUCGesturePhaseChanged, 3, TUCSwipeAxisHorizontal, 20, 4.05).count == 0, @"defaults: three-finger sideways is off");
}


#pragma mark - Dock swipe block (vectors from T650Native DockSwipeBlockTests)

static int32_t Word(NSData *d, NSUInteger at) {
    int32_t v;
    [d getBytes:&v range:NSMakeRange(at, 4)];
    return v;  // little-endian host
}

static NSData *Hex(NSString *s) {
    NSMutableData *d = [NSMutableData new];
    for (NSUInteger i = 0; i + 1 < s.length; i += 2) {
        unsigned int byte;
        [[NSScanner scannerWithString:[s substringWithRange:NSMakeRange(i, 2)]] scanHexInt:&byte];
        uint8_t b = (uint8_t)byte;
        [d appendBytes:&b length:1];
    }
    return d;
}

static void testDockBlockMatchesTheCasaLayout(void) {
    currentTest = @"dock block began";
    NSData *b = [TUCDockSwipeBlock buildWithTimestamp:0xb1fd3a289f2eULL kind:TUCSwipeKindVertical phase:TUCPhaseBegan progress:0.0181 progressDelta:0.0181 hasVelocity:NO velocity:0];
    uint64_t ts;
    [b getBytes:&ts range:NSMakeRange(0, 8)];
    CHECK(b.length == 68, @"size %lu", b.length);
    CHECK(ts == 0xb1fd3a289f2eULL, @"timestamp");
    CHECK(Word(b, 24) == 1 && Word(b, 28) == 40 && Word(b, 32) == 23, @"header words");
    CHECK(Word(b, 36) == 0x01000000, @"phase byte");
    CHECK(Word(b, 44) == 0 && Word(b, 48) < 0, @"vertical movement only, negative (up)");
    CHECK(Word(b, 60) == 0x00030002, @"axis + constant");
    CHECK(Word(b, 64) >= -1190 && Word(b, 64) <= -1180, @"progress fixed 16.16, got %d", Word(b, 64));

    currentTest = @"dock block ended";
    NSData *e = [TUCDockSwipeBlock buildWithTimestamp:1 kind:TUCSwipeKindVertical phase:TUCPhaseEnded progress:1.0 progressDelta:0.1 hasVelocity:YES velocity:3.739];
    CHECK(e.length == 96, @"size %lu", e.length);
    CHECK(Word(e, 24) == 2 && Word(e, 36) == 0x04000000 && Word(e, 64) == -65536, @"end header");
    CHECK(Word(e, 68) == 28 && Word(e, 72) == 9 && Word(e, 80) == 1, @"velocity child header");
    CHECK(Word(e, 84) >= -245050 && Word(e, 84) <= -245020 && Word(e, 84) == Word(e, 88) && Word(e, 92) == 0, @"velocity %d", Word(e, 84));
}

static void testDockBlockInsertion(void) {
    currentTest = @"dock block insert";
    NSData *ev = Hex(@"0000000200014035000000000001403600000000000140370000001e0002c0384407c800414fc0000002c03900000000000000000001003a0000000000000000"
                     "0001403b00000000000140330000000000014034000000000001406a000000000001406b000000000001406e000000170001406f000000000001407000000000"
                     "0001408400000001000140850000000000014073000000000001407b0000000200014086000000000001c07c3ca3d70a0001c07d000000000001c07e00000000"
                     "0001c081000000000001c082000000000001c0830000000000014088000000000001408a00000000");
    NSData *block = [TUCDockSwipeBlock buildWithTimestamp:1 kind:TUCSwipeKindVertical phase:TUCPhaseBegan progress:0.02 progressDelta:0.02 hasVelocity:NO velocity:0];
    NSData *result = [TUCDockSwipeBlock insertBlock:block intoSerializedEvent:ev];
    CHECK(result != nil && result.length == ev.length + 4 + block.length, @"length");

    uint8_t marker[4] = {0x00, 0x44, 0x10, 0x6d};
    NSRange at = [result rangeOfData:[NSData dataWithBytes:marker length:4] options:0 range:NSMakeRange(0, result.length)];
    CHECK(at.location != NSNotFound, @"block header present");
    if (at.location != NSNotFound) {
        uint8_t after[4];
        [result getBytes:after range:NSMakeRange(at.location + 4 + block.length, 4)];
        CHECK(after[0] == 0x00 && after[1] == 0x01 && after[2] == 0x40 && after[3] == 0x6e, @"block sits right before field 110");
        CHECK([[result subdataWithRange:NSMakeRange(at.location + 4, block.length)] isEqualToData:block], @"block bytes intact");
    }

    NSData *again = [TUCDockSwipeBlock insertBlock:[TUCDockSwipeBlock buildWithTimestamp:2 kind:2 phase:2 progress:0.05 progressDelta:0.03 hasVelocity:NO velocity:0] intoSerializedEvent:result];
    CHECK(again.length == result.length, @"an existing block is replaced, not duplicated");

    uint8_t garbage1[] = {0, 0, 0, 2, 0, 9, 0x40};
    uint8_t garbage2[] = {0, 0, 0, 2, 0, 1, 0x20, 0x01, 0, 0, 0, 0};
    CHECK([TUCDockSwipeBlock insertBlock:block intoSerializedEvent:[NSData dataWithBytes:garbage1 length:sizeof(garbage1)]] == nil, @"truncated -> nil");
    CHECK([TUCDockSwipeBlock insertBlock:block intoSerializedEvent:[NSData dataWithBytes:garbage2 length:sizeof(garbage2)]] == nil, @"unknown unit -> nil");
}


#pragma mark - Momentum and clicks

static void testMomentumCoastsAndStops(void) {
    currentTest = @"momentum";
    TUCScrollMomentum *m = [TUCScrollMomentum new];
    m.pointsPerMM = 4;
    CHECK(![m startWithVelocity:CGVectorMake(0, 50)], @"12.5 mm/s is too slow to coast");
    CHECK([m startWithVelocity:CGVectorMake(0, 800)], @"200 mm/s coasts");
    double total = 0;
    BOOL last = NO;
    int steps = 0;
    while (!last && steps < 10000) { total += [m step:0.008 last:&last].dy; steps++; }
    CHECK(last && !m.active, @"comes to rest");
    CHECK(total > 100 && total < 2000, @"coasts a plausible distance, got %f pt in %d steps", total, steps);
}

static void testScrollBoost(void) {
    currentTest = @"scroll boost";
    CHECK(TUCScrollBoost(0) == 1 && TUCScrollBoost(70) == 1, @"slow strokes follow the fingers");
    CHECK(TUCScrollBoost(170) > 1 && TUCScrollBoost(170) < 6, @"ramps between");
    CHECK(TUCScrollBoost(270) == 6 && TUCScrollBoost(1000) == 6, @"6x at full speed");
}

static void testClickCounter(void) {
    currentTest = @"click counter";
    TUCClickCounter *c = [TUCClickCounter new];
    c.radiusPoints = 20;
    CHECK([c pressAt:CGPointMake(0, 0) now:0] == 1, @"first");
    CHECK([c pressAt:CGPointMake(5, 5) now:0.2] == 2, @"double");
    CHECK([c pressAt:CGPointMake(5, 5) now:0.4] == 3, @"triple");
    CHECK([c pressAt:CGPointMake(100, 5) now:0.5] == 1, @"too far");
    CHECK([c pressAt:CGPointMake(100, 5) now:2] == 1, @"too late");
    [c pressForDragAt:CGPointMake(0, 0) now:3];
    CHECK([c pressAt:CGPointMake(0, 0) now:3.1] == 2, @"a drag press counts as the first click");
}



#pragma mark - Replays of real strokes

/// One stroke from a recording (Magic Touch Up run with TOUCHUP_RECORD=1): the frames from first contact to all lifted.
typedef struct {
    NSInteger swipesBegan;      // how many swipes the recognizer began with the stroke's final finger count
    NSInteger fingers;          // of the last swipe
    TUCSwipeAxis axis;
    double travel;              // the last swipe's travel when it ended
    BOOL committed;             // the native swipe it became ended committed (phase 4), with the given settings
    BOOL posted;                // anything native was posted for it
} StrokeOutcome;

static NSArray<NSArray<NSString *> *> *LoadStrokes(NSString *path) {
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    NSMutableArray *strokes = [NSMutableArray new];
    NSMutableArray *current = nil;
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSArray<NSString *> *p = [line componentsSeparatedByString:@" "];
        if (p.count < 3 || ![p[0] isEqualToString:@"F"]) continue;
        if (p[2].integerValue > 0) {
            if (current == nil) { current = [NSMutableArray new]; [strokes addObject:current]; }
            [current addObject:line];
        } else if (current != nil) {
            [current addObject:line];
            current = nil;
        }
    }
    return strokes;
}

/// Feeds a stroke's recorded frames ("F time count id:x,y ...", in mm) to a recognizer, ending with a lift if the
/// recording did not. Positions are scaled by `scale` (to correct a recording made with a wrong screen size), and the
/// screen is `screenWidthMM` wide at `pointsPerMM`.
static void ReplayFrames(NSArray<NSString *> *frames, TUCGestureRecognizer *recognizer, CGSize scale, double screenWidthMM,
                         double pointsPerMM, void (^handle)(TUCGestureEvent event, double now)) {
    NSMutableArray<NSString *> *all = [frames mutableCopy];
    NSArray<NSString *> *lastParts = [all.lastObject componentsSeparatedByString:@" "];
    if (lastParts[2].integerValue != 0) [all addObject:[NSString stringWithFormat:@"F %f 0", lastParts[1].doubleValue + 0.01]];

    for (NSString *line in all) {
        NSArray<NSString *> *p = [line componentsSeparatedByString:@" "];
        double now = p[1].doubleValue;
        NSInteger n = MIN(p[2].integerValue, 16);
        TUCContact contacts[16];
        for (NSInteger i = 0; i < n; i++) {
            NSArray<NSString *> *idAndXY = [p[3 + i] componentsSeparatedByString:@":"];
            NSArray<NSString *> *xy = [idAndXY[1] componentsSeparatedByString:@","];
            contacts[i].identifier = idAndXY[0].integerValue;
            contacts[i].mm = CGPointMake(xy[0].doubleValue * scale.width, xy[1].doubleValue * scale.height);
            contacts[i].point = CGPointMake(contacts[i].mm.x * pointsPerMM, contacts[i].mm.y * pointsPerMM);
        }
        for (NSValue *v in [recognizer handleContacts:(n ? contacts : NULL) count:n time:now screenWidthMM:screenWidthMM pointsPerMM:pointsPerMM]) {
            handle(TUCGestureEventFromValue(v), now);
        }
    }
}

static StrokeOutcome ReplayStroke(NSArray<NSString *> *frames, TUCGestureSettings *settings, CGSize scale, NSInteger fingers) {
    TUCGestureRecognizer *r = [TUCGestureRecognizer new];
    [r applySettings:settings];
    TUCSwipeTranslator *t = [TUCSwipeTranslator new];
    t.settings = settings;
    __block StrokeOutcome o = {0};

    ReplayFrames(frames, r, scale, 677 * scale.width, 1024 / (677 * scale.width), ^(TUCGestureEvent e, double now) {
            if (e.kind != TUCGestureKindSwipe || e.fingers < 3) return;
            // A three-finger swipe that a late fourth finger takes over is cancelled and restarted: count only the final one.
            if (e.phase == TUCGesturePhaseBegan && e.fingers == fingers) o.swipesBegan++;
            o.fingers = e.fingers;
            o.axis = e.axis;
            o.travel = e.value;
            for (NSValue *nv in [t translatePhase:e.phase fingers:e.fingers axis:e.axis travel:e.value now:now]) {
                TUCNativeSwipeEvent native = Native(nv);
                o.posted = YES;
                if (native.phase == TUCPhaseEnded) o.committed = YES;
                if (native.phase == TUCPhaseCancelled) o.committed = NO;
            }
    });
    return o;
}

/// Real strokes on a 7" 1024 x 600 JRP7813S (USB2IIC_CTP_CONTROL controller), which drops a contact for 40-200 ms now
/// and then and lands fingers up to ~130 ms apart. Labelled from their net movement.
///
/// The panel's EDID claims 677 x 381 mm (31"), and the recording was made in those units; the real visible area is
/// about 154 x 86 mm, so the frames are scaled to it (the "Screen size" setting does the same in the app).
static void testRecordedMultiFingerStrokes(void) {
    NSString *path = [[NSString stringWithUTF8String:__FILE__].stringByDeletingLastPathComponent
                      stringByAppendingPathComponent:@"Fixtures/jrp7813s-multifinger-20261122.txt"];
    NSArray<NSArray<NSString *> *> *strokes = LoadStrokes(path);
    currentTest = @"recording loads";
    CHECK(strokes.count == 24, @"strokes: %lu", strokes.count);
    if (strokes.count != 24) return;

    // Swipes routed for the finger counts each stroke used, so every one of them should post and commit. Strokes 0, 1
    // and 16 are left out: short, unclear strokes (0.12-0.34 s) whose intended gesture cannot be told from the data.
    TUCGestureSettings *threeFingers = Swipes(3, 3, NO, TUCPagesTriggerTwoFingerScroll);
    TUCGestureSettings *fourFingers = Swipes(4, 4, NO, TUCPagesTriggerTwoFingerScroll);

    struct { int index; NSInteger fingers; TUCSwipeAxis axis; int sign; const char *label; } expected[] = {
        { 2, 3, TUCSwipeAxisHorizontal, -1, "3-finger left" },
        { 7, 3, TUCSwipeAxisHorizontal, -1, "3-finger left" },
        { 8, 3, TUCSwipeAxisHorizontal, -1, "3-finger left" },
        { 9, 3, TUCSwipeAxisHorizontal, -1, "3-finger left" },
        { 4, 3, TUCSwipeAxisHorizontal, +1, "3-finger right" },
        { 5, 3, TUCSwipeAxisHorizontal, +1, "3-finger right" },
        { 6, 3, TUCSwipeAxisHorizontal, +1, "3-finger right" },
        { 3, 4, TUCSwipeAxisVertical, -1, "4-finger up (a contact drops out)" },
        { 10, 4, TUCSwipeAxisVertical, -1, "4-finger up (a contact drops out)" },
        { 11, 4, TUCSwipeAxisVertical, -1, "4-finger up (a contact drops out)" },
        { 12, 4, TUCSwipeAxisVertical, -1, "4-finger up (fourth lands 130 ms late)" },
        { 13, 4, TUCSwipeAxisPinch, -1, "4-finger pinch in" },
        { 14, 4, TUCSwipeAxisPinch, -1, "4-finger pinch in" },
        { 15, 4, TUCSwipeAxisPinch, -1, "4-finger pinch in" },
        { 17, 4, TUCSwipeAxisPinch, -1, "4-finger pinch in" },
        { 18, 4, TUCSwipeAxisPinch, +1, "4-finger spread" },
        { 19, 4, TUCSwipeAxisPinch, +1, "4-finger spread" },
        { 20, 4, TUCSwipeAxisPinch, +1, "4-finger spread (a contact drops out)" },
        { 21, 4, TUCSwipeAxisPinch, +1, "4-finger spread" },
        { 22, 4, TUCSwipeAxisPinch, +1, "4-finger spread" },
        { 23, 4, TUCSwipeAxisPinch, +1, "4-finger spread (a contact drops out)" },
    };

    BOOL verbose = getenv("REPLAY_VERBOSE") != NULL;
    for (size_t i = 0; i < sizeof(expected) / sizeof(expected[0]); i++) {
        currentTest = [NSString stringWithFormat:@"stroke %d: %s", expected[i].index, expected[i].label];
        StrokeOutcome o = ReplayStroke(strokes[expected[i].index], expected[i].fingers == 4 ? fourFingers : threeFingers,
                                       CGSizeMake(154.0 / 677.0, 86.0 / 381.0), expected[i].fingers);
        if (verbose) {
            printf("  stroke %2d %-38s began=%ld fingers=%ld axis=%ld travel=%7.1f posted=%d committed=%d\n", expected[i].index, expected[i].label,
                   (long)o.swipesBegan, (long)o.fingers, (long)o.axis, o.travel, o.posted, o.committed);
        }
        CHECK(o.fingers == expected[i].fingers && o.axis == expected[i].axis, @"got fingers %ld axis %ld", (long)o.fingers, (long)o.axis);
        CHECK(o.swipesBegan == 1, @"one swipe per stroke, got %ld", (long)o.swipesBegan);
        CHECK(o.travel * expected[i].sign > 5, @"travel %.1f mm", o.travel);
        CHECK(o.posted && o.committed, @"posted %d committed %d", o.posted, o.committed);
    }
}

/// Real two-finger taps on the same screen (recorded at 7" scale): both fingers are down together for 0-57 ms, often
/// less than the time a finger count takes to settle. Each must still be a two-finger tap.
static void testRecordedTwoFingerTaps(void) {
    NSString *path = [[NSString stringWithUTF8String:__FILE__].stringByDeletingLastPathComponent
                      stringByAppendingPathComponent:@"Fixtures/jrp7813s-two-finger-taps-20261122.txt"];
    NSArray<NSArray<NSString *> *> *strokes = LoadStrokes(path);
    currentTest = @"recorded two-finger taps";
    CHECK(strokes.count == 24, @"strokes: %lu", strokes.count);

    __block NSInteger twoFingerTaps = 0, otherTaps = 0;
    for (NSArray<NSString *> *stroke in strokes) {
        ReplayFrames(stroke, [TUCGestureRecognizer new], CGSizeMake(1, 1), 154, 6.65, ^(TUCGestureEvent e, double now) {
            if (e.kind != TUCGestureKindTap) return;
            if (e.fingers == 2) twoFingerTaps++; else otherTaps++;
        });
    }
    CHECK(twoFingerTaps == 24 && otherTaps == 0, @"two-finger taps %ld, other taps %ld", (long)twoFingerTaps, (long)otherTaps);
}

static void testQuickTwoFingerTapIsStillTwoFingers(void) {
    currentTest = @"one-frame two-finger tap";
    Driver *d = [Driver new];
    [d frame:@[@[@1, @50, @60], @[@2, @70, @60]]];
    [d lift];
    CHECK([d ofKind:TUCGestureKindTap].count == 1 && [d first:TUCGestureKindTap].fingers == 2, @"a two-finger tap shorter than the settle time is still two fingers");

    currentTest = @"one-finger tap with a one-frame second contact late in a long touch stays a click";
    Driver *e = [Driver new];
    [e hold:@[@[@1, @50, @60]] frames:20];
    [e frame:@[@[@1, @50, @60], @[@2, @52, @61]]];
    [e lift];
    CHECK([e ofKind:TUCGestureKindTap].count == 1 && [e first:TUCGestureKindTap].fingers == 1,
          @"expected one one-finger tap, got %lu taps", [e ofKind:TUCGestureKindTap].count);
}

static void testFourFingersLandingInOneFrameMeasureFromWhereTheyLanded(void) {
    currentTest = @"four fingers landing in the first frame";
    Driver *d = [Driver new];
    NSArray *four = @[@[@1, @100, @100], @[@2, @120, @95], @[@3, @140, @95], @[@4, @160, @100]];
    // All four land together, then move straight up 3 mm a frame: the first move happens before the count settles.
    [d frame:four];
    [d move:four dx:0 dy:-30 frames:10];
    [d lift];
    TUCGestureEvent last = [d last:TUCGestureKindSwipe];
    CHECK(last.axis == TUCSwipeAxisVertical && fabs(last.value + 30) < 0.01, @"travel should be the whole -30 mm, got %f", last.value);
}

static void testScrollVelocityOfAShortFlick(void) {
    currentTest = @"short flick velocity";
    TUCScrollVelocity *v = [TUCScrollVelocity new];
    // 40 ms of 10 pt every 10 ms: 1000 pt/s, whatever the 100 ms window.
    for (int i = 0; i < 4; i++) [v addDx:0 dy:10 now:1.0 + i * 0.01];
    CGVector speed = [v velocityAt:1.03];
    CHECK(fabs(speed.dy - 1000) < 100, @"a 40 ms flick reads at its own speed, got %f pt/s", speed.dy);

    TUCScrollVelocity *steady = [TUCScrollVelocity new];
    for (int i = 0; i < 30; i++) [steady addDx:0 dy:5 now:2.0 + i * 0.01];
    CHECK(fabs([steady velocityAt:2.29].dy - 500) < 50, @"a steady scroll reads 500 pt/s, got %f", [steady velocityAt:2.29].dy);
    CHECK([steady velocityAt:2.40].dy == 0, @"stopped before lifting: no speed");
}

int main(void) {
    @autoreleasepool {
        testOneFingerTapClicksWhereItLanded();
        testOneFingerMovePressesAtOriginAndDrags();
        testOneFingerLongPressPressesTheButton();
        testDragFollowsItsFingerWhenASecondLands();
        testTwoFingerTapIsATwoFingerTap();
        testStaggeredLandingIsStillTwoFingers();
        testTwoFingerVerticalScrollFollowsTheFingers();
        testTwoFingerPinchOutZoomsIn();
        testTwoFingerRotate();
        testTwoFingerSidewaysIsAPageSwipeWhenOn();
        testTwoFingersFromTheRightEdgeOpenNotificationCenter();
        testThreeFingerSwipeLeft();
        testFourFingerSwipeUp();
        testFourFingerPinchIn();
        testThreeThenFourFingersIsAFourFingerSwipe();
        testThreeFingerTap();
        testTranslatorCommitsALongSwipeUpAsMissionControl();
        testTranslatorCancelsAShortSlowSwipe();
        testTranslatorRoutesBySettings();
        testDockBlockMatchesTheCasaLayout();
        testDockBlockInsertion();
        testMomentumCoastsAndStops();
        testClickCounter();
        testScrollBoost();
        testDefaultsAndRouting();
        testFourFingersLandingInOneFrameMeasureFromWhereTheyLanded();
        testScrollVelocityOfAShortFlick();
        testRecordedMultiFingerStrokes();
        testRecordedTwoFingerTaps();
        testQuickTwoFingerTapIsStillTwoFingers();

        printf("%d checks, %d failed\n", checks, failures);
        return failures == 0 ? 0 : 1;
    }
}
