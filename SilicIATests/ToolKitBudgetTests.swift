//
//  ToolKitBudgetTests.swift
//  SilicIATests
//
//  Guards the per-tool reply budgeting — in particular that `webSearch`
//  gets a TIGHTER cap than the other tools. webSearch is the dominant
//  tool-calling transcript consumer (it packs several scraped pages), so
//  capping it below the shared budget is the mitigation for the
//  intermittent `GenerationError -1` context-window overflow.
//

import XCTest
@testable import SilicIA

final class ToolKitBudgetTests: XCTestCase {

    /// At the default (fast) profile the shared budget equals the webSearch
    /// ceiling, so webSearch uses the full shared budget — the ceiling only
    /// bites on richer profiles (see below).
    func testWebSearchCapEqualsSharedBudgetAtDefault() {
        let shared = TokenBudgeting.toolOutputTokenBudget(forResponseTokens: 500)
        XCTAssertEqual(shared, TokenBudgeting.webSearchReplyTokenCap,
                       "At the default profile the cap should match the shared budget (1000t)")
    }

    /// On a richer profile the shared budget exceeds the ceiling, so
    /// webSearch is held to the ceiling while the other tools get the full
    /// shared budget.
    @MainActor
    func testWebSearchCapBitesOnRicherProfile() {
        let (tools, sharedBudget, _) = ToolKit.assemble(
            config: makeConfig(webSearchAvailable: true),
            responseTokens: 600
        )
        XCTAssertGreaterThan(sharedBudget, TokenBudgeting.webSearchReplyTokenCap,
                             "Need a profile where the shared budget exceeds the cap for this test to be meaningful")
        let webTool = tools.compactMap { $0 as? WebSearchTool }.first
        let ragTool = tools.compactMap { $0 as? RAGSearchTool }.first
        XCTAssertEqual(webTool?.tokenBudget, TokenBudgeting.webSearchReplyTokenCap,
                       "webSearch should be held to the ceiling")
        XCTAssertEqual(ragTool?.tokenBudget, sharedBudget,
                       "searchContext should keep the full shared budget")
    }

    @MainActor
    private func makeConfig(webSearchAvailable: Bool) -> ToolKit.Configuration {
        ToolKit.Configuration(
            language: .english,
            corpusChunks: [],
            webSearchAvailable: webSearchAvailable,
            webSearchService: WebSearchService(),
            webScraper: WebScrapingService(),
            useWebVision: false,
            maxDuckDuckGoResults: 6,
            maxWikipediaResults: 2,
            useDuckDuckGo: true,
            useWikipedia: true
        )
    }

    /// webSearch is assembled with `min(sharedBudget, webSearchReplyTokenCap)`,
    /// while searchContext keeps the full shared budget.
    @MainActor
    func testWebSearchToolGetsCappedBudgetOthersDoNot() {
        let responseTokens = 500
        let (tools, sharedBudget, _) = ToolKit.assemble(
            config: makeConfig(webSearchAvailable: true),
            responseTokens: responseTokens
        )

        let webTool = tools.compactMap { $0 as? WebSearchTool }.first
        let ragTool = tools.compactMap { $0 as? RAGSearchTool }.first

        XCTAssertNotNil(webTool)
        XCTAssertNotNil(ragTool)

        let expectedWebBudget = min(sharedBudget, TokenBudgeting.webSearchReplyTokenCap)
        XCTAssertEqual(webTool?.tokenBudget, expectedWebBudget,
                       "webSearch should be capped at the dedicated ceiling")
        XCTAssertEqual(ragTool?.tokenBudget, sharedBudget,
                       "searchContext should keep the full shared budget")
    }

    /// When web search is disabled the kit omits the webSearch tool entirely.
    @MainActor
    func testNoWebSearchToolWhenUnavailable() {
        let (tools, _, _) = ToolKit.assemble(
            config: makeConfig(webSearchAvailable: false),
            responseTokens: 500
        )
        XCTAssertTrue(tools.compactMap { $0 as? WebSearchTool }.isEmpty)
    }
}
