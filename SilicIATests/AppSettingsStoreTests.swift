//
//  AppSettingsStoreTests.swift
//  SilicIATests
//
//  Covers the shared observable settings store: same-instance sharing, automatic
//  persistence, mutual exclusion, and search conversation recording.
//

import XCTest
import Observation
import SwiftData
@testable import SilicIA

@MainActor
final class AppSettingsStoreTests: XCTestCase {

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

    private final class SendableBox<T>: @unchecked Sendable {
        nonisolated(unsafe) var value: T
        init(_ value: T) { self.value = value }
    }

    func testSingletonObservationPersistenceAndMutualExclusion() throws {
        XCTAssertTrue(AppSettingsStore.shared === AppSettingsStore.shared)

        let fired = SendableBox(false)
        withObservationTracking {
            _ = AppSettingsStore.shared.settings
        } onChange: {
            fired.value = true
        }
        AppSettingsStore.shared.settings.language =
            AppSettingsStore.shared.settings.language == .french ? .english : .french
        XCTAssertTrue(fired.value, "Mutating settings should notify observation trackers")

        // Automatic persistence and in-memory bounds clamping
        AppSettingsStore.shared.settings.temperature = 0.77
        AppSettingsStore.shared.settings.maxDuckDuckGoResults = 2
        AppSettingsStore.shared.settings.save()

        let reloaded = AppSettings.load()
        XCTAssertEqual(reloaded.temperature, 0.77, accuracy: 0.0001)
        XCTAssertEqual(reloaded.maxDuckDuckGoResults, 2)

        // Context source mutual exclusion & legacy decoding
        var settings = AppSettings()
        settings.contextSourceKind = .web
        XCTAssertTrue(settings.useDuckDuckGo)
        XCTAssertFalse(settings.useWikipedia)

        settings.contextSourceKind = .wiki
        XCTAssertFalse(settings.useDuckDuckGo)
        XCTAssertTrue(settings.useWikipedia)

        settings.contextSourceKind = .offline
        XCTAssertFalse(settings.useDuckDuckGo)
        XCTAssertFalse(settings.useWikipedia)

        let legacyJSON = #"{"useDuckDuckGo": true, "useWikipedia": true}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacyJSON)
        XCTAssertTrue(decoded.useDuckDuckGo)
        XCTAssertFalse(decoded.useWikipedia)
    }

    func testSearchRegistersConversationInHistoricDataAndDefaults() throws {
        let container = try ModelContainer(
            for: Conversation.self, Message.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let chatService = ChatService()
        chatService.modelContext = context

        // Register a search query and answer
        chatService.startConversationFromSearch(
            query: "What is SwiftData?",
            answer: "SwiftData is Apple's modern persistence framework.",
            citations: "https://developer.apple.com"
        )

        let descriptor = FetchDescriptor<Conversation>()
        let conversations = try context.fetch(descriptor)
        XCTAssertEqual(conversations.count, 1)
        let messages = conversations[0].messages.sorted { $0.timestamp < $1.timestamp }
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].content, "What is SwiftData?")
        XCTAssertEqual(messages[1].content, "SwiftData is Apple's modern persistence framework.")

        // Deduplication: calling again with same exchange does not duplicate
        chatService.startConversationFromSearch(
            query: "What is SwiftData?",
            answer: "SwiftData is Apple's modern persistence framework.",
            citations: "https://developer.apple.com"
        )
        let reloaded = try context.fetch(descriptor)
        XCTAssertEqual(reloaded.count, 1)

        // Default settings verification
        let defaults = AppSettings()
        XCTAssertTrue(defaults.useWikipedia)
        XCTAssertFalse(defaults.useDuckDuckGo)
        XCTAssertEqual(defaults.outputProfileKind, .standard)
        XCTAssertTrue(defaults.isReaderViewAndSummaryEnabled)
    }
}
