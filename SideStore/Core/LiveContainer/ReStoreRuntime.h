#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
BOOL RSLCInitialize(NSError * _Nullable * _Nullable error);
BOOL RSLCShouldLaunchGuest(void);
int RSLCLaunchGuest(int argc, char * _Nullable * _Nonnull argv);
NSDictionary * _Nullable RSLCAppMetadata(NSString *bundlePath, NSError * _Nullable * _Nullable error);
void RSLCPrepareApp(NSString *bundlePath, NSString *containerID,
                    void (^completion)(BOOL success, NSString * _Nullable message));
BOOL RSLCOpenApp(NSString *relativePath, NSString *containerID, NSError * _Nullable * _Nullable error);
NS_ASSUME_NONNULL_END
