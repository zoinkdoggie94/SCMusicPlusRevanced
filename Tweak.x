
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// SCMusicPlusRevanced conservative sideload build for SCMusic.
// Removes fragile v8.60-specific initializer overrides and never hooks NSObject
// as a substitute for a missing SoundCloud class.
// This does not fix SoundCloud's own sideloading restrictions.

static NSArray<NSString *> *SCBlockedPatterns;

static BOOL SCIsBlockedURL(NSString *url) {
    if (!url.length) return NO;
    for (NSString *pattern in SCBlockedPatterns) {
        if ([url rangeOfString:pattern options:NSCaseInsensitiveSearch].location != NSNotFound)
            return YES;
    }
    return NO;
}

static Class SCClass(const char *objcName, const char *swiftName, const char *mangledName) {
    Class value = objc_getClass(objcName);
    if (!value && swiftName) value = objc_getClass(swiftName);
    if (!value && mangledName) value = objc_getClass(mangledName);
    return value;
}

@interface SCMusicURLProtocol : NSURLProtocol
@end

@implementation SCMusicURLProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    return SCIsBlockedURL(request.URL.absoluteString);
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}
- (void)startLoading {
    NSError *error = [NSError errorWithDomain:NSURLErrorDomain
                                        code:NSURLErrorCancelled
                                    userInfo:nil];
    [self.client URLProtocol:self didFailWithError:error];
}
- (void)stopLoading {}
@end

%group SCURLHook
%hook NSURLSessionConfiguration
- (NSArray *)protocolClasses {
    NSArray *classes = %orig;
    if ([classes containsObject:[SCMusicURLProtocol class]]) return classes;
    NSMutableArray *result = [NSMutableArray arrayWithObject:[SCMusicURLProtocol class]];
    if (classes) [result addObjectsFromArray:classes];
    return result;
}
%end
%end

%group SCQueueAdHook
%hook AdPlayQueueManager
- (BOOL)isItemMonetizable:(id)item { return NO; }
%end
%end

%group SCTrackHook
%hook PlayQueueTrack
- (BOOL)isMonetizable { return NO; }
%end
%end

%group SCSwiftTrackHook
%hook SCSoundCloudPlayQueueItemTrackEntity
- (BOOL)isMonetizable { return NO; }
- (BOOL)isMonetizableAdGeo { return NO; }
%end
%end

%group SCUpsellHook
%hook SCSoundCloudUpsellManager
- (BOOL)shouldUpsell { return NO; }
- (BOOL)shouldUpsellCreator { return NO; }
- (BOOL)shouldUpsellForTrack:(id)track { return NO; }
- (BOOL)shouldShowTabBarUpsell { return NO; }
- (BOOL)canNotUpsell { return YES; }
- (BOOL)shouldUpsellForPlaylist:(id)playlist { return NO; }
- (BOOL)shouldUpsellGoLite { return NO; }
%end
%end

%group SCFeaturesHook
%hook SCSoundCloudUserFeaturesService
- (BOOL)isNoAudioAdsEnabled { return YES; }
- (BOOL)isHQAudioFeatureEnabled { return YES; }
%end
%end

%group SCRequestHook
%hook SCSoundCloudAdsRequestPermitter
- (BOOL)shouldRequestAds { return NO; }
%end
%end

%group SCGoLiteHook
%hook SCSoundCloudGoLitePlanManager
- (BOOL)isGoLiteAvailable { return NO; }
%end
%end

%group SCUpdateHook
%hook FeatureFlagService
+ (NSString *)devIosUpdatePromptVersionsValue { return @""; }
%end
%end

%ctor {
    @autoreleasepool {
        SCBlockedPatterns = @[
            @"ads.soundcloud.com", @"ad.getAd", @"adsbygoogle",
            @"doubleclick.net", @"googlesyndication.com",
            @"google-analytics.com"
        ];

        [NSURLProtocol registerClass:[SCMusicURLProtocol class]];
        %init(SCURLHook);

        Class cls;
        cls = objc_getClass("AdPlayQueueManager");
        if (cls && class_getInstanceMethod(cls, @selector(isItemMonetizable:))) {
            %init(SCQueueAdHook);
        }

        cls = objc_getClass("PlayQueueTrack");
        if (cls && class_getInstanceMethod(cls, @selector(isMonetizable))) {
            %init(SCTrackHook);
        }

        cls = SCClass("SCSoundCloudPlayQueueItemTrackEntity",
                      "SoundCloud.PlayQueueItemTrackEntity",
                      "_TtC10SoundCloud24PlayQueueItemTrackEntity");
        if (cls && class_getInstanceMethod(cls, @selector(isMonetizable))) {
            %init(SCSwiftTrackHook, SCSoundCloudPlayQueueItemTrackEntity = cls);
        }

        cls = SCClass("SCSoundCloudUpsellManager", "SoundCloud.UpsellManager",
                      "_TtC10SoundCloud13UpsellManager");
        if (cls && class_getInstanceMethod(cls, @selector(shouldUpsell))) {
            %init(SCUpsellHook, SCSoundCloudUpsellManager = cls);
        }

        cls = SCClass("SCSoundCloudUserFeaturesService",
                      "SoundCloud.UserFeaturesService",
                      "_TtC10SoundCloud19UserFeaturesService");
        if (cls && class_getInstanceMethod(cls, @selector(isNoAudioAdsEnabled))) {
            %init(SCFeaturesHook, SCSoundCloudUserFeaturesService = cls);
        }

        cls = SCClass("SCSoundCloudAdsRequestPermitter",
                      "SoundCloud.AdsRequestPermitter",
                      "_TtC10SoundCloud19AdsRequestPermitter");
        if (cls && class_getInstanceMethod(cls, @selector(shouldRequestAds))) {
            %init(SCRequestHook, SCSoundCloudAdsRequestPermitter = cls);
        }

        cls = SCClass("SCSoundCloudGoLitePlanManager",
                      "SoundCloud.GoLitePlanManager",
                      "_TtC10SoundCloud17GoLitePlanManager");
        if (cls && class_getInstanceMethod(cls, @selector(isGoLiteAvailable))) {
            %init(SCGoLiteHook, SCSoundCloudGoLitePlanManager = cls);
        }

        cls = objc_getClass("FeatureFlagService");
        if (cls && class_getClassMethod(cls, @selector(devIosUpdatePromptVersionsValue))) {
            %init(SCUpdateHook);
        }
    }
}
