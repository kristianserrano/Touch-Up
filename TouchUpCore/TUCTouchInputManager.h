//
//  TUCTouchInputManager.h
//  Touch Up Core
//
//  Created by Sebastian Hueber on 03.02.23.
//

#import <AppKit/AppKit.h>
#import <TouchUpCore/TUCTouchDelegate.h>
#import <TouchUpCore/TUCTouch.h>
#import <TouchUpCore/TUCGestureSettings.h>

NS_ASSUME_NONNULL_BEGIN



@interface TUCTouchInputManager : NSObject

@property (weak, nonatomic) id<TUCTouchDelegate> delegate;

@property (strong, atomic) NSMutableSet<TUCTouch *> *touchSet;

/**
 Whether touches are turned into clicks and gestures at all (mouse, scroll, native gesture and key events).
 Turning it off lets go of anything held. The default value is YES.
 */
@property (nonatomic) BOOL postMouseEvents;

/**
 Which Magic Trackpad style gestures are on. Copied on set.
 */
@property (copy, nonatomic) TUCGestureSettings *gestureSettings;


/**
 The maximal distance in mm that two taps may be apart from each other to count as double click
 */
@property CGFloat doubleClickTolerance;

/**
 How long one finger has to rest without moving before it presses the mouse button (press and hold).
 The default value is 0.5 s.
 */
@property (nonatomic) NSTimeInterval longPressDuration;

/**
 How far in mm one finger has to travel before it presses the mouse button and drags.
 Below this, lifting the finger is a click. The default value is 3 mm.
 */
@property (nonatomic) CGFloat dragThreshold;

/**
 The maximum distance in mm a touch may travel between two reports while still counting as
 stationary. Only affects the phase shown for each touch in the debug view.
 */
@property CGFloat stationaryThreshold;

/**
 Width in points of a border along each screen edge in which the cursor is never posted.
 Touches inside this border are pushed inwards to its inner edge. The default value is 0 (off).
 */
@property CGFloat edgeDeadZone;

/**
 If a touch is no longer reported by the screen, wait for this number of incoming reports bevore deleting it from the touch set.
 */
@property NSInteger errorResistance;


/**
 If a touchscreen sometimes sends invalid touch data at location (0,0), activate this option to ignore them
 */
@property BOOL ignoreOriginTouches;


- (void)start;

- (void)stop;


/**
 Opt-in exclusive access. When YES, connected touchscreens are seized so macOS and other
 apps no longer receive their events — Magic Touch Up becomes the sole handler. Default is NO.
 Applies immediately to currently-connected devices and  future connections.
 */
- (void)setTouchscreensSeized:(BOOL)seized;


- (void)triggerSystemAccessibilityAccessAlert;

@end

NS_ASSUME_NONNULL_END
