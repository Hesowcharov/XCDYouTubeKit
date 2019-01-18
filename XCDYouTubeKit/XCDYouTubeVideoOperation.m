//
//  Copyright (c) 2013-2016 Cédric Luthi. All rights reserved.
//

#import "XCDYouTubeVideoOperation.h"

#import <objc/runtime.h>

#import "XCDYouTubeVideo+Private.h"
#import "XCDYouTubeError.h"
#import "XCDYouTubeVideoWebpage.h"
#import "XCDYouTubeDashManifestXML.h"
#import "XCDYouTubePlayerScript.h"
#import "XCDYouTubeLogger+Private.h"
#import "XCDYouTubeURLQueryOperation.h"

typedef NS_ENUM(NSUInteger, XCDYouTubeRequestType) {
	XCDYouTubeRequestTypeGetVideoInfo = 1,
	XCDYouTubeRequestTypeWatchPage,
	XCDYouTubeRequestTypeEmbedPage,
	XCDYouTubeRequestTypeJavaScriptPlayer,
	XCDYouTubeRequestTypeDashManifest,
	
};

@interface XCDYouTubeVideoOperation ()
@property (atomic, copy, readonly) NSString *videoIdentifier;
@property (atomic, copy, readonly) NSString *languageIdentifier;
@property (atomic, strong, readonly) NSArray <NSHTTPCookie *> *cookies;

@property (atomic, assign) NSInteger requestCount;
@property (atomic, assign) XCDYouTubeRequestType requestType;
@property (atomic, strong) NSMutableArray *eventLabels;
@property (atomic, strong) XCDYouTubeVideo *lastSuccessfulVideo;
@property (atomic, readonly) NSURLSession *session;
@property (atomic, strong) NSURLSessionDataTask *dataTask;

@property (atomic, assign) BOOL alternativeStreamFlag;
@property (atomic, assign) BOOL isExecuting;
@property (atomic, assign) BOOL isFinished;
@property (atomic, readonly) dispatch_semaphore_t operationStartSemaphore;

@property (atomic, strong) XCDYouTubeVideoWebpage *webpage;
@property (atomic, strong) XCDYouTubeVideoWebpage *embedWebpage;
@property (atomic, strong) XCDYouTubePlayerScript *playerScript;
@property (atomic, strong) XCDYouTubeVideo *noStreamVideo;
@property (atomic, strong) NSError *lastError;
@property (atomic, strong) NSError *youTubeError; // Error actually coming from the YouTube API, i.e. explicit and localized error

@property (atomic, strong, readwrite) NSError *error;
@property (atomic, strong, readwrite) XCDYouTubeVideo *video;
@end

@implementation XCDYouTubeVideoOperation

static NSError *YouTubeError(NSError *error, NSSet *regionsAllowed, NSString *languageIdentifier)
{
	if (error.code == XCDYouTubeErrorRestrictedPlayback && regionsAllowed.count > 0)
	{
		NSLocale *locale = [NSLocale localeWithLocaleIdentifier:languageIdentifier];
		NSMutableSet *allowedCountries = [NSMutableSet new];
		for (NSString *countryCode in regionsAllowed)
		{
			NSString *country = [locale displayNameForKey:NSLocaleCountryCode value:countryCode];
			[allowedCountries addObject:country ?: countryCode];
		}
		NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:error.userInfo];
		userInfo[XCDYouTubeAllowedCountriesUserInfoKey] = [allowedCountries copy];
		return [NSError errorWithDomain:error.domain code:error.code userInfo:[userInfo copy]];
	}
	else
	{
		return error;
	}
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"
- (instancetype) init
{
	@throw [NSException exceptionWithName:NSGenericException reason:@"Use the `initWithVideoIdentifier:cookies:languageIdentifier:` method instead." userInfo:nil];
} // LCOV_EXCL_LINE
#pragma clang diagnostic pop

