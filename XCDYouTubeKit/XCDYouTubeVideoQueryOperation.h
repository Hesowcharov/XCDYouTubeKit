//
//  XCDYouTubeVideoQueryOperation.h
//  XCDYouTubeKit Static Library
//
//  Created by Soneé John on 2/12/20.
//  Copyright © 2020 Cédric Luthi. All rights reserved.
//

#if !__has_feature(nullability)
#define NS_ASSUME_NONNULL_BEGIN
#define NS_ASSUME_NONNULL_END
#define nullable
#endif

#import <Foundation/Foundation.h>

#import "XCDYouTubeVideo.h"

NS_ASSUME_NONNULL_BEGIN

/// XCDYouTubeVideoQueryOperation is a subclass of `NSOperation` that  check to see if the `streamURLs` in a `XCDYouTubeVideo` object  is reachable (i.e. does not contain any HTTP errors). This operation will only run on a background queue, starting this operation on the main thread will raise an assertion.
/// You should probably use the higher level class `<XCDYouTubeClient>`. Use this class only if you are very familiar with `NSOperation` and need to manage dependencies between operations.
@interface XCDYouTubeVideoQueryOperation : NSOperation


/// Initializes a video  query operation with the specified video and cookies.
/// @param video The `<XCDYouTubeVideo>` object that this operation will query. Passing a `nil` video will throw an `NSInvalidArgumentException` exception.
/// @param cookies  An array of `NSHTTPCookie` objects, can be nil. These cookies can be used for certain videos that require a login.
- (instancetype) initWithVideo:(XCDYouTubeVideo *)video cookies:(nullable NSArray<NSHTTPCookie *> *)cookies NS_DESIGNATED_INITIALIZER;

/// The `video` object that the operation initialized initialized with.
@property (atomic, strong, readonly) XCDYouTubeVideo *video;

/// The array of `NSHTTPCookie` objects passed during initialization.
@property (atomic, copy, readonly, nullable) NSArray<NSHTTPCookie *>*cookies;

/// A dictionary of video stream URLs that are reachable. The keys are the YouTube [itag](https://en.wikipedia.org/wiki/YouTube#Quality_and_formats) values as `NSNumber` objects. The values are the video URLs as `NSURL` objects. There is also the special `XCDYouTubeVideoQualityHTTPLiveStreaming` key for live videos.
#if __has_feature(objc_generics)
@property (atomic, readonly) NSDictionary<id, NSURL *> *streamURLs;
#else
@property (atomic, readonly) NSDictionary *streamURLs;
#endif

/// Returns an error of the `XCDYouTubeVideoErrorDomain` domain if the operation failed or nil if it succeeded. The operation will only return an error if no stream URL is reachable (error code: `XCDYouTubeErrorNoStreamAvailable`). Also, this returns `nil` if the operation is not yet finished or if it was canceled.
@property (atomic, readonly, nullable) NSError *error;

/// A dictionary of `NSError` objects. The keys are the YouTube [itag](https://en.wikipedia.org/wiki/YouTube#Quality_and_formats) values as `NSNumber` objects. Use this property to query why a specific stream was unavailable.
#if __has_feature(objc_generics)
@property (atomic, readonly, nullable) NSDictionary<id, NSError *> *streamErrors;
#else
@property (atomic, readonly, nullable) NSDictionary *streamErrors;
#endif

@end

NS_ASSUME_NONNULL_END
