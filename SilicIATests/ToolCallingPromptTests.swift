//
//  ToolCallingPromptTests.swift
//  SilicIATests
//
//  Regression guard for tool calling prompt assembly, leak prevention,
//  prior exchange inclusion, answer capping, and transcript recovery.
//

import XCTest
@testable import SilicIA

final class ToolCallingPromptTests: XCTestCase {

    func testPromptAssemblyOrderingLeakPreventionAndPriorExchanges() {
        let grounding = "The critical micelle concentration was obtained by the osmotic-pressure method."
        let prompt = ChatService.assembleToolCallingPrompt(
            currentQuestion: "What is the yield?",
            priorUserQuestions: ["How is the property obtained?"],
            language: .english,
            groundingContext: grounding
        )

        // U-shaped attention: current question at start, grounding, prior questions, current question at end
        XCTAssertTrue(prompt.contains(grounding))
        XCTAssertTrue(prompt.contains("Context from the attached documents:"))
        let firstCurrentPos = prompt.range(of: "What is the yield?")!.lowerBound
        let groundingPos = prompt.range(of: grounding)!.lowerBound
        let lastCurrentPos = prompt.range(of: "What is the yield?", options: .backwards)!.lowerBound
        XCTAssertTrue(firstCurrentPos < groundingPos)
        XCTAssertTrue(groundingPos < lastCurrentPos)

        // Scaffolding never leaks across languages
        for language in [ModelLanguage.english, .french, .spanish] {
            let p = ChatService.assembleToolCallingPrompt(currentQuestion: "Q?", priorUserQuestions: ["A?"], language: language)
            XCTAssertFalse(p.lowercased().contains("max output"))
            XCTAssertFalse(p.contains("~"))
        }

        // Localized headers
        let promptFR = ChatService.assembleToolCallingPrompt(currentQuestion: "Q?", priorUserQuestions: [], language: .french, groundingContext: "Doc")
        XCTAssertTrue(promptFR.contains("Contexte tiré des documents joints :"))
        XCTAssertTrue(promptFR.contains("Réponds clairement et directement à la question suivante."))

        let promptES = ChatService.assembleToolCallingPrompt(currentQuestion: "Q?", priorUserQuestions: [], language: .spanish, groundingContext: "Doc")
        XCTAssertTrue(promptES.contains("Contexto de los documentos adjuntos:"))
        XCTAssertTrue(promptES.contains("Responde de forma clara y directa a la siguiente pregunta."))

        // Prior exchange inclusion & answer capping
        let exchange = ChatService.PriorExchange(
            userQuestion: "What is an embedding?",
            assistantAnswer: "An embedding maps high-dimensional data to vector space."
        )

        let promptWithExchange = ChatService.assembleToolCallingPrompt(
            currentQuestion: "How is it used?",
            priorUserQuestions: ["Earlier intro topic"],
            lastExchange: exchange,
            language: .english
        )

        XCTAssertTrue(promptWithExchange.contains("Earlier user questions:"))
        XCTAssertTrue(promptWithExchange.contains("- Earlier intro topic"))
        XCTAssertTrue(promptWithExchange.contains("Last exchange:"))
        XCTAssertTrue(promptWithExchange.contains("User: What is an embedding?"))
        XCTAssertTrue(promptWithExchange.contains("Assistant: An embedding maps high-dimensional data to vector space."))
        XCTAssertTrue(promptWithExchange.hasSuffix("How is it used?"))

        let sentence = "Vector embeddings encode high-dimensional semantic relationships. "
        let longAnswer = String(repeating: sentence, count: 30)
        let capped = ChatService.capPriorAssistantAnswer(longAnswer, maxChars: 1600)
        XCTAssertLessThanOrEqual(capped.count, 1605)
        XCTAssertTrue(capped.hasSuffix(".") || capped.hasSuffix("…"))
    }

    func testToolTranscriptRecoveryPrompt() {
        let promptEN = ChatService.assembleToolTranscriptRecoveryPrompt(
            currentQuestion: "What is Nc in equation 6?",
            priorUserQuestions: ["Explain equation 6."],
            language: .english,
            groundingContext: "Equation 6 is in Fig 5.",
            toolTranscript: "Tool: searchContext\nResult:\nNc is the number of carbons."
        )
        XCTAssertTrue(promptEN.contains("Tool results already gathered:"))
        XCTAssertTrue(promptEN.contains("Nc is the number of carbons."))
        XCTAssertTrue(promptEN.contains("Do not call any more tools."))
        XCTAssertEqual(promptEN.split(separator: "\n").last.map(String.init), "What is Nc in equation 6?")

        let promptFR = ChatService.assembleToolTranscriptRecoveryPrompt(
            currentQuestion: "Q?",
            priorUserQuestions: [],
            language: .french,
            groundingContext: "",
            toolTranscript: "Résultat"
        )
        XCTAssertTrue(promptFR.contains("Résultats d'outils déjà obtenus :"))
        XCTAssertTrue(promptFR.contains("N'appelle plus aucun outil."))
    }
}
