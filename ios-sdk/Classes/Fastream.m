#if ! __has_feature(objc_arc)
#error This file must be compiled with ARC. Either turn on ARC for the project or use -fobjc-arc flag on this file.
#endif

#include <arpa/inet.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <sys/socket.h>
#include <sys/sysctl.h>

#import <CommonCrypto/CommonDigest.h>
#import <CoreTelephony/CTCarrier.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <UIKit/UIDevice.h>

#import "Fastream.h"
#import "FastreamLogger.h"
#import "NSData+FastreamBase64.h"

#define VERSION @"0.1.4"

static NSString * const kSendingTimePlaceHolder = @"<SendingTimePlaceHolder>";
static NSString * const kSendingTimeKey = @"sending_time";

@interface Fastream () <UIAlertViewDelegate>

{
    NSUInteger _flushInterval;
}

// re-declare internally as readwrite
@property (atomic, copy) NSString *distinctId;
@property (atomic, copy) NSString *sessionId;
@property (atomic, copy) NSNumber* messageIndex;

@property (nonatomic, copy) NSString *apiToken;
@property (atomic, strong) NSDictionary *superProperties;
@property (atomic, strong) NSDictionary *automaticProperties;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSMutableArray *eventsQueue;
@property (nonatomic, assign) UIBackgroundTaskIdentifier taskId;
@property (nonatomic, strong) dispatch_queue_t serialQueue;
@property (nonatomic, assign) SCNetworkReachabilityRef reachability;
@property (nonatomic, strong) CTTelephonyNetworkInfo *telephonyInfo;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@property (nonatomic, strong) NSMutableDictionary *timedEvents;
@property (nonatomic, readonly, nullable) UIApplication *application;
@property (nonatomic) BOOL inBG;

@end

@implementation Fastream

static Fastream *sharedInstance = nil;


+ (Fastream *)sharedInstanceWithToken:(NSString *)apiToken serverURL:(NSString *)url launchOptions:(NSDictionary *)launchOptions
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[super alloc] initWithToken:apiToken serverURL:url launchOptions:launchOptions andFlushInterval:60];
    });
    return sharedInstance;
}

+ (Fastream *)sharedInstanceWithToken:(NSString *)apiToken serverURL:(NSString *)url
{
    return [Fastream sharedInstanceWithToken:apiToken serverURL:url launchOptions:nil];
}

+ (Fastream *)sharedInstance
{
    if (sharedInstance == nil) {
        FastreamDebug(@"warning sharedInstance called before sharedInstanceWithToken:");
    }
    return sharedInstance;
}

- (instancetype)initWithToken:(NSString *)apiToken serverURL:(NSString *)url launchOptions:(NSDictionary *)launchOptions andFlushInterval:(NSUInteger)flushInterval
{
    if (apiToken == nil) {
        apiToken = @"";
    }
    if ([apiToken length] == 0) {
        FastreamDebug(@"%@ warning empty api token", self);
    }
    if (self = [self init]) {
        self.messageIndex = 0;
        self.apiToken = apiToken;
        _flushInterval = flushInterval;
        self.flushOnBackground = YES;
        self.showNetworkActivityIndicator = YES;

        self.serverURL = url;

        self.distinctId = [self defaultDistinctId];
        self.sessionId = [[NSUUID UUID] UUIDString];
        self.superProperties = [NSMutableDictionary dictionary];
        self.telephonyInfo = [[CTTelephonyNetworkInfo alloc] init];
        self.automaticProperties = [self collectAutomaticProperties];
        self.eventsQueue = [NSMutableArray array];
        self.taskId = UIBackgroundTaskInvalid;
        NSString *label = [NSString stringWithFormat:@"com.fastream.%@.%p", apiToken, self];
        self.serialQueue = dispatch_queue_create([label UTF8String], DISPATCH_QUEUE_SERIAL);
        self.dateFormatter = [[NSDateFormatter alloc] init];
        [_dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"];
        [_dateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
        [_dateFormatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
        self.timedEvents = [NSMutableDictionary dictionary];


        if (![Fastream isAppExtension]) {
            if ([[UIApplication class] respondsToSelector:@selector(sharedApplication)]) {
                _application = [[UIApplication class] performSelector:@selector(sharedApplication)];
            }
#if !defined(FASTREAM_APP_EXTENSION)
            if(_application) {
                [self setUpListeners];
            }
#endif
        }

        [self unarchive];

        if (launchOptions && launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey]) {
            [self trackPushNotification:launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey] event:@"$app_open"];
        }
    }
    return self;
}

- (instancetype)initWithToken:(NSString *)apiToken serverURL:(NSString *)url andFlushInterval:(NSUInteger)flushInterval
{
    return [self initWithToken:apiToken serverURL:url launchOptions:nil andFlushInterval:flushInterval];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (_reachability != NULL) {
        if (!SCNetworkReachabilitySetCallback(_reachability, NULL, NULL)) {
            FastreamError(@"%@ error unsetting reachability callback", self);
        }
        if (!SCNetworkReachabilitySetDispatchQueue(_reachability, NULL)) {
            FastreamError(@"%@ error unsetting reachability dispatch queue", self);
        }
        CFRelease(_reachability);
        _reachability = NULL;
        FastreamDebug(@"realeased reachability");
    }
}

#pragma mark - Encoding/decoding utilities

static __unused NSString *MPURLEncode(NSString *s)
{
    return (NSString *)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (CFStringRef)s, NULL, CFSTR("!*'();:@&=+$,/?%#[]"), kCFStringEncodingUTF8));
}

