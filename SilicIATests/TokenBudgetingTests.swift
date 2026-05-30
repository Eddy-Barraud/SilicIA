//
//  TokenBudgetingTests.swift
//  SilicIATests
//

import XCTest
@testable import SilicIA

final class TokenBudgetingTests: XCTestCase {

    func testClampedOutputTokensMin() {
        let result = TokenBudgeting.clampedOutputTokens(requestedMaxTokens: 1)
        XCTAssertGreaterThanOrEqual(result, 1)
    }

    func testClampedOutputTokensMax() {
        let result = TokenBudgeting.clampedOutputTokens(requestedMaxTokens: 999_999)
        XCTAssertLessThanOrEqual(result, TokenBudgeting.contextWindowLimit)
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
        XCTAssertGreaterThanOrEqual(TokenBudgeting.estimatedTokens(forApproxWords: 0), 0)
    }

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
        XCTAssertEqual(TokenBudgeting.toolOutputTokenBudget(forResponseTokens: 500), 1000)
    }

    /// Tiny response cap (50t) must hit the floor so a tool reply isn't
    /// starved to nothing.
    func testToolBudgetClampedAtFloor() {
        XCTAssertEqual(
            TokenBudgeting.toolOutputTokenBudget(forResponseTokens: 50),
            TokenBudgeting.toolOutputTokenBudgetFloor
        )
    }

    /// The critical safety property: instructions + prompt overhead + the
    /// response + a single tool reply must never exceed the 4096-token
    /// window. Verified across the whole response-cap range, including the
    /// deep-profile cap that exposed the old hardcoded-ceiling overflow.
    func testToolBudgetNeverOverflowsWindowWithResponseAndInstructions() {
        for responseCap in [250, 500, 750, 1000, 1500, 3000, 5000] {
            let effectiveResponse = TokenBudgeting.clampedOutputTokens(requestedMaxTokens: responseCap)
            let toolBudget = TokenBudgeting.toolOutputTokenBudget(forResponseTokens: responseCap)
            let oneToolTurn = TokenBudgeting.instructionTokens
                + TokenBudgeting.promptOverheadTokens
                + effectiveResponse
                + toolBudget
            XCTAssertLessThanOrEqual(
                oneToolTurn,
                TokenBudgeting.contextWindowLimit,
                "A single tool reply at responseCap=\(responseCap) overflows the window: \(oneToolTurn) > \(TokenBudgeting.contextWindowLimit)"
            )
        }
    }

    /// Two tool replies (e.g. currentDateTime + webSearch) plus the
    /// response and instructions should also fit — the budget divides the
    /// available room by `assumedConcurrentToolReplies = 2`.
    func testToolBudgetSurvivesTwoConcurrentReplies() {
        for responseCap in [500, 1000, 1500] {
            let effectiveResponse = TokenBudgeting.clampedOutputTokens(requestedMaxTokens: responseCap)
            let toolBudget = TokenBudgeting.toolOutputTokenBudget(forResponseTokens: responseCap)
            let twoToolTurn = TokenBudgeting.instructionTokens
                + TokenBudgeting.promptOverheadTokens
                + effectiveResponse
                + (toolBudget * 2)
            XCTAssertLessThanOrEqual(
                twoToolTurn,
                TokenBudgeting.contextWindowLimit,
                "Two tool replies at responseCap=\(responseCap) overflow the window: \(twoToolTurn)"
            )
        }
    }

    /// Budget honours the floor for all realistic response caps (the app's
    /// slider never reaches the degenerate range where the response alone
    /// eats the window). Window-safety still takes precedence over the
    /// floor — that's covered by the overflow test above — but in normal
    /// operation the floor always holds.
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
