//
//  TokenBudgetingTests.swift
//  SilicIATests
//
//  Unit tests for TokenBudgeting clamping, estimation formulas,
//  and context window overflow guards.
//

import XCTest
@testable import SilicIA

final class TokenBudgetingTests: XCTestCase {

    func testClampedOutputTokensMin() {
        let result = TokenBudgeting.clampedOutputTokens(requestedMaxTokens: 1)
        XCTAssertGreaterThanOrEqual(result, 1)
    }
    func testTokenClamping() {
        // Output tokens clamp to [1, contextWindowLimit]
        XCTAssertGreaterThanOrEqual(TokenBudgeting.clampedOutputTokens(requestedMaxTokens: 1), 1)
        XCTAssertLessThanOrEqual(TokenBudgeting.clampedOutputTokens(requestedMaxTokens: 999_999), TokenBudgeting.contextWindowLimit)
        XCTAssertEqual(TokenBudgeting.clampedOutputTokens(requestedMaxTokens: 1000), 1000)

    func testClampedOutputTokensMax() {
        let result = TokenBudgeting.clampedOutputTokens(requestedMaxTokens: 999_999)
        XCTAssertLessThanOrEqual(result, TokenBudgeting.contextWindowLimit)
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

    func testClampedOutputTokensMid() {
        let result = TokenBudgeting.clampedOutputTokens(requestedMaxTokens: 1000)
        XCTAssertEqual(result, 1000)
    }

    func testClampedContextTokensMin() {
        let result = TokenBudgeting.clampedContextTokens(
            requestedContextTokens: 1,
            maxOutputTokens: 1500,
            settingsRange: AppSettings.maxContextTokensRange
        )
        XCTAssertGreaterThanOrEqual(result, AppSettings.maxContextTokensRange.lowerBound)
    }

    func testClampedContextTokensMax() {
        let result = TokenBudgeting.clampedContextTokens(
            requestedContextTokens: 999_999,
            maxOutputTokens: 1500,
            settingsRange: AppSettings.maxContextTokensRange
        )
        XCTAssertLessThanOrEqual(result, AppSettings.maxContextTokensRange.upperBound)
    }

    func testClampedContextTokensMid() {
        let result = TokenBudgeting.clampedContextTokens(
            requestedContextTokens: 1000,
            maxOutputTokens: 1500,
            settingsRange: AppSettings.maxContextTokensRange
        )
        XCTAssertGreaterThanOrEqual(result, AppSettings.maxContextTokensRange.lowerBound)
        XCTAssertLessThanOrEqual(result, AppSettings.maxContextTokensRange.upperBound)
    }

    func testEstimatedTokensForApproxWordsMin() {
    func testTokenAndCharacterEstimations() {
        XCTAssertGreaterThanOrEqual(TokenBudgeting.estimatedTokens(forApproxWords: 0), 0)
    }
        XCTAssertGreaterThan(TokenBudgeting.estimatedTokens(forApproxWords: 300), 0)

    func testEstimatedTokensForApproxWordsMid() {
        let result = TokenBudgeting.estimatedTokens(forApproxWords: 300)
        XCTAssertGreaterThan(result, 0)
    }

    func testEstimatedOutputCharacters() {
        XCTAssertEqual(TokenBudgeting.estimatedOutputCharacters(forTokens: 100), 300)
    }

    func testEstimatedOutputCharactersZero() {
        XCTAssertEqual(TokenBudgeting.estimatedOutputCharacters(forTokens: 0), 0)
    }

    func testEstimatedOutputSentencesMin() {
        XCTAssertGreaterThanOrEqual(TokenBudgeting.estimatedOutputSentences(forTokens: 0), 1)
    }
        XCTAssertGreaterThan(TokenBudgeting.estimatedOutputSentences(forTokens: 1000), 0)

    func testEstimatedOutputSentencesMid() {
        let result = TokenBudgeting.estimatedOutputSentences(forTokens: 1000)
        XCTAssertGreaterThan(result, 0)
    }

    func testEstimatedContextWords() {
        XCTAssertGreaterThan(TokenBudgeting.estimatedContextWords(forTokens: 100), 0)
    }

    func testEstimatedContextWordsZero() {
        XCTAssertGreaterThanOrEqual(TokenBudgeting.estimatedContextWords(forTokens: 0), 1)
    }

    // MARK: - Tool output token budget

    /// Default response cap (500t) should give tools a 1000-token reply
    /// budget per call — twice the response cap, comfortably under the
    /// window-aware ceiling.
    func testToolBudgetScalesAtTwoxAtDefault() {
    func testToolBudgetScalesAndClampsAtFloor() {
        // Default response cap (500t) scales 2x to 1000t
        XCTAssertEqual(TokenBudgeting.toolOutputTokenBudget(forResponseTokens: 500), 1000)
    }

    /// Tiny response cap (50t) must hit the floor so a tool reply isn't
    /// starved to nothing.
    func testToolBudgetClampedAtFloor() {
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

    /// The critical safety property: instructions + prompt overhead + the
    /// response + a single tool reply must never exceed the 4096-token
    /// window. Verified across the whole response-cap range, including the
    /// deep-profile cap that exposed the old hardcoded-ceiling overflow.
    func testToolBudgetNeverOverflowsWindowWithResponseAndInstructions() {
        for responseCap in [250, 500, 750, 1000, 1500, 3000, 5000] {
            // The model's response in tool mode is bounded by the
            // tool-calling clamp (reserves the schema/appendix overhead), not
            // the plain clamp — so a 3500/5000 request can't eat the window.
            let effectiveResponse = TokenBudgeting.clampedToolResponseTokens(requestedMaxTokens: responseCap)
            let toolBudget = TokenBudgeting.toolOutputTokenBudget(forResponseTokens: responseCap)
            // Reserve the REAL tool-calling cost: base instructions + the
            // tool-usage appendix and Foundation Models tool schemas
            // (`toolCallingOverheadTokens`) + prompt overhead + the response.
            let oneToolTurn = TokenBudgeting.instructionTokens
                + TokenBudgeting.toolCallingOverheadTokens
                + TokenBudgeting.promptOverheadTokens
                + effectiveResponse
                + toolBudget
            XCTAssertLessThanOrEqual(
                oneToolTurn,
                TokenBudgeting.contextWindowLimit,
                "A single tool reply at responseCap=\(responseCap) overflows the window: \(oneToolTurn) > \(TokenBudgeting.contextWindowLimit)"
                "A single tool reply at responseCap=\(responseCap) overflows: \(oneToolTurn) > \(TokenBudgeting.contextWindowLimit)"
            )
        }
    }

    /// Two tool replies (e.g. currentDateTime + webSearch) plus the
    /// response and instructions should also fit — the budget divides the
    /// available room by `assumedConcurrentToolReplies = 2`.
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
                "Two tool replies at responseCap=\(responseCap) overflow the window: \(twoToolTurn)"
                "Two tool replies at responseCap=\(responseCap) overflow: \(twoToolTurn)"
            )
        }
    }

    /// Budget honours the floor for all realistic response caps (the app's
    /// slider never reaches the degenerate range where the response alone
    /// eats the window). Window-safety still takes precedence over the
    /// floor — that's covered by the overflow test above — but in normal
    /// operation the floor always holds.
    /// The tool-calling response clamp must leave room for the overhead +
    /// at least the minimum context, even at the app's maximum response
    /// setting (3500) — otherwise tool calling has no window left and fails.
    func testToolResponseClampLeavesRoomForOverhead() {
        for responseCap in [500, 1500, 3500, 9999] {
            let clamped = TokenBudgeting.clampedToolResponseTokens(requestedMaxTokens: responseCap)
            let reservedBesidesResponse = TokenBudgeting.instructionTokens
            let reserved = TokenBudgeting.instructionTokens
                + TokenBudgeting.toolCallingOverheadTokens
                + TokenBudgeting.promptOverheadTokens
                + TokenBudgeting.minContextTokens
            XCTAssertLessThanOrEqual(
                clamped + reservedBesidesResponse,
                clamped + reserved,
                TokenBudgeting.contextWindowLimit,
                "Tool response clamp at \(responseCap) leaves no room for overhead + min context"
                "Tool response clamp at \(responseCap) leaves no room for overhead"
            )
        }
        // And it must never EXCEED the plain clamp (it only ever reserves more).
        XCTAssertLessThanOrEqual(
            TokenBudgeting.clampedToolResponseTokens(requestedMaxTokens: 3500),
            TokenBudgeting.clampedOutputTokens(requestedMaxTokens: 3500)
        )
    }

    /// Hybrid chat tool-calling grounds some context up front AND still
    /// expects at least one substantial tool reply plus a lightweight second
    /// reply (e.g. `calculate`). That combined transcript must still fit.
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

    func testToolBudgetHonoursFloorForRealisticCaps() {
        for responseCap in [1, 50, 500, 1000, 1500] {
            XCTAssertGreaterThanOrEqual(
                TokenBudgeting.toolOutputTokenBudget(forResponseTokens: responseCap),
                TokenBudgeting.toolOutputTokenBudgetFloor,
                "Floor not honoured at realistic responseCap=\(responseCap)"
            )
        }
    }
}
