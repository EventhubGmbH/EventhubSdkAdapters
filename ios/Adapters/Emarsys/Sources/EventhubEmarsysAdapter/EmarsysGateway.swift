// EventhubEmarsysAdapter 2.0.0-beta.1 — Emarsys iOS 3.10.x. Copy-in source (see README).
// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Eventhub GmbH
//
// The seam between the adapter's logic and the Emarsys SDK (EH-2526 Phase 9, decision 4).
// `LiveEmarsysGateway` is the only type in the adapter that touches `Emarsys.*`; the tests drive a
// fake. The adapter never calls `Emarsys.setup`, `setContact` / `clearContact` or any geofence API.

import EmarsysSDK
import Foundation

/// What the adapter needs from Emarsys, and nothing more.
@MainActor
protocol EmarsysGateway: AnyObject {
    /// Records an Emarsys custom event with string attributes.
    func track(eventName: String, attributes: [String: String])
}

/// The production gateway over the host-initialised Emarsys SDK. Emarsys silently drops calls made
/// before `Emarsys.setup(config:)` (3.10.x has no "ready" signal), so the host must call `setup`
/// before `Eventhub.configure` (README). No completion block is passed: Emarsys runs it off the main
/// thread, and the adapter has nothing to do with the result (Emarsys persists and retries itself).
@MainActor
final class LiveEmarsysGateway: EmarsysGateway {

    func track(eventName: String, attributes: [String: String]) {
        Emarsys.trackCustomEvent(eventName: eventName, eventAttributes: attributes)
    }
}
