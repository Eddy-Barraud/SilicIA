//
//  TokenBudgetingTests.swift
//  SilicIATests
//
//  Unit tests for TokenBudgeting clamping, estimation formulas,
//  output profiles, tool budgeting boundaries, and session coordination.
//

import XCTest
import FoundationModels
@testable import SilicIA

final class TokenBudgetingTests: XCTestCase {

    func testTokenClampingAndEstimationFormulas() {
        // Output tokens clamp to [1, contextWindowLimit]
        XCTAssertGreaterThanOrEqual(TokenBudgeting.clampedOutputTokens(requestedMaxTokens: 1), 1)
        XCTAssertLessThanOrEqual(TokenBudgeting.clampedOutputTokens(requestedMaxTokens: 999_999), TokenBudgeting.contextWindowLimit)
        XCTAssertEqual(TokenBudgeting.clampedOutputTokens(requestedMaxTokens: 1000), 1000)

        // Context tokens clamp to AppSettings range
        let range = AppSettings.maxContextTokensRange
        let minCtx = TokenBudgeting.clampedContextTokens(requestedContextTokens: 1, maxOutputTokens: 1500, settingsRange: range)
        let maxCtx = TokenBudgeting.clampedContextTokens(requestedContextTokens: 999_999, maxOutputTokens: 1500, settingsRange: range)
        XCTAssertGreaterThanOrEqual(minCtx, range.lowerBound)
        XCTAssertLessThanOrEqual(maxCtx, range.upperBound)

        // Estimations
        XCTAssertEqual(TokenBudgeting.estimatedOutputCharacters(forTokens: 100), 300)
        XCTAssertGreaterThanOrEqual(TokenBudgeting.estimatedOutputSentences(forTokens: 0), 1)
        XCTAssertEqual(TokenBudgeting.estimatedOutputWords(forTokens: 1000), 600)
        XCTAssertEqual(TokenBudgeting.estimatedContextWords(forTokens: 3096), 1857)

        // Budget split
        var settings = AppSettings()
        XCTAssertEqual(settings.maxContextTokens + settings.maxResponseTokens, settings.totalTokensBudget)
        for total in [1000, 2000, 2700, 3500] {
            settings.setTotalTokensBudget(total)
            XCTAssertEqual(settings.totalTokensBudget, total)
            XCTAssertEqual(settings.maxContextTokens + settings.maxResponseTokens, total)
        }
    }

    func testOutputProfilesAndReasoningLevels() {
        let concise = TokenBudgeting.outputProfile(forResponseTokens: 250)
        XCTAssertEqual(concise.kind, .concise)
        XCTAssertEqual(concise.reasoningLevel, .light)
        XCTAssertEqual(concise.keyPointsRangeString, "2 to 3")

        let standard = TokenBudgeting.outputProfile(forResponseTokens: 500)
        XCTAssertEqual(standard.kind, .standard)
        XCTAssertEqual(standard.reasoningLevel, .moderate)
        XCTAssertEqual(standard.keyPointsRangeString, "3 to 5")

        let detailed = TokenBudgeting.outputProfile(forResponseTokens: 1200)
        XCTAssertEqual(detailed.kind, .detailed)
        XCTAssertEqual(detailed.reasoningLevel, .deep)
        XCTAssertEqual(detailed.keyPointsRangeString, "5 to 7")

        // Reasoning level mappings
        XCTAssertEqual(TokenBudgeting.reasoningLevel(forResponseTokens: 250), .light)
        XCTAssertEqual(TokenBudgeting.reasoningLevel(forResponseTokens: 500), .moderate)
        XCTAssertEqual(TokenBudgeting.reasoningLevel(forResponseTokens: 1200), .deep)

        // Capability gating
        let capableCaps = LanguageModelCapabilities([.reasoning])
        XCTAssertEqual(SilicIADynamicProfile.effectiveReasoningLevel(requested: .light, capabilities: capableCaps), .light)
        let emptyCaps = LanguageModelCapabilities([])
        XCTAssertNil(SilicIADynamicProfile.effectiveReasoningLevel(requested: .moderate, capabilities: emptyCaps))

        // Implicit token settings
        var settings = AppSettings()
        settings.outputProfileKind = .concise
        XCTAssertEqual(settings.maxResponseTokens, 300)
        XCTAssertEqual(settings.maxContextTokens, 750)
        settings.outputProfileKind = .standard
        XCTAssertEqual(settings.maxResponseTokens, 500)
        XCTAssertEqual(settings.maxContextTokens, 1_400)
    }

