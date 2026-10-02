#import "ReStoreRuntime.h"
#import <dlfcn.h>
#import <objc/message.h>

#if TARGET_OS_IOS
@protocol RSLCAppInfo <NSObject>
- (instancetype)initWithBundlePath:(NSString *)path;
- (NSString *)displayName;
- (NSString *)bundleIdentifier;
- (NSString *)version;
- (UIImage *)iconIsDarkIcon:(BOOL)dark;
- (void)setRelativeBundlePath:(NSString *)path;
- (void)setDataUUID:(NSString *)uuid;
- (void)setContainerInfo:(NSArray *)containers;
- (void)save;
- (void)patchExecAndSignIfNeedWithCompletionHandler:(void (^)(BOOL, NSString *))completion
                                   progressHandler:(void (^)(NSProgress *))progress
                                         forceSign:(BOOL)force;
@end

static void *runtimeHandle;
static void *interfaceHandle;
static BOOL initialized;

static NSError *RSLCError(NSString *message) {
    return [NSError errorWithDomain:@"ReStore.LiveContainer" code:1
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

BOOL RSLCInitialize(NSError **error) {
    #if TARGET_OS_SIMULATOR
    if (error) *error = RSLCError(@"LiveContainer runs on an iOS device. Use the simulator to test SideStore and Signing.");
    return NO;
    #endif
    if (initialized) return YES;
    NSString *frameworks = NSBundle.mainBundle.privateFrameworksPath;
    if (!frameworks) {
        if (error) *error = RSLCError(@"The built-in LiveContainer runtime is missing.");
        return NO;
    }
    setenv("LC_HOME_PATH", NSHomeDirectory().UTF8String, 0);
    NSString *shared = [frameworks stringByAppendingPathComponent:@"LiveContainerShared.framework/LiveContainerShared"];
    runtimeHandle = runtimeHandle ?: dlopen(shared.UTF8String, RTLD_NOW | RTLD_GLOBAL);
    if (!runtimeHandle) {
        if (error) *error = RSLCError(@"Could not load the built-in LiveContainer runtime. Rebuild with the LiveContainer build phase enabled.");
        return NO;
    }
    void (*initialize)(void) = dlsym(runtimeHandle, "ReStoreLiveContainerInitialize");
    if (!initialize) {
        if (error) *error = RSLCError(@"This LiveContainer runtime was not built with the ReStore adapter.");
        return NO;
    }
    initialize();
    NSString *interface = [frameworks stringByAppendingPathComponent:@"LiveContainerSwiftUI.framework/LiveContainerSwiftUI"];
    interfaceHandle = interfaceHandle ?: dlopen(interface.UTF8String, RTLD_NOW | RTLD_GLOBAL);
    if (!interfaceHandle || !NSClassFromString(@"LCAppInfo")) {
        if (error) *error = RSLCError(@"LiveContainer's app-management framework could not be loaded.");
        return NO;
    }
    initialized = YES;
    return YES;
}

BOOL RSLCShouldLaunchGuest(void) {
    NSString *selected = [NSUserDefaults.standardUserDefaults stringForKey:@"selected"];
    return selected.length > 0 && ![selected isEqualToString:@"ui"];
}

int RSLCLaunchGuest(int argc, char **argv) {
    NSError *error;
    if (!RSLCInitialize(&error)) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"selected"];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"selectedContainer"];
        [NSUserDefaults.standardUserDefaults setObject:error.localizedDescription forKey:@"error"];
        return -1;
    }
    int (*start)(int, char **) = dlsym(runtimeHandle, "LiveContainerMain");
    // Guest startup changes the process environment and needs proper testing on supported iOS versions.
    if (start) return start(argc, argv);
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"selected"];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"selectedContainer"];
    [NSUserDefaults.standardUserDefaults setObject:@"LiveContainer's startup entry point is missing." forKey:@"error"];
    return -1;
}

