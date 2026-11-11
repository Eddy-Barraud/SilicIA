//
//  TokenBudgetingTests.swift
//  SilicIATests
//
//  Unit tests for TokenBudgeting clamping, estimation formulas,
//  and context window overflow guards.
//

import XCTest
import FoundationModels
@testable import SilicIA

final class TokenBudgetingTests: XCTestCase {

    func testTokenClamping() {
        // Output tokens clamp to [1, contextWindowLimit]
        XCTAssertGreaterThanOrEqual(TokenBudgeting.clampedOutputTokens(requestedMaxTokens: 1), 1)
        XCTAssertLessThanOrEqual(TokenBudgeting.clampedOutputTokens(requestedMaxTokens: 999_999), TokenBudgeting.contextWindowLimit)
        XCTAssertEqual(TokenBudgeting.clampedOutputTokens(requestedMaxTokens: 1000), 1000)

        // Context tokens clamp to AppSettings range
        let range = AppSettings.maxContextTokensRange
        let minCtx = TokenBudgeting.clampedContextTokens(requestedContextTokens: 1, maxOutputTokens: 1500, settingsRange: range)
        let maxCtx = TokenBudgeting.clampedContextTokens(requestedContextTokens: 999_999, maxOutputTokens: 1500, settingsRange: range)
        let midCtx = TokenBudgeting.clampedContextTokens(requestedContextTokens: 1000, maxOutputTokens: 1500, settingsRange: range)
        XCTAssertGreaterThanOrEqual(minCtx, range.lowerBound)
        XCTAssertLessThanOrEqual(maxCtx, range.upperBound)
        XCTAssertGreaterThanOrEqual(midCtx, range.lowerBound)
        XCTAssertLessThanOrEqual(midCtx, range.upperBound)
    }

    func testTokenAndCharacterEstimations() {
        XCTAssertGreaterThanOrEqual(TokenBudgeting.estimatedTokens(forApproxWords: 0), 0)
        XCTAssertGreaterThan(TokenBudgeting.estimatedTokens(forApproxWords: 300), 0)

        XCTAssertEqual(TokenBudgeting.estimatedOutputCharacters(forTokens: 100), 300)
        XCTAssertEqual(TokenBudgeting.estimatedOutputCharacters(forTokens: 0), 0)

        XCTAssertGreaterThanOrEqual(TokenBudgeting.estimatedOutputSentences(forTokens: 0), 1)
        XCTAssertGreaterThan(TokenBudgeting.estimatedOutputSentences(forTokens: 1000), 0)

        XCTAssertGreaterThan(TokenBudgeting.estimatedContextWords(forTokens: 100), 0)
        XCTAssertGreaterThanOrEqual(TokenBudgeting.estimatedContextWords(forTokens: 0), 1)

        XCTAssertEqual(TokenBudgeting.estimatedOutputWords(forTokens: 1000), 600)
        XCTAssertEqual(TokenBudgeting.estimatedContextWords(forTokens: 3096), 1857)
    }

    func testTokenBudgetSliderSplit() {
        XCTAssertEqual(AppSettings.defaultTotalTokensBudget, 2700)

        // Default settings split totalTokensBudget
        var settings = AppSettings()
        XCTAssertEqual(settings.maxContextTokens + settings.maxResponseTokens, settings.totalTokensBudget)

        // Test across variable total token budgets (1000 to 4000)
        for total in [1000, 1500, 2000, 2700, 3500, 4000] {
            settings.setTotalTokensBudget(total)
            XCTAssertEqual(settings.totalTokensBudget, total)
            XCTAssertEqual(settings.maxContextTokens + settings.maxResponseTokens, total)
            XCTAssertGreaterThanOrEqual(settings.maxContextTokens, AppSettings.maxContextTokensRange.lowerBound)
            XCTAssertGreaterThanOrEqual(settings.maxResponseTokens, AppSettings.maxResponseTokensRange.lowerBound)

            let inputWords = TokenBudgeting.estimatedContextWords(forTokens: settings.maxContextTokens)
            let outputWords = TokenBudgeting.estimatedOutputWords(forTokens: settings.maxResponseTokens)
            XCTAssertGreaterThan(inputWords, 0)
            XCTAssertGreaterThan(outputWords, 0)
        }
    }

