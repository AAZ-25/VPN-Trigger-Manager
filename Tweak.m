#import <Foundation/Foundation.h>
#import <CallKit/CallKit.h>
#import <NetworkExtension/NetworkExtension.h>
#import <ifaddrs.h>
#import <net/if.h>

static NSString *const VTMPreferencesDomain = @"com.aaz.vpntriggermanager";
static NSString *const VTMPreferencesChanged = @"com.aaz.vpntriggermanager/preferences.changed";
static NSString *const VTMTestRequested = @"com.aaz.vpntriggermanager/test.requested";
static NSString *const VTMTestFinished = @"com.aaz.vpntriggermanager/test.finished";
static NSString *const VTMLogPath = @"/var/mobile/Library/Logs/VPNTriggerManager.log";

static BOOL VTMEnabled = YES, VTMLoggingEnabled = NO, VTMStopPersonalVPN = NO;
static BOOL VTMVerifyDisconnect = YES, VTMRetryDisconnect = YES;
static BOOL VTMDisableOnDemand = NO, VTMAutoStartTestVPN = YES;

static void VTMLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void VTMLog(NSString *format, ...) {
    if (!VTMLoggingEnabled) return;
    va_list args; va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    static NSDateFormatter *formatter; static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    });
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [formatter stringFromDate:[NSDate date]], message];
    NSLog(@"[VPNTriggerManager] %@", message);
    @try {
        NSString *directory = [VTMLogPath stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:VTMLogPath error:nil];
        if ([attributes fileSize] > 1024 * 1024) [[NSFileManager defaultManager] removeItemAtPath:VTMLogPath error:nil];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        if (![[NSFileManager defaultManager] fileExistsAtPath:VTMLogPath]) [data writeToFile:VTMLogPath atomically:YES];
        else { NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:VTMLogPath]; [handle seekToEndOfFile]; [handle writeData:data]; [handle closeFile]; }
    } @catch (__unused NSException *exception) {}
}

static BOOL VTMReadBool(NSString *key, BOOL fallback) {
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)VTMPreferencesDomain);
    if (!value) return fallback;
    BOOL result = fallback;
    if (CFGetTypeID(value) == CFBooleanGetTypeID()) result = CFBooleanGetValue(value);
    else if (CFGetTypeID(value) == CFNumberGetTypeID()) result = [(__bridge NSNumber *)value boolValue];
    CFRelease(value); return result;
}

static void VTMLoadPreferences(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)VTMPreferencesDomain);
    VTMEnabled = VTMReadBool(@"enabled", YES);
    VTMLoggingEnabled = VTMReadBool(@"loggingEnabled", NO);
    VTMStopPersonalVPN = VTMReadBool(@"stopPersonalVPN", NO);
    VTMVerifyDisconnect = VTMReadBool(@"verifyDisconnect", YES);
    VTMRetryDisconnect = VTMReadBool(@"retryDisconnect", YES);
    VTMDisableOnDemand = VTMReadBool(@"disableOnDemand", NO);
    VTMAutoStartTestVPN = VTMReadBool(@"autoStartTestVPN", YES);
    VTMLog(@"Preferences loaded. enabled=%@ personal=%@ verify=%@ retry=%@ onDemand=%@ autoTest=%@",
           VTMEnabled ? @"YES" : @"NO", VTMStopPersonalVPN ? @"YES" : @"NO",
           VTMVerifyDisconnect ? @"YES" : @"NO", VTMRetryDisconnect ? @"YES" : @"NO",
           VTMDisableOnDemand ? @"YES" : @"NO", VTMAutoStartTestVPN ? @"YES" : @"NO");
}

static void VTMPreferencesDidChange(CFNotificationCenterRef c, void *o, CFStringRef n, const void *obj, CFDictionaryRef info) { VTMLoadPreferences(); }

static NSSet<NSString *> *VTMCurrentTunnelInterfaces(void) {
    NSMutableSet<NSString *> *interfaces = [NSMutableSet set]; struct ifaddrs *addresses = NULL;
    if (getifaddrs(&addresses) == 0) {
        for (struct ifaddrs *cursor = addresses; cursor; cursor = cursor->ifa_next) {
            if (!cursor->ifa_name) continue;
            NSString *name = [NSString stringWithUTF8String:cursor->ifa_name];
            if ([name hasPrefix:@"utun"] && (cursor->ifa_flags & IFF_UP)) [interfaces addObject:name];
        }
        freeifaddrs(addresses);
    }
    return interfaces.copy;
}