- (instancetype) initWithVideoIdentifier:(NSString *)videoIdentifier languageIdentifier:(NSString *)languageIdentifier cookies:(NSArray<NSHTTPCookie *> *)cookies
{
	if (!(self = [super init]))
		return nil; // LCOV_EXCL_LINE
	
	_videoIdentifier = videoIdentifier ?: @"";
	_languageIdentifier = languageIdentifier ?: @"en";
	
	_session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
	_cookies = [cookies copy];
	for (NSHTTPCookie *cookie in _cookies) {
		[_session.configuration.HTTPCookieStorage setCookie:cookie];
	}
	_operationStartSemaphore = dispatch_semaphore_create(0);
	
	return self;
}

- (instancetype) initWithVideoIdentifier:(NSString *)videoIdentifier languageIdentifier:(NSString *)languageIdentifier
{
	return [self initWithVideoIdentifier:videoIdentifier languageIdentifier:languageIdentifier cookies:nil];
}

#pragma mark - Requests

- (void) startNextRequest
{
	if (self.eventLabels.count == 0)
	{
		if (self.requestType == XCDYouTubeRequestTypeWatchPage || self.webpage)
			[self finishWithError];
		else
			[self startWatchPageRequest];
	}
	else
	{
		NSString *eventLabel = [self.eventLabels objectAtIndex:0];
		[self.eventLabels removeObjectAtIndex:0];
		
		NSDictionary *query = @{ @"video_id": self.videoIdentifier, @"hl": self.languageIdentifier, @"el": eventLabel, @"ps": @"default" };
		NSString *queryString = XCDQueryStringWithDictionary(query);
		NSURL *videoInfoURL = [NSURL URLWithString:[@"https://www.youtube.com/get_video_info?" stringByAppendingString:queryString]];
		[self startRequestWithURL:videoInfoURL type:XCDYouTubeRequestTypeGetVideoInfo];
	}
}

- (void) startWatchPageRequest
{
	NSDictionary *query = @{ @"v": self.videoIdentifier, @"hl": self.languageIdentifier, @"has_verified": @YES, @"bpctr": @9999999999 };
	NSString *queryString = XCDQueryStringWithDictionary(query);
	NSURL *webpageURL = [NSURL URLWithString:[@"https://www.youtube.com/watch?" stringByAppendingString:queryString]];
	[self startRequestWithURL:webpageURL type:XCDYouTubeRequestTypeWatchPage];
}

- (void) startRequestWithURL:(NSURL *)url type:(XCDYouTubeRequestType)requestType
{
	if (self.isCancelled)
		return;
	
	// Max (age-restricted VEVO) = 2×GetVideoInfo + 1×WatchPage + 1×EmbedPage + 1×JavaScriptPlayer + 1×GetVideoInfo + 1xDashManifest (multiplied by 2 since we may retry and try an alternative stream)
	if (++self.requestCount > 14)
	{
		// This condition should never happen but the request flow is quite complex so better abort here than go into an infinite loop of requests
		[self finishWithError];
		return;
	}
	
	XCDYouTubeLogDebug(@"Starting request: %@", url);
	
	NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:10];
	[request setValue:self.languageIdentifier forHTTPHeaderField:@"Accept-Language"];
	[request setValue:[NSString stringWithFormat:@"https://youtube.com/watch?v=%@", self.videoIdentifier] forHTTPHeaderField:@"Referer"];
	
	self.dataTask = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error)
	{
		if (self.isCancelled)
			return;
		
		if (error)
			[self handleConnectionError:error requestType:requestType];
		else
			[self handleConnectionSuccessWithData:data response:response requestType:requestType];
	}];
	[self.dataTask resume];
	
	self.requestType = requestType;
}

#pragma mark - Response Dispatch

