#import "VTMRootListController.h"
#import <spawn.h>
extern char **environ;
static NSString *const VTMPreferencesDomain = @"com.aaz.vpntriggermanager";
static NSString *const VTMTestRequested = @"com.aaz.vpntriggermanager/test.requested";
@implementation VTMRootListController
- (NSString *)title { return @"VPN Trigger Manager"; }

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}
- (void)runTest {
    CFPreferencesSetAppValue(CFSTR("lastTestResult"), CFSTR("Requesting test…"), (__bridge CFStringRef)VTMPreferencesDomain); CFPreferencesAppSynchronize((__bridge CFStringRef)VTMPreferencesDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)VTMTestRequested, NULL, NULL, YES);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"VPN Test Started" message:@"A 15-second incoming-call simulation has started. The tweak will try to start an available Packet Tunnel VPN, detect it, then disconnect only that new connection. Keep Settings open for the result." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:alert animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [self showLastTestResult]; });
}
- (void)showLastTestResult {
    CFPreferencesAppSynchronize((__bridge CFStringRef)VTMPreferencesDomain); CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("lastTestResult"), (__bridge CFStringRef)VTMPreferencesDomain);
    NSString *result = value ? [(__bridge id)value description] : @"No test result is available yet.";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Last Test Result" message:result preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:alert animated:YES completion:nil]; if (value) CFRelease(value);
}
- (void)respring {
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Respring" message:@"Restart SpringBoard now to reload the tweak?" preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Respring" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        const char *paths[] = { "/var/jb/usr/bin/sbreload", "/usr/bin/sbreload", "/usr/bin/killall" };
        for (NSUInteger i = 0; i < 3; i++) { if (![[NSFileManager defaultManager] isExecutableFileAtPath:[NSString stringWithUTF8String:paths[i]]]) continue; pid_t pid; char *const argsSbreload[] = { (char *)paths[i], NULL }; char *const argsKillall[] = { (char *)paths[i], "-9", "SpringBoard", NULL }; posix_spawn(&pid, paths[i], NULL, NULL, i == 2 ? argsKillall : argsSbreload, environ); break; }
    }]]; [self presentViewController:confirm animated:YES completion:nil];
}
@end
