//
//  TUCTouchInputManager.m
//  Touch Up Core
//
//  Created by Sebastian Hueber on 03.02.23.
//

#import "TUCTouchInputManager.h"

#import "HIDInterpreter.h"
#import "TUCGestureRecognizer.h"
#import "TUCGestureOutput.h"
#import "TUCTouchInputManager-C.h"

@interface TUCTouchInputManager ()

@property NSMutableDictionary<NSNumber *, NSNumber *> *frameIDsByLocationID;

/// Bumped on every report per digitizer; a lift check scheduled after a report only acts if no report came since.
@property NSMutableDictionary<NSNumber *, NSNumber *> *reportGenerationByLocationID;

/// One recognizer per digitizer, so fingers on two touchscreens never form one gesture.
@property NSMutableDictionary<NSNumber *, TUCGestureRecognizer *> *recognizersByLocationID;

/// Shared by all digitizers: there is one cursor.
@property (strong) TUCGestureOutput *output;

@end


@implementation TUCTouchInputManager

#pragma mark   Start & Stop

- (void)start {

    __weak id weakSelf = self;

    // needs to run on main anyway
//    [NSThread detachNewThreadWithBlock:^{
//        [NSThread setThreadPriority:1];
    OpenHIDManager((__bridge void *)(weakSelf));
//    }];

}

- (void)stop {
    // Let go of whatever is held, and make every pending lift check stale, so nothing is posted after stopping.
    [self.output reset];
    for (TUCGestureRecognizer *recognizer in self.recognizersByLocationID.allValues) {
        [recognizer reset];
    }
    for (NSNumber *locationID in self.reportGenerationByLocationID.allKeys) {
        [self invalidateLiftChecksForLocationID:locationID.unsignedIntValue];
    }
    CloseHIDManager();
}

- (void)setTouchscreensSeized:(BOOL)seized {
    SetTouchDevicesSeized(seized);
}


- (void)didConnectTouchscreenWithLocationID:(uint32_t)locationID {
    self.frameIDsByLocationID[@(locationID)] = @0;
    [self.delegate touchscreenDidConnectWithLocationID:locationID];
}

- (void)didDisconnectTouchscreenWithLocationID:(uint32_t)locationID {
    [self.frameIDsByLocationID removeObjectForKey:@(locationID)];
    [self.recognizersByLocationID removeObjectForKey:@(locationID)];
    [self invalidateLiftChecksForLocationID:locationID];

    // Its fingers are gone. A held button is let go whatever happens: the output does not know which touchscreen holds
    // it, and if it was this one, nothing else would release it (another screen's drag ends too, the lesser harm). The
    // rest of the output is reset unless another touchscreen is in the middle of a gesture.
    BOOL otherTouches = NO;
    for (TUCTouch *touch in [self.touchSet copy]) {
        if (touch.locationID == locationID) {
            [self.touchSet removeObject:touch];
        } else if (touch.isActive) {
            otherTouches = YES;
        }
    }
    if (otherTouches) {
        [self.output releaseHeldButton];
    } else {
        [self.output reset];
    }

    [self.delegate touchesDidChange];
    [self.delegate touchscreenDidDisconnectWithLocationID:locationID];
}


#pragma mark - Settings

- (void)setPostMouseEvents:(BOOL)postMouseEvents {
    if (_postMouseEvents && !postMouseEvents) {
        // Turned off mid-gesture: let go of whatever is held.
        [self.output reset];
        for (TUCGestureRecognizer *recognizer in self.recognizersByLocationID.allValues) {
            [recognizer reset];
        }
    }
    _postMouseEvents = postMouseEvents;
}

- (void)setGestureSettings:(TUCGestureSettings *)gestureSettings {
    _gestureSettings = [gestureSettings copy];
    self.output.settings = _gestureSettings;
    for (TUCGestureRecognizer *recognizer in self.recognizersByLocationID.allValues) {
        [recognizer applySettings:_gestureSettings];
    }
}

