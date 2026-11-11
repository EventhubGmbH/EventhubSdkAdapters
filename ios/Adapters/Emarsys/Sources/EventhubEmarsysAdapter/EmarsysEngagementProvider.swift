// EventhubEmarsysAdapter 2.0.0-beta.1 — Emarsys iOS 3.10.x. Copy-in source (see README).
// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Eventhub GmbH
//
// The Eventhub SDK 2.0 engagement adapter for Emarsys (EH-2526 Phase 9; design spec §2.2, §5).
// The host owns Emarsys: it calls `Emarsys.setup` (before `Eventhub.configure`), sets the contact and
// handles push itself; this adapter only sends three custom events and keeps its visited record.

import Combine
import EventhubCore
import Foundation

/// The `EngagementProvider` for Emarsys. Pass it to `Eventhub.configure`, after `Emarsys.setup`:
///
///     Emarsys.setup(config: config)
///     Eventhub.configure(CoreOptions(engagement: EmarsysEngagementProvider(visitedRetentionDays: 30), …))
///
/// What it does with Core's calls (spec §5): `eventhub_geofence_enter` / `eventhub_geofence_exit` for
/// observed crossings only, and `eventhub_place_visited` — on every observed enter, and otherwise
/// (initial-state events, exits, `syncOccupancy`) only when the place's last visited send is older
/// than `visitedRetentionDays`. Every event carries `place_id`, `place_slug`, `place_name`, `app_id`.
/// Segment on "has `eventhub_place_visited` … in the last R days"; trigger automations on
/// `eventhub_geofence_enter` only. `identity` is always `nil`: Emarsys exposes no install id.
/// Readiness is by host ordering: a send Emarsys drops before its setup is still recorded as sent,
/// so the place stays "visited" for R days (README).
@MainActor
public final class EmarsysEngagementProvider: EngagementProvider {

    static let maxEventAge: TimeInterval = 5 * 60

    private let gateway: any EmarsysGateway
    private let store: any EmarsysVisitedRecordStore
    private let rule: EmarsysVisitedRule
    private let now: () -> Date
    private let identitySubject = CurrentValueSubject<EngagementIdentity?, Never>(nil)

    private var consent: Bool?
    /// Bumped by `cancelPending()` (and so by `stop()` / `reset()`), as the port requires. Emarsys
    /// readiness is by host ordering, so the adapter holds no queue and nothing reads the generation
    /// for delivery (Phase 9 decision 3).
    private(set) var generation = 0

    /// The adapter for the host's Emarsys SDK (`Emarsys.setup` is the host's job, before
    /// `Eventhub.configure`).
    ///
    /// - Parameter visitedRetentionDays: R — how long one `eventhub_place_visited` keeps a place
    ///   "visited" before a restart, a sync or an exit inside it sends it again. Set it to at most
    ///   Emarsys's event retention and filter the segment on "in the last R days". Values below 1
    ///   are treated as 1.
    public convenience init(visitedRetentionDays: Int) {
        self.init(
            visitedRetentionDays: visitedRetentionDays,
            gateway: LiveEmarsysGateway(),
            store: EmarsysUserDefaultsVisitedRecordStore()
        )
    }

    init(
        visitedRetentionDays: Int,
        gateway: any EmarsysGateway,
        store: any EmarsysVisitedRecordStore,
        now: @escaping () -> Date = { Date() }
    ) {
        self.rule = EmarsysVisitedRule(retentionDays: visitedRetentionDays)
        self.gateway = gateway
        self.store = store
        self.now = now
    }

    // MARK: - EngagementProvider

    /// Always `nil` (replayed to every subscriber; never emits a value).
    public var identity: AnyPublisher<EngagementIdentity?, Never> {
        identitySubject.eraseToAnyPublisher()
    }

    /// Nothing to attach: the host's `Emarsys.setup` has already run (README).
    public func start() {}

    public func setTrackingConsent(_ granted: Bool?) {
        consent = granted
    }

    public func onGeofence(_ event: GeofenceEvent) {
        let current = now()
        guard consent != false, current.timeIntervalSince(event.occurredAt) <= Self.maxEventAge else { return }
        apply(rule.decision(for: event, record: store.read(), now: current))
    }

    /// The visit-state half only (spec §2.2): `eventhub_place_visited` for every due place in
    /// `inside`. There is no live state, so `retiredAppIds` has nothing to retire. Every sync — an
    /// empty `inside` too — prunes record entries older than R.
    public func syncOccupancy(appId: String, inside: [Place], retiredAppIds: [String]) {
        guard consent != false else { return }
        apply(rule.decision(forSync: inside, record: store.read(), now: now()))
    }

    /// Nothing is queued (readiness by host ordering); only the generation moves.
    public func cancelPending() {
        generation += 1
    }

    /// Clears the visited record: the next visit, restart or sync inside a place sends
    /// `eventhub_place_visited` again.
    public func reset() {
        cancelPending()
        store.clear()
    }

    /// Keeps the visited record; `identity` stays `nil`.
    public func stop() {
        cancelPending()
    }

    // MARK: - Delivery

    private func apply(_ decision: EmarsysVisitedDecision) {
        for payload in decision.events {
            gateway.track(eventName: payload.name, attributes: payload.attributes)
        }
        if let record = decision.record {
            store.write(record)
        }
    }
}
