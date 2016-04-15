/* Copyright (c) 2016 Google Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

//
//  GTLYouTubeLiveChatBanSnippet.h
//

// ----------------------------------------------------------------------------
// NOTE: This file is generated from Google APIs Discovery Service.
// Service:
//   YouTube Data API (youtube/v3)
// Description:
//   Programmatic access to YouTube features.
// Documentation:
//   https://developers.google.com/youtube/v3
// Classes:
//   GTLYouTubeLiveChatBanSnippet (0 custom class methods, 4 custom properties)

#if GTL_BUILT_AS_FRAMEWORK
  #import "GTL/GTLObject.h"
#else
  #import "GTLObject.h"
#endif

@class GTLYouTubeChannelProfileDetails;

// ----------------------------------------------------------------------------
//
//   GTLYouTubeLiveChatBanSnippet
//

@interface GTLYouTubeLiveChatBanSnippet : GTLObject

// The duration of a ban, only filled if the ban has type TEMPORARY.
@property (nonatomic, retain) NSNumber *banDurationSeconds;  // unsignedLongLongValue

@property (nonatomic, retain) GTLYouTubeChannelProfileDetails *bannedUserDetails;

// The chat this ban is pertinent to.
@property (nonatomic, copy) NSString *liveChatId;

// The type of ban.
@property (nonatomic, copy) NSString *type;

@end
