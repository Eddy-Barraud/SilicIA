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
    @MainActor
    func testWebSearchBudgetCeilingAtDefaultAndRicherProfiles() {
        // Default profile: shared budget equals cap (1000t)
        let shared = TokenBudgeting.toolOutputTokenBudget(forResponseTokens: 500)
        XCTAssertEqual(shared, TokenBudgeting.webSearchReplyTokenCap,
                       "At the default profile the cap should match the shared budget (1000t)")

        let (defaultTools, defaultSharedBudget, _) = ToolKit.assemble(
            config: makeConfig(webSearchAvailable: true),
            responseTokens: 500
        )
        let defaultWebTool = defaultTools.compactMap { $0 as? WebSearchTool }.first
        let defaultWikiTool = defaultTools.compactMap { $0 as? WikipediaTool }.first
        let defaultRagTool = defaultTools.compactMap { $0 as? RAGSearchTool }.first
        XCTAssertNotNil(defaultWebTool)
        XCTAssertNotNil(defaultWikiTool)
        XCTAssertNotNil(defaultRagTool)
        XCTAssertEqual(defaultWebTool?.tokenBudget, min(defaultSharedBudget, TokenBudgeting.webSearchReplyTokenCap))
        XCTAssertEqual(defaultWikiTool?.tokenBudget, defaultSharedBudget)
        XCTAssertEqual(defaultRagTool?.tokenBudget, defaultSharedBudget)

        // Richer profile: shared budget exceeds cap, webSearch is held to ceiling
        let (richTools, richSharedBudget, _) = ToolKit.assemble(
            config: makeConfig(webSearchAvailable: true),
            responseTokens: 600
        )
        XCTAssertGreaterThan(richSharedBudget, TokenBudgeting.webSearchReplyTokenCap,
                             "Need a profile where the shared budget exceeds the cap for this test to be meaningful")
        let richWebTool = richTools.compactMap { $0 as? WebSearchTool }.first
        let richWikiTool = richTools.compactMap { $0 as? WikipediaTool }.first
        let richRagTool = richTools.compactMap { $0 as? RAGSearchTool }.first
        XCTAssertEqual(richWebTool?.tokenBudget, TokenBudgeting.webSearchReplyTokenCap,
                       "webSearch should be held to the ceiling")
        XCTAssertEqual(richWikiTool?.tokenBudget, richSharedBudget,
                       "wikipediaSearch should keep the full shared budget")
        XCTAssertEqual(richRagTool?.tokenBudget, richSharedBudget,
                       "searchContext should keep the full shared budget")
    }

    @MainActor
    private func makeConfig(
        webSearchAvailable: Bool,
        hasCorpus: Bool = true,
        useDuckDuckGo: Bool = true,
        useWikipedia: Bool = true
    ) -> ToolKit.Configuration {
        let chunks: [RAGChunk] = hasCorpus ? [
            RAGChunk(source: "document.pdf", text: "Sample document passage for budgeting tests.", url: nil, pdfPage: 1)
        ] : []
        return ToolKit.Configuration(
            language: .english,
            corpusChunks: chunks,
            webSearchAvailable: webSearchAvailable,
            webSearchService: WebSearchService(),
            webScraper: WebScrapingService(),
            maxDuckDuckGoResults: 6,
            maxWikipediaResults: 2,
            useDuckDuckGo: useDuckDuckGo,
            useWikipedia: useWikipedia
        )
    }

    /// When web search is disabled the kit omits the webSearch and wikipediaSearch tools entirely.
    /// When no documents exist in corpus, the kit omits searchContext entirely.
    @MainActor
    func testNoWebSearchToolWhenUnavailable() {
        let (tools, _, _) = ToolKit.assemble(
            config: makeConfig(webSearchAvailable: false, hasCorpus: true),
            responseTokens: 500
        )
        XCTAssertTrue(tools.compactMap { $0 as? WebSearchTool }.isEmpty)
        XCTAssertTrue(tools.compactMap { $0 as? WikipediaTool }.isEmpty)
        XCTAssertFalse(tools.compactMap { $0 as? RAGSearchTool }.isEmpty)

        let (noCorpusTools, _, _) = ToolKit.assemble(
            config: makeConfig(webSearchAvailable: true, hasCorpus: false),
            responseTokens: 500
        )
        XCTAssertFalse(noCorpusTools.compactMap { $0 as? WebSearchTool }.isEmpty)
        XCTAssertFalse(noCorpusTools.compactMap { $0 as? WikipediaTool }.isEmpty)
        XCTAssertTrue(noCorpusTools.compactMap { $0 as? RAGSearchTool }.isEmpty,
                      "searchContext must be omitted when there are no corpus chunks")
    }

    /// When both sources are disabled, neither webSearch nor wikipediaSearch is present,
    /// leaving the LLM completely offline.
    @MainActor
    func testOfflineModeWhenBothSourcesDisabled() {
        let (tools, _, _) = ToolKit.assemble(
            config: makeConfig(
                webSearchAvailable: true,
                hasCorpus: false,
                useDuckDuckGo: false,
                useWikipedia: false
            ),
            responseTokens: 500
        )
        XCTAssertTrue(tools.compactMap { $0 as? WebSearchTool }.isEmpty, "webSearch must be omitted when useDuckDuckGo is false")
        XCTAssertTrue(tools.compactMap { $0 as? WikipediaTool }.isEmpty, "wikipediaSearch must be omitted when useWikipedia is false")
        XCTAssertTrue(tools.compactMap { $0 as? RAGSearchTool }.isEmpty, "searchContext must be omitted when no corpus")
        // Only offline utilities remain (DateTimeTool and CalculatorTool)
        let toolNames = tools.map(\.name)
        XCTAssertTrue(toolNames.contains("currentDateTime"))
        XCTAssertTrue(toolNames.contains("calculate"))
    }

    /// When one source is enabled and the other is disabled, only the enabled source is registered.
    @MainActor
    func testIndependentSourceToggling() {
        // Internet (DuckDuckGo) only
        let (ddgTools, _, _) = ToolKit.assemble(
            config: makeConfig(
                webSearchAvailable: true,
                hasCorpus: false,
                useDuckDuckGo: true,
                useWikipedia: false
            ),
            responseTokens: 500
        )
        XCTAssertFalse(ddgTools.compactMap { $0 as? WebSearchTool }.isEmpty, "webSearch must be registered")
        XCTAssertTrue(ddgTools.compactMap { $0 as? WikipediaTool }.isEmpty, "wikipediaSearch must be omitted")

        // Wikipedia only
        let (wikiTools, _, _) = ToolKit.assemble(
            config: makeConfig(
                webSearchAvailable: true,
                hasCorpus: false,
                useDuckDuckGo: false,
                useWikipedia: true
            ),
            responseTokens: 500
        )
        XCTAssertTrue(wikiTools.compactMap { $0 as? WebSearchTool }.isEmpty, "webSearch must be omitted")
        XCTAssertFalse(wikiTools.compactMap { $0 as? WikipediaTool }.isEmpty, "wikipediaSearch must be registered")
    }
}
