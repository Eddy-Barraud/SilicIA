//
//  ToolCallingPromptTests.swift
//  SilicIATests
//
//  Regression guard for tool calling prompt assembly, leak prevention,
//  and grounding context injection.
//

import XCTest
@testable import SilicIA

final class ToolCallingPromptTests: XCTestCase {

    func testPromptAssemblyAndLeakPrevention() {
        let priorAnswer = "The CMC is computed via the osmotic pressure breakpoint method."

        // Single turn & ordering
        let prompt = ChatService.assembleToolCallingPrompt(
            currentQuestion: "And the osmotic pressure?",
            priorUserQuestions: ["How is the CMC computed?", "How are micelles detected?"],
            language: .english
        )
        XCTAssertTrue(prompt.contains("How is the CMC computed?"))
        XCTAssertTrue(prompt.contains("How are micelles detected?"))
        XCTAssertFalse(prompt.contains(priorAnswer))
        XCTAssertFalse(prompt.contains("Assistant:"))

        // Current question is the last line
        let lastLine = prompt.split(separator: "\n").last.map(String.init) ?? ""
        XCTAssertEqual(lastLine, "And the osmotic pressure?")

        // Scaffolding never leaks across languages
        for language in [ModelLanguage.english, .french, .spanish] {
            let p = ChatService.assembleToolCallingPrompt(currentQuestion: "Q?", priorUserQuestions: ["A?"], language: language)
            XCTAssertFalse(p.lowercased().contains("max output"))
            XCTAssertFalse(p.contains("~"))
        }
    }

    func testGroundingContextHandling() {
        let grounding = "The critical micelle concentration was obtained by the osmotic-pressure method."
        let prompt = ChatService.assembleToolCallingPrompt(
            currentQuestion: "What is the yield?",
            priorUserQuestions: ["How is the property obtained?"],
            language: .english,
            groundingContext: grounding
        )
        XCTAssertTrue(prompt.contains(grounding))
        XCTAssertTrue(prompt.contains("Context from the attached documents:"))
        XCTAssertTrue(prompt.lowercased().contains("use the context above for specific facts"))

        // Ordering: grounding precedes prior questions, which precede current question
        let groundingPos = prompt.range(of: grounding)!.lowerBound
        let priorPos = prompt.range(of: "How is the property obtained?")!.lowerBound
        let currentPos = prompt.range(of: "What is the yield?")!.lowerBound
        XCTAssertTrue(groundingPos < priorPos)
        XCTAssertTrue(priorPos < currentPos)

        // Empty grounding is a no-op and uses the direct non-coercive imperative
        let ungrounded = ChatService.assembleToolCallingPrompt(currentQuestion: "Q?", priorUserQuestions: ["A?"], language: .english)
        let blankGrounding = ChatService.assembleToolCallingPrompt(currentQuestion: "Q?", priorUserQuestions: ["A?"], language: .english, groundingContext: "   \n  ")
        XCTAssertEqual(ungrounded, blankGrounding)
        XCTAssertTrue(ungrounded.contains("Answer the following question clearly and directly from your knowledge."))
        XCTAssertTrue(ungrounded.contains("Use available tools only if a calculation or real-time date/time is required:"))
    }

    func testGroundingLocalization() {
        let expectations: [(ModelLanguage, String)] = [
            (.english, "Context from the attached documents:"),
            (.french, "Contexte tiré des documents joints :"),
            (.spanish, "Contexto de los documentos adjuntos:")
        ]
        for (language, header) in expectations {
            let prompt = ChatService.assembleToolCallingPrompt(currentQuestion: "Q?", priorUserQuestions: [], language: language, groundingContext: "Doc text")
            XCTAssertTrue(prompt.contains(header), "Missing header for \(language)")
        }
    }