- (void)setLongPressDuration:(NSTimeInterval)longPressDuration {
    _longPressDuration = longPressDuration;
    for (TUCGestureRecognizer *recognizer in self.recognizersByLocationID.allValues) {
        recognizer.longPressSeconds = longPressDuration;
    }
}

- (void)setDragThreshold:(CGFloat)dragThreshold {
    _dragThreshold = dragThreshold;
    for (TUCGestureRecognizer *recognizer in self.recognizersByLocationID.allValues) {
        recognizer.dragSlopMM = dragThreshold;
    }
}

- (TUCGestureRecognizer *)recognizerForLocationID:(uint32_t)locationID {
    TUCGestureRecognizer *recognizer = self.recognizersByLocationID[@(locationID)];
    if (recognizer == nil) {
        recognizer = [TUCGestureRecognizer new];
        recognizer.longPressSeconds = self.longPressDuration;
        recognizer.dragSlopMM = self.dragThreshold;
        [recognizer applySettings:self.gestureSettings];
        self.recognizersByLocationID[@(locationID)] = recognizer;
    }
    return recognizer;
}



#pragma mark - Reacting to HID Events

- (NSInteger)currentFrameIDForLocationID:(uint32_t)locationID {
    return self.frameIDsByLocationID[@(locationID)].integerValue;
}

- (void)didProcessReportForLocationID:(uint32_t)locationID {
    // go through all touches: if the frame is not the latest one, the touch might be old and should be removed.
    NSInteger currentFrameID = [self currentFrameIDForLocationID:locationID];

    for (TUCTouch *touch in self.touchSet) {
        if (touch.locationID != locationID) continue;

        if (touch.lastUpdated + self.errorResistance < currentFrameID) {
            [touch setPhase:NSTouchPhaseCancelled];
            [self removeTouchLater:touch];
        }
    }

    self.frameIDsByLocationID[@(locationID)] = @(currentFrameID + 1);

    self.output.lastReportTime = TUCUptimeSeconds();
    [self processFrameForLocationID:locationID];
    [self scheduleLiftCheckForLocationID:locationID];
}


/**
 Some touchscreens stop sending reports when the last fingers lift, without a final "tip up" for each of them. The
 touches would then stay down until the next touch, mixing with its fingers (and a gesture session would never end).
 A touchscreen reports every few ms while anything touches it, even a finger held still, so silence means no fingers.
 */
static const NSTimeInterval TUCLiftTimeout = 0.35;

/// Silence this long (a few report intervals) probably means the fingers lifted: a scroll starts coasting then, without
/// waiting for the lift timeout.
static const NSTimeInterval TUCQuietTimeout = 0.07;

/// Makes the lift checks already scheduled for this digitizer stale. The counter moves on rather than being removed: a
/// counter that started again could reach a pending check's number and match it by chance.
- (void)invalidateLiftChecksForLocationID:(uint32_t)locationID {
    self.reportGenerationByLocationID[@(locationID)] = @(self.reportGenerationByLocationID[@(locationID)].integerValue + 1);
}

- (void)scheduleLiftCheckForLocationID:(uint32_t)locationID {
    NSInteger generation = self.reportGenerationByLocationID[@(locationID)].integerValue + 1;
    self.reportGenerationByLocationID[@(locationID)] = @(generation);

    __weak TUCTouchInputManager *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(TUCQuietTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        TUCTouchInputManager *strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf.reportGenerationByLocationID[@(locationID)].integerValue != generation) return;
        if (strongSelf.postMouseEvents) [strongSelf.output fingersWentQuiet];
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(TUCLiftTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        TUCTouchInputManager *strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf.reportGenerationByLocationID[@(locationID)].integerValue != generation) return;

        BOOL lifted = NO;
        for (TUCTouch *touch in [strongSelf activeTouches]) {
            if (touch.locationID != locationID) continue;
            [touch setPhase:NSTouchPhaseEnded];
            [strongSelf removeTouchLater:touch];
            lifted = YES;
        }
        if (lifted) {
            [strongSelf.delegate touchesDidChange];
            [strongSelf processFrameForLocationID:locationID];  // no fingers: ends the gesture
        }
    });
}


/**
 Hands every finger currently on this digitizer to its recognizer, and posts what it recognised.
 */
