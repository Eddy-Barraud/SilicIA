//
//  FoundingUserStore.swift
//  SilicIA
//
//  Tracks whether this install is a "founding user" — someone who
//  installed the app during the fully-free era, before any paywall
//  shipped. Founding users are grandfathered into full access forever,
//  which is both the fair thing to do and a strong community-goodwill
//  move ("everyone who joined before vX keeps everything free").
//
//  The flag is captured ONCE, on first launch, and persisted. While the
//  app is in its dormant pre-paywall phase (`paywallEverShipped == false`)
//  every new install captures `isFoundingUser = true`. The build that
//  finally activates the paywall flips `paywallEverShipped` to true, so
//  installs from that point on capture `isFoundingUser = false` and fall
//  under the paid model.
//

import Foundation

/// Persisted record of when this install first launched and whether it
/// qualifies as a grandfathered founding user. Pure value-free namespace —
/// all state lives in `UserDefaults` so it survives relaunches.
enum FoundingUserStore {
    private static let firstLaunchDateKey = "foundingUser.firstLaunchDate"
    private static let isFoundingUserKey = "foundingUser.isFoundingUser"

    /// Whether any build the user could have installed has shipped the
    /// paywall. While `false` (the current dormant phase) every fresh
    /// install is a founding user.
    ///
    /// IMPORTANT: flip this to `true` in the SAME release that sets
    /// `Entitlements.paywallActive = true`. That single pairing is what
    /// "turns on" monetization while still grandfathering everyone who
    /// arrived earlier.
    static let paywallEverShipped = false

    /// Captures founding-user status on first launch. Idempotent: only the
    /// first ever launch writes; later launches read the persisted value.
    /// Call once, early, from the app entry point.
    static func registerLaunchIfNeeded(defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: firstLaunchDateKey) == nil else { return }
        defaults.set(Date(), forKey: firstLaunchDateKey)
        // Anyone who first launches before the paywall ships is a founding
        // user and stays grandfathered for the lifetime of the install.
        defaults.set(!paywallEverShipped, forKey: isFoundingUserKey)
    }

    /// Whether this install is grandfathered into full free access.
    static func isFoundingUser(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: isFoundingUserKey)
    }

    /// The date this install first launched, if recorded.
    static func firstLaunchDate(defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: firstLaunchDateKey) as? Date
    }
}
