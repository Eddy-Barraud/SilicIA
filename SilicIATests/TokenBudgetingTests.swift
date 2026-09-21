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
}
