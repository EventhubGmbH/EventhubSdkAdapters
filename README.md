# Eventhub SDK Adapters — 2.0.0-beta.1

The open-source **engagement adapters** of the Eventhub SDK 2.0 for iOS: small Swift folders you copy
into your app to connect the Eventhub Core to the Airship or Emarsys SDK your app already runs. The
compiled Core itself — `EventhubCore.xcframework` with the `EventhubSDK` wrapper, the Swift package
manifest, the podspec and the integration guide — is **provided by Eventhub (Google Drive)** as
`EventhubSDK-ios-2.0.0-beta.1.zip`; it is not in this repository.

> This branch (`master`) is **release-only**: every commit is made by Eventhub's release lane, one
> per release, tagged `2.x.y` — the tag is the Core version the adapters were built against. Report
> issues to Eventhub instead of opening pull requests here. The same repository is mirrored at
> `hhhc/EventhubSdkAdapters` (the agency's working copy, identical content); this one,
> `EventhubGmbH/EventhubSdkAdapters`, is the one to link.

## This tag

| | |
|---|---|
| Core version | **2.0.0-beta.1** — use the adapters of this tag with `EventhubSDK-ios-2.0.0-beta.1.zip` (same number) |
| Where the Core is | provided by Eventhub (Google Drive): the zip, the integration guide `README_Eventhub_SDK_iOS_v<version>.pdf` and `checksums.txt` (SHA-256 of the zip) |
| Airship adapter | `ios/Adapters/Airship/` — Airship iOS **19.x, 20.x, 21.x**, one source |
| Emarsys adapter | `ios/Adapters/Emarsys/` — Emarsys iOS **3.10.x** |
| Android | `android/adapters/` follows with the Android SDK 2.0 — same version number, one tag for both platforms |
| Built with | Core: Xcode 26.6, **iOS 15+**; adapters: Swift 5 and Swift 6 language mode; consumer-tested with Xcode 26.6 and 27.1 |

## How the pieces fit

- **Core** (`EventhubCore`, in the zip) — a closed, compiled static XCFramework: geofencing, location,
  the anonymous id, consent, Eventhub analytics and the WebView URL contract. It contains **no**
  Airship, Emarsys or Segment code; your app compiles the Segment stack Core was built against
  (analytics-swift 1.7.1, sovran-swift 1.1.2, jsonsafeencoding-swift 2.0.0 — the zip's package and
  podspec pin them).
- **Adapters** (this repository, and the same folders inside the zip) — an adapter implements Core's
  `EngagementProvider` port for one engagement SDK. Because it is compiled in your app against the
  Airship / Emarsys version you pin, nothing is bundled twice and no version lock applies; you can read,
  diff and patch it.
- **Your app** owns its engagement SDK: `Airship.takeOff` / `Emarsys.setup`, push permission and
  notification registration stay in your code. The SDK never prompts the user for anything on its own.

## Install

1. **Get the Core.** Download `EventhubSDK-ios-2.0.0-beta.1.zip` from the folder Eventhub shares with you,
   compare it with `checksums.txt`, unzip it into your app repository (for example `Vendor/EventhubSDK/`)
   and follow its `README.md` for one of the three paths — **local Swift package** (recommended), **manual**
   XCFrameworks, or the **`:path` pod** for React Native apps on CocoaPods. The zip carries the same
   adapter folders as this tag, so one download is complete.
2. **Copy the adapter** of the same version into your app:

   | Your app | Where the adapter folder goes | Import |
   |---|---|---|
   | SwiftPM (local package) | a target or local Swift package of its own, depending on `EventhubSDK` and `AirshipCore` / `EmarsysSDKLibrary` | as shipped |
   | Manual (XCFrameworks) | the app target | as shipped |
   | CocoaPods with the Airship pod (`@ua/react-native-airship` ≤ 26 → Airship 20; 21 has no pod) | the app target | `import AirshipCore` → `import AirshipKit` in `AirshipChannelGateway.swift` |
   | CocoaPods with `@ua/react-native-airship` 27 (Airship 21 via SwiftPM, dynamic frameworks, Xcode 27) | the app target | as shipped (`AirshipCore`) |
   | Emarsys, any path | the app target or a target of its own | as shipped (`EmarsysSDK`) |

   The folder to copy is `ios/Adapters/<Provider>/Sources/Eventhub<Provider>Adapter/` (Airship: four files,
   Emarsys: five). Every internal name carries the provider prefix, so both adapters, or an adapter and
   your own code, can share one target.
3. **Attach it at launch**, after your engagement SDK is up:

   ```swift
   import AirshipKit      // SwiftPM: import AirshipCore
   import EventhubSDK

   // application(_:didFinishLaunchingWithOptions:), on the main thread:
   try Airship.takeOff(airshipConfig)                                           // yours, first
   Eventhub.configure(CoreOptions(engagement: AirshipEngagementProvider()))     // then Eventhub
   ```

   Emarsys: `Emarsys.setup(config:)` **before** `Eventhub.configure(CoreOptions(engagement:
   EmarsysEngagementProvider(visitedRetentionDays: …)))`. Without an adapter Core runs with
   `NoopEngagementProvider` and never touches your engagement SDK.

Everything else — what your app must provide (Info.plist keys, the `location` background mode, push, a
consent decision), `start` / `stop` / `reset`, consent, the WebView URL contract, the public API,
troubleshooting and the migration from 1.x — is in the integration guide inside the zip
(`README.md` and `README_Eventhub_SDK_iOS_v<version>.pdf`).

## The adapters

Each folder has a README with the host duties, the call order, the exact tag / event semantics and
the differences to 1.x.

- **Airship** — `AirshipEngagementProvider()`. `Airship.takeOff` before `Eventhub.configure` (the
  adapter also queues work for a later take-off, e.g. from JavaScript in a React Native app). Tags
  `<slug>_<placeId>_<appId>` ("visited") and `live_<slug>_<placeId>_<appId>` ("inside"), custom events
  `eventhub_custom_entry_event` / `eventhub_custom_exit_event` — the 1.x names, so existing segments
  and automations keep working. New: no automation events for state found at an app restart.
- **Emarsys** — `EmarsysEngagementProvider(visitedRetentionDays:)`. `Emarsys.setup(config:)` **before**
  `Eventhub.configure` (Emarsys drops earlier calls silently). Custom events `eventhub_geofence_enter`
  / `_exit` and `eventhub_place_visited` once per place and retention window. Keep Emarsys's own
  geofencing disabled unless Core's geofencing policy is `.off` — it would stop Core's regions.
- **Your own** — implement `EngagementProvider` (`identity`, `start`, `stop`, `setTrackingConsent`,
  `onGeofence`, `syncOccupancy`, `cancelPending`, `reset`); the two adapters are the reference.

An adapter is not a package: there is no package-manager update path. When you upgrade the SDK, copy
the folder of the new tag again — the tag always equals the Core version in the zip's name.

## Versions and support

- One release = one tag `2.x.y` here and one `EventhubSDK-ios-2.x.y.zip` from Eventhub, the same
  number for iOS and Android; a fix for one platform still bumps both. Always pair the adapter folder
  and the Core of the **same** version.
- Within a major, the host API and the adapter port are stable; adapters keep compiling against the
  engagement SDK ranges in the table above as those SDKs move.
- Each adapter's README lists the exact engagement SDK versions it was tested with; `CHANGELOG.md`
  lists what changed per release. A new tag here means a new Core version is available from Eventhub.

## Changelog, license, contact

- `CHANGELOG.md` — what changed per release.
- **License.** Everything in this repository — and every source in the zip (adapters, `Package.swift`,
  the wrapper source, the podspecs) — is licensed under the **Apache License 2.0** (`LICENSE`): use it in
  commercial apps, modify it, keep the notice. The compiled Core in the zip (`EventhubCore.xcframework`,
  `EventhubSDK.xcframework`) is provided under your agreement with Eventhub GmbH. The Core contains no
  third-party code; the Segment stack your package manager compiles comes under its own MIT /
  Apache-2.0 licenses.
- Eventhub GmbH, Bäckerstr. 6, 21244 Buchholz, Germany.
