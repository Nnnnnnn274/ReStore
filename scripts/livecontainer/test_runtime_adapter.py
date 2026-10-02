"""Run adapter integration checks without Xcode or signing credentials."""
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch
import os
import subprocess
import sys

from prepare_runtime import prepare


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "Dependencies/LiveContainer"
FILES = ("LiveContainer/LCSharedUtils.m", "LiveContainer/LCBootstrap.m",
         "LiveContainerSwiftUI/Utilities/LCUtils.m")


class RuntimeAdapterTests(unittest.TestCase):
    def test_fresh_build_embeds_every_required_runtime_product(self):
        bash = shutil.which("bash")
        if os.name == "nt":
            git_bash = Path("C:/Program Files/Git/bin/bash.exe")
            bash = str(git_bash) if git_bash.exists() else None
        if not bash:
            self.skipTest("Bash is unavailable")
        scratch = ROOT / "build"
        scratch.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as directory:
            root = Path(directory)
            self.assertTrue(root.resolve().is_relative_to(scratch.resolve()))
            source = root / "Dependencies/LiveContainer"
            for name in FILES:
                destination = source / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(SOURCE / name, destination)
            for name in ("LiveContainer.xcodeproj/project.pbxproj", "litehook/src/litehook.h",
                         "OpenSSL/Frameworks/iphoneos/OpenSSL.framework/OpenSSL"):
                destination = source / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.touch()
            shutil.copyfile(SOURCE / "LICENSE", source / "LICENSE")
            helpers = root / "scripts/livecontainer"
            helpers.mkdir(parents=True)
            shutil.copyfile(ROOT / "scripts/livecontainer/prepare_runtime.py", helpers / "prepare_runtime.py")
            harness = root / "test_build.sh"
            harness.write_text('''#!/bin/bash
set -euo pipefail
git() { echo e370a92dfc03ce109ebce00ed4a7cfc64ad1c801; }
shasum() { echo adapter-test; }
python3() { "$TEST_PYTHON" "$@"; }
rsync() {
    local source="${@: -2:1}" destination="${@: -1}"
    mkdir -p "$destination"
    cp -R "$source/." "$destination/"
}
xcodebuild() {
    local target="" destination="" previous=""
    for argument in "$@"; do
        if [[ "$previous" == "-target" ]]; then target="$argument"; fi
        if [[ "$argument" == CONFIGURATION_BUILD_DIR=* ]]; then destination="${argument#*=}"; fi
        previous="$argument"
    done
    case "$target" in
        LiveContainerShared|LiveContainerSwiftUI)
            mkdir -p "$destination/$target.framework"
            touch "$destination/$target.framework/$target" ;;
        TweakLoader|ZSign) touch "$destination/$target.dylib" ;;
        *) exit 2 ;;
    esac
}
source "$TEST_BUILD_SCRIPT"
''', encoding="utf-8", newline="\n")
            products = root / "Host/ReStore.app"
            products.mkdir(parents=True)
            def shell_path(path):
                absolute = Path(path).resolve().as_posix()
                return "/" + absolute[0].lower() + absolute[2:] if os.name == "nt" else absolute
            env = dict(os.environ, PLATFORM_NAME="iphoneos", SRCROOT=shell_path(root),
                       DERIVED_FILE_DIR=shell_path(root / "Derived"), CONFIGURATION="Debug",
                       SDK_VERSION="test", ARCHS="arm64", TARGET_BUILD_DIR=shell_path(root / "Host"),
                       FRAMEWORKS_FOLDER_PATH="ReStore.app/Frameworks",
                       UNLOCALIZED_RESOURCES_FOLDER_PATH="ReStore.app", CODE_SIGNING_ALLOWED="NO",
                       TEST_PYTHON=shell_path(sys.executable),
                       TEST_BUILD_SCRIPT=shell_path(ROOT / "scripts/livecontainer/build_runtime.sh"))
            result = subprocess.run([bash, shell_path(harness)], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            for name in ("LiveContainerShared.framework/LiveContainerShared",
                         "LiveContainerSwiftUI.framework/LiveContainerSwiftUI", "TweakLoader.dylib",
                         "ZSign.dylib", "OpenSSL.framework/OpenSSL"):
                self.assertTrue((products / "Frameworks" / name).is_file(), name)
            self.assertTrue((products / "LiveContainer-LICENSE.txt").is_file())

    def test_adapter_keeps_guest_bootstrap_and_returns_to_restore_host(self):
        originals = {name: (SOURCE / name).read_bytes() for name in FILES}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in FILES:
                destination = root / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(SOURCE / name, destination)
            modern_write_text = Path.write_text

            def legacy_write_text(path, data, encoding=None, errors=None):
                return modern_write_text(path, data, encoding=encoding, errors=errors)

            # Exercise the API signature available in Xcode's older bundled Python.
            with patch.object(Path, "write_text", legacy_write_text):
                prepare(root)
            bootstrap = (root / FILES[1]).read_text(encoding="utf-8")
            self.assertIn("ReStoreLiveContainerInitialize", bootstrap)
            self.assertIn("invokeAppMain(selectedApp, selectedContainer, argc, argv)", bootstrap)
            self.assertIn('dlsym(RTLD_DEFAULT, "ReStoreHostMain")', bootstrap)
            self.assertNotIn("return LiveContainerSwiftUIMain();", bootstrap)
            shared = (root / FILES[0]).read_text(encoding="utf-8")
            utils = (root / FILES[2]).read_text(encoding="utf-8")
            self.assertIn('@"ReStoreCertificateProvider"', shared)
            self.assertIn('@"certificatePassword"', shared)
            self.assertIn('@"appGroupIdentifier"', shared)
            self.assertIn('@"certificateData"', utils)
            # The provider reads Keychain; signing data must not be loaded from plaintext defaults.
            self.assertNotIn('return [nud objectForKey:@"LCCertificateData"]', utils)
        for name, data in originals.items():
            self.assertEqual((SOURCE / name).read_bytes(), data)


if __name__ == "__main__":
    unittest.main()