- (void)processFrameForLocationID:(uint32_t)locationID {
    if (!self.postMouseEvents) {
        return;
    }

    TUCScreen *screen = [self touchscreenForLocationID:locationID];
    if (screen == nil) {
        return;
    }

    NSArray<TUCTouch *> *touches = [[[self activeTouches] allObjects] sortedArrayUsingSelector:@selector(compareWithAnotherTouch:)];

    // Millimetres on the glass, for the gesture thresholds.
    CGSize physical = [self physicalSizeForLocationID:locationID screen:screen];
    CGFloat pointsPerMM = screen.frame.size.width / physical.width;

    TUCContact *contacts = calloc(MAX(touches.count, 1), sizeof(TUCContact));
    if (contacts == NULL) {
        return;
    }
    NSInteger count = 0;
    for (TUCTouch *touch in touches) {
        if (touch.locationID != locationID) continue;
        contacts[count].identifier = touch.contactID;
        contacts[count].mm = CGPointMake(touch.location.x * physical.width, touch.location.y * physical.height);
        contacts[count].point = [self clampScreenPointRelativeToAbsolute:touch.location locationID:locationID];
        count++;
    }

    double now = TUCUptimeSeconds();
    self.output.doubleClickTolerancePoints = self.doubleClickTolerance * pointsPerMM;

    TUCGestureRecognizer *recognizer = [self recognizerForLocationID:locationID];
    recognizer.doubleTapZoneMM = self.doubleClickTolerance;
    recognizer.doubleTapSeconds = [NSEvent doubleClickInterval];
    NSArray<NSValue *> *events = [recognizer handleContacts:contacts
                                                                                     count:count
                                                                                      time:now
                                                                             screenWidthMM:physical.width
                                                                               pointsPerMM:pointsPerMM];
    if (TUCRecordingEnabled()) {
        printf("F %.4f %ld", now, (long)count);
        for (NSInteger i = 0; i < count; i++) {
            printf(" %ld:%.2f,%.2f", (long)contacts[i].identifier, contacts[i].mm.x, contacts[i].mm.y);
        }
        printf("\n");
        for (NSValue *value in events) {
            TUCGestureEvent e = TUCGestureEventFromValue(value);
            printf("E kind=%ld fingers=%ld phase=%ld axis=%ld value=%.2f\n", (long)e.kind, (long)e.fingers, (long)e.phase, (long)e.axis, e.value);
        }
    }
    free(contacts);

    for (NSValue *value in events) {
        [self.output post:TUCGestureEventFromValue(value)];
    }
}


/**
 Records where a finger is. The gestures are recognised once the whole report has been read (`didProcessReportForLocationID:`).
 */
- (void)updateTouch:(NSInteger)contactID locationID:(uint32_t)locationID withLocation:(CGPoint)digitizerPoint onSurface:(BOOL)isOnSurface tooLargeForFinger:(BOOL)confidenceFlag {

    // assume that this is an erroneous message!!!
    if (self.ignoreOriginTouches && CGPointEqualToPoint(digitizerPoint, CGPointZero)) {
        return;
    }

    CGPoint point = [self convertDigitizerPointToRelativeScreenPoint:digitizerPoint locationID:locationID];

    BOOL isNewTouch = NO;
    TUCTouch *touch = [self obtainTouchWithID:contactID locationID:locationID isNew:&isNewTouch];

    [touch setLocation: point];
    [touch setIsOnSurface:isOnSurface];
    [touch setConfidenceFlag:confidenceFlag];
    [touch setLastUpdated:[self currentFrameIDForLocationID:locationID]];

    if (!isOnSurface) {
        [touch setPhase: NSTouchPhaseEnded];
        [self removeTouchLater:touch];
        [self.delegate touchesDidChange];
        return;

    }

    if(touch.previousPhase != NSTouchPhaseEnded && !isNewTouch) {
        // Stationary or moving (shown in the debug view). Convert each axis to mm first (x scales with the panel
        // width, y with its height), then take the distance, so a non-square screen does not distort the threshold.
        CGSize physicalSize = [self physicalSizeForLocationID:locationID screen:[self touchscreenForLocationID:locationID]];
        CGFloat dxMM = (touch.location.x - touch.previousLocation.x) * physicalSize.width;
        CGFloat dyMM = (touch.location.y - touch.previousLocation.y) * physicalSize.height;
        CGFloat movedDistanceMM = sqrt(dxMM * dxMM + dyMM * dyMM);
        BOOL isStationary = movedDistanceMM < self.stationaryThreshold;

        [touch setPhase:isStationary ? NSTouchPhaseStationary : NSTouchPhaseMoved];
    }


    [self.delegate touchesDidChange];

    return;
}