static BOOL VTMVPNStatusIsActive(NEVPNStatus status) { return status == NEVPNStatusConnecting || status == NEVPNStatusConnected || status == NEVPNStatusReasserting; }
static NSString *VTMVPNStatusName(NEVPNStatus status) {
    switch (status) {
        case NEVPNStatusInvalid: return @"invalid"; case NEVPNStatusDisconnected: return @"disconnected";
        case NEVPNStatusConnecting: return @"connecting"; case NEVPNStatusConnected: return @"connected";
        case NEVPNStatusReasserting: return @"reasserting"; case NEVPNStatusDisconnecting: return @"disconnecting";
    }
    return [NSString stringWithFormat:@"unknown(%ld)", (long)status];
}

static NSString *VTMManagerKey(NETunnelProviderManager *manager) {
    NETunnelProviderProtocol *protocol = (NETunnelProviderProtocol *)manager.protocolConfiguration;
    return [NSString stringWithFormat:@"%@|%@|%@", manager.localizedDescription ?: @"", protocol.providerBundleIdentifier ?: @"", protocol.serverAddress ?: @""];
}

static void VTMStoreTestResult(NSString *result) {
    CFPreferencesSetAppValue(CFSTR("lastTestResult"), (__bridge CFStringRef)result, (__bridge CFStringRef)VTMPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)VTMPreferencesDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)VTMTestFinished, NULL, NULL, YES);
    VTMLog(@"Test result: %@", result);
}

static void VTMRestoreOnDemand(NSSet<NSString *> *restoreKeys) {
    if (restoreKeys.count == 0) return;
    [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray<NETunnelProviderManager *> *managers, NSError *error) {
        if (error) { VTMLog(@"Connect On Demand restore load failed. domain=%@ code=%ld", error.domain ?: @"unknown", (long)error.code); return; }
        for (NETunnelProviderManager *manager in managers) {
            if (![restoreKeys containsObject:VTMManagerKey(manager)] || manager.onDemandEnabled) continue;
            manager.onDemandEnabled = YES;
            [manager saveToPreferencesWithCompletionHandler:^(NSError *saveError) {
                VTMLog(@"Connect On Demand restore completed. success=%@", saveError ? @"NO" : @"YES");
            }];
        }
        VTMLog(@"Connect On Demand restore requested. targets=%lu", (unsigned long)restoreKeys.count);
    }];
}

static void VTMVerifyTargets(NSSet<NSString *> *targetKeys, NSSet<NSString *> *restoreKeys, NSUInteger attempt, BOOL isTest) {
    [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray<NETunnelProviderManager *> *managers, NSError *error) {
        if (error) {
            VTMLog(@"Packet tunnel verification failed. domain=%@ code=%ld", error.domain ?: @"unknown", (long)error.code);
            VTMRestoreOnDemand(restoreKeys);
            if (isTest) VTMStoreTestResult(@"Failed: could not verify the VPN status.");
            return;
        }
        NSMutableArray *activeTargets = [NSMutableArray array];
        for (NETunnelProviderManager *manager in managers)
            if ([targetKeys containsObject:VTMManagerKey(manager)] && VTMVPNStatusIsActive(manager.connection.status)) [activeTargets addObject:manager];
        if (activeTargets.count == 0) {
            VTMLog(@"Target VPN disconnect confirmed. active=0");
            VTMRestoreOnDemand(restoreKeys);
            if (isTest) VTMStoreTestResult(@"Success: the simulated call detected and disconnected the new VPN.");
        } else if (attempt == 1 && VTMRetryDisconnect) {
            for (NETunnelProviderManager *manager in activeTargets) [manager.connection stopVPNTunnel];
            VTMLog(@"Target VPN still active; retrying once. count=%lu", (unsigned long)activeTargets.count);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                VTMVerifyTargets(targetKeys, restoreKeys, 2, isTest);
            });
        } else {
            VTMLog(@"Target VPN disconnect not confirmed. count=%lu", (unsigned long)activeTargets.count);
            VTMRestoreOnDemand(restoreKeys);
            if (isTest) VTMStoreTestResult(@"Failed: the VPN remained active after the stop request.");
        }
    }];
}

