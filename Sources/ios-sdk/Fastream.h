#import <Foundation/Foundation.h>

#import <UIKit/UIKit.h>

@protocol FastreamDelegate;

@interface Fastream : NSObject

#pragma mark Properties

@property (atomic, readonly, copy) NSString *distinctId;

@property (atomic, readonly, copy) NSString *sessionId;

@property (atomic, readonly, copy) NSNumber* messageIndex;

@property (atomic, copy) NSString *nameTag;

@property (atomic, copy) NSString *serverURL;

@property (atomic) NSUInteger flushInterval;

@property (atomic) BOOL flushOnBackground;

@property (atomic) BOOL showNetworkActivityIndicator;

@property (atomic, weak) id<FastreamDelegate> delegate; // allows fine grain control over uploading (optional)

+ (Fastream *)sharedInstanceWithToken:(NSString *)apiToken serverURL:(NSString*)url;

+ (Fastream *)sharedInstanceWithToken:(NSString *)apiToken serverURL:(NSString*)url launchOptions:(NSDictionary *)launchOptions;

+ (Fastream *)sharedInstance;

- (instancetype)initWithToken:(NSString *)apiToken serverURL:(NSString *)url andFlushInterval:(NSUInteger)flushInterval;

- (void)identify:(NSString *)distinctId;

- (void)trackCustomEvent:(NSDictionary *)customEvent;

- (void)track:(NSString *)event customEvent:(NSDictionary *)customEvent;

- (void)track:(NSString *)event properties:(NSDictionary *)properties;

- (void)trackPushNotification:(NSDictionary *)userInfo;

- (void)registerSuperProperties:(NSDictionary *)properties;

- (void)registerSuperPropertiesOnce:(NSDictionary *)properties;

- (void)registerSuperPropertiesOnce:(NSDictionary *)properties defaultValue:(id)defaultValue;

- (void)unregisterSuperProperty:(NSString *)propertyName;

- (void)clearSuperProperties;

- (void)timeEvent:(NSString *)event;

- (void)clearTimedEvents;

- (void)reset;

- (void)flush;

- (void)archive;

- (void)createAlias:(NSString *)alias forDistinctID:(NSString *)distinctID;

- (NSString *)libVersion;

@end

@protocol FastreamDelegate <NSObject>
@optional

- (BOOL)fastreamWillFlush:(Fastream *)fastream;

@end
