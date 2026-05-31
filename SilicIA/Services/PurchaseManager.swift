//
//  PurchaseManager.swift
//  SilicIA
//
//  StoreKit 2 wrapper for the single "unlock everything" premium product.
//  Wired but DORMANT: nothing in the app consumes `isPremium` yet (see
//  `Entitlements.paywallActive`), so this changes no behaviour at v1. It
//  exists so the paid line can be drawn later by flipping one flag instead
//  of retrofitting StoreKit into a shipped app.
//
//  App Store Connect configuration this expects:
//    - Product ID:   premiumfeaturespaywallv2
//    - Reference name: premium-features-paywall
//    - Apple ID:     6775203125
//
//  Requires the In-App Purchase capability on the app target. For local
//  testing, add a StoreKit configuration file containing the product above
//  and select it in the scheme's Run > Options > StoreKit Configuration.
//

import Foundation
import Combine
import StoreKit

/// Owns the premium product, the user's entitlement state, and the
/// purchase / restore flows. `@MainActor` so `@Published` mutations are
/// always delivered on the main thread for SwiftUI.
@MainActor
final class PurchaseManager: ObservableObject {
    /// App Store product identifier for the premium unlock.
    static let premiumProductID = "premiumfeaturespaywallv2"

    /// Whether the user currently owns premium. Derived from StoreKit
    /// entitlements and kept live by the transaction listener.
    @Published private(set) var isPremium = false
    /// The loaded premium product (nil until `loadProduct()` succeeds).
    /// Drives price display on a future paywall.
    @Published private(set) var premiumProduct: Product?
    @Published private(set) var isLoadingProduct = false
    /// Last user-facing error from a purchase / restore / load attempt.
    @Published var purchaseError: String?

    /// Background task draining `Transaction.updates` for the app's
    /// lifetime, so entitlements granted out-of-band (Ask to Buy approvals,
    /// Family Sharing, restores on another device) reflect without a
    /// manual restore.
    private var updatesListenerTask: Task<Void, Never>?

    init() {
        updatesListenerTask = listenForTransactions()
        // Local entitlement check only (no network) — safe to run always.
        Task { await refreshEntitlements() }
    }

    deinit {
        updatesListenerTask?.cancel()
    }

    // MARK: - Product loading

    /// Fetches the premium product metadata from the App Store. Safe to
    /// call repeatedly; a future paywall calls this before presenting.
    func loadProduct() async {
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        do {
            let products = try await Product.products(for: [Self.premiumProductID])
            premiumProduct = products.first
            if premiumProduct == nil {
                purchaseError = "Premium product '\(Self.premiumProductID)' not found in App Store Connect."
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Purchase / restore

    /// Initiates purchase of the premium unlock. Returns `true` only on a
    /// verified, completed purchase. Auto-loads the product first if needed.
    @discardableResult
    func purchasePremium() async -> Bool {
        if premiumProduct == nil {
            await loadProduct()
        }
        guard let product = premiumProduct else { return false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlements()
                return isPremium
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseError = error.localizedDescription
            return false
        }
    }

    /// Forces a sync with the App Store and re-evaluates entitlements.
    /// StoreKit 2 keeps entitlements current automatically, but a paywall
    /// should still offer an explicit "Restore Purchases" button (App
    /// Store guideline requirement) that calls this.
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Entitlement evaluation

    /// Recomputes `isPremium` from the user's current entitlements. A
    /// non-consumable / subscription counts only while present and not
    /// revoked.
    func refreshEntitlements() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if transaction.productID == Self.premiumProductID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        isPremium = owned
    }

    // MARK: - Internals

    /// Listens for transaction updates for the app's lifetime. Runs off the
    /// main actor; hops back via the `@MainActor` methods it awaits.
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard let self else { continue }
                guard let transaction = try? Self.verify(result) else { continue }
                await transaction.finish()
                await self.refreshEntitlements()
            }
        }
    }

    /// Unwraps a `VerificationResult`, throwing if StoreKit couldn't verify
    /// the JWS signature. Instance sugar over the `nonisolated` `verify`.
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        try Self.verify(result)
    }

    /// `nonisolated` so the detached transaction listener can call it
    /// without hopping to the main actor (it touches no mutable state).
    nonisolated private static func verify<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
}
