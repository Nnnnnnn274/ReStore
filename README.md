# ReStore

ReStore is an independent continuation of [SideStore](https://github.com/SideStore/SideStore), which originated from [AltStore](https://github.com/rileytestut/AltStore). ReStore is not an official SideStore or AltStore release.

[![Nightly ReStore build](https://github.com/Nnnnnnn274/ReStore/actions/workflows/nightly.yml/badge.svg)](https://github.com/Nnnnnnn274/ReStore/actions/workflows/nightly.yml)

[Download ReStore](https://github.com/Nnnnnnn274/ReStore/releases/tag/nightly) · [Report a ReStore issue](https://github.com/Nnnnnnn274/ReStore/issues)

## Features

The iOS interface has two large sections: **LiveContainer** and **ReStore**, with a persistent hide/show control. The ReStore workspace includes News, Sources, Browse, My Apps, Settings, and Signing.

Signing supports multiple Apple accounts saved in Keychain. Apps retain their signing account and refresh sequentially with that account's credentials and certificate. Removing an account leaves its apps assigned to it, so refreshing requests the missing account instead of silently changing the signer.

Custom signing works without Apple ID login. Import a `.p12`/`.pfx` bundle, or a `.cer`/`.crt`/`.der`/`.pem` certificate with its unencrypted private key, together with a matching `.mobileprovision`. Import separate profiles for extensions when a wildcard profile does not authorize them. The importer checks the key pair, certificate authorization, and expiration; installation checks device and app identifiers.

Apple ID sign-in creates or reuses the account's certificate and private key automatically; there is no certificate password to enter. Password-free P12 imports accept a blank password. Certificate and key validation supports PEM and DER keys in PKCS#1 and PKCS#8 formats without a PKCS#12 import round trip. Embedded installer identities are reused only when their serial matches the requested certificate, and public-only portal refreshes preserve saved private keys.

[LiveContainer](https://github.com/LiveContainer/LiveContainer) 3.8.0 is compiled from its pinned source and embedded during the ReStore build. No IPA injection step is required. Guests use its executable preparation and runtime hooks. Import, launch, search, and delete are available in the library. Preparing guests requires the certificate and private key that signed the running ReStore app. Opening a guest restarts the host process.

## Build

Requires macOS, Xcode supporting synchronized project groups (CI uses Xcode 26.4), and an iOS 15+ device. Initialize dependencies, configure signing using `CodeSigning.xcconfig.sample`, and open `ReStore.xcodeproj`:

```sh
git submodule update --init --recursive
python3 scripts/livecontainer/test_runtime_adapter.py
make build fakesign ipa
```

This produces `ReStore.ipa`. The **ReStore** target compiles and embeds LiveContainer automatically. Simulator builds omit the guest runtime. For signing regression tests, choose an installed simulator on your Mac:

```sh
xcodebuild test -project ReStore.xcodeproj -scheme ReStoreTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The main app uses `com.ReStore.ReStore`, with ReStore-branded backup and widget targets. It installs separately from older SideStore-branded builds; iOS does not transfer their sandbox or Keychain automatically. Export needed accounts and app data before switching. Internal database filenames and legacy installed-app URL schemes remain compatible with existing backup formats. New host links use `restore://`.

Nightly releases include `ReStore.ipa`, debug symbols, and `source.json`, containing download URLs for this repository. Add the [ReStore source](https://github.com/Nnnnnnn274/ReStore/releases/download/nightly/source.json) to receive ReStore builds.

Original ReStore monogram assets are checked in. To regenerate their sizes and color variants, run `python3 scripts/branding/generate_icons.py` with Pillow installed.

## Credits and license

Upstream authorship and license notices are preserved. ReStore uses SideStore and AltStore code, [SideSign](https://github.com/SideStore/SideSign), [Minimuxer](https://github.com/SideStore/minimuxer), [EM Proxy](https://github.com/jkcoxson/em_proxy), LiveContainer, and other dependencies credited in their source and license files. Installation uses [LocalDevVPN](https://github.com/jkcoxson/LocalDevVPN).

This project is licensed under [AGPLv3](LICENSE). See [CONTRIBUTING.md](CONTRIBUTING.md) for contributions to this independent fork.
