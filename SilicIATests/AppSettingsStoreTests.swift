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
import SwiftData
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

    func testSingletonAndObservation() {
        XCTAssertTrue(AppSettingsStore.shared === AppSettingsStore.shared)

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

    func testMutationsPersistAutomatically() {
        AppSettingsStore.shared.settings.totalTokensBudget = 2700

        // Individual field update & read-after-write
        AppSettingsStore.shared.settings.temperature = 0.77
        XCTAssertEqual(AppSettings.load().temperature, 0.77, accuracy: 0.0001)

        AppSettingsStore.shared.settings.language = .spanish
        XCTAssertEqual(AppSettings.load().language, .spanish)

        AppSettingsStore.shared.settings.maxResponseTokens = 321
        XCTAssertEqual(AppSettingsStore.shared.settings.maxResponseTokens, 321)

        // Multiple field updates persist together
        AppSettingsStore.shared.settings.maxContextTokens = 1234
        AppSettingsStore.shared.settings.useWikipedia = false

        let reloaded = AppSettings.load()
        XCTAssertEqual(reloaded.maxContextTokens, 1234)
        XCTAssertFalse(reloaded.useWikipedia)

        AppSettingsStore.shared.settings.setTotalTokensBudget(3200)
        let reloadedBudget = AppSettings.load()
        XCTAssertEqual(reloadedBudget.totalTokensBudget, 3200)
    }

    func testContextSourceKindMutualExclusion() {
        var settings = AppSettings()

        // Setting to Web enables DuckDuckGo and disables Wikipedia
        settings.contextSourceKind = .web
        XCTAssertTrue(settings.useDuckDuckGo)
        XCTAssertFalse(settings.useWikipedia)
        XCTAssertEqual(settings.contextSourceKind, .web)

        // Setting to Wiki enables Wikipedia and disables DuckDuckGo
        settings.contextSourceKind = .wiki
        XCTAssertFalse(settings.useDuckDuckGo)
        XCTAssertTrue(settings.useWikipedia)
        XCTAssertEqual(settings.contextSourceKind, .wiki)

        // Setting to Offline disables both
        settings.contextSourceKind = .offline
        XCTAssertFalse(settings.useDuckDuckGo)
        XCTAssertFalse(settings.useWikipedia)
        XCTAssertEqual(settings.contextSourceKind, .offline)

        // Setting property directly enforces mutual exclusivity
        settings.useWikipedia = true
        XCTAssertFalse(settings.useDuckDuckGo)
        XCTAssertTrue(settings.useWikipedia)
        XCTAssertEqual(settings.contextSourceKind, .wiki)

        settings.useDuckDuckGo = true
        XCTAssertTrue(settings.useDuckDuckGo)
        XCTAssertFalse(settings.useWikipedia)
        XCTAssertEqual(settings.contextSourceKind, .web)
    }

    func testMaxDuckDuckGoResultsRangeAllowsDownToTwo() {
        XCTAssertEqual(AppSettings.maxDuckDuckGoResultsRange.lowerBound, 2)
        XCTAssertEqual(AppSettings.maxDuckDuckGoResultsRange.upperBound, 12)

        var settings = AppSettings()
        settings.maxDuckDuckGoResults = 2
        settings.save()

        let reloaded = AppSettings.load()
        XCTAssertEqual(reloaded.maxDuckDuckGoResults, 2)
    }

    func testSearchRegistersConversationInHistoricData() throws {
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
            answer: "SwiftData is Apple's modern data modeling and persistence framework.",
            citations: "https://developer.apple.com"
        )

        let descriptor = FetchDescriptor<Conversation>()
        let conversations = try context.fetch(descriptor)
        XCTAssertEqual(conversations.count, 1)

        let conv = conversations[0]
        let sortedMessages = conv.messages.sorted { $0.timestamp < $1.timestamp }
        XCTAssertEqual(sortedMessages.count, 2)
        XCTAssertEqual(sortedMessages[0].role, "user")
        XCTAssertEqual(sortedMessages[0].content, "What is SwiftData?")
        XCTAssertEqual(sortedMessages[1].role, "assistant")
        XCTAssertEqual(sortedMessages[1].content, "SwiftData is Apple's modern data modeling and persistence framework.")
        XCTAssertEqual(sortedMessages[1].citations, "https://developer.apple.com")

        // Deduplication: calling again with the same search exchange does not duplicate the conversation
        chatService.startConversationFromSearch(
            query: "What is SwiftData?",
            answer: "SwiftData is Apple's modern data modeling and persistence framework.",
            citations: "https://developer.apple.com"
        )
        let reloadedConversations = try context.fetch(descriptor)
        XCTAssertEqual(reloadedConversations.count, 1)

        // Starting a search immediately registers with empty answer, then updates when completed
        let newSearchQuery = "How does SwiftData handle migrations?"
        chatService.startConversationFromSearch(query: newSearchQuery, answer: "", citations: nil)

        let searches = try context.fetch(descriptor)
        XCTAssertEqual(searches.count, 2)
        let searchConv = searches.first { $0.title == newSearchQuery || $0.messages.first?.content == newSearchQuery }
        XCTAssertNotNil(searchConv)
        XCTAssertEqual(searchConv?.messages.count, 1)
        XCTAssertEqual(searchConv?.messages.first?.content, newSearchQuery)

        // When search completes and provides summary
        chatService.startConversationFromSearch(
            query: newSearchQuery,
            answer: "SwiftData uses SchemaMigrationPlan and VersionedSchema.",
            citations: "https://apple.com"
        )
        let afterSummarySearches = try context.fetch(descriptor)
        XCTAssertEqual(afterSummarySearches.count, 2)
        let updatedConv = afterSummarySearches.first { $0.title == newSearchQuery || $0.messages.first?.content == newSearchQuery }
        XCTAssertEqual(updatedConv?.messages.count, 2)
        XCTAssertEqual(updatedConv?.messages.last?.content, "SwiftData uses SchemaMigrationPlan and VersionedSchema.")
    }
}