    func testToolTokenBudgetBoundaries() {
        // Floor scaling
        XCTAssertEqual(TokenBudgeting.toolOutputTokenBudget(forResponseTokens: 500), 1000)
        XCTAssertEqual(TokenBudgeting.toolOutputTokenBudget(forResponseTokens: 50), TokenBudgeting.toolOutputTokenBudgetFloor)

        // Single and two concurrent tool replies fit within window
        for responseCap in [500, 1000, 1500] {
            let effectiveResponse = TokenBudgeting.clampedToolResponseTokens(requestedMaxTokens: responseCap)
            let toolBudget = TokenBudgeting.toolOutputTokenBudget(forResponseTokens: responseCap)

            let singleTurn = TokenBudgeting.instructionTokens
                + TokenBudgeting.toolCallingOverheadTokens
                + TokenBudgeting.promptOverheadTokens
                + effectiveResponse
                + toolBudget
            XCTAssertLessThanOrEqual(singleTurn, TokenBudgeting.contextWindowLimit)

            let twoTurn = singleTurn + toolBudget
            XCTAssertLessThanOrEqual(twoTurn, TokenBudgeting.contextWindowLimit)

            let groundingChars = TokenBudgeting.maxHybridToolGroundingCharacters(
                maxOutputTokens: responseCap,
                reservedToolReplyTokens: toolBudget + 120
            )
            let groundingTokens = TokenBudgeting.estimatedTokens(forApproxCharacters: groundingChars)
            let totalWithGrounding = singleTurn + groundingTokens + 120
            XCTAssertLessThanOrEqual(totalWithGrounding, TokenBudgeting.contextWindowLimit)
        }
    }

    @MainActor
    func testSessionCoordinatorAndErrorClassification() throws {
        let coordinator = DynamicSessionCoordinator()
        var settings = AppSettings()
        settings.language = .english
        settings.maxResponseTokens = 300

        coordinator.switchActiveViewMode(.searchSummary, settings: settings, prewarm: false)
        XCTAssertEqual(coordinator.currentSnapshot.mode, .searchSummary)

        settings.maxResponseTokens = 600
        coordinator.switchActiveViewMode(.chat, settings: settings, prewarm: false)
        XCTAssertEqual(coordinator.currentSnapshot.mode, .chat)

        // Ephemeral session acquisition preserves shared mode
        _ = coordinator.acquireSession(
            mode: .searchQueryGeneration,
            instructions: "Generate query",
            temperature: 0.2,
            maxResponseTokens: 60
        )
        XCTAssertEqual(coordinator.currentSnapshot.mode, .chat)

        // Error classification
        let timeout = LanguageModelError.timeout(LanguageModelError.Timeout(debugDescription: "timeout"))
        XCTAssertTrue(AIService.classifyGenerationError(timeout).isTransient)

        let refusal = LanguageModelError.refusal(LanguageModelError.Refusal(explanation: "policy", debugDescription: "refusal"))
        XCTAssertFalse(AIService.classifyGenerationError(refusal).isTransient)
        XCTAssertFalse(AIService.classifyGenerationError(CancellationError()).isTransient)

        // Context overflow detection
        let overflow = LanguageModelError.contextSizeExceeded(
            LanguageModelError.ContextSizeExceeded(contextSize: 4096, tokenCount: 5000, debugDescription: "overflow")
        )
        XCTAssertTrue(ChatService.isContextWindowOverflow(overflow))
        XCTAssertFalse(ChatService.isContextWindowOverflow(timeout))

        // WikiFast JSON decoding
        let json = """
        [{"title": "Hermite interpolation", "text": "# Hermite interpolation\\n\\nIn numerical analysis, Hermite interpolation is a method."}]
        """.data(using: .utf8)!
        let articles = try JSONDecoder().decode([WikiFastArticle].self, from: json)
        XCTAssertEqual(articles.count, 1)
        XCTAssertEqual(articles[0].title, "Hermite interpolation")
        XCTAssertEqual(WebSearchService.onlineWikipediaURL(forTitle: articles[0].title), "https://en.wikipedia.org/wiki/Hermite_interpolation")
    }
}
