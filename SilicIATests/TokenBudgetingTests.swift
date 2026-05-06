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
}
