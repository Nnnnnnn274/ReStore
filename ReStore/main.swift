import UIKit

@_cdecl("ReStoreHostMain")
func reStoreHostMain(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32 {
    // Both process startup and LiveContainer's host callback enter on the main thread.
    MainActor.assumeIsolated {
        UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.self))
    }
}

#if os(iOS)
ReStoreCertificateProvider.prepareHost()
if RSLCShouldLaunchGuest() {
    let result = RSLCLaunchGuest(CommandLine.argc, CommandLine.unsafeArgv)
    if result >= 0 { exit(result) }
}
#endif
_ = reStoreHostMain(CommandLine.argc, CommandLine.unsafeArgv)
