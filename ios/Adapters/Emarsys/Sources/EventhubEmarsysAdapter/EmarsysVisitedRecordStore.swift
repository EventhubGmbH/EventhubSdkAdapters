// EventhubEmarsysAdapter 2.0.0-beta.1 — Emarsys iOS 3.10.x. Copy-in source (see README).
// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Eventhub GmbH
//
// The persistence seam of the adapter (EH-2526 Phase 9, decision 4): the visited record survives
// process restarts and `stop()`, and is cleared by `reset()`. The tests use an in-memory store.

import EventhubCore
import Foundation

/// Persistence of the visited record (`PlaceKey → lastSentAt`).
@MainActor
protocol EmarsysVisitedRecordStore: AnyObject {
    func read() -> EmarsysVisitedRecord
    func write(_ record: EmarsysVisitedRecord)
    func clear()
}

/// The production store: the record as JSON under one versioned `UserDefaults` key. An unreadable
/// value reads as an empty record (the next visit re-sends `eventhub_place_visited`, which the
/// rolling window tolerates).
@MainActor
final class EmarsysUserDefaultsVisitedRecordStore: EmarsysVisitedRecordStore {

    static let key = "eventhub.emarsys-adapter.visited.v1"

    private struct Entry: Codable {
        let appId: String
        let placeId: String
        let lastSentAt: Date
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func read() -> EmarsysVisitedRecord {
        guard
            let data = defaults.data(forKey: Self.key),
            let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [:] }
        var record: EmarsysVisitedRecord = [:]
        for entry in entries {
            record[PlaceKey(appId: entry.appId, placeId: entry.placeId)] = entry.lastSentAt
        }
        return record
    }

    func write(_ record: EmarsysVisitedRecord) {
        let entries = record
            .map { Entry(appId: $0.key.appId, placeId: $0.key.placeId, lastSentAt: $0.value) }
            .sorted { ($0.appId, $0.placeId) < ($1.appId, $1.placeId) }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.key)
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
