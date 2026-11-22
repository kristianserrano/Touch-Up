//
//  GestureTests.m
//  Touch Up Core tests
//
//  Tests for the pure gesture logic (TUCGestureRecognizer, TUCSwipeTranslator, TUCDockSwipeBlock, momentum).
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
    CHECK(fabs(total - 30 * kPPMM) < 0.001, @"scroll should total the finger travel in points (120), got %f", total);
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

static void testTranslatorCommitsALongSwipeUpAsMissionControl(void) {
    currentTest = @"translator mission control";
    TUCSwipeTranslator *t = [TUCSwipeTranslator new];
    double now = 0;
    NSMutableArray<NSValue *> *out = [NSMutableArray new];
    [out addObjectsFromArray:Translate(t, TUCGesturePhaseBegan, 3, TUCSwipeAxisVertical, 0, now)];
    for (int i = 1; i <= 20; i++) {
        now += 0.01;
        [out addObjectsFromArray:Translate(t, TUCGesturePhaseChanged, 3, TUCSwipeAxisVertical, -2.0 * i, now)];
    }
    [out addObjectsFromArray:Translate(t, TUCGesturePhaseEnded, 3, TUCSwipeAxisVertical, -40, now + 0.01)];

    TUCNativeSwipeEvent began = Native(out.firstObject);
    TUCNativeSwipeEvent end = Native(out.lastObject);
    CHECK(began.cgType == TUCEventTypeDockSwipe && began.phase == TUCPhaseBegan && began.progress < 0, @"Dock swipe begins upward (negative)");
    CHECK(Native(out[1]).hasFlavor && Native(out[1]).flavor == TUCFlavorUp, @"flavor up on the first change");
    CHECK(end.phase == TUCPhaseEnded && end.hasVelocity, @"commits with a velocity");
}

static void testTranslatorCancelsAShortSlowSwipe(void) {
    currentTest = @"translator cancel";
    TUCSwipeTranslator *t = [TUCSwipeTranslator new];
    Translate(t, TUCGesturePhaseBegan, 3, TUCSwipeAxisHorizontal, 0, 0);
    Translate(t, TUCGesturePhaseChanged, 3, TUCSwipeAxisHorizontal, -3, 0.1);
    NSArray *end = Translate(t, TUCGesturePhaseEnded, 3, TUCSwipeAxisHorizontal, -3, 0.5);
    CHECK(Native(end.lastObject).phase == TUCPhaseCancelled, @"a 3 mm swipe is cancelled");
}

static void testTranslatorRoutesBySettings(void) {
    currentTest = @"translator routing";
    TUCSwipeTranslator *t = [TUCSwipeTranslator new];

    // Defaults: two-finger sideways = page swipe (navigation, type 29), three-finger sideways = full-screen apps (Dock, type 30).
    Translate(t, TUCGesturePhaseBegan, 2, TUCSwipeAxisHorizontal, 0, 0);
    NSArray *pages = Translate(t, TUCGesturePhaseChanged, 2, TUCSwipeAxisHorizontal, 20, 0.05);
    CHECK(pages.count > 0 && Native(pages.firstObject).cgType == TUCEventTypeGesture && Native(pages.firstObject).subtype == TUCSubtypeNavigationSwipe, @"two-finger -> navigation swipe");
    Translate(t, TUCGesturePhaseEnded, 2, TUCSwipeAxisHorizontal, 20, 0.1);

    Translate(t, TUCGesturePhaseBegan, 3, TUCSwipeAxisHorizontal, 0, 1);
    NSArray *apps = Translate(t, TUCGesturePhaseChanged, 3, TUCSwipeAxisHorizontal, 20, 1.05);
    CHECK(apps.count > 0 && Native(apps.firstObject).cgType == TUCEventTypeDockSwipe, @"three-finger -> Dock swipe");
    Translate(t, TUCGesturePhaseEnded, 3, TUCSwipeAxisHorizontal, 20, 1.1);

    // Switched off: nothing is posted for the whole swipe.
    TUCGestureSettings *s = [TUCGestureSettings defaultSettings];
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

        printf("%d checks, %d failed\n", checks, failures);
        return failures == 0 ? 0 : 1;
    }
}
