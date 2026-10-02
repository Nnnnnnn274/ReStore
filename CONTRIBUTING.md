# Contributing to ReStore

This repository is an independent continuation of SideStore. Reports and contributions about ReStore belong in [this repository](https://github.com/Nnnnnnn274/ReStore), rather than upstream support channels.

Preserve upstream copyright and license notices. Contributions remain subject to [CERTIFICATE-OF-ORIGIN.md](CERTIFICATE-OF-ORIGIN.md). Never commit certificates, private keys, pairing files, account credentials, anisette data, or device identifiers.

## Development

Use macOS with Xcode supporting synchronized project groups. CI uses Xcode 26.4; the app supports iOS 15+.

```sh
git clone https://github.com/Nnnnnnn274/ReStore.git --recurse-submodules
cd ReStore
cp CodeSigning.xcconfig.sample CodeSigning.xcconfig
open ReStore.xcodeproj
```

Configure your development team and device signing locally. Build the **ReStore** scheme. The backup helper is **ReStoreBackup** and the widget is **ReStoreWidgetExtension**. Dependencies are pinned submodules and Swift packages; initialize them recursively before building.

To package an unsigned archive for sideloading:

```sh
make build fakesign ipa
```

The output is `ReStore.ipa`. `BUILD_CONFIG`, `MARKETING_VERSION`, and `BUNDLE_ID_SUFFIX` can be supplied to Make as described in the Makefile. The built-in LiveContainer phase compiles its runtime from source for device builds.

Use the `ReStoreTests` scheme for account and provisioning identity regressions, and `python3 scripts/livecontainer/test_runtime_adapter.py` for the runtime adapter. Validate signing, refresh, backup, and guest launch on a device when changing those paths. Windows can inspect the repository and run the Python adapter checks, but cannot compile the iOS targets.

Swift uses four spaces and LF line endings. Follow adjacent formatting and use tabs in Makefiles. Keep changes focused and explain their behavior and validation.
