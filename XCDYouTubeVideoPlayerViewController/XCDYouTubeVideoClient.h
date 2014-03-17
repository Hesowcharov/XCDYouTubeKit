//
//  XCDYouTubeVideoClient.h
//  XCDYouTubeVideoPlayerViewController
//
//  Created by Cédric Luthi on 17.03.14.
//  Copyright (c) 2014 Cédric Luthi. All rights reserved.
//

#import <Foundation/Foundation.h>

@class XCDYouTubeVideo;

@interface XCDYouTubeVideoClient : NSObject

+ (instancetype) sharedClient;

- (void) getYouTubeVideoWithIdentifier:(NSString *)videoIdentifier completionHandler:(void (^)(XCDYouTubeVideo *video, NSError *error))completionHandler;

@end