    func testOutputProfiles() {
        let concise = TokenBudgeting.outputProfile(forResponseTokens: 250)
        XCTAssertEqual(concise.kind, .concise)
        XCTAssertEqual(concise.localizedName(for: .english), "Concise")
        XCTAssertEqual(concise.localizedName(for: .french), "Concis")
        XCTAssertEqual(concise.keyPointsRangeString, "2 to 3")
        XCTAssertTrue(concise.personaDirective(for: .english).contains("concise"))
        XCTAssertTrue(concise.structureDirective(for: .french).contains("concise"))

        let standard = TokenBudgeting.outputProfile(forResponseTokens: 500)
        XCTAssertEqual(standard.kind, .standard)
        XCTAssertEqual(standard.localizedName(for: .english), "Standard")
        XCTAssertEqual(standard.keyPointsRangeString, "3 to 5")
        XCTAssertTrue(standard.personaDirective(for: .english).contains("informative"))
        XCTAssertTrue(standard.structureDirective(for: .french).contains("concise"))
        XCTAssertTrue(standard.structureDirective(for: .french).contains("points clés"))

        let detailed = TokenBudgeting.outputProfile(forResponseTokens: 1200)
        XCTAssertEqual(detailed.kind, .detailed)
        XCTAssertEqual(detailed.localizedName(for: .english), "Detailed")
        XCTAssertEqual(detailed.localizedName(for: .french), "Détaillé")
        XCTAssertEqual(detailed.keyPointsRangeString, "5 to 7")
        XCTAssertTrue(detailed.personaDirective(for: .english).contains("in-depth"))
        XCTAssertTrue(detailed.structureDirective(for: .french).contains("synthèse approfondie"))
    }

    func testOutputProfileReasoningLevelMapping() {
        XCTAssertEqual(TokenBudgeting.OutputProfileKind.concise.reasoningLevel, .light)
        XCTAssertEqual(TokenBudgeting.OutputProfileKind.standard.reasoningLevel, .moderate)
        XCTAssertEqual(TokenBudgeting.OutputProfileKind.detailed.reasoningLevel, .deep)

        let concise = TokenBudgeting.outputProfile(forResponseTokens: 250)
        XCTAssertEqual(concise.reasoningLevel, .light)
        XCTAssertEqual(TokenBudgeting.reasoningLevel(forResponseTokens: 250), .light)
        XCTAssertEqual(TokenBudgeting.reasoningLevel(forResponseTokens: 399), .light)

        let standard = TokenBudgeting.outputProfile(forResponseTokens: 500)
        XCTAssertEqual(standard.reasoningLevel, .moderate)
        XCTAssertEqual(TokenBudgeting.reasoningLevel(forResponseTokens: 400), .moderate)
        XCTAssertEqual(TokenBudgeting.reasoningLevel(forResponseTokens: 800), .moderate)

        let detailed = TokenBudgeting.outputProfile(forResponseTokens: 1200)
        XCTAssertEqual(detailed.reasoningLevel, .deep)
        XCTAssertEqual(TokenBudgeting.reasoningLevel(forResponseTokens: 801), .deep)
        XCTAssertEqual(TokenBudgeting.reasoningLevel(forResponseTokens: 1500), .deep)
    }

