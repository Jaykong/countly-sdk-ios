// CountlyLocationManager.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

NSString* const kCountlyRCOutputEndpoint        = @"/o";
NSString* const kCountlyRCSDKEndpoint           = @"/sdk";

NSString* const kCountlyRCKeyMethod             = @"method";
NSString* const kCountlyRCKeyFetchRemoteConfig  = @"fetch_remote_config";
NSString* const kCountlyRCKeyAppKey             = @"app_key";
NSString* const kCountlyRCKeyDeviceID           = @"device_id";
NSString* const kCountlyRCKeyMetrics            = @"metrics";
NSString* const kCountlyRCKeyKeys               = @"keys";
NSString* const kCountlyRCKeyOmitKeys           = @"omit_keys";

@interface CountlyRemoteConfig ()
@property (nonatomic) NSDictionary* cachedRemoteConfig;
@end

@implementation CountlyRemoteConfig

+ (instancetype)sharedInstance
{
    if (!CountlyCommon.sharedInstance.hasStarted)
        return nil;

    static CountlyRemoteConfig* s_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

- (instancetype)init
{
    if (self = [super init])
    {
        self.cachedRemoteConfig = [CountlyPersistency.sharedInstance retrieveRemoteConfig];
    }

    return self;
}

#pragma mark ---

- (void)startRemoteConfig
{
    if (!self.isEnabledOnInitialConfig)
        return;

    if (!CountlyConsentManager.sharedInstance.hasAnyConsent)
        return;

    COUNTLY_LOG(@"Fetching remote config on start...");

    [self fetchRemoteConfigForKeys:nil omitKeys:nil completionHandler:^(NSDictionary *remoteConfig, NSError *error)
    {
        if (!error)
        {
            COUNTLY_LOG(@"Fetching remote config on start is successful. \n%@", remoteConfig);

            self.cachedRemoteConfig = remoteConfig;
            [CountlyPersistency.sharedInstance storeRemoteConfig:self.cachedRemoteConfig];
        }
        else
        {
            COUNTLY_LOG(@"Fetching remote config on start failed: %@", error);
        }

        if (self.remoteConfigCompletionHandler)
            self.remoteConfigCompletionHandler(error);
    }];
}

- (id)remoteConfigValueForKey:(NSString *)key
{
    return self.cachedRemoteConfig[key];
}

#pragma mark ---

- (void)fetchRemoteConfigForKeys:(NSArray *)keys omitKeys:(NSArray *)omitKeys completionHandler:(void (^)(NSDictionary* remoteConfig, NSError * error))completionHandler
{
    if (!completionHandler)
        return;

    NSURL* remoteConfigURL = [self remoteConfigURLForKeys:keys omitKeys:omitKeys];

    NSURLRequest* request = [NSURLRequest requestWithURL:remoteConfigURL];
    NSURLSessionTask* task = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error)
    {
        if (error) //NOTE: remote config request error
        {
            COUNTLY_LOG(@"Request <%p> failed!\nError: %@", request, error);

            dispatch_async(dispatch_get_main_queue(), ^
            {
                completionHandler(nil, error);
            });

            return;
        }

        NSDictionary* remoteConfig = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];

        if (error) //NOTE: JSON parse error
        {
            COUNTLY_LOG(@"Remote Config Request <%p> failed!\nServer reply: %@", request, [data cly_stringUTF8]);

            dispatch_async(dispatch_get_main_queue(), ^
            {
                completionHandler(nil, error);
            });

            return;
        }

        COUNTLY_LOG(@"Remote Config Request <%p> successfully completed.", request);

        dispatch_async(dispatch_get_main_queue(), ^
        {
            completionHandler(remoteConfig, error);
        });
    }];

    [task resume];

    COUNTLY_LOG(@"Remote Config Request <%p> started:\n[%@] %@ \n%@", (id)request, request.HTTPMethod, request.URL.absoluteString, [request.HTTPBody cly_stringUTF8]);
}

- (NSURL *)remoteConfigURLForKeys:(NSArray *)keys omitKeys:(NSArray *)omitKeys
{
    NSString* URLString = [NSString stringWithFormat:@"%@%@%@?%@=%@&%@=%@&%@=%@",
                           CountlyConnectionManager.sharedInstance.host,
                           kCountlyRCOutputEndpoint, kCountlyRCSDKEndpoint,
                           kCountlyRCKeyMethod, kCountlyRCKeyFetchRemoteConfig,
                           kCountlyRCKeyAppKey, CountlyConnectionManager.sharedInstance.appKey,
                           kCountlyRCKeyDeviceID, CountlyDeviceInfo.sharedInstance.deviceID.cly_URLEscaped];
    if (keys)
    {
        URLString = [URLString stringByAppendingFormat:@"&%@=%@", kCountlyRCKeyKeys, keys.cly_JSONify];
    }
    else if (omitKeys)
    {
        URLString = [URLString stringByAppendingFormat:@"&%@=%@", kCountlyRCKeyOmitKeys, omitKeys.cly_JSONify];
    }

    if (CountlyConsentManager.sharedInstance.consentForSessions)
    {
        URLString = [URLString stringByAppendingFormat:@"&%@=%@", kCountlyRCKeyMetrics, [CountlyDeviceInfo metrics]];
    }

    return [NSURL URLWithString:URLString];
}

@end
