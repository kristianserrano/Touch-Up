//
//  TUCGestureRecognizer.h
//  Touch Up Core
//
//  Contact frames -> gesture intents, for a touchscreen (direct input). Pure logic: no OS calls, so it is tested.
//
//  The multi-finger part is a port of T650Native's GestureRecognizer (src/T650Native/Touch/GestureRecognizer.cs),
//  which follows the Magic Trackpad: a touch "session" runs from first contact down to all contacts up, and behaviour
//  follows the *settled* finger count, so fingers landing a moment apart never change the mode.
//
//   - 1 finger: direct manipulation. A tap clicks where the finger touched; moving past the drag slop (or holding still
//     for the long-press time) presses the left button there and drags with the finger.
//   - 2 fingers: scroll, pinch (zoom), rotate, swipe between pages, or an edge swipe from the right (Notification
//     Center), decided once from net motion and latched. A tap is a secondary click (a double tap is smart zoom).
//   - 3-4 fingers: swipes (full-screen apps, Mission Control, App Exposé; 4-finger pinch for Launchpad and Show
//     Desktop). A three-finger tap is Look Up.
//
//  Distances are millimetres on the glass; points are global screen coordinates (top-left origin).
//

#import <Foundation/Foundation.h>
#import "TUCNativeGesture.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TUCGestureKind) {
    TUCGestureKindTouchBegan,  // point: where the first finger landed
    TUCGestureKindDragBegan,   // point: where the button goes down
    TUCGestureKindDragMoved,   // point
    TUCGestureKindDragEnded,   // point: where the button comes up
    TUCGestureKindTap,         // fingers, point
    TUCGestureKindScroll,      // delta (points, +right/+down finger movement), point (pair midpoint), value = points per mm
    TUCGestureKindScrollEnd,
    TUCGestureKindPinch,       // value: multiplicative scale since the last event, point (midpoint)
    TUCGestureKindPinchEnd,
    TUCGestureKindRotate,      // value: degrees, positive = clockwise on screen, point (midpoint)
    TUCGestureKindRotateEnd,
    TUCGestureKindSwipe,       // phase, fingers, axis, value = net travel in mm (+right, +down, +spread out), point (centroid)
    TUCGestureKindEdgeSwipe,   // phase, value = inward (leftward) travel in mm from the right edge
};

typedef struct {
    TUCGestureKind kind;
    CGPoint point;
    CGVector delta;
    double value;
    NSInteger fingers;
    TUCGesturePhase phase;
    TUCSwipeAxis axis;
} TUCGestureEvent;

/// One finger at one instant.
typedef struct {
    NSInteger identifier;
    CGPoint mm;      // millimetres on the glass, in the screen's orientation (x right, y down)
    CGPoint point;   // global screen coordinates (points)
} TUCContact;


@interface TUCGestureRecognizer : NSObject

#pragma mark Tunables

@property double settleSeconds;          // how long a finger count must hold to count...
@property NSInteger settleFrames;        // ...or for this many reports, whichever comes first (fast screens settle sooner)
@property double dragSlopMM;             // one finger travelling this far presses the button and drags
@property double longPressSeconds;       // one finger held still this long presses the button (press and hold)
@property double tapMaxDuration;         // seconds, for two- and three-finger taps
@property double tapMaxTravelMM;         // for two- and three-finger taps
@property double modeDecisionTravelMM;   // motion before scroll / pinch / rotate / swipe is chosen
@property double multiSwipeTravelMM;     // four fingers: a stroke that is not a pinch waits for this much travel
@property double edgeMarginMM;           // two fingers starting this close to the right edge can edge-swipe
@property double pinchBias;              // two fingers: spread change must beat translation by this factor
@property double rotateBias;             // two fingers: rotation arc must beat translation by this factor
@property double multiPinchBias;         // four or more fingers: the same, lower (a thumb closing on three fingers moves the centroid)
@property double dragUpgradeSeconds;     // a three-finger swipe this young that gets a fourth finger was a four-finger one
@property double tapLandingSeconds;      // fingers down together within this long of the first count for a quick tap

#pragma mark Switches (from the settings)

/// A two-finger sideways stroke is a page swipe (Swipe between pages, two-finger trigger).
@property BOOL pagesWithTwoFingers;
/// A three-finger up/down swipe is reported (Mission Control / App Exposé on three fingers).
@property BOOL threeFingerVertical;

- (void)applySettings:(TUCGestureSettings *)settings;

#pragma mark Input

/**
 Feed one frame: every finger currently on the glass. Returns NSValue-wrapped TUCGestureEvent structs.
 An empty frame ends the session.
 */
- (NSArray<NSValue *> *)handleContacts:(const TUCContact *_Nullable)contacts
                                 count:(NSInteger)count
                                  time:(double)now
                         screenWidthMM:(double)screenWidthMM
                           pointsPerMM:(double)pointsPerMM;

/// Forget everything in flight, without saying anything.
- (void)reset;

@end

/// Unwraps an event from the array the recognizer returns.
static inline TUCGestureEvent TUCGestureEventFromValue(NSValue *value) {
    TUCGestureEvent e;
    [value getValue:&e size:sizeof(e)];
    return e;
}

NS_ASSUME_NONNULL_END
