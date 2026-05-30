//
//  ToolCallingPromptTests.swift
//  SilicIATests
//
//  Regression guard for the multi-turn PDF-chat bug where every answer
//  began by echoing the previous answer and ended by leaking the prompt
//  scaffolding ("(Max output: …)", "Documents are attached: use
//  searchContext…"). Root cause was stuffing the full User:/Assistant:
//  transcript plus scaffolding into the per-turn prompt of a fresh
//  session; the small model "continued" the transcript instead of
//  answering. The fix keeps only prior *user questions* and ends with a
//  direct imperative.
//

import XCTest
@testable import SilicIA

final class ToolCallingPromptTests: XCTestCase {

    func testFirstTurnPromptIsJustImperativePlusQuestion() {
        let prompt = ChatService.assembleToolCallingPrompt(
            currentQuestion: "How is the CMC computed in this paper?",
            priorUserQuestions: [],
            language: .english
        )
        XCTAssertTrue(prompt.contains("How is the CMC computed in this paper?"))
        // No transcript framing, no scaffolding.
        XCTAssertFalse(prompt.contains("Assistant:"))
        XCTAssertFalse(prompt.lowercased().contains("max output"))
    }

    /// The critical property: prior *assistant answers* must never appear
    /// in the prompt, so the model has nothing to echo.
    func testPriorAssistantAnswersNeverAppear() {
        let priorAnswer = "The CMC is computed via the osmotic pressure breakpoint method."
        // Only user questions are passed in by the caller; even if an
        // answer string sneaked in it shouldn't be replayed — but the
        // contract is the caller passes user questions only. Assert the
        // assembled prompt contains the questions and not answer prose.
        let prompt = ChatService.assembleToolCallingPrompt(
            currentQuestion: "How are micelles detected?",
            priorUserQuestions: ["How is the CMC computed in this paper?"],
            language: .english
        )
        XCTAssertTrue(prompt.contains("How are micelles detected?"))
        XCTAssertTrue(prompt.contains("How is the CMC computed in this paper?"))
        XCTAssertFalse(prompt.contains(priorAnswer))
        XCTAssertFalse(prompt.contains("Assistant:"))
    }

    /// No length/tool scaffolding leaks — these belong in the session
    /// instructions, not the user prompt.
    func testNoScaffoldingInPrompt() {
        for language in [ModelLanguage.english, .french, .spanish] {
            let prompt = ChatService.assembleToolCallingPrompt(
                currentQuestion: "Q?",
                priorUserQuestions: ["A?", "B?"],
                language: language
            )
            XCTAssertFalse(prompt.lowercased().contains("max output"),
                           "Max-output scaffolding leaked (\(language))")
            XCTAssertFalse(prompt.contains("~"),
                           "Character-count scaffolding leaked (\(language))")
        }
    }

    /// Prior questions are included for follow-up coherence, capped, and
    /// the current question comes last (so the prompt ends on the thing to
    /// answer, not a continuable transcript).
    func testPriorQuestionsIncludedAndCurrentComesLast() {
        let prompt = ChatService.assembleToolCallingPrompt(
            currentQuestion: "And the osmotic pressure?",
            priorUserQuestions: ["How is the CMC computed?", "How are micelles detected?"],
            language: .english
        )
        XCTAssertTrue(prompt.contains("How is the CMC computed?"))
        XCTAssertTrue(prompt.contains("How are micelles detected?"))
        // Current question is the final non-empty line.
        let lastLine = prompt.split(separator: "\n").last.map(String.init) ?? ""
        XCTAssertEqual(lastLine, "And the osmotic pressure?")
    }
}