- (NSData *)JSONSerializeObject:(id)obj
{
    id coercedObj = [self JSONSerializableObjectForObject:obj];
    NSError *error = nil;
    NSData *data = nil;
    @try {
        data = [NSJSONSerialization dataWithJSONObject:coercedObj options:0 error:&error];
    }
    @catch (NSException *exception) {
        FastreamError(@"%@ exception encoding api data: %@", self, exception);
    }
    if (error) {
        FastreamError(@"%@ error encoding api data: %@", self, error);
    }
    return data;
}

- (id)JSONSerializableObjectForObject:(id)obj
{
    // valid json types
    if ([obj isKindOfClass:[NSString class]] ||
        [obj isKindOfClass:[NSNumber class]] ||
        [obj isKindOfClass:[NSNull class]]) {
        return obj;
    }
    // recurse on containers
    if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray *a = [NSMutableArray array];
        for (id i in obj) {
            [a addObject:[self JSONSerializableObjectForObject:i]];
        }
        return [NSArray arrayWithArray:a];
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        for (id key in obj) {
            NSString *stringKey;
            if (![key isKindOfClass:[NSString class]]) {
                stringKey = [key description];
                FastreamDebug(@"%@ warning: property keys should be strings. got: %@. coercing to: %@", self, [key class], stringKey);
            } else {
                stringKey = [NSString stringWithString:key];
            }
            id v = [self JSONSerializableObjectForObject:obj[key]];
            d[stringKey] = v;
        }
        return [NSDictionary dictionaryWithDictionary:d];
    }
    // some common cases
    if ([obj isKindOfClass:[NSDate class]]) {
        return [self.dateFormatter stringFromDate:obj];
    } else if ([obj isKindOfClass:[NSURL class]]) {
        return [obj absoluteString];
    }
    // default to sending the object's description
    NSString *s = [obj description];
    FastreamDebug(@"%@ warning: property values should be valid json types. got: %@. coercing to: %@", self, [obj class], s);
    return s;
}

- (NSString *)encodeAPIData:(NSArray *)array
{
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:array options:NSJSONWritingPrettyPrinted error:nil];
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    return jsonString;
}

#pragma mark - Tracking

+ (void)assertPropertyTypes:(NSDictionary *)properties
{
    for (id __unused k in properties) {
        NSAssert([k isKindOfClass: [NSString class]], @"%@ property keys must be NSString. got: %@ %@", self, [k class], k);
        // would be convenient to do: id v = [properties objectForKey:k]; but
        // when the NSAssert's are stripped out in release, it becomes an
        // unused variable error. also, note that @YES and @NO pass as
        // instances of NSNumber class.
        NSAssert([properties[k] isKindOfClass:[NSString class]] ||
                 [properties[k] isKindOfClass:[NSNumber class]] ||
                 [properties[k] isKindOfClass:[NSNull class]] ||
                 [properties[k] isKindOfClass:[NSArray class]] ||
                 [properties[k] isKindOfClass:[NSDictionary class]] ||
                 [properties[k] isKindOfClass:[NSDate class]] ||
                 [properties[k] isKindOfClass:[NSURL class]],
                 @"%@ property values must be NSString, NSNumber, NSNull, NSArray, NSDictionary, NSDate or NSURL. got: %@ %@", self, [properties[k] class], properties[k]);
    }
}

