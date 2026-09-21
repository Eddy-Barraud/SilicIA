//
//  ModelAnsweringTests.swift
//  SilicIATests
//
//  Integration tests that drive the REAL on-device model through
//  ChatService.sendMessage and assert it answers cleanly across multi-turn
//  conversations and tool-calling mode.
//
//  These require Apple Intelligence to be available on the test host. When
//  it isn't (most CI), every test SKIPS rather than fails — so the suite
//  stays green and deterministic, and these run for real on a capable Mac.
//
//  Kept offline (web search disabled, no documents) so the only moving
//  part is the model itself: answers come from its own knowledge, no
//  network flakiness.
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

    /// Sends one message with offline, modest-length settings and returns
    /// after the model finishes.
    private func ask(_ question: String, useToolCalling: Bool = false) async {
        await chatService.sendMessage(
            question,
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
            useWikipedia: false,
            useToolCalling: useToolCalling
        )
    }

    /// Asserts the most recent turn produced a clean, non-empty assistant answer.
    private func assertLastAnswerClean(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(chatService.errorMessage, "model surfaced an error", file: file, line: line)
        XCTAssertEqual(chatService.messages.last?.role, .assistant, file: file, line: line)
        let answer = chatService.messages.last?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        XCTAssertFalse(answer.isEmpty, "assistant answer was empty", file: file, line: line)
    }

    // MARK: - Multi-turn conversation

    func testMultiTurnChatAnswersWithoutError() async {
        let questions = [
            "What is the capital of France?",
            "Name one landmark in that city."
        ]
        for q in questions {
            await ask(q)
            assertLastAnswerClean()
        }
        XCTAssertEqual(chatService.messages.count, 4) // 2 turns × (user + assistant)
    }

    // MARK: - Tool-calling path (governor + loop breaker)

    func testToolCallingQuestionFinishesCleanly() async {
        await ask("Briefly, what is a factorial?", useToolCalling: true)
        XCTAssertEqual(chatService.messages.count, 2)
        assertLastAnswerClean()
        let answer = chatService.messages.last?.content ?? ""
        let lowerAnswer = answer.lowercased()
        XCTAssertFalse(lowerAnswer.contains("context does not"), "Model mentioned 'context does not': \(answer)")
        XCTAssertFalse(lowerAnswer.contains("provided context"), "Model mentioned 'provided context': \(answer)")
    }

    func testToolCallingMathematicalQuestionDirectAnswerWithoutContext() async {
        await ask("What is a cubic spline interpolation?", useToolCalling: true)
        XCTAssertEqual(chatService.messages.count, 2)
        assertLastAnswerClean()
        let answer = chatService.messages.last?.content ?? ""
        let lowerAnswer = answer.lowercased()

        // Assert the model does NOT exhibit false refusal or context apology
        XCTAssertFalse(lowerAnswer.contains("provided context"), "Model mentioned 'provided context': \(answer)")
        XCTAssertFalse(lowerAnswer.contains("context provided"), "Model mentioned 'context provided': \(answer)")
        XCTAssertFalse(lowerAnswer.contains("based on the context"), "Model mentioned 'based on the context': \(answer)")
        XCTAssertFalse(lowerAnswer.contains("cannot define"), "Model claimed it cannot define: \(answer)")
        XCTAssertFalse(lowerAnswer.contains("additional context or sources"), "Model asked for additional context: \(answer)")
        XCTAssertFalse(lowerAnswer.contains("source:"), "Model output spurious source citation: \(answer)")

        // Assert the model gave an informative answer with mathematical content
        XCTAssertTrue(
            lowerAnswer.contains("spline") || lowerAnswer.contains("polynomial") || lowerAnswer.contains("curve") || lowerAnswer.contains("interpolation"),
            "Model answer missing mathematical keywords: \(answer)"
        )
    }
}
