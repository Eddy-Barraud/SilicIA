//
//  ToolKitBudgetTests.swift
//  SilicIATests
//
//  Guards the tool kit assembly, source activation matrix (both on, web only,
//  wiki only, both off), and per-tool budgeting.
//

import XCTest
@testable import SilicIA

final class ToolKitBudgetTests: XCTestCase {

    @MainActor
    func testToolKitBudgetAndRAGToolSizing() {
        let (defaultTools, defaultSharedBudget, _) = ToolKit.assemble(
            config: makeConfig(webSearchAvailable: true),
            responseTokens: 500
        )
        let searchSourcesTool = defaultTools.first { $0.name == "searchSources" }
        let defaultRagTool = defaultTools.compactMap { $0 as? RAGSearchTool }.first
        XCTAssertNotNil(searchSourcesTool, "searchSources must be registered when sources are enabled")
        XCTAssertNotNil(defaultRagTool)
        XCTAssertEqual(defaultRagTool?.tokenBudget, defaultSharedBudget)

        let (richTools, richSharedBudget, _) = ToolKit.assemble(
            config: makeConfig(webSearchAvailable: true),
            responseTokens: 600
        )
        let richRagTool = richTools.compactMap { $0 as? RAGSearchTool }.first
        XCTAssertEqual(richRagTool?.tokenBudget, richSharedBudget)
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

    /// When web search is disabled the kit omits the searchSources tool entirely.
    /// When no documents exist in corpus, the kit omits searchContext entirely.
    @MainActor
    func testNoSearchSourcesToolWhenUnavailable() {
        let (tools, _, _) = ToolKit.assemble(
            config: makeConfig(webSearchAvailable: false, hasCorpus: true),
            responseTokens: 500
        )
        XCTAssertFalse(tools.contains { $0.name == "searchSources" })
        XCTAssertFalse(tools.compactMap { $0 as? RAGSearchTool }.isEmpty)

        let (noCorpusTools, _, _) = ToolKit.assemble(
            config: makeConfig(webSearchAvailable: true, hasCorpus: false),
            responseTokens: 500
        )
        XCTAssertTrue(noCorpusTools.contains { $0.name == "searchSources" })
        XCTAssertTrue(noCorpusTools.compactMap { $0 as? RAGSearchTool }.isEmpty,
                      "searchContext must be omitted when there are no corpus chunks")
    }

    /// When both sources are disabled, no searchSources tool is present,
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
        XCTAssertFalse(tools.contains { $0.name == "searchSources" }, "searchSources must be omitted when both sources are false")
        XCTAssertTrue(tools.compactMap { $0 as? RAGSearchTool }.isEmpty, "searchContext must be omitted when no corpus")
        // Only offline utilities remain (DateTimeTool and CalculatorTool)
        let toolNames = tools.map(\.name)
        XCTAssertTrue(toolNames.contains("currentDateTime"))
        XCTAssertTrue(toolNames.contains("calculate"))
    }

    /// Tests the source activation matrix: both on, web only, wiki only.
    @MainActor
    func testIndependentSourceToggling() {
        // Both enabled -> SearchSourcesTool
        let (bothTools, _, _) = ToolKit.assemble(
            config: makeConfig(
                webSearchAvailable: true,
                hasCorpus: false,
                useDuckDuckGo: true,
                useWikipedia: true
            ),
            responseTokens: 500
        )
        XCTAssertFalse(bothTools.compactMap { $0 as? SearchSourcesTool }.isEmpty, "SearchSourcesTool must be registered when both on")
        XCTAssertTrue(bothTools.compactMap { $0 as? WebSourcesTool }.isEmpty)
        XCTAssertTrue(bothTools.compactMap { $0 as? WikiSourcesTool }.isEmpty)

        // Internet (DuckDuckGo) only -> WebSourcesTool
        let (ddgTools, _, _) = ToolKit.assemble(
            config: makeConfig(
                webSearchAvailable: true,
                hasCorpus: false,
                useDuckDuckGo: true,
                useWikipedia: false
            ),
            responseTokens: 500
        )
        XCTAssertFalse(ddgTools.compactMap { $0 as? WebSourcesTool }.isEmpty, "WebSourcesTool must be registered")
        XCTAssertTrue(ddgTools.compactMap { $0 as? SearchSourcesTool }.isEmpty)
        XCTAssertTrue(ddgTools.compactMap { $0 as? WikiSourcesTool }.isEmpty)

        // Wikipedia only -> WikiSourcesTool
        let (wikiTools, _, _) = ToolKit.assemble(
            config: makeConfig(
                webSearchAvailable: true,
                hasCorpus: false,
                useDuckDuckGo: false,
                useWikipedia: true
            ),
            responseTokens: 500
        )
        XCTAssertFalse(wikiTools.compactMap { $0 as? WikiSourcesTool }.isEmpty, "WikiSourcesTool must be registered")
        XCTAssertTrue(wikiTools.compactMap { $0 as? SearchSourcesTool }.isEmpty)
        XCTAssertTrue(wikiTools.compactMap { $0 as? WebSourcesTool }.isEmpty)
    }
}
