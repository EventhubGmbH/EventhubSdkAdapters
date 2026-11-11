// EventhubEmarsysAdapter 2.0.0-beta.1 — the Eventhub SDK 2.0 engagement adapter for Emarsys.
// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Eventhub GmbH
// Supported: Emarsys iOS 3.10.x (tested 3.10.0, 3.10.2), iOS 15+, Swift 5 and Swift 6 language
// mode. Copy-in source: copy this folder into your app target.
// Depends on EventhubCore and EmarsysSDK only.

/// Version facts of this copy-in adapter (stamped at release; see the README).
enum EmarsysAdapterInfo {
    /// The adapter version; equals the Eventhub SDK release tag it was copied from.
    static let version = "2.0.0-beta.1"
    /// The Emarsys iOS SDK range this source is tested against.
    static let supportedEmarsysRange = "3.10.x"
}