- (NSString *)defaultDistinctId
{
    NSString *distinctId = [self IFA];

    if (!distinctId && NSClassFromString(@"UIDevice")) {
        distinctId = [[UIDevice currentDevice].identifierForVendor UUIDString];
    }
    if (!distinctId) {
        FastreamDebug(@"%@ error getting device identifier: falling back to uuid", self);
        distinctId = [[NSUUID UUID] UUIDString];
    }
    return distinctId;
}


- (void)identify:(NSString *)distinctId
{
    if (distinctId == nil || distinctId.length == 0) {
        FastreamDebug(@"%@ cannot identify blank distinct id: %@", self, distinctId);
        return;
    }
    dispatch_async(self.serialQueue, ^{
        self.distinctId = distinctId;
        if ([self inBackground]) {
            [self archiveProperties];
        }
    });
}

- (void)createAlias:(NSString *)alias forDistinctID:(NSString *)distinctID
{
    if (!alias || [alias length] == 0) {
        FastreamError(@"%@ create alias called with empty alias: %@", self, alias);
        return;
    }
    if (!distinctID || [distinctID length] == 0) {
        FastreamError(@"%@ create alias called with empty distinct id: %@", self, distinctID);
        return;
    }
    [self track:@"$create_alias" properties:@{@"distinct_id": distinctID, @"alias": alias}];
}

- (void)track:(NSString *)event
{
    [self track:event properties:nil];
}

- (void)trackCustomEvent:(NSDictionary *)customEvent{
    [self track:nil properties:nil customEvent:customEvent];
}

- (void)track:(NSString *)event customEvent:(NSDictionary *)customEvent{
    [self track:event properties:nil customEvent:customEvent];
}

- (void)track:(NSString *)event properties:(NSDictionary *)properties{
    [self track:event properties:properties customEvent:nil];
}

- (void)track:(NSString *)event properties:(NSDictionary *)properties customEvent:(NSDictionary*)customEvent
{
    if (event == nil || [event length] == 0) {
        FastreamError(@"%@ Fastream track called with empty event parameter. not using an event", self);
    }
    properties = [properties copy];
    [Fastream assertPropertyTypes:properties];

    double epochInterval = [[NSDate date] timeIntervalSince1970];
    NSNumber *epochSeconds = @(round(epochInterval));
    dispatch_async(self.serialQueue, ^{
        NSNumber *eventStartTime = self.timedEvents[event];
        NSMutableDictionary *p = [NSMutableDictionary dictionary];
        [p addEntriesFromDictionary:self.automaticProperties];
        p[@"token"] = self.apiToken;
        p[@"time"] = epochSeconds;
        if (eventStartTime) {
            [self.timedEvents removeObjectForKey:event];
            p[@"$duration"] = @([[NSString stringWithFormat:@"%.3f", epochInterval - [eventStartTime doubleValue]] floatValue]);
        }
        if (self.nameTag) {
            p[@"mp_name_tag"] = self.nameTag;
        }
        if (self.distinctId) {
            p[@"distinct_id"] = self.distinctId;
        }
        if (self.sessionId) {
            p[@"session_id"] = self.sessionId;
        }
        // TODO: add integer overflow check, and generate a new session id on overflow
        self.messageIndex = [NSNumber numberWithInt:[self.messageIndex intValue] + 1];
        p[@"message_index"] = self.messageIndex;
        p[kSendingTimeKey] = kSendingTimePlaceHolder;
        [p addEntriesFromDictionary:self.superProperties];
        if (properties) {
            [p addEntriesFromDictionary:properties];
        }
//        NSDictionary *e = @{@"event": event, @"properties": [NSDictionary dictionaryWithDictionary:p]};
        NSMutableDictionary *e = [NSMutableDictionary new];
        [e setObject:[NSDictionary dictionaryWithDictionary:p] forKeyedSubscript:@"properties"];
        if (event) {
            [e setObject:event forKeyedSubscript:@"event"];
        }
        if (customEvent) {
            NSMutableDictionary *args = [customEvent mutableCopy];
            [args addEntriesFromDictionary:e];
            e = args;
        }
        FastreamDebug(@"%@ queueing event: %@", self, e);
        [self.eventsQueue addObject:e];
        if ([self.eventsQueue count] > 500) {
            [self.eventsQueue removeObjectAtIndex:0];
        }
        if ([self inBackground]) {
            [self archiveEvents];
        }
    });

    if ([Fastream isAppExtension]) {
        [self flush];
    }
}


