# Eventhub Emarsys adapter (iOS) — `EmarsysEngagementProvider`

The open-source engagement adapter that connects **Eventhub SDK 2.0** to **your own Emarsys SDK**.
Eventhub Core does geofencing, analytics and the WebView contract; this adapter turns Core's place
transitions into Emarsys custom events and keeps a small record of "visited" sends so Emarsys
segments can say "visited place P in the last R days".

| | |
| --- | --- |
| Adapter version | `2.0.0-beta.1` (= the Eventhub SDK release it ships with; stamped in every source file header) |
| Emarsys iOS | **3.10.x** (tested: 3.10.0 and 3.10.2, the latest; there is no 3.11 or 4.x yet) |
| iOS / Xcode | iOS 15+ (Eventhub Core's floor; Emarsys itself needs iOS 14); Xcode 26.6+ |
| Swift | Swift 5 **and** Swift 6 language mode |
| Depends on | `EventhubCore` (from the Eventhub SDK package) and `EmarsysSDK` — nothing else |
| Public API | `EmarsysEngagementProvider` (one class) and its `init(visitedRetentionDays:)` |

## Install (copy-in)

The adapter is **source you copy into your app**, not a package you depend on — so it compiles
against whichever Emarsys 3.10.x you already pin, and you can read every line of it.

1. Add the Eventhub SDK (`EventhubSDK`: local Swift package, manual XCFrameworks or CocoaPods `:path` pod) as described in the README of the release zip `EventhubSDK-ios-<version>.zip`.
2. Copy the folder `Sources/EventhubEmarsysAdapter/` (five Swift files) from the **same release
   tag** as your Eventhub SDK into your project. Recommended: a target or local Swift package of its
   own named `EventhubEmarsysAdapter` that depends on `EventhubSDK` and Emarsys, so the adapter's
   internal type names stay out of your app module. Copying the files straight into the app target
   works as well: every internal type and file name carries the `Emarsys` prefix, so the
   adapter cannot clash with your own code or with the Airship adapter in the same target.
3. SwiftPM (product `EmarsysSDKLibrary`) and CocoaPods (pod `EmarsysSDK`, also what
   `react-native-emarsys-wrapper` brings in) expose the same module, `EmarsysSDK` — no edit needed.
   On Xcode 27, CocoaPods hosts must raise the `EmarsysSDK` pod's deployment target (it declares
   iOS 14; Xcode 27 accepts 15+) with a `post_install` hook — the snippet is in the README of the
   release zip.
4. When you upgrade the Eventhub SDK, copy the folder of the new tag again.

## Use

The host owns Emarsys. **Call `Emarsys.setup` before `Eventhub.configure`** — Emarsys silently drops
every call made before its setup and has no "ready" signal, so the adapter relies on this order (the
same `AppDelegate` slot where an Airship app calls `takeOff`).

> **If the order is wrong, the loss lasts R days, not one event.** The adapter cannot see that
> Emarsys dropped a send, so it writes its visited record anyway: an `eventhub_place_visited`
> dropped before `Emarsys.setup` (a configure-before-setup or a lazy setup) is recorded as sent, and
> the place is not *due* again for `visitedRetentionDays` — even after Emarsys is up, a restart or a
> sync inside it sends nothing until R has passed. Only `reset()` (or deleting the app) clears the
> record. Enter / exit events of the dropped window are lost as well. Keep `Emarsys.setup` first,
> synchronously, on every launch.

```swift
import EmarsysSDK
import EventhubSDK

// application(_:didFinishLaunchingWithOptions:), on the main thread, every launch
Emarsys.setup(config: config)                             // yours — the adapter never calls it
Eventhub.configure(CoreOptions(
    engagement: EmarsysEngagementProvider(visitedRetentionDays: 30),
    geofencing: .places                                   // see "Emarsys geofencing" below
))

// later, when the user joins an event
try await Eventhub.start(StartConfig(baseUrl: baseUrl, token: token))
```

**Contact and push are yours.** The adapter never calls `setContact` / `clearContact`, never touches
push and never enables Emarsys geofencing. Emarsys attributes events to whichever contact is current
when it sends them.

## What the adapter does

Every event carries the same four string attributes: `place_id`, `place_slug`, `place_name`, `app_id`.

