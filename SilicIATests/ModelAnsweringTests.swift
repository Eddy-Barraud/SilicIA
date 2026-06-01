//
//  ModelAnsweringTests.swift
//  SilicIATests
//
//  Integration tests that drive the REAL on-device model through
//  ChatService.sendMessage and assert it answers cleanly across the
//  conversation shapes that previously broke: the same question repeated
//  1/2/3 times, and several distinct questions in one chat. Also exercises
//  the tool-calling path (governor + loop breaker) end to end.
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

    /// Asserts the most recent turn produced a clean, non-empty assistant
    /// answer.
    private func assertLastAnswerClean(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(chatService.errorMessage, "model surfaced an error", file: file, line: line)
        XCTAssertEqual(chatService.messages.last?.role, .assistant, file: file, line: line)
        let answer = chatService.messages.last?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        XCTAssertFalse(answer.isEmpty, "assistant answer was empty", file: file, line: line)
    }

    // MARK: - Same question, 1 / 2 / 3 times

    func testSingleQuestionAnswersWithoutError() async {
        await ask("What is the capital of France?")
        XCTAssertEqual(chatService.messages.count, 2)   // user + assistant
        assertLastAnswerClean()
    }

    func testSameQuestionTwiceAnswersBothTimes() async {
        for _ in 1...2 {
            await ask("Define photosynthesis in one sentence.")
            assertLastAnswerClean()
        }
        XCTAssertEqual(chatService.messages.count, 4)   // 2 × (user + assistant)
    }

    func testSameQuestionThreeTimesAnswersEachTime() async {
        for _ in 1...3 {
            await ask("What is a prime number?")
            assertLastAnswerClean()
        }
        XCTAssertEqual(chatService.messages.count, 6)   // 3 × (user + assistant)
    }

    // MARK: - Several distinct questions in one chat

    func testThreeDifferentQuestionsInSameChat() async {
        let questions = [
            "What is 12 times 8?",
            "Name a primary colour.",
            "What gas do plants absorb?"
        ]
        for q in questions {
            await ask(q)
            assertLastAnswerClean()
        }
        XCTAssertEqual(chatService.messages.count, 6)
    }

    // MARK: - Tool-calling path (governor + loop breaker)

    /// The tool-calling path must also finish cleanly — this is the route
    /// that previously looped to a context-window overflow.
    func testToolCallingQuestionFinishesCleanly() async {
        await ask("Briefly, what is a factorial?", useToolCalling: true)
        XCTAssertEqual(chatService.messages.count, 2)
        assertLastAnswerClean()
    }

    /// Repeating a tool-calling question several times must not error or
    /// degrade — exercises the per-generation governor being fresh each turn.
    func testToolCallingSameQuestionThriceFinishesCleanly() async {
        for _ in 1...3 {
            await ask("Briefly, what is a factorial?", useToolCalling: true)
            assertLastAnswerClean()
        }
        XCTAssertEqual(chatService.messages.count, 6)
    }
}