- (void)trackPushNotification:(NSDictionary *)userInfo event:(NSString *)event
{
    FastreamDebug(@"%@ tracking push payload %@", self, userInfo);

    if (userInfo && userInfo[@"mp"]) {
        NSDictionary *mpPayload = userInfo[@"mp"];

        if ([mpPayload isKindOfClass:[NSDictionary class]] && mpPayload[@"m"] && mpPayload[@"c"]) {
            [self track:event properties:@{@"campaign_id": mpPayload[@"c"],
                                           @"message_id": mpPayload[@"m"],
                                           @"message_type": @"push"}];
        } else {
            FastreamError(@"%@ malformed Fastream push payload %@", self, mpPayload);
        }
    }
}

- (void)trackPushNotification:(NSDictionary *)userInfo
{
    [self trackPushNotification:userInfo event:@"$campaign_received"];
}

- (void)registerSuperProperties:(NSDictionary *)properties
{
    properties = [properties copy];
    [Fastream assertPropertyTypes:properties];
    dispatch_async(self.serialQueue, ^{
        NSMutableDictionary *tmp = [NSMutableDictionary dictionaryWithDictionary:self.superProperties];
        [tmp addEntriesFromDictionary:properties];
        self.superProperties = [NSDictionary dictionaryWithDictionary:tmp];
        if ([self inBackground]) {
            [self archiveProperties];
        }
    });
}

- (void)registerSuperPropertiesOnce:(NSDictionary *)properties
{
    [self registerSuperPropertiesOnce:properties defaultValue:nil];
}

- (void)registerSuperPropertiesOnce:(NSDictionary *)properties defaultValue:(id)defaultValue
{
    properties = [properties copy];
    [Fastream assertPropertyTypes:properties];
    dispatch_async(self.serialQueue, ^{
        NSMutableDictionary *tmp = [NSMutableDictionary dictionaryWithDictionary:self.superProperties];
        for (NSString *key in properties) {
            id value = tmp[key];
            if (value == nil || [value isEqual:defaultValue]) {
                tmp[key] = properties[key];
            }
        }
        self.superProperties = [NSDictionary dictionaryWithDictionary:tmp];
        if ([self inBackground]) {
            [self archiveProperties];
        }
    });
}

- (void)unregisterSuperProperty:(NSString *)propertyName
{
    dispatch_async(self.serialQueue, ^{
        NSMutableDictionary *tmp = [NSMutableDictionary dictionaryWithDictionary:self.superProperties];
        if (tmp[propertyName] != nil) {
            [tmp removeObjectForKey:propertyName];
        }
        self.superProperties = [NSDictionary dictionaryWithDictionary:tmp];
        if ([self inBackground]) {
            [self archiveProperties];
        }
    });
}

- (void)clearSuperProperties
{
    dispatch_async(self.serialQueue, ^{
        self.superProperties = @{};
        if ([self inBackground]) {
            [self archiveProperties];
        }
    });
}

- (NSDictionary *)currentSuperProperties
{
    return [self.superProperties copy];
}

- (void)timeEvent:(NSString *)event
{
    if (event == nil || [event length] == 0) {
        FastreamError(@"Fastream cannot time an empty event");
        return;
    }
    dispatch_async(self.serialQueue, ^{
        self.timedEvents[event] = @([[NSDate date] timeIntervalSince1970]);
    });
}

- (void)clearTimedEvents
{   dispatch_async(self.serialQueue, ^{
        self.timedEvents = [NSMutableDictionary dictionary];
    });
}

- (void)reset
{
    dispatch_async(self.serialQueue, ^{
        self.distinctId = [self defaultDistinctId];
        self.nameTag = nil;
        self.superProperties = [NSMutableDictionary dictionary];
        self.eventsQueue = [NSMutableArray array];
        self.timedEvents = [NSMutableDictionary dictionary];
        [self archive];
    });
}

#pragma mark - Network control

- (NSUInteger)flushInterval
{
    @synchronized(self) {
        return _flushInterval;
    }
}

- (void)setFlushInterval:(NSUInteger)interval
{
    @synchronized(self) {
        _flushInterval = interval;
    }
    [self startFlushTimer];
}