#pragma mark - Touch Set

/**
 The `touchSet` can contain touches whose phase is ended or cancelled. activeTouches. filteres those out
 */
- (NSSet<TUCTouch *> *)activeTouches {
    NSPredicate *p1 = [NSPredicate predicateWithFormat:@"phase != %d", NSTouchPhaseEnded];
    NSPredicate *p2 = [NSPredicate predicateWithFormat:@"phase != %d", NSTouchPhaseCancelled];

    NSPredicate *predicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[p1, p2]];

    return [self.touchSet filteredSetUsingPredicate:predicate];
}


/// How long an ended touch stays in `touchSet` (it no longer counts as active), so the debug view can show it lifting.
static const NSTimeInterval TUCEndedTouchLinger = 0.5;

/**
 Removes an ended or cancelled touch from the touch set after a moment (see TUCEndedTouchLinger). The gestures only see
 active touches, so this is for the debug view.
 */
- (void)removeTouchLater:(TUCTouch *)touch {
    __weak id weakSelf = self;
    NSUUID *uuid = touch.uuid;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(TUCEndedTouchLinger * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        for(TUCTouch *touch in [weakSelf touchSet]) {
            if (touch.uuid == uuid && [[weakSelf touchSet] containsObject:touch]) {
                [[weakSelf touchSet] removeObject:touch];
                [[weakSelf delegate] touchesDidChange];
                return;
            }
        }
    });
}


/**
 The active touch with this contact ID on this digitizer, if there is one.
 */
- (TUCTouch *)findActiveTouchWithID:(NSInteger)contactID locationID:(uint32_t)locationID {
    NSSet *set = [self activeTouches];

    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"contactID == %d AND locationID == %u", contactID, locationID];
    TUCTouch *touch = [[set filteredSetUsingPredicate:predicate] anyObject];
    return touch;
}

/**
 Returns the existing touch object or a new one if this ID does not exist in the set yet.
 */
- (TUCTouch *)obtainTouchWithID:(NSInteger)contactID locationID:(uint32_t)locationID isNew:(BOOL*)isNew {
    TUCTouch *touch = [self findActiveTouchWithID:contactID locationID:locationID];
    *isNew = NO;
    if(!touch) {
        touch = [[TUCTouch alloc] initWithContactID:contactID locationID:locationID];
        [self.touchSet addObject:touch];
        *isNew = YES;
    }
    return touch;
}





#pragma mark - Screen Characteristics

/**
 the relative hardware points are always in the direction the digitizer is built in.
 If the display is rotated, we need to rotate these points
 */
- (CGPoint)convertDigitizerPointToRelativeScreenPoint:(CGPoint)devicePoint locationID:(uint32_t)locationID {
    TUCScreen *screen = [self touchscreenForLocationID:locationID];

    CGFloat rotation = screen.rotation;

    CGFloat extra = [[self delegate] digitizerRotationForLocationID:locationID];

    rotation += extra;
    rotation = fmod(rotation, 360);
    if (rotation < 0) {
        rotation += 360;
    }

    // Rotate the glass-relative point into the screen's content orientation.
    CGPoint rotated;
    if (rotation == 180) {
        rotated = CGPointMake(1 - devicePoint.x, 1 - devicePoint.y);
    } else if (rotation == 90) {
        rotated = CGPointMake(1 - devicePoint.y, devicePoint.x);
    } else if (rotation == 270) {
        rotated = CGPointMake(devicePoint.y, 1 - devicePoint.x);
    } else {
        rotated = devicePoint;
    }

    // Then account for any letterboxing when the content doesn't fill the panel (mirroring
    // a differently-shaped display). A no-op when the aspect ratios already match.
    return [screen convertGlassPointToContentPoint:rotated];
}