- (void) handleConnectionSuccessWithData:(NSData *)data response:(NSURLResponse *)response requestType:(XCDYouTubeRequestType)requestType
{
	CFStringEncoding encoding = CFStringConvertIANACharSetNameToEncoding((__bridge CFStringRef)response.textEncodingName ?: CFSTR(""));
	// Use kCFStringEncodingMacRoman as fallback because it defines characters for every byte value and is ASCII compatible. See https://mikeash.com/pyblog/friday-qa-2010-02-19-character-encodings.html
	NSString *responseString = CFBridgingRelease(CFStringCreateWithBytes(kCFAllocatorDefault, data.bytes, (CFIndex)data.length, encoding != kCFStringEncodingInvalidId ? encoding : kCFStringEncodingMacRoman, false)) ?: @"";
	NSAssert(responseString.length > 0, @"Failed to decode response from %@ (response.textEncodingName = %@, data.length = %@)", response.URL, response.textEncodingName, @(data.length));
	
	XCDYouTubeLogVerbose(@"Response: %@\n%@", response, responseString);
	
	switch (requestType)
	{
		case XCDYouTubeRequestTypeGetVideoInfo:
			[self handleVideoInfoResponseWithInfo:XCDDictionaryWithQueryString(responseString) response:response];
			break;
		case XCDYouTubeRequestTypeWatchPage:
			[self handleWebPageWithHTMLString:responseString];
			break;
		case XCDYouTubeRequestTypeEmbedPage:
			[self handleEmbedWebPageWithHTMLString:responseString];
			break;
		case XCDYouTubeRequestTypeJavaScriptPlayer:
			[self handleJavaScriptPlayerWithScript:responseString];
			break;
		case XCDYouTubeRequestTypeDashManifest:
			[self handleDashManifestWithXMLString:responseString response:response];
			break;
	}
}

- (void) handleConnectionError:(NSError *)connectionError requestType:(XCDYouTubeRequestType)requestType
{
	//Shoud not return a connection error if was as a result of requesting the Dash Manifiest (we have a sucessfully created `XCDYouTubeVideo` and should just finish the operation as if were a 'sucessful' one
	if (requestType == XCDYouTubeRequestTypeDashManifest)
	{
		[self finishWithVideo:self.lastSuccessfulVideo];
		return;
	}
	
	NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: connectionError.localizedDescription,
	                            NSUnderlyingErrorKey: connectionError };
	self.lastError = [NSError errorWithDomain:XCDYouTubeVideoErrorDomain code:XCDYouTubeErrorNetwork userInfo:userInfo];
	
	[self startNextRequest];
}

#pragma mark - Response Parsing

- (void) handleVideoInfoResponseWithInfo:(NSDictionary *)info response:(NSURLResponse *)response
{
	XCDYouTubeLogDebug(@"Handling video info response");
	
	NSMutableDictionary *mutableInfo = [info mutableCopy];
	if (self.alternativeStreamFlag) {
		[mutableInfo setValue:@(YES) forKey:XCDYouTubeVideoOptionsAlternativeStreamFlag];
	}
	
	NSError *error = nil;
	XCDYouTubeVideo *video = [[XCDYouTubeVideo alloc] initWithIdentifier:self.videoIdentifier info:mutableInfo playerScript:self.playerScript response:response error:&error];
	if (video)
	{
		self.lastSuccessfulVideo = video;
		
		if (info[@"dashmpd"])
		{
			NSURL *dashmpdURL = [NSURL URLWithString:(NSString *_Nonnull)info[@"dashmpd"]];
			[self startRequestWithURL:dashmpdURL type:XCDYouTubeRequestTypeDashManifest];
			return;
		}
		[video mergeVideo:self.noStreamVideo];
		[self finishWithVideo:video];
	}
	else
	{
		if ([error.domain isEqual:XCDYouTubeVideoErrorDomain] && error.code == XCDYouTubeErrorUseCipherSignature)
		{
			self.noStreamVideo = error.userInfo[XCDYouTubeNoStreamVideoUserInfoKey];
			
			[self startWatchPageRequest];
		}
		else
		{
			self.lastError = error;
			if (error.code > 0)
				self.youTubeError = error;
			
			[self startNextRequest];
		}
	}
}

- (void) handleWebPageWithHTMLString:(NSString *)html
{
	XCDYouTubeLogDebug(@"Handling web page response");
	
	self.webpage = [[XCDYouTubeVideoWebpage alloc] initWithHTMLString:html];
	
	if (self.webpage.javaScriptPlayerURL)
	{
		[self startRequestWithURL:self.webpage.javaScriptPlayerURL type:XCDYouTubeRequestTypeJavaScriptPlayer];
	}
	else
	{
		if (self.webpage.isAgeRestricted)
		{
			NSString *embedURLString = [NSString stringWithFormat:@"https://www.youtube.com/embed/%@", self.videoIdentifier];
			[self startRequestWithURL:[NSURL URLWithString:embedURLString] type:XCDYouTubeRequestTypeEmbedPage];
		}
		else
		{
			[self startNextRequest];
		}
	}
}