- (void)startFlushTimer
{
    [self stopFlushTimer];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.flushInterval > 0) {
            self.timer = [NSTimer scheduledTimerWithTimeInterval:self.flushInterval
                                                          target:self
                                                        selector:@selector(flush)
                                                        userInfo:nil
                                                         repeats:YES];
            FastreamDebug(@"%@ started flush timer: %@", self, self.timer);
        }
    });
}

- (void)stopFlushTimer
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.timer) {
            [self.timer invalidate];
            FastreamDebug(@"%@ stopped flush timer: %@", self, self.timer);
        }
        self.timer = nil;
    });
}

- (void)flush
{
    dispatch_async(self.serialQueue, ^{
        FastreamDebug(@"%@ flush starting", self);

        __strong id<FastreamDelegate> strongDelegate = self.delegate;
        if (strongDelegate != nil && [strongDelegate respondsToSelector:@selector(fastreamWillFlush:)] && ![strongDelegate fastreamWillFlush:self]) {
            FastreamDebug(@"%@ flush deferred by delegate", self);
            return;
        }

        [self flushEvents];

        FastreamDebug(@"%@ flush complete", self);
    });
}

- (void)flushEvents
{
    [self flushQueue:_eventsQueue
            endpoint:[@"/inputs/api/" stringByAppendingString: [self apiToken]]];
}

- (void)flushQueue:(NSMutableArray *)queue endpoint:(NSString *)endpoint
{
    while ([queue count] > 0) {
        NSUInteger batchSize = ([queue count] > 50) ? 50 : [queue count];
        NSArray *batch = [queue subarrayWithRange:NSMakeRange(0, batchSize)];

        // adding Sending Timestamp
        double epochInterval = [[NSDate date] timeIntervalSince1970];
        for (NSMutableDictionary *event in batch){
            NSMutableDictionary *properties = [[event objectForKeyedSubscript:@"properties"] mutableCopy];
            properties[kSendingTimeKey] = @(round(epochInterval));
            [event setObject:[NSDictionary dictionaryWithDictionary:properties] forKeyedSubscript:@"properties"];
        }

        NSString *postBody = [self encodeAPIData:batch];
        FastreamDebug(@"%@ flushing %lu of %lu to %@: %@", self, (unsigned long)[batch count], (unsigned long)[queue count], endpoint, queue);
        NSURLRequest *request = [self apiRequestWithEndpoint:endpoint andBody:postBody];
        NSError *error = nil;

        [self updateNetworkActivityIndicator:YES];

        NSURLResponse *urlResponse = nil;
        NSData *responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&urlResponse error:&error];

        [self updateNetworkActivityIndicator:NO];
        
        if (error) {
            FastreamError(@"%@ network failure: %@", self, error);
            break;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *) urlResponse;
        NSInteger httpResponseStatusCode = [httpResponse statusCode];
        if (httpResponseStatusCode != 200) {
            FastreamError(@"%@ http failure: %@", self, httpResponseStatusCode);
            break;
        }

        [queue removeObjectsInArray:batch];
    }
}

- (NSURLRequest *)apiRequestWithEndpoint:(NSString *)endpoint andBody:(NSString *)body
{
    NSURL *URL = [NSURL URLWithString:[self.serverURL stringByAppendingString:endpoint]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL];
    [request setValue:@"gzip" forHTTPHeaderField:@"Accept-Encoding"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];
    FastreamDebug(@"%@ http request: %@?%@", self, URL, body);
    return request;
}

#pragma mark - Persistence

- (NSString *)filePathForData:(NSString *)data
{
    NSString *filename = [NSString stringWithFormat:@"fastream-%@-%@.plist", self.apiToken, data];
    return [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) lastObject]
            stringByAppendingPathComponent:filename];
}

- (NSString *)eventsFilePath
{
    return [self filePathForData:@"events"];
}

- (NSString *)propertiesFilePath
{
    return [self filePathForData:@"properties"];
}

- (void)archive
{
    [self archiveEvents];
    [self archiveProperties];
}

- (void)archiveEvents
{
    NSString *filePath = [self eventsFilePath];
    NSMutableArray *eventsQueueCopy = [NSMutableArray arrayWithArray:[self.eventsQueue copy]];
    FastreamDebug(@"%@ archiving events data to %@: %@", self, filePath, eventsQueueCopy);
    if (![NSKeyedArchiver archiveRootObject:eventsQueueCopy toFile:filePath]) {
        FastreamError(@"%@ unable to archive events data", self);
    }
}

