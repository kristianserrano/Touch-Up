//
//  TUCGestureSettings.h
//  Touch Up Core
//
//  Which Magic Trackpad style gestures are on, and how they are triggered.
//  Modelled on System Settings > Trackpad, and on the T650Native project's gesture settings.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// How "Swipe between pages" is performed.
typedef NS_ENUM(NSInteger, TUCPagesTrigger) {
    TUCPagesTriggerTwoFingerScroll = 0,       // scroll left or right with two fingers (the Magic Trackpad default)
    TUCPagesTriggerThreeFingerSwipe = 1,      // swipe with three fingers
    TUCPagesTriggerTwoOrThreeFingerSwipe = 2, // either
};

@interface TUCGestureSettings : NSObject <NSCopying>

#pragma mark Scrolling

/// Content follows the fingers. Off: the opposite, like a scroll wheel.
@property BOOL naturalScrolling;
/// A two-finger scroll keeps coasting for a moment after the fingers lift.
@property BOOL scrollMomentum;

#pragma mark Point & Click

/// Tap with two fingers for a secondary click.
@property BOOL secondaryClick;
/// Tap with three fingers to look up the word under the fingers (Control-Command-D).
@property BOOL lookUp;

#pragma mark Scroll & Zoom

/// Pinch with two fingers to zoom.
@property BOOL zoom;
/// Double-tap with two fingers to smart zoom.
@property BOOL smartZoom;
/// Rotate two fingers.
@property BOOL rotate;

#pragma mark More Gestures

@property BOOL swipeBetweenPages;
@property TUCPagesTrigger pagesTrigger;

@property BOOL swipeBetweenFullScreenApps;
/// 3 or 4.
@property NSInteger fullScreenAppsFingers;

/// Swipe up. Shares its finger count with App Exposé, as macOS does.
@property BOOL missionControl;
/// Swipe down.
@property BOOL appExpose;
/// 3 or 4, for both Mission Control and App Exposé.
@property NSInteger missionControlFingers;

/// Pinch with thumb and three fingers.
@property BOOL launchpad;
/// Spread with thumb and three fingers.
@property BOOL showDesktop;

/// Swipe left from the right edge with two fingers.
@property BOOL notificationCenter;

+ (instancetype)defaultSettings;

@end

NS_ASSUME_NONNULL_END
