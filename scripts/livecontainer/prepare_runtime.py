"""Adapt a build-directory copy of the pinned LiveContainer source for ReStore."""
from pathlib import Path
import sys


def write_source(path, source):
    # Xcode's bundled Python does not support Path.write_text's newline argument.
    with path.open("w", encoding="utf-8", newline="\n") as output:
        output.write(source)


def replace_body(path, signature, body):
    source = path.read_text(encoding="utf-8")
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        if source[end] == "{":
            depth += 1
        elif source[end] == "}":
            depth -= 1
        end += 1
    source = source[:opening + 1] + "\n" + body + "\n" + source[end - 1:]
    write_source(path, source)


def remove_section(source, start_marker, end_marker):
    start = source.index(start_marker)
    end = source.index(end_marker, start)
    return source[:start] + source[end:]


def prepare(root):
    shared = root / "LiveContainer/LCSharedUtils.m"
    utilities = root / "LiveContainerSwiftUI/Utilities/LCUtils.m"
    replace_body(shared, "+ (NSString *)certificatePassword", """
    Class provider = NSClassFromString(@"ReStoreCertificateProvider");
    return ((id (*)(id, SEL))objc_msgSend)(provider, NSSelectorFromString(@"certificatePassword"));""")
    replace_body(shared, "+ (NSString *)appGroupID", """
    Class provider = NSClassFromString(@"ReStoreCertificateProvider");
    return ((id (*)(id, SEL))objc_msgSend)(provider, NSSelectorFromString(@"appGroupIdentifier"));""")
    replace_body(utilities, "+ (NSData *)certificateData", """
    Class provider = NSClassFromString(@"ReStoreCertificateProvider");
    return ((id (*)(id, SEL))objc_msgSend)(provider, NSSelectorFromString(@"certificateData"));""")
    for path in (shared, utilities):
        source = path.read_text(encoding="utf-8")
        if "#import <objc/message.h>" not in source:
            write_source(path, "#import <objc/message.h>\n" + source)

    bootstrap = root / "LiveContainer/LCBootstrap.m"
    source = bootstrap.read_text(encoding="utf-8")
    initializer = """
__attribute__((visibility("default"))) void ReStoreLiveContainerInitialize(void) {
    lcMainBundle = NSBundle.mainBundle;
    lcUserDefaults = NSUserDefaults.standardUserDefaults;
    lcSharedDefaults = [[NSUserDefaults alloc] initWithSuiteName:[LCSharedUtils appGroupID]];
    lcAppUrlScheme = lcMainBundle.infoDictionary[@"CFBundleURLTypes"][0][@"CFBundleURLSchemes"][0];
    lcAppGroupPath = [LCSharedUtils appGroupPath].path;
    setenv("LC_HOME_PATH", NSHomeDirectory().UTF8String, 0);
}

"""
    source = source.replace("int LiveContainerMain(int argc, char *argv[]) {", initializer + "int LiveContainerMain(int argc, char *argv[]) {", 1)
    start = source.index('    void *LiveContainerSwiftUIHandle = dlopen(')
    end_marker = "    return LiveContainerSwiftUIMain();"
    end = source.index(end_marker, start) + len(end_marker)
    source = source[:start] + """    int (*hostMain)(int, char **) = dlsym(RTLD_DEFAULT, "ReStoreHostMain");
    return hostMain ? hostMain(argc, argv) : 1;""" + source[end:]
    source = remove_section(source, "    // Setup tweak loader", "    // If JIT is enabled")
    source = remove_section(source, '    if(![guestAppInfo[@"dontInjectTweakLoader"] boolValue]) {',
                            "    // Preload executable")
    source = remove_section(source, '    if([guestAppInfo[@"dontInjectTweakLoader"] boolValue] &&',
                            "    // Fix dynamic properties")
    write_source(bootstrap, source)

    app_info = root / "LiveContainerSwiftUI/Models/LCAppInfo.m"
    source = app_info.read_text(encoding="utf-8")
    # Revision 8 re-patches existing guests to neutralize the old TweakLoader load command.
    source = source.replace("    int currentPatchRev = 7;", """    [self setDontInjectTweakLoader:YES];
    [self setDontLoadTweakLoader:YES];
    int currentPatchRev = 8;""", 1)
    source = source.replace("LCPatchExecSlice(path, header, ![self dontInjectTweakLoader])",
                            "LCPatchExecSlice(path, header, false)", 1)
    write_source(app_info, source)

    macho = root / "LiveContainer/LCMachOUtils.m"
    source = macho.read_text(encoding="utf-8")
    # Keep removal of legacy injection, without adding a placeholder to fresh guests.
    source = source.replace("    } else  {\n        if (freeLoadCommandCountLeft >= tweakLoaderLoadDylibCmdSize)",
                            "    } else if (doInject) {\n        if (freeLoadCommandCountLeft >= tweakLoaderLoadDylibCmdSize)", 1)
    write_source(macho, source)


if __name__ == "__main__":
    prepare(Path(sys.argv[1]).resolve())
