// EventhubAirshipAdapter 2.0.0-beta.1 — Airship iOS 19.x / 20.x / 21.x. Copy-in source (see README).
// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Eventhub GmbH
//
// The Eventhub SDK 2.0 engagement adapter for Airship (EH-2526 Phase 8; design spec §2.2, §5).
// The host owns Airship: it calls `Airship.takeOff` and enables push itself; this adapter only
// attaches to the running instance — tags, custom events and the channel id.

import Combine
import EventhubCore
import Foundation

/// The `EngagementProvider` for Airship. Pass it to `Eventhub.configure`:
///
///     Eventhub.configure(CoreOptions(engagement: AirshipEngagementProvider(), …))
///
/// What it does with Core's calls (spec §5): place tags `<slug>_<placeId>_<appId>` ("ever visited",
/// never removed) and `live_<slug>_<placeId>_<appId>` ("currently inside", converged by
/// `syncOccupancy` from the channel's own tag set), custom events `eventhub_custom_entry_event` /
/// `eventhub_custom_exit_event` for observed crossings only, and the channel id as `identity`.
/// Work that arrives before Airship is ready is held in memory (transitions: at most 50, oldest
/// dropped; state: only the latest `syncOccupancy`) and delivered on `Airship.onReady`.
@MainActor
public final class AirshipEngagementProvider: EngagementProvider {

    static let providerName = "airship"
    static let queueCapacity = 50
    static let maxEventAge: TimeInterval = 5 * 60

    private struct OccupancySync {
        let appId: String
        let inside: [Place]
        let retiredAppIds: [String]
    }

    private let gateway: any AirshipChannelGateway
    private let now: () -> Date
    private let identitySubject = CurrentValueSubject<EngagementIdentity?, Never>(nil)

    private var consent: Bool?
    /// Transitions held until Airship is ready (cap 50, oldest dropped).
    private var queue: [GeofenceEvent] = []
    /// The latest state work; superseded by every `syncOccupancy`, kept by `cancelPending()` /
    /// `stop()` (F1), applied first when Airship becomes ready.
    private var pendingSync: OccupancySync?
    /// Bumped by `cancelPending()` (and so by `stop()` / `reset()`): a readiness callback of an
    /// older generation does nothing.
    private var generation = 0
    private var scheduledGeneration: Int?

    private var isStarted = false
    /// Bumped by `start()` / `stop()`: an identity attach scheduled by an earlier start does nothing.
    private var lifecycle = 0
    private var identityTask: Task<Void, Never>?

    /// The adapter for the host's Airship instance (`Airship.takeOff` is the host's job).
    public convenience init() {
        self.init(gateway: LiveAirshipGateway())
    }

    init(gateway: any AirshipChannelGateway, now: @escaping () -> Date = { Date() }) {
        self.gateway = gateway
        self.now = now
    }

    // MARK: - EngagementProvider

    /// The Airship channel id as `EngagementIdentity(provider: "airship", id: <channel id>)`; `nil`
    /// until known and again after `stop()`.
    /// Replays the current value to new subscribers; emits on the main actor.
    public var identity: AnyPublisher<EngagementIdentity?, Never> {
        identitySubject.eraseToAnyPublisher()
    }

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        lifecycle += 1
        let attached = lifecycle
        gateway.onReady { [weak self] in
            guard let self, self.isStarted, self.lifecycle == attached else { return }
            self.attachIdentity()
        }
    }

    public func setTrackingConsent(_ granted: Bool?) {
        consent = granted
        if granted == false {
            queue.removeAll()   // queued transitions are never forwarded under consent false
        }
    }

    public func onGeofence(_ event: GeofenceEvent) {
        guard consent != false else { return }
        if gateway.isReady {
            deliverPending()
            deliver(event)
            return
        }
        queue.append(event)
        if queue.count > Self.queueCapacity {
            queue.removeFirst(queue.count - Self.queueCapacity)
        }
        scheduleDelivery()
    }

    public func syncOccupancy(appId: String, inside: [Place], retiredAppIds: [String]) {
        pendingSync = OccupancySync(appId: appId, inside: inside, retiredAppIds: retiredAppIds)
        if gateway.isReady {
            deliverPending()
        } else {
            scheduleDelivery()
        }
    }

    public func cancelPending() {
        queue.removeAll()
        generation += 1
        scheduleDelivery()   // the pending sync survives and needs a current-generation callback
    }

    /// Airship's tags belong to the host's channel, so there is no install-level record to clear:
    /// only the transition queue goes.
    public func reset() {
        cancelPending()
    }

    public func stop() {
        cancelPending()
        identityTask?.cancel()
        identityTask = nil
        isStarted = false
        lifecycle += 1
        identitySubject.send(nil)
    }

    // MARK: - Delivery

    private func scheduleDelivery() {
        guard pendingSync != nil || !queue.isEmpty, scheduledGeneration != generation else { return }
        let scheduled = generation
        scheduledGeneration = scheduled
        gateway.onReady { [weak self] in
            guard let self, self.generation == scheduled else { return }
            self.scheduledGeneration = nil
            self.deliverPending()
        }
    }

    /// The latest sync first, then the held transitions in order.
    private func deliverPending() {
        if let sync = pendingSync {
            pendingSync = nil
            apply(sync)
        }
        let held = queue
        queue.removeAll()
        held.forEach(deliver)
    }

    /// One `editTags` per sync, computed from the channel's tags at apply time (decision 6).
    private func apply(_ sync: OccupancySync) {
        let edit = AirshipOccupancyDiff.edit(
            currentTags: gateway.tags,
            appId: sync.appId,
            inside: sync.inside,
            retiredAppIds: sync.retiredAppIds,
            additionsAllowed: consent != false
        )
        guard !edit.isEmpty else { return }
        gateway.editTags(add: edit.add, remove: edit.remove)
    }

    private func deliver(_ event: GeofenceEvent) {
        guard consent != false, now().timeIntervalSince(event.occurredAt) <= Self.maxEventAge else { return }
        let edit = AirshipOccupancyDiff.edit(for: event)
        gateway.editTags(add: edit.add, remove: edit.remove)
        if let payload = AirshipCustomEventPayload.forTransition(event) {
            gateway.track(eventName: payload.name, properties: payload.properties)
        }
    }

    // MARK: - Identity

    private func attachIdentity() {
        publish(channelId: gateway.channelId)
        let updates = gateway.channelIdUpdates
        identityTask?.cancel()
        identityTask = Task { [weak self] in
            for await channelId in updates {
                guard !Task.isCancelled, let self else { return }
                self.publish(channelId: channelId)
            }
        }
    }

    private func publish(channelId: String?) {
        let identity = channelId.map { EngagementIdentity(provider: Self.providerName, id: $0) }
        guard identity != identitySubject.value else { return }
        identitySubject.send(identity)
    }
}
