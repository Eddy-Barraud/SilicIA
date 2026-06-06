//
//  AppSettingsStoreTests.swift
//  SilicIATests
//
//  Covers the shared observable settings store that is now the single
//  source of truth for every screen: same-instance sharing, automatic
//  persistence on mutation, and change publication (the mechanism that
//  keeps ContentView's tab bar in sync with a language change made in a
//  nested settings page).
//

import XCTest
import Observation
@testable import SilicIA

@MainActor
final class AppSettingsStoreTests: XCTestCase {

    /// The store is a process-wide singleton persisting to the real
    /// UserDefaults; snapshot and restore around each test so cases don't
    /// leak state into each other or the rest of the suite.
    private var snapshot: AppSettings!

    override func setUp() async throws {
        try await super.setUp()
        #if DEBUG
        FoundationModelAvailability.isTestingOverride = .available
        #endif
        snapshot = AppSettingsStore.shared.settings
    }

    override func tearDown() async throws {
        AppSettingsStore.shared.settings = snapshot
        #if DEBUG
        FoundationModelAvailability.isTestingOverride = nil
        #endif
        try await super.tearDown()
    }

    func testSharedIsASingleInstance() {
        XCTAssertTrue(AppSettingsStore.shared === AppSettingsStore.shared)
    }

    /// Mutating a field writes through to UserDefaults (AppSettings.load()
    /// sees it) — no explicit save() call needed.
    func testMutationPersistsAutomatically() {
        AppSettingsStore.shared.settings.temperature = 0.77
        XCTAssertEqual(AppSettings.load().temperature, 0.77, accuracy: 0.0001)

        AppSettingsStore.shared.settings.language = .spanish
        XCTAssertEqual(AppSettings.load().language, .spanish)
    }

    /// The in-memory value is updated immediately (read-after-write).
    func testReadAfterWriteReflectsNewValue() {
        AppSettingsStore.shared.settings.maxResponseTokens = 321
        XCTAssertEqual(AppSettingsStore.shared.settings.maxResponseTokens, 321)
    }

    /// A mutation is observable so SwiftUI readers re-render — this is what
    /// propagates a language switch to the top tab bar. Verified via the
    /// Observation framework's `withObservationTracking`, which fires its
    /// `onChange` synchronously when a tracked property is mutated.
    func testMutationIsObservable() {
        var fired = false
        withObservationTracking {
            _ = AppSettingsStore.shared.settings
        } onChange: {
            fired = true
        }

        AppSettingsStore.shared.settings.language =
            AppSettingsStore.shared.settings.language == .french ? .english : .french

        XCTAssertTrue(fired, "mutating settings should notify observation trackers")
    }

    /// Several independent fields all persist together.
    func testMultipleFieldUpdatesAllPersist() {
        AppSettingsStore.shared.settings.useToolCalling = true
        AppSettingsStore.shared.settings.maxContextTokens = 1234
        AppSettingsStore.shared.settings.useWikipedia = false

        let reloaded = AppSettings.load()
        XCTAssertTrue(reloaded.useToolCalling)
        XCTAssertEqual(reloaded.maxContextTokens, 1234)
        XCTAssertFalse(reloaded.useWikipedia)
    }
}
