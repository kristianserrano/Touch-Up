//
//  TUCTouch.h
//  Touch Up Core
//
//  Created by Sebastian Hueber on 03.02.23.
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN


@interface TUCTouch : NSObject

@property (strong) NSUUID *uuid;
@property NSInteger contactID;
@property uint32_t locationID;

@property BOOL isOnSurface; //tip
@property BOOL confidenceFlag;

@property (nonatomic) NSTouchPhase phase;
@property NSTouchPhase previousPhase;

@property (nonatomic) CGPoint location;
@property CGPoint previousLocation;

@property NSInteger lastUpdated; // the page ID during last update


- (instancetype)initWithContactID:(NSInteger)contactID locationID:(uint32_t)locationID;



- (BOOL)isActive;

- (NSComparisonResult) compareWithAnotherTouch:(TUCTouch*) anotherTouch;

@end

NS_ASSUME_NONNULL_END
