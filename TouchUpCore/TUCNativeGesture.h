//
//  TUCNativeGesture.h
//  Touch Up Core
//
//  The pure (no OS calls) half of posting trackpad gestures: the undocumented CGEvent field numbers, the swipe
//  translator, the Dock swipe HID block that macOS 27 requires, double-click counting and scroll momentum.
//
//  Ported from T650Native (src/T650Native/Mac/NativeGesture.cs, SwipeTranslator.cs, DockSwipeBlock.cs and
//  ExclusiveMode.cs). None of the field numbers are documented by Apple: they were recorded from a Logitech
//  Casa Touch under Logi Options+. If a gesture stops working after a macOS update, these are what to re-record.
//

#import <Foundation/Foundation.h>
#import <time.h>
#import "TUCGestureSettings.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - CGEvent field numbers

// What kind of gesture the event is (field 110).
static const uint32_t TUCFieldSubtype = 110;
static const int64_t TUCSubtypeRotate = 5;
static const int64_t TUCSubtypeMagnify = 8;
static const int64_t TUCSubtypeSmartZoom = 22;
static const int64_t TUCSubtypeDockSwipe = 23;
static const int64_t TUCSubtypeNavigationSwipe = 16;

// Where it is in its life (field 132).
static const uint32_t TUCFieldPhase = 132;
static const int64_t TUCPhaseBegan = 1;
static const int64_t TUCPhaseChanged = 2;
static const int64_t TUCPhaseEnded = 4;
static const int64_t TUCPhaseCancelled = 8;

// The amount of a rotation (degrees) or magnification (a fraction), a double.
static const uint32_t TUCFieldAmount = 113;

// Swipe kinds.
static const int64_t TUCSwipeKindHorizontal = 1;
static const int64_t TUCSwipeKindVertical = 2;
static const int64_t TUCSwipeKindPinch = 3;

static const uint32_t TUCFieldSwipeKind = 123;
static const uint32_t TUCFieldSwipeKindCopy = 165;
static const uint32_t TUCFieldPhaseCopy = 134;
static const uint32_t TUCFieldProgressBits = 135;
static const uint32_t TUCFieldConstant136 = 136;
static const uint32_t TUCFieldConstant138 = 138;
static const uint32_t TUCFieldProgress = 124;
static const uint32_t TUCFieldKindFloat = 119;
static const uint32_t TUCFieldKindFloatCopy = 139;
static const uint32_t TUCFieldPhaseFloat = 120;
static const uint32_t TUCFieldPhaseFloatCopy = 140;
static const uint32_t TUCFieldFlavor = 115;
static const uint32_t TUCFieldFlavorCopy = 117;
static const uint32_t TUCFieldFlavorCopy2 = 164;
static const uint32_t TUCFieldVelocity = 129;
static const uint32_t TUCFieldVelocityCopy = 130;

// Direction flavors (sent on the first "changed" event of a swipe).
static const int64_t TUCFlavorUp = 1;
static const int64_t TUCFlavorDown = 2;
static const int64_t TUCFlavorLeft = 4;
static const int64_t TUCFlavorRight = 8;
static const int64_t TUCFlavorPinchOut = 16;
static const int64_t TUCFlavorPinchIn = 32;

// CGEvent types and the flags recorded gesture events carry.
static const uint32_t TUCEventTypeGesture = 29;     // rotate, magnify, smart zoom, navigation swipe
static const uint32_t TUCEventTypeDockSwipe = 30;
static const uint64_t TUCGestureFlags = 0x20000100;


#pragma mark - Shared helpers

/// Seconds of uptime: the clock the frames, the output and the timers all measure with.
static inline double TUCUptimeSeconds(void) {
    return (double)clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1e9;
}

/// Points per millimetre when a screen's size is unknown (~100 dpi).
static const double TUCFallbackPointsPerMM = 4;

/// Whether TOUCHUP_RECORD is set: the manager prints every frame and recognised event, the output what it does with
/// scrolling, to stdout (line-buffered by OpenHIDManager), for replaying real strokes in Tests/.
BOOL TUCRecordingEnabled(void);


#pragma mark - Swipes

typedef NS_ENUM(NSInteger, TUCSwipeAxis) {
    TUCSwipeAxisHorizontal,
    TUCSwipeAxisVertical,
    TUCSwipeAxisPinch,
};

typedef NS_ENUM(NSInteger, TUCGesturePhase) {
    TUCGesturePhaseBegan,
    TUCGesturePhaseChanged,
    TUCGesturePhaseEnded,
};