static id<RSLCAppInfo> RSLCInfo(NSString *path) {
    Class infoClass = NSClassFromString(@"LCAppInfo");
    return [(id<RSLCAppInfo>)[infoClass alloc] initWithBundlePath:path];
}

NSDictionary *RSLCAppMetadata(NSString *bundlePath, NSError **error) {
    if (!RSLCInitialize(error)) return nil;
    id<RSLCAppInfo> info = RSLCInfo(bundlePath);
    if (!info) {
        if (error) *error = RSLCError(@"Could not read this container app.");
        return nil;
    }
    NSMutableDictionary *metadata = [@{
        @"name": [info displayName] ?: bundlePath.lastPathComponent,
        @"bundleIdentifier": [info bundleIdentifier] ?: @"",
        @"version": [info version] ?: @""
    } mutableCopy];
    UIImage *icon = [info iconIsDarkIcon:NO];
    if (icon) metadata[@"icon"] = icon;
    return metadata;
}

void RSLCPrepareApp(NSString *bundlePath, NSString *containerID, void (^completion)(BOOL, NSString *)) {
    NSError *error;
    if (!RSLCInitialize(&error)) { completion(NO, error.localizedDescription); return; }
    Class provider = NSClassFromString(@"ReStoreCertificateProvider");
    if (!((id (*)(id, SEL))objc_msgSend)(provider, NSSelectorFromString(@"certificatePassword"))) {
        completion(NO, @"Import the certificate and private key that signed ReStore, or re-sign ReStore with your saved account before adding container apps.");
        return;
    }
    id<RSLCAppInfo> info = RSLCInfo(bundlePath);
    if (!info) { completion(NO, @"This IPA has no readable app bundle."); return; }
    [info setRelativeBundlePath:bundlePath.lastPathComponent];
    [info setDataUUID:containerID];
    [info setContainerInfo:@[@{@"folderName": containerID, @"name": @"Default",
                              @"isolateAppGroup": @YES, @"spoofIdentifierForVendor": @YES}]];
    [info save];
    [info patchExecAndSignIfNeedWithCompletionHandler:completion progressHandler:^(NSProgress *progress) {} forceSign:YES];
}

BOOL RSLCOpenApp(NSString *relativePath, NSString *containerID, NSError **error) {
    if (![relativePath.pathExtension isEqualToString:@"app"] ||
        ![[NSUUID alloc] initWithUUIDString:relativePath.stringByDeletingPathExtension] ||
        ![[NSUUID alloc] initWithUUIDString:containerID]) {
        if (error) *error = RSLCError(@"Invalid container identifier.");
        return NO;
    }
    if (!RSLCInitialize(error)) return NO;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:relativePath forKey:@"selected"];
    [defaults setObject:containerID forKey:@"selectedContainer"];
    [defaults setBool:NO forKey:@"LCOpenSideStore"];
    [defaults synchronize];
    Class shared = NSClassFromString(@"LCSharedUtils");
    SEL selector = NSSelectorFromString(@"launchToGuestApp");
    BOOL opened = ((BOOL (*)(id, SEL))objc_msgSend)(shared, selector);
    if (!opened) {
        [defaults removeObjectForKey:@"selected"];
        [defaults removeObjectForKey:@"selectedContainer"];
        if (error) *error = RSLCError(@"Could not restart into the container app. Close and reopen ReStore to try again.");
    }
    return opened;
}
#else
BOOL RSLCInitialize(NSError **error) { return NO; }
BOOL RSLCShouldLaunchGuest(void) { return NO; }
int RSLCLaunchGuest(int argc, char **argv) { return -1; }
NSDictionary *RSLCAppMetadata(NSString *path, NSError **error) { return nil; }
void RSLCPrepareApp(NSString *path, NSString *containerID, void (^completion)(BOOL, NSString *)) { completion(NO, @"LiveContainer requires iOS."); }
BOOL RSLCOpenApp(NSString *path, NSString *containerID, NSError **error) { return NO; }
#endif
