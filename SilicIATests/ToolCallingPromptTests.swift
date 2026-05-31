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

    // MARK: - Hybrid grounding (PDF/image reliability fix)

    /// When grounding context is supplied it appears in the prompt, the
    /// model is told to base its answer on it, AND the current question is
    /// still the final line (so the prompt ends on the thing to answer).
    func testGroundingContextAppearsAndQuestionStaysLast() {
        let grounding = "The critical micelle concentration was obtained by the osmotic-pressure breakpoint method at 25 °C."
        let prompt = ChatService.assembleToolCallingPrompt(
            currentQuestion: "How is the property obtained?",
            priorUserQuestions: [],
            language: .english,
            groundingContext: grounding
        )
        XCTAssertTrue(prompt.contains(grounding), "Grounding passages must be injected")
        XCTAssertTrue(prompt.contains("Context from the attached documents:"))
        XCTAssertTrue(prompt.lowercased().contains("base your answer on the context above"))
        // Question is still the last line even with grounding prepended.
        let lastLine = prompt.split(separator: "\n").last.map(String.init) ?? ""
        XCTAssertEqual(lastLine, "How is the property obtained?")
        // Leak-prevention contract still holds with grounding present.
        XCTAssertFalse(prompt.contains("Assistant:"))
    }

    /// Grounding + prior questions coexist; ordering is grounding → prior
    /// questions → imperative + current question.
    func testGroundingAndPriorQuestionsOrdering() {
        let grounding = "Section 3 describes the synthesis route."
        let prompt = ChatService.assembleToolCallingPrompt(
            currentQuestion: "What is the yield?",
            priorUserQuestions: ["How is the property obtained?"],
            language: .english,
            groundingContext: grounding
        )
        let groundingPos = prompt.range(of: grounding)!.lowerBound
        let priorPos = prompt.range(of: "How is the property obtained?")!.lowerBound
        let currentPos = prompt.range(of: "What is the yield?")!.lowerBound
        XCTAssertTrue(groundingPos < priorPos, "Grounding should precede prior questions")
        XCTAssertTrue(priorPos < currentPos, "Prior questions should precede the current question")
    }

    /// Empty / whitespace grounding is a no-op: the prompt is identical to
    /// the un-grounded form, so the non-document chat path is unaffected.
    func testEmptyGroundingIsNoOp() {
        let plain = ChatService.assembleToolCallingPrompt(
            currentQuestion: "Q?",
            priorUserQuestions: ["A?"],
            language: .english
        )
        let blank = ChatService.assembleToolCallingPrompt(
            currentQuestion: "Q?",
            priorUserQuestions: ["A?"],
            language: .english,
            groundingContext: "   \n  "
        )
        XCTAssertEqual(plain, blank)
    }

    /// Grounding imperative is localized for every supported language.
    func testGroundingImperativeLocalized() {
        let grounding = "Some attached document text."
        let expectations: [(ModelLanguage, String)] = [
            (.english, "Context from the attached documents:"),
            (.french, "Contexte tiré des documents joints :"),
            (.spanish, "Contexto de los documentos adjuntos:")
        ]
        for (language, header) in expectations {
            let prompt = ChatService.assembleToolCallingPrompt(
                currentQuestion: "Q?",
                priorUserQuestions: [],
                language: language,
                groundingContext: grounding
            )
            XCTAssertTrue(prompt.contains(header), "Missing grounding header for \(language)")
            XCTAssertTrue(prompt.contains(grounding))
        }
    }
}
