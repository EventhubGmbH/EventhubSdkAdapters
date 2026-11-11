# Eventhub Airship adapter (iOS) — `AirshipEngagementProvider`

The open-source engagement adapter that connects **Eventhub SDK 2.0** to **your own Airship SDK**.
Eventhub Core does geofencing, analytics and the WebView contract; this adapter turns Core's place
transitions into Airship channel tags and custom events, and reports the Airship channel id back to
Core.

| | |
| --- | --- |
| Adapter version | `2.0.0-beta.1` (= the Eventhub SDK release it ships with; stamped in every source file header) |
| Airship iOS | **19.x, 20.x and 21.x** — one source (tested: 19.11.10, 20.12.1, 21.1.0) |
| iOS / Xcode | iOS 15+ (Airship 19) or iOS 16+ (Airship 20 / 21); Xcode 26.6+ (Airship 21: Xcode 27.1+) |
| Swift | Swift 5 **and** Swift 6 language mode |
| Depends on | `EventhubCore` (from the Eventhub SDK package) and `AirshipCore` — nothing else |
| Public API | `AirshipEngagementProvider` (one class) and its `init()` |

## Install (copy-in)

The adapter is **source you copy into your app**, not a package you depend on — so it compiles
against whichever Airship 19/20/21 you already pin, and you can read every line of it.

1. Add the Eventhub SDK (`EventhubSDK`: local Swift package, manual XCFrameworks or CocoaPods `:path` pod) as described in the README of the release zip `EventhubSDK-ios-<version>.zip`.
2. Copy the folder `Sources/EventhubAirshipAdapter/` (four Swift files) from the **same release
   tag** as your Eventhub SDK into your project. Recommended: a target or local Swift package of its
   own named `EventhubAirshipAdapter` that depends on `EventhubSDK` and `AirshipCore`, so the
   adapter's internal type names stay out of your app module. Copying the files straight into the
   app target works as well: every internal type and file name carries the `Airship` prefix, so the
   adapter cannot clash with your own code or with the Emarsys adapter in the same target.
3. CocoaPods only (Airship ≤ 20; Airship 21 has no pod): the `Airship` pod's module is called
   `AirshipKit` — change `import AirshipCore` to `import AirshipKit` in `AirshipChannelGateway.swift`
   (the only file that imports Airship).
4. When you upgrade the Eventhub SDK, copy the folder of the new tag again.

## Use

The host owns Airship. Take off first, exactly as today, then configure Eventhub with the adapter:

```swift
import AirshipCore
import EventhubSDK

// application(_:didFinishLaunchingWithOptions:), on the main thread
Airship.takeOff(…)                                        // yours — the adapter never calls it
Eventhub.configure(CoreOptions(engagement: AirshipEngagementProvider()))

// later, when the user joins an event
try await Eventhub.start(StartConfig(baseUrl: baseUrl, token: token))
```

**Push is yours too.** 1.x enabled push inside the SDK; 2.0 does not. Keep (or add) in your app:
`Airship.push.userPushNotificationsEnabled = true` and your `defaultPresentationOptions`.

## What the adapter does

| Core says | Airship effect |
| --- | --- |
| enter (observed crossing) | tags `<slug>_<placeId>_<appId>` ("ever visited") and `live_<slug>_<placeId>_<appId>` ("currently inside"); custom event `eventhub_custom_entry_event` with `placeName`, `placeSlug`, `placeId` |
| exit (observed crossing) | removes the live tag, **also** sets the permanent tag (a real exit proves the visit); custom event `eventhub_custom_exit_event` |
| enter / exit at (re)start (`isInitialState`) | the same tags, **no** custom event — automations never fire on an app restart |
| `syncOccupancy` | reads the channel's own tags and converges them: adds missing live/permanent tags for the places the device is inside, removes stale `live_…_<appId>` tags of this event and of every event this install used before |
| consent `false` | no custom events, no tag additions, queued transitions dropped; removing live tags still happens (removing a marker is not tracking). `nil` (unknown) behaves like `true` |
| `identity` | `EngagementIdentity(provider: "airship", id: <channel id>)` once the channel id is known, re-emitted when it changes, `nil` after `stop()` |
| `reset()` | drops the queued transitions (as `cancelPending()`); Airship's tags belong to your channel, so there is no install record to clear |

Tag and event names are exactly the 1.x ones, so existing Airship segments and automations keep
working. Permanent tags are never removed.

**Tag length.** Airship silently drops tags longer than 128 characters. `live_<slug>_<placeId>_<appId>`
grows with the place slug: with a very long slug the tag is never set, and every occupancy sync tries
to add it again (as in 1.x). Keep place slugs short enough that the live tag stays within 128
characters (≈ 100 for the slug with typical ids).

**Before Airship is ready** (`Airship.takeOff` is synchronous and `onReady` runs at once when Airship
is flying, so with the order above nothing waits; the queue covers a host that configures Eventhub
before `takeOff`, e.g. a deferred take-off) the adapter holds work in memory: up to 50 transitions
(oldest dropped) and the latest occupancy state, delivered on `Airship.onReady`. A transition older than 5 minutes at delivery is dropped (an
automation like "15 minutes after entering" started late is worse than none); its tags are repaired by
the next occupancy sync. Work not delivered before the process ends is lost by design.

## Changes from 1.x

- The SDK no longer calls `Airship.takeOff` or enables push — the host does both.
- Eventhub consent no longer touches `Airship.privacyManager`; your Airship privacy settings are
  yours alone. (With Airship's `tagsAndAttributes` feature disabled, Airship reports an empty tag
  set to the adapter and applies its own privacy rules to the adapter's edits.)
- No custom event for state found at (re)start; an exit also stamps the permanent tag.
- Live tags are converged from the channel's own tag set, including tags of earlier events this
  install joined under 2.0. Live tags written by 1.x for an installation this install never started
  under 2.0 are not recognised and stay until you remove them.

## Develop and test (Eventhub SDK repo)

The adapter is developed in `EventhubSDK/Adapters/Airship/` and copied into the public
`EventhubSdkAdapters` repo at release. `./test-matrix.sh` builds the real Core as a static
XCFramework (`Release/CoreXCFramework/build-core-xcframework.sh --slices sim` in the SDK repo) and runs the Swift Testing suite once per Airship major ×
Swift language mode on simulators (19.11.10 / 20.12.1 with Xcode 26.6, 21.1.0 with Xcode 27.1); it
prints a result table and exits non-zero on any failure. Everything it generates (`Package.swift`,
`.matrix/`, DerivedData under `~/Library/Developer/Xcode/DerivedData/EventhubAirshipAdapter-matrix/`)
stays out of git. The tests never call `Airship.takeOff` and need no Airship credentials: they drive
the adapter through an internal gateway seam (`AirshipChannelGateway`).