| Core says | Emarsys effect |
| --- | --- |
| enter (observed crossing) | `eventhub_geofence_enter`, then `eventhub_place_visited` **always** (records the send time) |
| exit (observed crossing) | `eventhub_geofence_exit`, then `eventhub_place_visited` if the place is *due* (a real exit proves the visit) |
| enter / exit at (re)start (`isInitialState`) | `eventhub_place_visited` if *due* — **never** an enter or exit event, so automations do not fire on an app restart |
| `syncOccupancy` | `eventhub_place_visited` for every place the device is inside that is *due* — never an enter event. Earlier events' ids (`retiredAppIds`) are ignored: Emarsys has no "currently inside" state to clean up |
| consent `false` | nothing is sent and the visited record is left as it is. `nil` (unknown) behaves like `true`. When consent turns `true` while the device is inside a place, the following sync sends `eventhub_place_visited` (no enter) |
| `reset()` | clears the visited record; `stop()` keeps it |
| `identity` | always `nil` — Emarsys exposes no install id, so the WebView URL carries no `asid` |

*Due* means: the adapter has no record of an `eventhub_place_visited` send for this place, or the
last one is **older than `visitedRetentionDays`** (R). The record is kept per place and Eventhub
installation (`appId` + `placeId`) in `UserDefaults` under `eventhub.emarsys-adapter.visited.v1`,
and entries older than R are pruned whenever it is written and on every occupancy sync (an empty
one too, e.g. on `stop()`). A transition older than 5 minutes when
Core hands it over is dropped entirely; the next occupancy sync repairs the visited half.

## Setting up Emarsys

- **`visitedRetentionDays` is required.** Choose R **at most** as long as Emarsys keeps custom events
  for segmentation in your account. Values below 1 are treated as 1.
- **Segment on "has event `eventhub_place_visited` with `place_id == P` in the last R days".** A
  plain "has event" filter means "within Emarsys's retention", not "within R" — the window would
  silently stretch. "Ever visited" (Airship's permanent tag) is not expressible on Emarsys; the
  closest is "visited within R days".
- **Trigger Automation Center programs on `eventhub_geofence_enter` only** (Mobile Event trigger,
  filtered by `place_slug` or `place_id`), never on `eventhub_place_visited`: the latter is also sent
  at an app restart inside a place and after a consent grant.
- **"Currently inside" segments are not supported** on Emarsys (no tags); enter and exit events are
  still sent.

## Emarsys geofencing

Emarsys's own (console-defined) geofencing removes **every** region the app monitors — Eventhub
Core's included — whenever it refreshes its regions and when it is disabled (Emarsys 3.10.x calls
`stopMonitoringForRegion:` on the app-wide `monitoredRegions`). So:

- **Leave Emarsys geofencing disabled** (never call `Emarsys.geofence.enable()`) unless you configure
  Eventhub with `geofencing: .off`.
- With `geofencing: .off` Core registers no regions and sends no place events; the adapter then has
  nothing to forward.

## Changes from 1.x

1.x had no Emarsys support; this adapter is new in 2.0. The Eventhub facade class is `Eventhub`
(module `EventhubCore`, re-exported by `EventhubSDK`).

## Develop and test (Eventhub SDK repo)

The adapter is developed in `EventhubSDK/Adapters/Emarsys/` and copied into the public
`EventhubSdkAdapters` repo at release. `./test-matrix.sh` builds the real Core as a static
XCFramework (`Release/CoreXCFramework/build-core-xcframework.sh --slices sim` in the SDK repo) and runs the Swift Testing suite in six
cells: Emarsys 3.10.0 and 3.10.2 with Xcode 26.6 on iOS 15.5, and 3.10.2 with Xcode 27.1 on iOS 27.0,
each in Swift 5 and Swift 6 language mode. It prints a result table and exits non-zero on any
failure; `./test-matrix.sh 3.10.2` or `./test-matrix.sh xcode27` runs a subset. Everything it
generates (`Package.swift`, `.matrix/`, DerivedData under
`~/Library/Developer/Xcode/DerivedData/EventhubEmarsysAdapter-matrix/`) stays out of git. The tests
never call `Emarsys.setup` and need no Emarsys account or application code: they drive the adapter
through internal seams (`EmarsysGateway`, `EmarsysVisitedRecordStore`) with a fake gateway, an in-memory
store and a hand-moved clock. Live runs against Emarsys are the Eventhub SDK's example app and the
customer acceptance test.
