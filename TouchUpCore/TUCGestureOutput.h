//
//  TUCGestureOutput.h
//  Touch Up Core
//
//  Recognizer events -> macOS events: mouse clicks and drags under the fingers, phased trackpad scrolling with
//  momentum, and the native gesture events a Magic Trackpad produces (magnify, rotate, smart zoom, navigation and
//  Dock swipes). A port of T650Native's GestureOutput and MacApi (src/T650Native/Mac/).
//
//  Main thread only: the HID callbacks, the momentum timer and the smart-zoom timer all run there.
//  Posting needs the Accessibility permission; without it macOS drops every event silently.
//

#import <AppKit/AppKit.h>
#import "TUCGestureRecognizer.h"

NS_ASSUME_NONNULL_BEGIN

@interface TUCGestureOutput : NSObject

@property (copy, nonatomic) TUCGestureSettings *settings;

/// Two taps this close (points) can be a double click.
@property double doubleClickTolerancePoints;

/// Inward travel (mm) from the right edge that opens Notification Center.
@property double edgeCommitMM;

/// How long a two-finger tap waits for a second one (smart zoom) before it right-clicks.
@property double smartZoomWindowSeconds;

- (void)post:(TUCGestureEvent)event;

/// When the touchscreen last sent a report (seconds of uptime). A scroll's lift speed is measured as of then: some screens
/// stop reporting when the fingers lift, and the lift is only noticed later.
@property double lastReportTime;

/// The touchscreen has been silent for a moment: the fingers have probably lifted. A scroll ends now and coasts, rather
/// than when the lift is confirmed; if the fingers move again, scrolling simply carries on.
- (void)fingersWentQuiet;

/// Called when posting is switched off or the app quits, so a half-finished gesture or a held button isn't left behind.
- (void)reset;

/// Posts a no-op cursor move, which makes macOS show its Accessibility prompt if the permission is missing.
- (void)nudgeCursor;

@end

NS_ASSUME_NONNULL_END
