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

    /// The dedicated webSearch ceiling must be below the shared tool budget
    /// at the default response cap, otherwise the cap is a no-op.
    func testWebSearchCapIsBelowSharedBudgetAtDefault() {
        let shared = TokenBudgeting.toolOutputTokenBudget(forResponseTokens: 500)
        XCTAssertGreaterThan(shared, TokenBudgeting.webSearchReplyTokenCap,
                             "Shared budget should exceed the webSearch cap so the cap actually bites")
    }

    @MainActor
    private func makeConfig(webSearchAvailable: Bool) -> ToolKit.Configuration {
        ToolKit.Configuration(
            language: .english,
            corpusChunks: [],
            webSearchAvailable: webSearchAvailable,
            webSearchService: WebSearchService(),
            webScraper: WebScrapingService(),
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
        let (tools, sharedBudget) = ToolKit.assemble(
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
        let (tools, _) = ToolKit.assemble(
            config: makeConfig(webSearchAvailable: false),
            responseTokens: 500
        )
        XCTAssertTrue(tools.compactMap { $0 as? WebSearchTool }.isEmpty)
    }
}
