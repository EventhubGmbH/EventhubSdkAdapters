# Changelog

All releases of the Eventhub SDK. iOS and Android share the version number; a one-platform fix still
bumps both. Each tag of this repository is the Core version the adapters were built against; the
compiled Core of the same version is provided by Eventhub (Google Drive) as `EventhubSDK-ios-<v>.zip`.

## 2.0.0-beta.1 — first public beta (iOS adapters)

The first tag of this repository and the first 2.0 build Eventhub hands out: the iOS Core
`2.0.0-beta.1` (static, signed `EventhubCore.xcframework`, iOS 15+, built with Xcode 26.6 and
consumer-tested with Xcode 26.6 and 27.1) and the two copy-in iOS adapters at the same version.

- **Repository:** `ios/Adapters/Airship/` (Airship iOS 19.x, 20.x, 21.x — one source) and
  `ios/Adapters/Emarsys/` (Emarsys iOS 3.10.x), each with its README; this changelog, the repository
  README and the Apache-2.0 `LICENSE`. `android/adapters/` is not part of this tag — the Android
  adapters follow with the Android release lane, and the Android Core 2.0 is not released yet.
- **Compiled SDK (Eventhub, Google Drive):** `EventhubSDK-ios-2.0.0-beta.1.zip` — its unzipped root is at
  once a local Swift package (`Package.swift` with the binary Core by path, the `EventhubSDK` wrapper and
  the exact Segment pins analytics-swift 1.7.1 / sovran-swift 1.1.2 / jsonsafeencoding-swift 2.0.0), the
  CocoaPods pod (`EventhubSDK.podspec` for `:path`, git-sourced Segment podspecs in `ios/Podspecs/`) and
  the manual folder (`EventhubCore.xcframework`, `EventhubSDK.xcframework`), plus the same adapter
  folders, the integration guide and the Apache-2.0 `LICENSE` of the sources. The binaries are provided
  under your agreement with Eventhub GmbH. `checksums.txt` next to the zip lists its SHA-256.
- **Beta:** the public API and the engagement port can still change before `2.0.0`; the Android SDK 2.0
  and the React Native packages are not part of this release.

Changes against 1.x (iOS): the facade class keeps its name `Eventhub`, the module is `EventhubSDK` /
`EventhubCore`; `Eventhub.setup(airshipAppKey:…)` becomes `Eventhub.configure(_:)` +
`Eventhub.start(_:)`; Airship credentials, `takeOff`, push permission and registration move to the
app; consent no longer touches `Airship.privacyManager`; the DEBUG-only publishers are replaced by
`diagnostics`. The full migration table is in the integration guide.