    func testDynamicSessionCoordinatorSwitchesModesAndSettings() {
        let coordinator = DynamicSessionCoordinator()
        var settings = AppSettings()
        settings.language = .english
        settings.maxResponseTokens = 300
        settings.temperature = 0.4

        coordinator.switchActiveViewMode(.searchSummary, settings: settings, prewarm: false)
        let searchSnap = coordinator.currentSnapshot
        XCTAssertEqual(searchSnap.mode, .searchSummary)
        XCTAssertEqual(searchSnap.reasoningLevel, .light)
        XCTAssertEqual(searchSnap.temperature, 0.4)
        XCTAssertFalse(searchSnap.instructionsText.isEmpty)
        let searchInstructions = searchSnap.instructionsText

        // Switch to Chat view mode with standard token category
        settings.maxResponseTokens = 600
        settings.temperature = 0.7
        coordinator.switchActiveViewMode(.chat, settings: settings, prewarm: false)
        let chatSnap = coordinator.currentSnapshot
        XCTAssertEqual(chatSnap.mode, .chat)
        XCTAssertEqual(chatSnap.reasoningLevel, .moderate)
        XCTAssertEqual(chatSnap.temperature, 0.7)
        XCTAssertFalse(chatSnap.instructionsText.isEmpty)
        XCTAssertNotEqual(chatSnap.instructionsText, searchInstructions)

        // Update settings to detailed token category and French language
        settings.maxResponseTokens = 1200
        settings.language = .french
        coordinator.handleSettingsChanged(settings)
        let updatedChatSnap = coordinator.currentSnapshot
        XCTAssertEqual(updatedChatSnap.mode, .chat)
        XCTAssertEqual(updatedChatSnap.reasoningLevel, .deep)
        XCTAssertNotEqual(updatedChatSnap.instructionsText, chatSnap.instructionsText)
    }

    func testToolBudgetScalesAndClampsAtFloor() {
        // Default response cap (500t) scales 2x to 1000t
        XCTAssertEqual(TokenBudgeting.toolOutputTokenBudget(forResponseTokens: 500), 1000)

        // Tiny response cap clamps to floor
        XCTAssertEqual(
            TokenBudgeting.toolOutputTokenBudget(forResponseTokens: 50),
            TokenBudgeting.toolOutputTokenBudgetFloor
        )

        for responseCap in [1, 50, 500, 1000, 1500] {
            XCTAssertGreaterThanOrEqual(
                TokenBudgeting.toolOutputTokenBudget(forResponseTokens: responseCap),
                TokenBudgeting.toolOutputTokenBudgetFloor,
                "Floor not honoured at responseCap=\(responseCap)"
            )
        }
    }

    func testToolBudgetNeverOverflowsWindowWithResponseAndInstructions() {
        for responseCap in [250, 500, 750, 1000, 1500, 3000, 5000] {
            let effectiveResponse = TokenBudgeting.clampedToolResponseTokens(requestedMaxTokens: responseCap)
            let toolBudget = TokenBudgeting.toolOutputTokenBudget(forResponseTokens: responseCap)
            let oneToolTurn = TokenBudgeting.instructionTokens
                + TokenBudgeting.toolCallingOverheadTokens
                + TokenBudgeting.promptOverheadTokens
                + effectiveResponse
                + toolBudget
            XCTAssertLessThanOrEqual(
                oneToolTurn,
                TokenBudgeting.contextWindowLimit,
                "A single tool reply at responseCap=\(responseCap) overflows: \(oneToolTurn) > \(TokenBudgeting.contextWindowLimit)"
            )
        }
    }

    func testToolBudgetSurvivesTwoConcurrentReplies() {
        for responseCap in [500, 1000, 1500, 3500] {
            let effectiveResponse = TokenBudgeting.clampedToolResponseTokens(requestedMaxTokens: responseCap)
            let toolBudget = TokenBudgeting.toolOutputTokenBudget(forResponseTokens: responseCap)
            let twoToolTurn = TokenBudgeting.instructionTokens
                + TokenBudgeting.toolCallingOverheadTokens
                + TokenBudgeting.promptOverheadTokens
                + effectiveResponse
                + (toolBudget * 2)
            XCTAssertLessThanOrEqual(
                twoToolTurn,
                TokenBudgeting.contextWindowLimit,
                "Two tool replies at responseCap=\(responseCap) overflow: \(twoToolTurn)"
            )
        }
    }