- (void)archiveProperties
{
    NSString *filePath = [self propertiesFilePath];
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    [p setValue:self.distinctId forKey:@"distinctId"];
    [p setValue:self.nameTag forKey:@"nameTag"];
    [p setValue:self.superProperties forKey:@"superProperties"];
    [p setValue:self.timedEvents forKey:@"timedEvents"];
    FastreamDebug(@"%@ archiving properties data to %@: %@", self, filePath, p);
    if (![NSKeyedArchiver archiveRootObject:p toFile:filePath]) {
        FastreamError(@"%@ unable to archive properties data", self);
    }
}

- (void)unarchive
{
    [self unarchiveEvents];
    [self unarchiveProperties];
}

- (id)unarchiveFromFile:(NSString *)filePath
{
    id unarchivedData = nil;
    @try {
        unarchivedData = [NSKeyedUnarchiver unarchiveObjectWithFile:filePath];
        FastreamDebug(@"%@ unarchived data from %@: %@", self, filePath, unarchivedData);
    }
    @catch (NSException *exception) {
        FastreamError(@"%@ unable to unarchive data in %@, starting fresh", self, filePath);
        unarchivedData = nil;
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSError *error;
        BOOL removed = [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
        if (!removed) {
            FastreamError(@"%@ unable to remove archived file at %@ - %@", self, filePath, error);
        }
    }
    return unarchivedData;
}

- (void)unarchiveEvents
{
    self.eventsQueue = (NSMutableArray *)[self unarchiveFromFile:[self eventsFilePath]];
    if (!self.eventsQueue) {
        self.eventsQueue = [NSMutableArray array];
    }
}

- (void)unarchiveProperties
{
    NSDictionary *properties = (NSDictionary *)[self unarchiveFromFile:[self propertiesFilePath]];
    if (properties) {
        self.distinctId = properties[@"distinctId"] ? properties[@"distinctId"] : [self defaultDistinctId];
        self.nameTag = properties[@"nameTag"];
        self.superProperties = properties[@"superProperties"] ? properties[@"superProperties"] : [NSMutableDictionary dictionary];
        self.timedEvents = properties[@"timedEvents"] ? properties[@"timedEvents"] : [NSMutableDictionary dictionary];
    }
}

#pragma mark - Application Helpers

- (NSString *)description
{
    return [NSString stringWithFormat:@"<Fastream: %p %@>", self, self.apiToken];
}

- (NSString *)deviceModel
{
    size_t size;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    char answer[size];
    sysctlbyname("hw.machine", answer, &size, NULL, 0);
    NSString *results = @(answer);
    return results;
}

- (NSString *)watchModel
{
    NSString *model = nil;
    Class WKInterfaceDeviceClass = NSClassFromString(@"WKInterfaceDevice");
    if (WKInterfaceDeviceClass) {
        SEL currentDeviceSelector = NSSelectorFromString(@"currentDevice");
        id device = ((id (*)(id, SEL))[WKInterfaceDeviceClass methodForSelector:currentDeviceSelector])(WKInterfaceDeviceClass, currentDeviceSelector);
        SEL screenBoundsSelector = NSSelectorFromString(@"screenBounds");
        if (device && [device respondsToSelector:screenBoundsSelector]) {
            NSInvocation *screenBoundsInvocation = [NSInvocation invocationWithMethodSignature:[device methodSignatureForSelector:screenBoundsSelector]];
            [screenBoundsInvocation setSelector:screenBoundsSelector];
            [screenBoundsInvocation invokeWithTarget:device];
            CGRect screenBounds;
            [screenBoundsInvocation getReturnValue:(void *)&screenBounds];
             if(screenBounds.size.width == 136.0f){
                model = @"Apple Watch 38mm";
            } else if(screenBounds.size.width == 156.0f) {
                model = @"Apple Watch 42mm";
            } else {
                model = @"Apple Watch";
            }
        }
    }
    return model;
}

- (NSString *)IFA
{
    NSString *ifa = nil;
#if !defined(MIXPANEL_NO_IFA)
    Class ASIdentifierManagerClass = NSClassFromString(@"ASIdentifierManager");
    if (ASIdentifierManagerClass) {
        SEL sharedManagerSelector = NSSelectorFromString(@"sharedManager");
        id sharedManager = ((id (*)(id, SEL))[ASIdentifierManagerClass methodForSelector:sharedManagerSelector])(ASIdentifierManagerClass, sharedManagerSelector);
        SEL advertisingIdentifierSelector = NSSelectorFromString(@"advertisingIdentifier");
        NSUUID *uuid = ((NSUUID* (*)(id, SEL))[sharedManager methodForSelector:advertisingIdentifierSelector])(sharedManager, advertisingIdentifierSelector);
        ifa = [uuid UUIDString];
    }
#endif
    return ifa;
}

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 70000
- (void)setCurrentRadio
{
    dispatch_async(self.serialQueue, ^(){
        NSMutableDictionary *properties = [self.automaticProperties mutableCopy];
        properties[@"$radio"] = [self currentRadio];
        self.automaticProperties = [properties copy];
    });
}

- (NSString *)currentRadio
{
    NSString *radio = _telephonyInfo.currentRadioAccessTechnology;
    if (!radio) {
        radio = @"None";
    } else if ([radio hasPrefix:@"CTRadioAccessTechnology"]) {
        radio = [radio substringFromIndex:23];
    }
    return radio;
}
#endif

- (NSString *)libVersion
{
    return VERSION;
}

- (NSDictionary *)collectAutomaticProperties
{
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    UIDevice *device = [UIDevice currentDevice];
    NSString *deviceModel = [self deviceModel];
    CGSize size = [UIScreen mainScreen].bounds.size;
    CTCarrier *carrier = [self.telephonyInfo subscriberCellularProvider];

    // Use setValue semantics to avoid adding keys where value can be nil.
    [p setValue:[[NSBundle mainBundle] infoDictionary][@"CFBundleVersion"] forKey:@"$app_version"];
    [p setValue:[[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"] forKey:@"$app_release"];
    [p setValue:[self IFA] forKey:@"$ios_ifa"];
    [p setValue:carrier.carrierName forKey:@"$carrier"];
    [p setValue:[self watchModel] forKey:@"$watch_model"];

    [p addEntriesFromDictionary:@{
                                  @"mp_lib": @"iphone",
                                  @"$lib_version": [self libVersion],
                                  @"$manufacturer": @"Apple",
                                  @"$os": [device systemName],
                                  @"$os_version": [device systemVersion],
                                  @"$model": deviceModel,
                                  @"mp_device_model": deviceModel, //legacy
                                  @"$screen_height": @((NSInteger)size.height),
                                  @"$screen_width": @((NSInteger)size.width)
                                  }];
    return [p copy];
}

- (BOOL)inBackground
{
    if (![Fastream isAppExtension]) {
        return _inBG;
    }
    return NO;
}

- (void)updateNetworkActivityIndicator:(BOOL)on
{
    if (![Fastream isAppExtension]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.showNetworkActivityIndicator) {
                self.application.networkActivityIndicatorVisible = on;
            }
        });
    }
}

#if !defined(FASTREAM_APP_EXTENSION)

#pragma mark - UIApplication Events

- (void)setUpListeners
{
    // wifi reachability
    BOOL reachabilityOk = NO;
    NSURL* url = [NSURL URLWithString:self.serverURL];
    NSString* host = [url host];
    if ((_reachability = SCNetworkReachabilityCreateWithName(NULL, host.UTF8String)) != NULL) {
        SCNetworkReachabilityContext context = {0, (__bridge void*)self, NULL, NULL, NULL};
        if (SCNetworkReachabilitySetCallback(_reachability, FastreamReachabilityCallback, &context)) {
            if (SCNetworkReachabilitySetDispatchQueue(_reachability, self.serialQueue)) {
                reachabilityOk = YES;
                FastreamDebug(@"%@ successfully set up reachability callback", self);
            } else {
                // cleanup callback if setting dispatch queue failed
                SCNetworkReachabilitySetCallback(_reachability, NULL, NULL);
            }
        }
    }
    if (!reachabilityOk) {
        FastreamError(@"%@ failed to set up reachability callback: %s", self, SCErrorString(SCError()));
    }

    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];

    // cellular info
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 70000
    if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1) {
        [self setCurrentRadio];
        [notificationCenter addObserver:self
                               selector:@selector(setCurrentRadio)
                                   name:CTRadioAccessTechnologyDidChangeNotification
                                 object:nil];
    }
