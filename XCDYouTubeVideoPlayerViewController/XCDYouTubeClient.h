//
//  XCDYouTubeClient.h
//  XCDYouTubeVideoPlayerViewController
//
//  Created by Cédric Luthi on 17.03.14.
//  Copyright (c) 2014 Cédric Luthi. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol XCDYouTubeOperation
- (void) cancel;
@end

@class XCDYouTubeVideo;

@interface XCDYouTubeClient : NSObject

- (id<XCDYouTubeOperation>) getVideoWithIdentifier:(NSString *)videoIdentifier completionHandler:(void (^)(XCDYouTubeVideo *video, NSError *error))completionHandler;

@end