    func testGroundedAnswerImperativeLocalization() {
        let promptEN = ChatService.assembleToolCallingPrompt(currentQuestion: "Q?", priorUserQuestions: [], language: .english, groundingContext: "Doc")
        XCTAssertTrue(promptEN.contains("Answer the following question clearly and directly."))
        XCTAssertTrue(promptEN.contains("Use the context above for specific facts and supplement with your knowledge"))

        let promptFR = ChatService.assembleToolCallingPrompt(currentQuestion: "Q?", priorUserQuestions: [], language: .french, groundingContext: "Doc")
        XCTAssertTrue(promptFR.contains("Réponds clairement et directement à la question suivante."))
        XCTAssertTrue(promptFR.contains("Appuie-toi sur le contexte ci-dessus pour les faits précis et complète avec tes connaissances"))

        let promptES = ChatService.assembleToolCallingPrompt(currentQuestion: "Q?", priorUserQuestions: [], language: .spanish, groundingContext: "Doc")
        XCTAssertTrue(promptES.contains("Responde de forma clara y directa a la siguiente pregunta."))
        XCTAssertTrue(promptES.contains("Apóyate en el contexto anterior para los hechos precisos y completa con tus conocimientos"))
    }

    func testToolTranscriptRecoveryPrompt() {
        // Recovery prompt prioritizes results and ends on question
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
        let lastLine = promptEN.split(separator: "\n").last.map(String.init) ?? ""
        XCTAssertEqual(lastLine, "What is Nc in equation 6?")

        // Localized recovery prompt
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

    func testUngroundedWebSearchPromptLocalization() {
        let promptEN = ChatService.assembleToolCallingPrompt(
            currentQuestion: "Q?",
            priorUserQuestions: [],
            language: .english,
            webSearchAvailable: true,
            useDuckDuckGo: true,
            useWikipedia: true
        )
        XCTAssertTrue(promptEN.contains("search with searchSources before answering. Favor a single query, reserve Wikipedia for precise data and facts"))

        let promptFR = ChatService.assembleToolCallingPrompt(
            currentQuestion: "Q?",
            priorUserQuestions: [],
            language: .french,
            webSearchAvailable: true,
            useDuckDuckGo: true,
            useWikipedia: true
        )
        XCTAssertTrue(promptFR.contains("effectue une recherche avec l'outil searchSources avant de répondre. Privilégie une seule requête, réserve Wikipédia aux données et faits précis"))

        let promptES = ChatService.assembleToolCallingPrompt(
            currentQuestion: "Q?",
            priorUserQuestions: [],
            language: .spanish,
            webSearchAvailable: true,
            useDuckDuckGo: true,
            useWikipedia: true
        )
        XCTAssertTrue(promptES.contains("realiza una búsqueda con searchSources antes de responder. Prioriza una sola consulta, reserva Wikipedia para datos y hechos precisos"))
    }

    func testChatPromptWithWikipediaOnly() {
        let promptFR = ChatService.assembleToolCallingPrompt(
            currentQuestion: "qu'est ce qu'un décile ?",
            priorUserQuestions: [],
            language: .french,
            webSearchAvailable: true,
            useDuckDuckGo: false,
            useWikipedia: true
        )
        XCTAssertTrue(promptFR.contains("utilise searchSources (privilégie 1 sujet, jusqu'à 2 si difficile) avant de répondre"))
    }

    func testChatPromptWithDuckDuckGoOnly() {
        let promptFR = ChatService.assembleToolCallingPrompt(
            currentQuestion: "derniers résultats de foot",
            priorUserQuestions: [],
            language: .french,
            webSearchAvailable: true,
            useDuckDuckGo: true,
            useWikipedia: false
        )
        XCTAssertTrue(promptFR.contains("utilise searchSources (privilégie 1 requête, jusqu'à 2 si difficile) avant de répondre"))
    }

    func testChatPromptOffline() {
        let promptFR = ChatService.assembleToolCallingPrompt(
            currentQuestion: "bonjour",
            priorUserQuestions: [],
            language: .french,
            webSearchAvailable: false,
            useDuckDuckGo: false,
            useWikipedia: false
        )
        XCTAssertTrue(promptFR.contains("à partir de tes connaissances"))
        XCTAssertFalse(promptFR.contains("searchSources"))
    }
}
