// EventhubAirshipAdapter 2.0.0-beta.1 — Airship iOS 19.x / 20.x / 21.x. Copy-in source (see README).
// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Eventhub GmbH
//
// The seam between the adapter's logic and the Airship SDK (EH-2526 Phase 8, decision 4).
// `LiveAirshipGateway` is the only type in the adapter that touches `Airship.*`; the tests drive a
// fake. The adapter never calls `takeOff`, never enables push and never touches `privacyManager`.

import AirshipCore
import Foundation

/// What the adapter needs from Airship, and nothing more.
@MainActor
protocol AirshipChannelGateway: AnyObject {
    /// `true` once the host's `Airship.takeOff` has run (`Airship.isFlying`).
    var isReady: Bool { get }
    /// Runs `callback` when Airship is ready — at once if it already is (`Airship.onReady`).
    func onReady(_ callback: @escaping @MainActor @Sendable () -> Void)
    /// The channel id, `nil` until the channel exists. Only valid while ready.
    var channelId: String? { get }
    /// The current channel id (if any) and every later one. Only valid while ready.
    var channelIdUpdates: AsyncStream<String> { get }
    /// The channel's locally readable tag set. Only valid while ready.
    var tags: [String] { get }
    /// One atomic tag edit: removals and additions applied together. Only valid while ready.
    func editTags(add: [String], remove: [String])
    /// Records an Airship custom event with string properties. Only valid while ready.
    func track(eventName: String, properties: [String: String])
}

/// The production gateway over the host-initialised Airship singleton. `Airship.channel` traps
/// before `takeOff`, so every member but `isReady` / `onReady` is called only after readiness.
@MainActor
final class LiveAirshipGateway: AirshipChannelGateway {

    var isReady: Bool { Airship.isFlying }

    func onReady(_ callback: @escaping @MainActor @Sendable () -> Void) {
        Airship.onReady(callback: callback)
    }

    var channelId: String? { Airship.channel.identifier }

    var channelIdUpdates: AsyncStream<String> { Airship.channel.identifierUpdates }

    var tags: [String] { Airship.channel.tags }

    func editTags(add: [String], remove: [String]) {
        // `editTags(_:)` applies the editor when the block returns.
        Airship.channel.editTags { editor in
            editor.remove(remove)
            editor.add(add)
        }
    }

    func track(eventName: String, properties: [String: String]) {
        // From Airship 19 on `CustomEvent` is a value type with mutating setters
        // (1.x's `let event` + `event.properties = …` no longer compiles).
        var event = CustomEvent(name: eventName)
        for (key, value) in properties.sorted(by: { $0.key < $1.key }) {
            event.setProperty(string: value, forKey: key)
        }
        event.track()
    }
}
