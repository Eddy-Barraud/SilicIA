//
//  ModelAnsweringTests.swift
//  SilicIATests
//
//  Integration tests that drive the REAL on-device model through
//  ChatService.sendMessage and AIService.summarize to assert clean generation.
//
//  These require Apple Intelligence to be available on the test host. When
//  it isn't (most CI), tests skip rather than fail.
//

import XCTest
import SwiftData
@testable import SilicIA

@MainActor
final class ModelAnsweringTests: XCTestCase {

    private var chatService: ChatService!
    private var container: ModelContainer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(
            FoundationModelAvailability.check().isAvailable,
            "Apple Intelligence unavailable on this host — skipping model integration tests."
        )
        container = try ModelContainer(
            for: Conversation.self, Message.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        chatService = ChatService()
        chatService.modelContext = container.mainContext
    }

    override func tearDown() async throws {
        chatService = nil
        container = nil
        try await super.tearDown()
    }

    func testChatServiceAnswersCleanly() async {
        await chatService.sendMessage(
            "Briefly, what is a factorial?",
            contextInput: "",
            pdfURLs: [],
            imageURLs: [],
            includeWebSearch: false,
            maxDuckDuckGoResults: 1,
            maxWikipediaResults: 1,
            language: .english,
            temperature: 0.3,
            maxResponseTokens: 200,
            maxContextTokens: 1000,
            useDuckDuckGo: false,
            useWikipedia: false
        )

        XCTAssertNil(chatService.errorMessage)
        XCTAssertEqual(chatService.messages.last?.role, .assistant)
        let answer = chatService.messages.last?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        XCTAssertFalse(answer.isEmpty, "Assistant answer was empty")
        let lowerAnswer = answer.lowercased()
        XCTAssertFalse(lowerAnswer.contains("context does not"), "Model mentioned 'context does not': \(answer)")
        XCTAssertFalse(lowerAnswer.contains("provided context"), "Model mentioned 'provided context': \(answer)")
    }

    func testAIServiceSummarizeGeneratesCleanAnswerWithoutLaTeXArtifacts() async {
        let aiService = AIService()
        let summary = await aiService.summarize(
            query: "How to set up SwiftData step by step",
            results: [],
            maxScrapingResults: 0,
            maxScrapingChars: 0,
            temperature: 0.3,
            maxTokens: 300,
            language: .english,
            generateAnswer: true
        )
        let text = summary.summary
        XCTAssertFalse(text.isEmpty, "Summary was empty")
        XCTAssertFalse(text.contains(#"\begin{array}"#), "Summary wrapped output in array: \(text)")
        XCTAssertFalse(text.lowercased().contains("foundation model developed by apple"), "Summary leaked model intro: \(text)")
        XCTAssertTrue(text.lowercased().contains("swiftdata") || text.lowercased().contains("model"))
    }
}