    func testToolResponseClampLeavesRoomForOverhead() {
        for responseCap in [500, 1500, 3500, 9999] {
            let clamped = TokenBudgeting.clampedToolResponseTokens(requestedMaxTokens: responseCap)
            let reserved = TokenBudgeting.instructionTokens
                + TokenBudgeting.toolCallingOverheadTokens
                + TokenBudgeting.promptOverheadTokens
                + TokenBudgeting.minContextTokens
            XCTAssertLessThanOrEqual(
                clamped + reserved,
                TokenBudgeting.contextWindowLimit,
                "Tool response clamp at \(responseCap) leaves no room for overhead"
            )
        }
        XCTAssertLessThanOrEqual(
            TokenBudgeting.clampedToolResponseTokens(requestedMaxTokens: 3500),
            TokenBudgeting.clampedOutputTokens(requestedMaxTokens: 3500)
        )
    }

    func testHybridToolGroundingLeavesRoomForToolReplies() {
        for responseCap in [500, 1000, 1500] {
            let response = TokenBudgeting.clampedToolResponseTokens(requestedMaxTokens: responseCap)
            let toolReply = TokenBudgeting.toolOutputTokenBudget(forResponseTokens: responseCap)
            let groundingChars = TokenBudgeting.maxHybridToolGroundingCharacters(
                maxOutputTokens: responseCap,
                reservedToolReplyTokens: toolReply + 120
            )
            let groundingTokens = TokenBudgeting.estimatedTokens(forApproxCharacters: groundingChars)
            let total = TokenBudgeting.instructionTokens
                + TokenBudgeting.toolCallingOverheadTokens
                + TokenBudgeting.promptOverheadTokens
                + response
                + groundingTokens
                + toolReply
                + 120
            XCTAssertLessThanOrEqual(
                total,
                TokenBudgeting.contextWindowLimit,
                "Hybrid grounding at responseCap=\(responseCap) leaves no room for tool replies"
            )
        }
    }

    func testProfileReasoningCapabilityGating() {
        // When reasoning capability is absent (as on on-device SystemLanguageModel.default),
        // effectiveReasoningLevel MUST be nil to prevent LanguageModelError.unsupportedCapability.
        let defaultCaps = SystemLanguageModel.default.capabilities
        let effectiveOnDefault = SilicIADynamicProfile.effectiveReasoningLevel(
            requested: .light,
            capabilities: defaultCaps
        )
        if defaultCaps.contains(.reasoning) {
            XCTAssertEqual(effectiveOnDefault, .light)
        } else {
            XCTAssertNil(effectiveOnDefault)
        }

        // When reasoning capability is present, requested level is preserved.
        let capableCaps = LanguageModelCapabilities([.reasoning])
        XCTAssertEqual(
            SilicIADynamicProfile.effectiveReasoningLevel(requested: .light, capabilities: capableCaps),
            .light
        )
        XCTAssertEqual(
            SilicIADynamicProfile.effectiveReasoningLevel(requested: .moderate, capabilities: capableCaps),
            .moderate
        )
        XCTAssertEqual(
            SilicIADynamicProfile.effectiveReasoningLevel(requested: .deep, capabilities: capableCaps),
            .deep
        )

        // Empty capabilities yield nil
        let emptyCaps = LanguageModelCapabilities([])
        XCTAssertNil(SilicIADynamicProfile.effectiveReasoningLevel(requested: .moderate, capabilities: emptyCaps))
    }

