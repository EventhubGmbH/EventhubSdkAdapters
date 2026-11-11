// EventhubAirshipAdapter 2.0.0-beta.1 — the Eventhub SDK 2.0 engagement adapter for Airship.
// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Eventhub GmbH
// Supported: Airship iOS 19.x, 20.x and 21.x (tested 19.11.10, 20.12.1, 21.1.0), iOS 15+,
// Swift 5 and Swift 6 language mode. Copy-in source: copy this folder into your app target.
// Depends on EventhubCore and AirshipCore only.

/// Version facts of this copy-in adapter (stamped at release; see the README).
enum AirshipAdapterInfo {
    /// The adapter version; equals the Eventhub SDK release tag it was copied from.
    static let version = "2.0.0-beta.1"
    /// The Airship majors this source is tested against.
    static let supportedAirshipMajors = [19, 20, 21]
}