- (void) handleEmbedWebPageWithHTMLString:(NSString *)html
{
	XCDYouTubeLogDebug(@"Handling embed web page response");
	
	self.embedWebpage = [[XCDYouTubeVideoWebpage alloc] initWithHTMLString:html];
	
	if (self.embedWebpage.javaScriptPlayerURL)
	{
		[self startRequestWithURL:self.embedWebpage.javaScriptPlayerURL type:XCDYouTubeRequestTypeJavaScriptPlayer];
	}
	else
	{
		[self startNextRequest];
	}
}

- (void) handleJavaScriptPlayerWithScript:(NSString *)script
{
	XCDYouTubeLogDebug(@"Handling JavaScript player response");
	
	self.playerScript = [[XCDYouTubePlayerScript alloc] initWithString:script];
	
	if (self.webpage.isAgeRestricted && self.cookies.count == 0)
	{
		NSString *eurl = [@"https://youtube.googleapis.com/v/" stringByAppendingString:self.videoIdentifier];
		NSString *sts = [(NSObject *)self.embedWebpage.playerConfiguration[@"sts"] description] ?: [(NSObject *)self.webpage.playerConfiguration[@"sts"] description] ?: @"";
		NSDictionary *query = @{ @"video_id": self.videoIdentifier, @"hl": self.languageIdentifier, @"eurl": eurl, @"sts": sts};
		NSString *queryString = XCDQueryStringWithDictionary(query);
		NSURL *videoInfoURL = [NSURL URLWithString:[@"https://www.youtube.com/get_video_info?" stringByAppendingString:queryString]];
		[self startRequestWithURL:videoInfoURL type:XCDYouTubeRequestTypeGetVideoInfo];
	}
	else
	{
		[self handleVideoInfoResponseWithInfo:self.webpage.videoInfo response:nil];
	}
}

- (void) handleDashManifestWithXMLString:(NSString *)XMLString response:(NSURLResponse *)response
{
	XCDYouTubeLogDebug(@"Handling Dash Manifest response");
	
	XCDYouTubeDashManifestXML *dashManifestXML = [[XCDYouTubeDashManifestXML alloc]initWithXMLString:XMLString];
	NSDictionary *dashhManifestStreamURLs = dashManifestXML.streamURLs;
	if (dashhManifestStreamURLs)
		[self.lastSuccessfulVideo mergeDashManifestStreamURLs:dashhManifestStreamURLs];
	
	[self finishWithVideo:self.lastSuccessfulVideo];
}

#pragma mark - Finish Operation

- (void) finishWithVideo:(XCDYouTubeVideo *)video
{
	[self queryVideo:video completionHandler:^(XCDYouTubeVideo * _Nullable queryVideo) {
		if (!queryVideo && !self.alternativeStreamFlag)
		{
			//Retry
			self.alternativeStreamFlag = YES;
			self.eventLabels = [[NSMutableArray alloc] initWithArray:@[ @"embedded", @"detailpage" ]];
			[self startNextRequest];
			return;
		}
		
		if (!queryVideo && self.alternativeStreamFlag)
		{
			//Error
			[self finishWithError];
			return;
		}
		
		self.video = video;
		XCDYouTubeLogInfo(@"Video operation finished with success: %@", video);
		XCDYouTubeLogDebug(@"%@", ^{ return video.debugDescription; }());
		[self finish];
	}];
}

