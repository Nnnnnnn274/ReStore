#!/bin/bash
set -euo pipefail
trap 'runtime_status=$?; if [[ "$runtime_status" -ne 0 ]]; then echo "error: Built-in LiveContainer build failed with exit status $runtime_status." >&2; fi' EXIT

# Build the runtime from source; it is shipped inside this app, with no IPA injection step.
if [[ "${PLATFORM_NAME:-}" != "iphoneos" ]]; then
    exit 0
fi

project_root="${SRCROOT:?}"
runtime_source="$project_root/Dependencies/LiveContainer"
runtime_build="${DERIVED_FILE_DIR:?}/ReStoreLiveContainer"
runtime_products="$runtime_build/Products"
runtime_revision="e370a92dfc03ce109ebce00ed4a7cfc64ad1c801"

if [[ ! -f "$runtime_source/LiveContainer.xcodeproj/project.pbxproj" ]]; then
    echo "error: Initialize Dependencies/LiveContainer and its submodules before building ReStore."
    exit 1
fi
if [[ "$(git -C "$runtime_source" rev-parse HEAD)" != "$runtime_revision" ]]; then
    echo "error: ReStore's runtime adapter requires the pinned LiveContainer 3.8.0 dependency."
    exit 1
fi
if [[ ! -f "$runtime_source/litehook/src/litehook.h" ]] ||
   [[ ! -f "$runtime_source/OpenSSL/Frameworks/iphoneos/OpenSSL.framework/OpenSSL" ]]; then
    echo "error: Initialize LiveContainer's recursive submodules before building."
    exit 1
fi

runtime_fingerprint="$(shasum -a 256 "$project_root/scripts/livecontainer/prepare_runtime.py" "$0")-${CONFIGURATION}-${SDK_VERSION}-${ARCHS}"
if [[ ! -f "$runtime_build/fingerprint" ]] || [[ "$(cat "$runtime_build/fingerprint")" != "$runtime_fingerprint" ]]; then
    mkdir -p "$runtime_build/Source" "$runtime_products"
    rsync -a --exclude='.git' "$runtime_source/" "$runtime_build/Source/"
    python3 "$project_root/scripts/livecontainer/prepare_runtime.py" "$runtime_build/Source"
    for runtime_target in LiveContainerShared LiveContainerSwiftUI ZSign; do
        xcodebuild build \
        -project "$runtime_build/Source/LiveContainer.xcodeproj" \
        -target "$runtime_target" \
        -configuration "${CONFIGURATION}" -sdk iphoneos \
        CONFIGURATION_BUILD_DIR="$runtime_products" \
        SYMROOT="$runtime_build/Build" OBJROOT="$runtime_build/Intermediates" \
        ARCHS="${ARCHS}" ONLY_ACTIVE_ARCH=NO \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
        ENABLE_USER_SCRIPT_SANDBOXING=NO
    done
    printf '%s' "$runtime_fingerprint" > "$runtime_build/fingerprint"
fi

framework_destination="${TARGET_BUILD_DIR:?}/${FRAMEWORKS_FOLDER_PATH:?}"
mkdir -p "$framework_destination"
# Remove optional products left by older incremental builds.
rm -f "$framework_destination/TweakLoader.dylib"
rm -rf "$framework_destination/CydiaSubstrate.framework"
for framework in LiveContainerShared LiveContainerSwiftUI; do
    rsync -a "$runtime_products/$framework.framework/" "$framework_destination/$framework.framework/"
done
if [[ ! -f "$runtime_products/ZSign.dylib" ]]; then
    echo "error: Required embedded runtime library ZSign was not built."
    exit 1
fi
cp "$runtime_products/ZSign.dylib" "$framework_destination/"
if [[ -d "$runtime_source/OpenSSL/Frameworks/iphoneos/OpenSSL.framework" ]]; then
    rsync -a "$runtime_source/OpenSSL/Frameworks/iphoneos/OpenSSL.framework/" "$framework_destination/OpenSSL.framework/"
fi
for required in LiveContainerShared LiveContainerSwiftUI; do
    if [[ ! -f "$framework_destination/$required.framework/$required" ]]; then
        echo "error: Required embedded runtime framework $required was not built."
        exit 1
    fi
done
if [[ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ]] && [[ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
    for product in "$framework_destination"/*.framework "$framework_destination"/*.dylib; do
        [[ -e "$product" ]] || continue
        /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --preserve-metadata=identifier "$product"
    done
fi
cp "$runtime_source/LICENSE" "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/LiveContainer-LICENSE.txt"
