// EventhubEmarsysAdapter 2.0.0-beta.1 — Emarsys iOS 3.10.x. Copy-in source (see README).
// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Eventhub GmbH
//
// The pure part of the adapter (EH-2526 Phase 9; design spec §5): the three custom events with their
// attributes, and the visited-record rule that decides when `eventhub_place_visited` is sent.
// Nothing here touches Emarsys or storage.

import EventhubCore
import Foundation

/// The adapter's own record of `eventhub_place_visited` sends: `PlaceKey → lastSentAt`. Keyed by
/// `(appId, placeId)`, so the same place id under two installations is two entries.
typealias EmarsysVisitedRecord = [PlaceKey: Date]

/// An Emarsys custom event: a name and string attributes (`trackCustomEvent(eventName:eventAttributes:)`).
struct EmarsysEventPayload: Equatable, Sendable {
    static let enterEventName = "eventhub_geofence_enter"
    static let exitEventName = "eventhub_geofence_exit"
    static let visitedEventName = "eventhub_place_visited"

    let name: String
    let attributes: [String: String]

    /// The four attributes every event carries (spec §5).
    static func attributes(for place: Place) -> [String: String] {
        [
            "place_id": place.key.placeId,
            "place_slug": place.slug,
            "place_name": place.name,
            "app_id": place.key.appId,
        ]
    }

    static func enter(_ place: Place) -> EmarsysEventPayload {
        EmarsysEventPayload(name: enterEventName, attributes: attributes(for: place))
    }

    static func exit(_ place: Place) -> EmarsysEventPayload {
        EmarsysEventPayload(name: exitEventName, attributes: attributes(for: place))
    }

    static func visited(_ place: Place) -> EmarsysEventPayload {
        EmarsysEventPayload(name: visitedEventName, attributes: attributes(for: place))
    }
}

/// What one port call sends and how it leaves the record.
struct EmarsysVisitedDecision: Equatable, Sendable {
    let events: [EmarsysEventPayload]
    /// The record after the call (pruned), or `nil` when the call changes nothing.
    let record: EmarsysVisitedRecord?
}

/// The visited-record rule with retention window R (spec §5, Phase 9 decision 5).
///
/// - A real enter sends `eventhub_geofence_enter`, then `eventhub_place_visited` **always**.
/// - An initial-state enter sends `eventhub_place_visited` only when the place is *due*.
/// - A real exit sends `eventhub_geofence_exit`, then `eventhub_place_visited` when due (F2).
/// - An initial-state exit sends `eventhub_place_visited` when due (F2), nothing else.
/// - `syncOccupancy` sends `eventhub_place_visited` for every due place in `inside`, never an enter.
///
/// *Due* = no entry for the place, or the entry is older than R (`now − lastSentAt > R`). Every
/// visited send records `lastSentAt = now`; every write prunes entries older than R, and a sync that
/// sends nothing (an empty `inside` too) still writes the pruned record when an entry expired.
struct EmarsysVisitedRule: Sendable {
    static let secondsPerDay: TimeInterval = 24 * 60 * 60

    /// R in days, at least 1 (values below 1 clamp to 1).
    let retentionDays: Int

    init(retentionDays: Int) {
        self.retentionDays = max(1, retentionDays)
    }

    var retention: TimeInterval {
        TimeInterval(retentionDays) * Self.secondsPerDay
    }

    func isDue(lastSentAt: Date?, now: Date) -> Bool {
        guard let lastSentAt else { return true }
        return now.timeIntervalSince(lastSentAt) > retention
    }

    /// The record without entries older than R.
    func pruned(_ record: EmarsysVisitedRecord, now: Date) -> EmarsysVisitedRecord {
        record.filter { !isDue(lastSentAt: $0.value, now: now) }
    }

    /// The decision for one transition.
    func decision(for event: GeofenceEvent, record: EmarsysVisitedRecord, now: Date) -> EmarsysVisitedDecision {
        let place = event.place
        let due = isDue(lastSentAt: record[place.key], now: now)
        var events: [EmarsysEventPayload] = []
        let sendsVisited: Bool
        if event.transition == .enter {
            if !event.isInitialState {
                events.append(.enter(place))
            }
            sendsVisited = !event.isInitialState || due
        } else {
            if !event.isInitialState {
                events.append(.exit(place))
            }
            sendsVisited = due
        }
        guard sendsVisited else {
            return EmarsysVisitedDecision(events: events, record: nil)
        }
        events.append(.visited(place))
        var updated = record
        updated[place.key] = now
        return EmarsysVisitedDecision(events: events, record: pruned(updated, now: now))
    }

    /// The decision for one `syncOccupancy` (the visit-state half only, spec §2.2).
    func decision(forSync inside: [Place], record: EmarsysVisitedRecord, now: Date) -> EmarsysVisitedDecision {
        var updated = record
        var events: [EmarsysEventPayload] = []
        for place in inside where isDue(lastSentAt: updated[place.key], now: now) {
            events.append(.visited(place))
            updated[place.key] = now
        }
        let prunedRecord = pruned(updated, now: now)
        guard !events.isEmpty else {
            // Nothing to send: write only when the prune removed an expired entry.
            return EmarsysVisitedDecision(events: [], record: prunedRecord == record ? nil : prunedRecord)
        }
        return EmarsysVisitedDecision(events: events, record: prunedRecord)
    }
}