- (void)queryVideo:(XCDYouTubeVideo *)video completionHandler:(void (^)(XCDYouTubeVideo * __nullable video))completionHandler
{
	
	NSOperationQueue *outerQueue = [NSOperationQueue new];
	outerQueue.qualityOfService = NSQualityOfServiceUserInitiated;
	outerQueue.maxConcurrentOperationCount = 1;
	
	[outerQueue addOperationWithBlock:^{
		
		NSSet <NSNumber *>*queryTags = [NSSet setWithArray:@[@(XCDYouTubeVideoQualityHD720), @(XCDYouTubeVideoQualityHD720), @(XCDYouTubeVideoQualityMedium360), @(XCDYouTubeVideoQualitySmall240)]];
		
		NSMutableArray <XCDYouTubeURLQueryOperation *>*operations = [NSMutableArray new];
		
		[video.streamURLs enumerateKeysAndObjectsUsingBlock:^(NSNumber *key, NSURL *streamURL, BOOL * _Nonnull stop) {
			if ([queryTags containsObject:key])
			{
				XCDYouTubeURLQueryOperation *operation = [[XCDYouTubeURLQueryOperation alloc]initWithURL:streamURL info:@{key : streamURL} cookes:self.cookies];
				[operations addObject:operation];
			}
		}];
		
		NSURL *liveStreamURL = video.streamURLs[XCDYouTubeVideoQualityHTTPLiveStreaming];
		if (liveStreamURL) {
			[operations addObject:[[XCDYouTubeURLQueryOperation alloc]initWithURL:liveStreamURL info:@{XCDYouTubeVideoQualityHTTPLiveStreaming : liveStreamURL} cookes:self.cookies]];
		}
		
		if (operations.count == 0)
		{
			completionHandler(nil);
			return;
		}
		
		NSOperationQueue *queue = [NSOperationQueue new];
		queue.maxConcurrentOperationCount = 6;
		
		[queue addOperations:operations waitUntilFinished:YES];
		
		NSMutableDictionary *streamURLs = [NSMutableDictionary new];
		
		for (XCDYouTubeURLQueryOperation *operation in operations)
		{
			if (operation.error == nil && [(NSHTTPURLResponse *)operation.response statusCode] == 200)
			{
				[streamURLs addEntriesFromDictionary:(NSDictionary *_Nonnull)operation.info];
			}
		}
		
		if (streamURLs.count == 0)
		{
			completionHandler(nil);
			return;
		}
		
		completionHandler(video);
	}];
}

- (void) finishWithError
{
	self.error = self.youTubeError ? YouTubeError(self.youTubeError, self.webpage.regionsAllowed, self.languageIdentifier) : self.lastError;
	XCDYouTubeLogError(@"Video operation finished with error: %@\nDomain: %@\nCode:   %@\nUser Info: %@", self.error.localizedDescription, self.error.domain, @(self.error.code), self.error.userInfo);
	[self finish];
}

- (void) finish
{
	self.isExecuting = NO;
	self.isFinished = YES;
}

#pragma mark - NSOperation

+ (BOOL) automaticallyNotifiesObserversForKey:(NSString *)key
{
	SEL selector = NSSelectorFromString(key);
	return selector == @selector(isExecuting) || selector == @selector(isFinished) || [super automaticallyNotifiesObserversForKey:key];
}

- (BOOL) isConcurrent
{
	return YES;
}

- (void) start
{
	dispatch_semaphore_signal(self.operationStartSemaphore);
	
	if (self.isCancelled)
		return;
	
	if (self.videoIdentifier.length != 11)
	{
		XCDYouTubeLogWarning(@"Video identifier length should be 11. [%@]", self.videoIdentifier);
	}
	
	XCDYouTubeLogInfo(@"Starting video operation: %@", self);
	
	self.isExecuting = YES;
	
	self.eventLabels = [[NSMutableArray alloc] initWithArray:@[ @"embedded", @"detailpage" ]];
	[self startNextRequest];
}

- (void) cancel
{
	if (self.isCancelled || self.isFinished)
		return;
	
	XCDYouTubeLogInfo(@"Canceling video operation: %@", self);
	
	[super cancel];
	
	[self.dataTask cancel];
	
	// Wait for `start` to be called in order to avoid this warning: *** XCDYouTubeVideoOperation 0x7f8b18c84880 went isFinished=YES without being started by the queue it is in
	dispatch_semaphore_wait(self.operationStartSemaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(200 * NSEC_PER_MSEC)));
	[self finish];
}

#pragma mark - NSObject

- (NSString *) description
{
	return [NSString stringWithFormat:@"<%@: %p> %@ (%@)", self.class, self, self.videoIdentifier, self.languageIdentifier];
}

@end