    @MainActor
    func testDynamicSessionCoordinatorPrewarmDeduplication() {
        guard FoundationModelAvailability.check().isAvailable else { return }

        let coordinator = DynamicSessionCoordinator()
        var settings = AppSettings()
        settings.language = .french
        settings.maxResponseTokens = 500

        let initialCount = coordinator.prewarmCount
        coordinator.switchActiveViewMode(.searchSummary, settings: settings, prewarm: true)
        let countAfterFirst = coordinator.prewarmCount
        XCTAssertGreaterThanOrEqual(countAfterFirst, initialCount)

        // Switching to identical mode & settings must not trigger a redundant prewarm
        coordinator.switchActiveViewMode(.searchSummary, settings: settings, prewarm: true)
        XCTAssertEqual(coordinator.prewarmCount, countAfterFirst)

        // Switching to a different mode (Chat) changes the key and must trigger a prewarm
        coordinator.switchActiveViewMode(.chat, settings: settings, prewarm: true)
        XCTAssertEqual(coordinator.prewarmCount, countAfterFirst + 1)
    }

    func testLanguageModelErrorClassification() {
        // Permanent / non-transient errors must NOT be retried
        let permanentErrors: [LanguageModelError] = [
            .guardrailViolation(LanguageModelError.GuardrailViolation(debugDescription: "guardrail")),
            .refusal(LanguageModelError.Refusal(explanation: "policy", debugDescription: "refusal")),
            .unsupportedCapability(
                LanguageModelError.UnsupportedCapability(
                    capability: .reasoning,
                    debugDescription: "The model doesn't support the requested capability."
                )
            ),
            .unsupportedTranscriptContent(
                LanguageModelError.UnsupportedTranscriptContent(
                    unsupportedContent: [],
                    debugDescription: "bad transcript"
                )
            ),
            .unsupportedGenerationGuide(
                LanguageModelError.UnsupportedGenerationGuide(
                    schemaName: "guide",
                    debugDescription: "guide not supported"
                )
            ),
            .unsupportedLanguageOrLocale(
                LanguageModelError.UnsupportedLanguageOrLocale(
                    languageCode: Locale.LanguageCode("xx"),
                    debugDescription: "unsupported language"
                )
            )
        ]
        for err in permanentErrors {
            let diagnosis = AIService.classifyGenerationError(err)
            XCTAssertFalse(diagnosis.isTransient, "Expected permanent error for \(err)")
            XCTAssertTrue(diagnosis.label.contains("LanguageModelError"))
        }

        // Transient errors should be eligible for retry
        let transientErrors: [LanguageModelError] = [
            .contextSizeExceeded(LanguageModelError.ContextSizeExceeded(contextSize: 4096, tokenCount: 5000, debugDescription: "overflow")),
            .rateLimited(LanguageModelError.RateLimited(resetDate: nil, debugDescription: "rate limited")),
            .timeout(LanguageModelError.Timeout(debugDescription: "timeout"))
        ]
        for err in transientErrors {
            let diagnosis = AIService.classifyGenerationError(err)
            XCTAssertTrue(diagnosis.isTransient, "Expected transient error for \(err)")
            XCTAssertTrue(diagnosis.label.contains("LanguageModelError"))
        }

        // Cancellation
        XCTAssertFalse(AIService.classifyGenerationError(CancellationError()).isTransient)
    }