#endif

    // Application lifecycle events
    [notificationCenter addObserver:self
                           selector:@selector(applicationWillTerminate:)
                               name:UIApplicationWillTerminateNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(applicationWillResignActive:)
                               name:UIApplicationWillResignActiveNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(applicationDidBecomeActive:)
                               name:UIApplicationDidBecomeActiveNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(applicationDidEnterBackground:)
                               name:UIApplicationDidEnterBackgroundNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(applicationWillEnterForeground:)
                               name:UIApplicationWillEnterForegroundNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(appLinksNotificationRaised:)
                               name:@"com.parse.bolts.measurement_event"
                             object:nil];
}

static void FastreamReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *info)
{
    if (info != NULL && [(__bridge NSObject*)info isKindOfClass:[Fastream class]]) {
        @autoreleasepool {
            Fastream *fastream = (__bridge Fastream *)info;
            [fastream reachabilityChanged:flags];
        }
    } else {
        FastreamError(@"reachability callback received unexpected info object");
    }
}

- (void)reachabilityChanged:(SCNetworkReachabilityFlags)flags
{
    // this should be run in the serial queue. the reason we don't dispatch_async here
    // is because it's only ever called by the reachability callback, which is already
    // set to run on the serial queue. see SCNetworkReachabilitySetDispatchQueue in init
    BOOL wifi = (flags & kSCNetworkReachabilityFlagsReachable) && !(flags & kSCNetworkReachabilityFlagsIsWWAN);
    NSMutableDictionary *properties = [self.automaticProperties mutableCopy];
    properties[@"$wifi"] = wifi ? @YES : @NO;
    self.automaticProperties = [properties copy];
    FastreamDebug(@"%@ reachability changed, wifi=%d", self, wifi);
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    _inBG = false;
    FastreamDebug(@"%@ application did become active", self);
    [self startFlushTimer];
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    FastreamDebug(@"%@ application will resign active", self);
    [self stopFlushTimer];
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    _inBG = true;
    FastreamDebug(@"%@ did enter background", self);
    self.taskId = [self.application beginBackgroundTaskWithExpirationHandler:^{
        FastreamDebug(@"%@ flush %lu cut short", self, (unsigned long)self.taskId);
        [self.application endBackgroundTask:self.taskId];
        self.taskId = UIBackgroundTaskInvalid;
    }];
    FastreamDebug(@"%@ starting background cleanup task %lu", self, (unsigned long)self.taskId);

    if (self.flushOnBackground) {
        [self flush];
    }

    dispatch_async(_serialQueue, ^{
        [self archive];
        FastreamDebug(@"%@ ending background cleanup task %lu", self, (unsigned long)self.taskId);
        if (self.taskId != UIBackgroundTaskInvalid) {
            [self.application endBackgroundTask:self.taskId];
            self.taskId = UIBackgroundTaskInvalid;
        }
//        self.decideResponseCached = NO;
    });
}

