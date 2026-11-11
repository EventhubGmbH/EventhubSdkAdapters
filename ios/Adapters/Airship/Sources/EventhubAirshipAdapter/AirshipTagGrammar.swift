// EventhubAirshipAdapter 2.0.0-beta.1 — Airship iOS 19.x / 20.x / 21.x. Copy-in source (see README).
// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Eventhub GmbH
//
// The pure half of the adapter (EH-2526 Phase 8.3): the 1.x tag grammar, the occupancy diff and the
// custom-event payloads. No Airship import — everything here is plain values, unit-tested without
// an Airship instance.

import EventhubCore

/// The 1.x Airship tag names (`AirshipInteractor.swift`, spec §2.2 / SP4), unchanged in 2.0:
/// - permanent ("ever visited") tag `<slug>_<placeId>_<appId>`, never removed by the adapter;
/// - live ("currently inside") tag `live_<slug>_<placeId>_<appId>`.
///
/// A slug may itself contain `_`, so tags are read from the right (F7): the last segment is the
/// `appId`, the one before it the `placeId`, everything between `live_` and that the slug. The
/// adapter only ever asks "is this a live tag of app X?", so matching anchors on the known `appId`
/// (an `appId` containing `_` works too); the `placeId` is the segment right before it.
enum AirshipTagGrammar {

    static let livePrefix = "live_"

    /// `<slug>_<placeId>_<appId>` — the place's own `appId` (its `PlaceKey`).
    static func permanentTag(for place: Place) -> String {
        "\(place.slug)_\(place.key.placeId)_\(place.key.appId)"
    }

    /// `live_<slug>_<placeId>_<appId>`.
    static func liveTag(for place: Place) -> String {
        livePrefix + permanentTag(for: place)
    }

    /// The slug and place id of `tag` if it is a live tag of `appId`, else `nil`. Permanent tags
    /// (no `live_` prefix), live tags of another app and malformed tags (empty slug or place id)
    /// are not live tags of `appId`.
    static func parseLiveTag(_ tag: String, appId: String) -> (slug: String, placeId: String)? {
        guard !appId.isEmpty, tag.hasPrefix(livePrefix) else { return nil }
        let body = tag.dropFirst(livePrefix.count)
        let appSuffix = "_" + appId
        guard body.hasSuffix(appSuffix) else { return nil }
        let slugAndPlace = body.dropLast(appSuffix.count)
        guard let separator = slugAndPlace.lastIndex(of: "_") else { return nil }
        let slug = slugAndPlace[..<separator]
        let placeId = slugAndPlace[slugAndPlace.index(after: separator)...]
        guard !slug.isEmpty, !placeId.isEmpty else { return nil }
        return (String(slug), String(placeId))
    }

    static func isLiveTag(_ tag: String, ofAppId appId: String) -> Bool {
        parseLiveTag(tag, appId: appId) != nil
    }
}

/// One atomic channel tag edit: removals and additions applied together (decision 6).
struct AirshipTagEdit: Equatable, Sendable {
    var add: [String]
    var remove: [String]

    static let none = AirshipTagEdit(add: [], remove: [])

    var isEmpty: Bool { add.isEmpty && remove.isEmpty }
}

/// `syncOccupancy` as a pure function of the channel's current tags (spec §2.2, §5).
enum AirshipOccupancyDiff {

    /// The edit that makes the channel consistent with `inside`:
    /// - adds every missing live and permanent tag of `inside` — only if `additionsAllowed`
    ///   (consent `false` forbids additions; removals always apply);
    /// - removes every live tag of `appId` or of a `retiredAppIds` entry that is not desired.
    /// Permanent tags and tags of any other app (or no app) are never removed.
    /// Order is deterministic: additions in `inside` order (live, then permanent), removals in
    /// `currentTags` order.
    static func edit(
        currentTags: [String],
        appId: String,
        inside: [Place],
        retiredAppIds: [String],
        additionsAllowed: Bool
    ) -> AirshipTagEdit {
        let current = Set(currentTags)
        let desiredLive = Set(inside.map(AirshipTagGrammar.liveTag(for:)))
        let scopedAppIds = [appId] + retiredAppIds.filter { $0 != appId }

        var add: [String] = []
        if additionsAllowed {
            var seen = Set<String>()
            for place in inside {
                for tag in [AirshipTagGrammar.liveTag(for: place), AirshipTagGrammar.permanentTag(for: place)]
                where !current.contains(tag) && seen.insert(tag).inserted {
                    add.append(tag)
                }
            }
        }

        var remove: [String] = []
        var removed = Set<String>()
        for tag in currentTags where !desiredLive.contains(tag) && !removed.contains(tag) {
            if scopedAppIds.contains(where: { AirshipTagGrammar.isLiveTag(tag, ofAppId: $0) }) {
                remove.append(tag)
                removed.insert(tag)
            }
        }
        return AirshipTagEdit(add: add, remove: remove)
    }

    /// The tag edit of one transition (1.x `trackGeofenceEvent`): an enter adds the permanent and
    /// the live tag; an exit stamps the permanent tag too (F2: a real exit proves a visit whose
    /// enter was dropped) and removes the live tag. Same for `isInitialState` events.
    ///
    /// `if` instead of `switch`: the binary Core is built with library evolution, where `Transition`
    /// is a non-frozen enum (a `switch` would need `@unknown default`, which a source-built Core
    /// then warns about as unreachable).
    static func edit(for event: GeofenceEvent) -> AirshipTagEdit {
        let permanent = AirshipTagGrammar.permanentTag(for: event.place)
        let live = AirshipTagGrammar.liveTag(for: event.place)
        if event.transition == .enter {
            return AirshipTagEdit(add: [permanent, live], remove: [])
        }
        return AirshipTagEdit(add: [permanent], remove: [live])
    }
}

/// An Airship custom event as 1.x sent it: `eventhub_custom_entry_event` /
/// `eventhub_custom_exit_event` with the string properties `placeName`, `placeSlug`, `placeId`.
struct AirshipCustomEventPayload: Equatable, Sendable {
    static let entryEventName = "eventhub_custom_entry_event"
    static let exitEventName = "eventhub_custom_exit_event"

    let name: String
    let properties: [String: String]

    /// `nil` for `isInitialState` events: reconciliation never fires an automation (§2.2).
    static func forTransition(_ event: GeofenceEvent) -> AirshipCustomEventPayload? {
        guard !event.isInitialState else { return nil }
        return AirshipCustomEventPayload(
            name: event.transition == .enter ? entryEventName : exitEventName,
            properties: [
                "placeName": event.place.name,
                "placeSlug": event.place.slug,
                "placeId": event.place.key.placeId,
            ]
        )
    }
}
