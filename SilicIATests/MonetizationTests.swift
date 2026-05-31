//
//  MonetizationTests.swift
//  SilicIATests
//
//  Covers the dormant monetization plumbing: founding-user capture and the
//  Entitlements gate layer. The paid line is OFF (`Entitlements.paywallActive
//  == false`), so the contract under test is "everything stays unlocked and
//  no setting is clamped" — i.e. v1 behaves exactly like the free app.
//

import XCTest
@testable import SilicIA

final class MonetizationTests: XCTestCase {

    // MARK: - FoundingUserStore

    /// An isolated defaults suite so tests never touch the real app domain.
    private func makeDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "test.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testFirstLaunchCapturesFoundingUser() {
        let defaults = makeDefaults()
        XCTAssertFalse(FoundingUserStore.isFoundingUser(defaults: defaults))
        XCTAssertNil(FoundingUserStore.firstLaunchDate(defaults: defaults))

        FoundingUserStore.registerLaunchIfNeeded(defaults: defaults)

        // Dormant phase (paywallEverShipped == false) ⇒ grandfathered.
        XCTAssertTrue(FoundingUserStore.isFoundingUser(defaults: defaults))
        XCTAssertNotNil(FoundingUserStore.firstLaunchDate(defaults: defaults))
    }

    func testRegisterLaunchIsIdempotent() {
        let defaults = makeDefaults()
        FoundingUserStore.registerLaunchIfNeeded(defaults: defaults)
        let firstDate = FoundingUserStore.firstLaunchDate(defaults: defaults)

        // A later launch must not overwrite the recorded first-launch date.
        FoundingUserStore.registerLaunchIfNeeded(defaults: defaults)
        XCTAssertEqual(firstDate, FoundingUserStore.firstLaunchDate(defaults: defaults))
    }

    // MARK: - Entitlements (dormant contract)

    @MainActor
    func testDormantEntitlementsUnlockEverything() {
        // A non-founding, non-premium user still gets full access while the
        // paywall is dormant — proving v1 gates nothing.
        let entitlements = Entitlements(
            purchaseManager: PurchaseManager(),
            isFoundingUser: false
        )
        XCTAssertTrue(entitlements.hasPremiumAccess)
        XCTAssertTrue(entitlements.canUseDeepSearch)
        XCTAssertTrue(entitlements.canAttachDocuments)
        XCTAssertTrue(entitlements.canUseMultipleWebSourcesPerProvider)
        XCTAssertTrue(entitlements.canUseToolCalling)
        XCTAssertTrue(entitlements.canExceedFreeOutputTokens)
    }

    @MainActor
    func testDormantClampsAreNoOps() {
        let entitlements = Entitlements(
            purchaseManager: PurchaseManager(),
            isFoundingUser: false
        )
        // While dormant, requested values pass through untouched even when
        // they exceed the free-tier limits.
        XCTAssertEqual(entitlements.clampedMaxResponseTokens(2000), 2000)
        XCTAssertEqual(entitlements.clampedResultsPerProvider(5), 5)
    }

    /// Sanity check that the free-tier constants match the product spec, so
    /// a stray edit to either number is caught.
    func testFreeTierLimitConstants() {
        XCTAssertEqual(Entitlements.freeMaxResponseTokens, 500)
        XCTAssertEqual(Entitlements.freeMaxResultsPerProvider, 1)
    }
}