    func testChatServiceContextWindowOverflowDetection() {
        let overflow = LanguageModelError.contextSizeExceeded(
            LanguageModelError.ContextSizeExceeded(contextSize: 4096, tokenCount: 5000, debugDescription: "overflow")
        )
        XCTAssertTrue(ChatService.isContextWindowOverflow(overflow))

        let nonOverflow = LanguageModelError.timeout(
            LanguageModelError.Timeout(debugDescription: "timeout")
        )
        XCTAssertFalse(ChatService.isContextWindowOverflow(nonOverflow))

        let nsError = NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "exceeded model context window size"])
        XCTAssertTrue(ChatService.isContextWindowOverflow(nsError))
    }

    func testSummaryContextUtilizationFactorScaling() {
        XCTAssertEqual(AIService.summaryContextUtilizationFactor(forTokens: 250), 0.8)
        XCTAssertEqual(AIService.summaryContextUtilizationFactor(forTokens: 399), 0.8)
        XCTAssertEqual(AIService.summaryContextUtilizationFactor(forTokens: 400), 0.9)
        XCTAssertEqual(AIService.summaryContextUtilizationFactor(forTokens: 750), 0.9)
        XCTAssertEqual(AIService.summaryContextUtilizationFactor(forTokens: 1200), 1.0)
    }

    func testQueryRequiresTools() {
        XCTAssertFalse(AIService.queryRequiresTools("classe les pays exportateurs de terres rares"))
        XCTAssertFalse(AIService.queryRequiresTools("qui est Albert Einstein"))
        XCTAssertTrue(AIService.queryRequiresTools("combien font 42 * 3.14"))
        XCTAssertTrue(AIService.queryRequiresTools("quelle est la date d'aujourd'hui"))
    }

    @MainActor
    func testCoordinatorPreservesSharedSessionWhenQueryGenerationAcquired() {
        let coordinator = DynamicSessionCoordinator()
        var settings = AppSettings()
        settings.maxResponseTokens = 500
        coordinator.switchActiveViewMode(.searchSummary, settings: settings, prewarm: false)

        XCTAssertEqual(coordinator.currentSnapshot.mode, .searchSummary)

        // Acquiring an ephemeral session (e.g. searchQueryGeneration) must NOT mutate shared session snapshot
        _ = coordinator.acquireSession(
            mode: .searchQueryGeneration,
            instructions: "Generate 1 query",
            temperature: 0.2,
            maxResponseTokens: 60
        )

        XCTAssertEqual(coordinator.currentSnapshot.mode, .searchSummary, "Shared session must remain in searchSummary mode")
    }

    func testSearchSourcesToolQueryGenerationForConciseAndStandard() async {
        guard FoundationModelAvailability.check().isAvailable else { return }

        // Concise mode (1+1 queries)
        let conciseResults = await SearchSourcesTool.generateQueries(
            for: "énergie solaire en France",
            language: .french,
            maxResponseTokens: 250,
            useDuckDuckGo: true,
            useWikipedia: true
        )
        XCTAssertFalse(conciseResults.webQueries.isEmpty)
        XCTAssertFalse(conciseResults.wikiQueries.isEmpty)

        // Concise mode for specific question
        let cobaltResults = await SearchSourcesTool.generateQueries(
            for: "quel est le premier pays exportateur de Cobalt ?",
            language: .french,
            maxResponseTokens: 250,
            useDuckDuckGo: true,
            useWikipedia: true
        )
        XCTAssertFalse(cobaltResults.webQueries.isEmpty)
        XCTAssertFalse(cobaltResults.wikiQueries.isEmpty)

        // Standard mode (2+2 queries)
        let standardResults = await SearchSourcesTool.generateQueries(
            for: "énergie solaire en France",
            language: .french,
            maxResponseTokens: 500,
            useDuckDuckGo: true,
            useWikipedia: true
        )
        XCTAssertFalse(standardResults.webQueries.isEmpty)
        XCTAssertFalse(standardResults.wikiQueries.isEmpty)

        // WikiFast mode (English mandatory for wikiQueries)
        let wikiFastResults = await SearchSourcesTool.generateQueries(
            for: "interpolation de Lagrange",
            language: .french,
            maxResponseTokens: 250,
            useDuckDuckGo: true,
            useWikipedia: true,
            wikipediaSource: .wikiFast
        )
        XCTAssertFalse(wikiFastResults.webQueries.isEmpty)
        XCTAssertFalse(wikiFastResults.wikiQueries.isEmpty)
    }

    func testWikipediaSourceSettingsPersistenceAndBackwardCompatibility() throws {
        var settings = AppSettings()
        XCTAssertEqual(settings.wikipediaSource, .wikiFast)

        settings.wikipediaSource = .online
        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)
        XCTAssertEqual(decoded.wikipediaSource, .online)

        // Backward compatibility: JSON payload without wikipediaSource must default to defaultSettings.wikipediaSource (.wikiFast)
        let legacyJSON = """
        {
            "maxDuckDuckGoResults": 5,
            "maxWikipediaResults": 3,
            "totalTokensBudget": 2500,
            "maxResponseTokens": 500,
            "temperature": 0.7,
            "maxContextTokens": 2000,
            "useDuckDuckGo": true,
            "useWikipedia": true,
            "language": "French"
        }
        """.data(using: .utf8)!
        let legacyDecoded = try JSONDecoder().decode(AppSettings.self, from: legacyJSON)
        XCTAssertEqual(legacyDecoded.wikipediaSource, .wikiFast)
    }

    func testWikiFastArticleDecodingAndURLFormatting() throws {
        let topNJSON = """
        [
            {
                "title": "Hermite interpolation",
                "text": "# Hermite interpolation\\n\\nIn numerical analysis, Hermite interpolation is a method of interpolating data points."
            },
            {
                "title": "Lagrange polynomial",
                "text": "# Lagrange polynomial\\n\\nIn numerical analysis, the Lagrange interpolating polynomial is the unique polynomial of lowest degree."
            }
        ]
        """.data(using: .utf8)!

        let articles = try JSONDecoder().decode([WikiFastArticle].self, from: topNJSON)
        XCTAssertEqual(articles.count, 2)
        XCTAssertEqual(articles[0].title, "Hermite interpolation")

        let url = WebSearchService.onlineWikipediaURL(forTitle: articles[0].title)
        XCTAssertEqual(url, "https://en.wikipedia.org/wiki/Hermite_interpolation")

        let snippet = WebSearchService.extractLeadSnippet(fromMarkdown: articles[0].text, fallback: articles[0].title)
        XCTAssertEqual(snippet, "In numerical analysis, Hermite interpolation is a method of interpolating data points.")

        let singleJSON = """
        {
            "title": "Hermite interpolation",
            "text": "# Hermite interpolation\\n\\nIn numerical analysis, Hermite interpolation is a method of interpolating data points."
        }
        """.data(using: .utf8)!
        let singleArticle = try JSONDecoder().decode(WikiFastArticle.self, from: singleJSON)
        XCTAssertEqual(singleArticle, articles[0])
    }

    func testReasoningLevelImplicitTokenSettings() {
        var settings = AppSettings()

        settings.outputProfileKind = .concise
        XCTAssertEqual(settings.outputProfileKind, .concise)
        XCTAssertEqual(settings.maxResponseTokens, 300)
        XCTAssertEqual(settings.maxContextTokens, 750)
        XCTAssertEqual(settings.totalTokensBudget, 1050)
        XCTAssertEqual(settings.outputProfileKind.implicitContextCharacters, 2_200)

        settings.outputProfileKind = .standard
        XCTAssertEqual(settings.outputProfileKind, .standard)
        XCTAssertEqual(settings.maxResponseTokens, 500)
        XCTAssertEqual(settings.maxContextTokens, 1_400)
        XCTAssertEqual(settings.totalTokensBudget, 1_900)
        XCTAssertEqual(settings.outputProfileKind.implicitContextCharacters, 4_200)

        settings.outputProfileKind = .detailed
        XCTAssertEqual(settings.outputProfileKind, .detailed)
        XCTAssertEqual(settings.maxResponseTokens, 900)
        XCTAssertEqual(settings.maxContextTokens, 2_000)
        XCTAssertEqual(settings.totalTokensBudget, 2_900)
        XCTAssertEqual(settings.outputProfileKind.implicitContextCharacters, 6_000)
    }
}