/// One native swipe event to post. cgType 30 = Dock swipe, 29 = navigation swipe.
typedef struct {
    uint32_t cgType;
    int64_t subtype;
    int64_t kind;
    int64_t phase;
    double progress;
    BOOL hasFlavor;
    int64_t flavor;
    BOOL hasVelocity;
    double velocity;
} TUCNativeSwipeEvent;

/**
 Turns swipe travel (millimetres on the glass) into native swipe events: signed progress, the direction carried on
 the begin event, a one-time flavor, and a commit-or-cancel decision with a release velocity.

 Progress is POSITIVE for fingers LEFT / DOWN / pinch IN and NEGATIVE for RIGHT / UP / spread OUT.
 */
@interface TUCSwipeTranslator : NSObject

/// Finger travel in mm that equals progress 1.0.
@property double horizontalFull;
@property double verticalFull;
@property double pinchFull;

@property (copy) TUCGestureSettings *settings;

/// Returns NSValue-wrapped TUCNativeSwipeEvent structs.
- (NSArray<NSValue *> *)translatePhase:(TUCGesturePhase)phase
                               fingers:(NSInteger)fingers
                                  axis:(TUCSwipeAxis)axis
                                travel:(double)travelMM
                                   now:(double)nowSeconds;

/// A swipe that has begun and not ended: its cancelled end event (empty if none is under way).
- (NSArray<NSValue *> *)cancel;

@end


#pragma mark - Dock swipe HID block

/**
 From macOS 27 a Dock swipe (type 30) is ignored unless it carries an embedded IOHIDEvent (DockSwipe) in data field
 109, which no setter reaches: the event is serialised, the block added, and the event rebuilt.
 */
@interface TUCDockSwipeBlock : NSObject

+ (NSData *)buildWithTimestamp:(uint64_t)timestamp
                          kind:(int64_t)kind
                         phase:(int64_t)phase
                      progress:(double)progress
                 progressDelta:(double)progressDelta
                   hasVelocity:(BOOL)hasVelocity
                      velocity:(double)velocity;

/// Adds (or replaces) the block in a serialised event. nil if the data does not parse.
+ (nullable NSData *)insertBlock:(NSData *)block intoSerializedEvent:(NSData *)serialized;

@end


#pragma mark - Clicks

/// Apps tell a double-click from two clicks by the click-state field: a second press within the double-click
/// interval and near the first counts as 2 (then 3).
@interface TUCClickCounter : NSObject
@property double intervalSeconds;
@property double radiusPoints;
- (int64_t)pressAt:(CGPoint)point now:(double)nowSeconds;
/// A press that starts a drag is always a single click (never the second of a double click); a press right after it
/// counts as the second.
- (int64_t)pressForDragAt:(CGPoint)point now:(double)nowSeconds;
@end


#pragma mark - Scroll momentum

/// Scroll acceleration for the fingers, fitted to a Mac trackpad's recorded strokes (T650Native's scripts/record-scroll.swift)
/// as TUCScrollVelocity measures them: up to 100 mm/s the content follows the fingers exactly, then up to 3x at 260 mm/s.
/// T650Native's numbers differ because it measures speed differently; do not copy them across.
double TUCScrollBoost(double millimetresPerSecond);

/// How much faster than the fingers the coasting starts, fitted the same way: 1.8x for a gentle stroke, 5x for a flick.
double TUCLaunchBoost(double millimetresPerSecond);

/// How fast the fingers were scrolling when they lifted (points per second). A finger that stopped and then lifted
/// must not fling the page.
@interface TUCScrollVelocity : NSObject
- (void)addDx:(double)dx dy:(double)dy now:(double)now;
- (CGVector)velocityAt:(double)now;
- (void)reset;
@end

/// The coasting after the fingers lift, as a Mac's trackpad coasts: it starts at the fingers' speed with TUCLaunchBoost, and slows
/// sooner the slower it gets. The steps are already boosted.
@interface TUCScrollMomentum : NSObject
/// Points per millimetre, so the thresholds (defined in mm/s) apply on any screen.
@property double pointsPerMM;
@property (readonly) BOOL active;
- (BOOL)startWithVelocity:(CGVector)velocity;
/// Advance by dt seconds: how far to scroll in that time; *last is set when it has come to rest.
- (CGVector)step:(double)dt last:(BOOL *)last;
- (void)cancel;
@end

NS_ASSUME_NONNULL_END