static void VTMStopTargets(NSSet<NSString *> *baselineManagerKeys, BOOL isTest) {
    [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray<NETunnelProviderManager *> *managers, NSError *error) {
        if (error) {
            VTMLog(@"Packet tunnel configuration load failed. domain=%@ code=%ld", error.domain ?: @"unknown", (long)error.code);
            if (isTest) VTMStoreTestResult(@"Failed: could not load Packet Tunnel configurations.");
            return;
        }
        NSMutableSet *targetKeys = [NSMutableSet set];
        NSMutableSet *restoreOnDemandKeys = [NSMutableSet set];
        for (NETunnelProviderManager *manager in managers) {
            NSString *key = VTMManagerKey(manager);
            if (!VTMVPNStatusIsActive(manager.connection.status) || [baselineManagerKeys containsObject:key]) continue;
            [targetKeys addObject:key];
            void (^stopBlock)(void) = ^{
                [manager.connection stopVPNTunnel];
                VTMLog(@"Packet tunnel stop sent. status=%@", VTMVPNStatusName(manager.connection.status));
            };
            if (VTMDisableOnDemand && manager.onDemandEnabled) {
                [restoreOnDemandKeys addObject:key];
                manager.onDemandEnabled = NO;
                [manager saveToPreferencesWithCompletionHandler:^(NSError *saveError) {
                    VTMLog(@"Connect On Demand temporary disable completed. success=%@", saveError ? @"NO" : @"YES");
                    stopBlock();
                }];
            } else stopBlock();
        }
        VTMLog(@"Target scan complete. configurations=%lu targets=%lu preserved=%lu", (unsigned long)managers.count, (unsigned long)targetKeys.count, (unsigned long)baselineManagerKeys.count);
        if (targetKeys.count == 0) {
            if (isTest) VTMStoreTestResult(@"No new Packet Tunnel VPN was detected during the simulated call.");
            return;
        }
        NSSet *targets = targetKeys.copy;
        NSSet *restoreKeys = restoreOnDemandKeys.copy;
        if (VTMVerifyDisconnect) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                VTMVerifyTargets(targets, restoreKeys, 1, isTest);
            });
        } else {
            if (isTest) VTMStoreTestResult(@"Stop request sent. Enable verification to confirm disconnection.");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                VTMRestoreOnDemand(restoreKeys);
            });
        }
    }];
    if (VTMStopPersonalVPN) {
        [[NEVPNManager sharedManager] loadFromPreferencesWithCompletionHandler:^(NSError *error) {
            NEVPNManager *manager = [NEVPNManager sharedManager];
            if (!error && VTMVPNStatusIsActive(manager.connection.status)) {
                [manager.connection stopVPNTunnel];
                VTMLog(@"Optional Personal VPN stop sent. status=%@", VTMVPNStatusName(manager.connection.status));
            }
        }];
    } else VTMLog(@"Personal VPN preserved by preference.");
}

@interface VTMCallMonitor : NSObject <CXCallObserverDelegate>
@property(nonatomic,strong) CXCallObserver *observer; @property(nonatomic,strong) dispatch_queue_t queue; @property(nonatomic,strong) dispatch_source_t tunnelTimer;
@property(nonatomic,copy) NSSet<NSString *> *baselineTunnels; @property(nonatomic,copy) NSSet<NSString *> *baselineManagerKeys;
@property(nonatomic,assign) BOOL trackingIncomingCall, tunnelAppearedDuringCall, syntheticTest;
@end

