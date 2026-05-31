//
//  Entitlements.swift
//  SilicIA
//
//  Central feature-gating layer. Every premium-capable feature asks THIS
//  type whether it's unlocked, so the entire paid line lives in one place
//  and the call sites read as intent ("if entitlements.canUseDeepSearch").
//
//  DORMANT BY DESIGN. While `paywallActive == false` every check returns
//  `true`, so the app behaves exactly like the fully-free v1 — no UI
//  change, no clamping, nothing gated. When the paywall build is ready,
//  flip `paywallActive` to true (and `FoundingUserStore.paywallEverShipped`
//  in the same release) and gating activates: a feature is unlocked iff the
//  user was grandfathered as a founding user OR owns premium.
//
//  Features that will become paid (per product spec):
//    1. Deep / "Extensive" search.
//    2. Attaching PDFs and images as context.
//    3. More than one DuckDuckGo source.
//    4. More than one Wikipedia source.
//    5. The tool-calling (experimental) toggle.
//    6. More than 500 tokens of output.
//

import Foundation
import Combine

/// Resolves whether premium features are unlocked for the current user.
/// Observes `PurchaseManager` so SwiftUI views bound to this object update
/// when the purchase state changes.
@MainActor
final class Entitlements: ObservableObject {
    /// Master switch. Keep `false` until the paywall build ships. Flipping
    /// this is the single act that turns monetization on; pair it with
    /// `FoundingUserStore.paywallEverShipped = true` in the same release.
    static let paywallActive = false

    // MARK: - Free-tier limits
    // The numbers the gates translate into when the paywall is active.
    // Centralised so the gate logic and any "Free: up to N" UI copy read
    // the same source of truth.

    /// Output-token ceiling for the free tier.
    static let freeMaxResponseTokens = 500
    /// Per-provider (DuckDuckGo / Wikipedia) source ceiling for free tier.
    static let freeMaxResultsPerProvider = 1

    private let purchaseManager: PurchaseManager
    private let isFoundingUser: Bool
    private var cancellable: AnyCancellable?

    init(
        purchaseManager: PurchaseManager,
        isFoundingUser: Bool = FoundingUserStore.isFoundingUser()
    ) {
        self.purchaseManager = purchaseManager
        self.isFoundingUser = isFoundingUser
        // Re-publish purchase-state changes so views observing Entitlements
        // refresh when a purchase / restore lands.
        cancellable = purchaseManager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    /// True when the user has unrestricted access: the paywall isn't active
    /// yet, they were grandfathered in as a founding user, or they own
    /// premium. Every named gate below resolves to this today.
    var hasPremiumAccess: Bool {
        !Self.paywallActive || isFoundingUser || purchaseManager.isPremium
    }

    // MARK: - Named feature gates
    // Named individually (rather than every call site reading
    // `hasPremiumAccess`) so the paid line can later be split per-feature
    // without touching call sites, and so each site documents its intent.

    /// (1) "Extensive" deep search in SearchView.
    var canUseDeepSearch: Bool { hasPremiumAccess }

    /// (2) Attaching PDFs and images as chat/search context.
    var canAttachDocuments: Bool { hasPremiumAccess }

    /// (3)+(4) Using more than one result from a web provider
    /// (DuckDuckGo / Wikipedia).
    var canUseMultipleWebSourcesPerProvider: Bool { hasPremiumAccess }

    /// (5) The tool-calling (experimental) toggle in settings.
    var canUseToolCalling: Bool { hasPremiumAccess }

    /// (6) Raising max output above the free-tier ceiling.
    var canExceedFreeOutputTokens: Bool { hasPremiumAccess }

    // MARK: - Clamps
    // Convenience helpers that translate a requested numeric setting into
    // what the user is actually entitled to. Call-site usage later, e.g.:
    //   let cap = entitlements.clampedMaxResponseTokens(settings.maxResponseTokens)
    // While dormant these return the requested value unchanged.

    /// Clamps a requested per-provider source count to the entitlement.
    func clampedResultsPerProvider(_ requested: Int) -> Int {
        canUseMultipleWebSourcesPerProvider
            ? requested
            : min(requested, Self.freeMaxResultsPerProvider)
    }

    /// Clamps a requested output-token value to the entitlement.
    func clampedMaxResponseTokens(_ requested: Int) -> Int {
        canExceedFreeOutputTokens
            ? requested
            : min(requested, Self.freeMaxResponseTokens)
    }
}