- (CGPoint)clampScreenPointRelativeToAbsolute:(CGPoint)relativePoint locationID:(uint32_t)locationID {
    TUCScreen *screen = [self touchscreenForLocationID:locationID];
    CGPoint clamped = [screen clampRelativePoint:relativePoint toEdgeInset:self.edgeDeadZone];
    return [screen convertPointRelativeToAbsolute:clamped];
}



/**
 The visible area in mm: the user's size for this touchscreen if they gave one, else the display's own (EDID), else
 ~100 dpi as a guess.
 */
- (CGSize)physicalSizeForLocationID:(uint32_t)locationID screen:(TUCScreen *)screen {
    if ([self.delegate respondsToSelector:@selector(physicalSizeForLocationID:)]) {
        CGSize size = [self.delegate physicalSizeForLocationID:locationID];
        if (size.width > 0 && size.height > 0) return size;
    }

    CGSize native = screen.nativePhysicalSize;
    if (native.width > 0 && native.height > 0) return native;

    return CGSizeMake(screen.frame.size.width / TUCFallbackPointsPerMM, screen.frame.size.height / TUCFallbackPointsPerMM);
}



- (TUCScreen *)touchscreenForLocationID:(uint32_t)locationID {
    if (self.delegate != nil) {
        return [self.delegate touchscreenForLocationID:locationID];
    }

    return [[TUCScreen allScreens] firstObject];
}




#pragma mark -

- (instancetype)init {
    if(self = [super init]) {
        self.touchSet = [NSMutableSet new];
        self.frameIDsByLocationID = [NSMutableDictionary new];
        self.recognizersByLocationID = [NSMutableDictionary new];
        self.reportGenerationByLocationID = [NSMutableDictionary new];
        self.output = [TUCGestureOutput new];

        _postMouseEvents = YES;
        self.gestureSettings = [TUCGestureSettings defaultSettings];

        self.doubleClickTolerance = 5;
        self.longPressDuration = 0.5;
        self.dragThreshold = 3;
        self.stationaryThreshold = 0.1;
        self.edgeDeadZone = 0;
        self.errorResistance = 0;

        self.ignoreOriginTouches = NO;
    }
    return self;
}


- (NSString *)debugDescription {
    NSMutableString *str = [[NSString stringWithFormat:@"Touch Set contains %ld touches:{\n", [self.touchSet count]] mutableCopy];

    for (TUCTouch *touch in [[self.touchSet allObjects] sortedArrayUsingSelector:@selector(compareWithAnotherTouch:)] ) {
        [str appendString: [NSString stringWithFormat:@"  %@\n", [touch debugDescription]] ];
    }

    [str appendString:@"}"];
    return str;
}

- (void)triggerSystemAccessibilityAccessAlert {
    [self.output nudgeCursor];
}



#pragma mark - Bridge calls of C Header to Objective-C

void TouchInputManagerUpdateTouchPosition(void *self, uint32_t locationID, CFIndex contactID, CGFloat x, CGFloat y, Boolean onSurface, Boolean isValid) {
    CGPoint point = CGPointMake(x, y);
    [(__bridge id)self updateTouch:(NSInteger)contactID locationID:locationID withLocation:point onSurface:onSurface tooLargeForFinger:isValid];
}

void TouchInputManagerDidProcessReport(void *self, uint32_t locationID) {
    [(__bridge id)self didProcessReportForLocationID:locationID];
}

void TouchInputManagerDidConnectTouchscreen(void *self, uint32_t locationID) {
    [(__bridge id)self didConnectTouchscreenWithLocationID:locationID];
}

void TouchInputManagerDidDisconnectTouchscreen(void *self, uint32_t locationID) {
    [(__bridge id)self didDisconnectTouchscreenWithLocationID:locationID];
}


@end