@implementation VTMCallMonitor
+ (instancetype)sharedMonitor { static VTMCallMonitor *m; static dispatch_once_t once; dispatch_once(&once, ^{ m = [VTMCallMonitor new]; }); return m; }
- (void)start { self.queue = dispatch_queue_create("com.aaz.vpntriggermanager.calls", DISPATCH_QUEUE_SERIAL); self.observer = [CXCallObserver new]; [self.observer setDelegate:self queue:self.queue]; VTMLog(@"Loaded in process: %@", NSProcessInfo.processInfo.processName); VTMLog(@"CXCallObserver started"); }
- (BOOL)hasActiveIncomingCall { for (CXCall *call in self.observer.calls) if (!call.outgoing && !call.hasEnded) return YES; return NO; }
- (void)callObserver:(CXCallObserver *)observer callChanged:(CXCall *)call { if (self.syntheticTest) return; BOOL active = [self hasActiveIncomingCall]; if (active && !self.trackingIncomingCall) [self beginTrackingTest:NO]; else if (!active && self.trackingIncomingCall) [self finishTracking]; }
- (void)captureActiveManagersAndContinue:(void (^)(void))completion {
    [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray<NETunnelProviderManager *> *managers, NSError *error) {
        NSMutableSet *keys = [NSMutableSet set]; if (!error) for (NETunnelProviderManager *manager in managers) if (VTMVPNStatusIsActive(manager.connection.status)) [keys addObject:VTMManagerKey(manager)];
        dispatch_async(self.queue, ^{ self.baselineManagerKeys = keys.copy; completion(); });
    }];
}
- (void)beginTrackingTest:(BOOL)isTest {
    if (!VTMEnabled) { VTMLog(@"Tracking ignored because tweak is disabled"); if (isTest) VTMStoreTestResult(@"Test could not start because the tweak is disabled."); return; }
    self.trackingIncomingCall = YES; self.syntheticTest = isTest; self.tunnelAppearedDuringCall = NO; self.baselineTunnels = VTMCurrentTunnelInterfaces();
    [self captureActiveManagersAndContinue:^{
        if (!self.trackingIncomingCall) { VTMLog(@"Tracking ended before the Packet Tunnel baseline finished loading"); return; }
        VTMLog(@"%@ call started. baselineTunnels=%lu activePacketVPNs=%lu", isTest ? @"Simulated" : @"Incoming", (unsigned long)self.baselineTunnels.count, (unsigned long)self.baselineManagerKeys.count);
        self.tunnelTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.queue);
        dispatch_source_set_timer(self.tunnelTimer, dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), 750 * NSEC_PER_MSEC, 100 * NSEC_PER_MSEC);
        __weak typeof(self) weakSelf = self; dispatch_source_set_event_handler(self.tunnelTimer, ^{ [weakSelf inspectTunnels]; }); dispatch_resume(self.tunnelTimer);
        if (isTest && VTMAutoStartTestVPN) [self autoStartTestVPN];
        if (isTest) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC), self.queue, ^{ if (self.syntheticTest) [self finishTracking]; });
    }];
}
- (void)autoStartTestVPN {
    [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray<NETunnelProviderManager *> *managers, NSError *error) {
        if (error) { VTMLog(@"Test auto-start load failed. domain=%@ code=%ld", error.domain ?: @"unknown", (long)error.code); return; }
        for (NETunnelProviderManager *manager in managers) {
            if (VTMVPNStatusIsActive(manager.connection.status) || !manager.enabled) continue;
            NSError *startError = nil; BOOL started = [manager.connection startVPNTunnelAndReturnError:&startError];
            VTMLog(@"Test auto-start requested. started=%@ errorDomain=%@ errorCode=%ld", started ? @"YES" : @"NO", startError.domain ?: @"none", (long)startError.code); return;
        }
        VTMLog(@"Test auto-start found no eligible disconnected Packet Tunnel configuration");
    }];
}
- (void)inspectTunnels { if (!self.trackingIncomingCall) return; NSMutableSet *newTunnels = VTMCurrentTunnelInterfaces().mutableCopy; [newTunnels minusSet:self.baselineTunnels ?: [NSSet set]]; if (newTunnels.count && !self.tunnelAppearedDuringCall) { self.tunnelAppearedDuringCall = YES; VTMLog(@"New tunnel detected during %@ call. count=%lu", self.syntheticTest ? @"simulated" : @"incoming", (unsigned long)newTunnels.count); } }
- (void)finishTracking {
    [self inspectTunnels]; BOOL wasTest = self.syntheticTest; self.trackingIncomingCall = NO; self.syntheticTest = NO;
    if (self.tunnelTimer) { dispatch_source_cancel(self.tunnelTimer); self.tunnelTimer = nil; }
    BOOL shouldStop = self.tunnelAppearedDuringCall; NSSet *baselineKeys = self.baselineManagerKeys ?: [NSSet set];
    VTMLog(@"%@ call ended. VPN-started-during-call=%@", wasTest ? @"Simulated" : @"Tracked incoming", shouldStop ? @"YES" : @"NO");
    self.baselineTunnels = nil; self.baselineManagerKeys = nil; self.tunnelAppearedDuringCall = NO;
    if (shouldStop) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1200 * NSEC_PER_MSEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ VTMStopTargets(baselineKeys, wasTest); });
    else if (wasTest) VTMStoreTestResult(@"No new VPN tunnel was detected during the 15-second test.");
}
- (void)requestSyntheticTest { dispatch_async(self.queue, ^{ if (self.trackingIncomingCall) { VTMStoreTestResult(@"Test not started: a call or another test is already active."); return; } VTMStoreTestResult(@"Test running: simulating an incoming call for 15 seconds…"); [self beginTrackingTest:YES]; }); }
@end

static void VTMTestDidRequest(CFNotificationCenterRef c, void *o, CFStringRef n, const void *obj, CFDictionaryRef info) { [[VTMCallMonitor sharedMonitor] requestSyntheticTest]; }
__attribute__((constructor)) static void VTMInitialize(void) {
    @autoreleasepool { VTMLoadPreferences();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, VTMPreferencesDidChange, (__bridge CFStringRef)VTMPreferencesChanged, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, VTMTestDidRequest, (__bridge CFStringRef)VTMTestRequested, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        dispatch_async(dispatch_get_main_queue(), ^{ [[VTMCallMonitor sharedMonitor] start]; });
    }
}