- (void)applicationWillEnterForeground:(NSNotificationCenter *)notification
{
    FastreamDebug(@"%@ will enter foreground", self);
    dispatch_async(self.serialQueue, ^{
        if (self.taskId != UIBackgroundTaskInvalid) {
            [self.application endBackgroundTask:self.taskId];
            self.taskId = UIBackgroundTaskInvalid;
            [self updateNetworkActivityIndicator:NO];
        }
    });
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    FastreamDebug(@"%@ application will terminate", self);
    dispatch_async(_serialQueue, ^{
       [self archive];
    });
}

- (void)appLinksNotificationRaised:(NSNotification *)notification
{
    NSDictionary *eventMap = @{@"al_nav_out": @"$al_nav_out",
                               @"al_nav_in": @"$al_nav_in",
                               @"al_ref_back_out": @"$al_ref_back_out"
                               };
    NSDictionary *userInfo = [notification userInfo];
    if (userInfo && userInfo[@"event_name"] && userInfo[@"event_args"] && eventMap[userInfo[@"event_name"]]) {
        [self track:eventMap[userInfo[@"event_name"]] properties:userInfo[@"event_args"]];
    }
}

#endif

+ (BOOL)isAppExtension {
#if TARGET_OS_IOS
    return [[NSBundle mainBundle].bundlePath hasSuffix:@".appex"];
#else
    return NO;
#endif
}

@end
