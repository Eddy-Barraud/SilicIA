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

    func testFoundingUserRegistrationAndIdempotence() {
        let defaults = makeDefaults()
        XCTAssertFalse(FoundingUserStore.isFoundingUser(defaults: defaults))
        XCTAssertNil(FoundingUserStore.firstLaunchDate(defaults: defaults))

        FoundingUserStore.registerLaunchIfNeeded(defaults: defaults)

        // Dormant phase (paywallEverShipped == false) => grandfathered.
        XCTAssertTrue(FoundingUserStore.isFoundingUser(defaults: defaults))
        let firstDate = FoundingUserStore.firstLaunchDate(defaults: defaults)
        XCTAssertNotNil(firstDate)

        // A later launch must not overwrite the recorded first-launch date.
        FoundingUserStore.registerLaunchIfNeeded(defaults: defaults)
        XCTAssertEqual(firstDate, FoundingUserStore.firstLaunchDate(defaults: defaults))
    }

    // MARK: - Entitlements (dormant contract)

    @MainActor
    func testDormantEntitlementsAndLimits() {
        let entitlements = Entitlements(
            purchaseManager: PurchaseManager(),
            isFoundingUser: false
        )
        // Full access while paywall is dormant
        XCTAssertTrue(entitlements.hasPremiumAccess)
        XCTAssertTrue(entitlements.canUseDeepSearch)
        XCTAssertTrue(entitlements.canAttachDocuments)
        XCTAssertTrue(entitlements.canUseMultipleWebSourcesPerProvider)
        XCTAssertTrue(entitlements.canUseToolCalling)
        XCTAssertTrue(entitlements.canExceedFreeOutputTokens)

        // Clamps are no-ops while dormant
        XCTAssertEqual(entitlements.clampedMaxResponseTokens(2000), 2000)
        XCTAssertEqual(entitlements.clampedResultsPerProvider(5), 5)

        // Free-tier constants check
        XCTAssertEqual(Entitlements.freeMaxResponseTokens, 500)
        XCTAssertEqual(Entitlements.freeMaxResultsPerProvider, 1)
    }
}
