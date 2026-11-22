//
//  TUCGestureSettings.m
//  Touch Up Core
//

#import "TUCGestureSettings.h"

@implementation TUCGestureSettings

- (instancetype)init {
    if (self = [super init]) {
        _naturalScrolling = YES;
        _scrollMomentum = YES;

        _secondaryClick = YES;
        _lookUp = NO;

        _zoom = YES;
        _smartZoom = YES;
        _rotate = YES;

        _swipeBetweenPages = YES;
        _pagesTrigger = TUCPagesTriggerTwoFingerScroll;
        _swipeBetweenFullScreenApps = YES;
        _fullScreenAppsFingers = 3;
        _missionControl = YES;
        _appExpose = YES;
        _missionControlFingers = 3;
        _launchpad = YES;
        _showDesktop = YES;
        _notificationCenter = YES;
    }
    return self;
}

+ (instancetype)defaultSettings {
    return [[self alloc] init];
}

- (id)copyWithZone:(NSZone *)zone {
    TUCGestureSettings *c = [[[self class] allocWithZone:zone] init];
    c.naturalScrolling = self.naturalScrolling;
    c.scrollMomentum = self.scrollMomentum;
    c.secondaryClick = self.secondaryClick;
    c.lookUp = self.lookUp;
    c.zoom = self.zoom;
    c.smartZoom = self.smartZoom;
    c.rotate = self.rotate;
    c.swipeBetweenPages = self.swipeBetweenPages;
    c.pagesTrigger = self.pagesTrigger;
    c.swipeBetweenFullScreenApps = self.swipeBetweenFullScreenApps;
    c.fullScreenAppsFingers = self.fullScreenAppsFingers;
    c.missionControl = self.missionControl;
    c.appExpose = self.appExpose;
    c.missionControlFingers = self.missionControlFingers;
    c.launchpad = self.launchpad;
    c.showDesktop = self.showDesktop;
    c.notificationCenter = self.notificationCenter;
    return c;
}

@end
