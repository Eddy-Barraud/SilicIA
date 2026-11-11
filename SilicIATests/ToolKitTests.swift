//
//  ToolKitTests.swift
//  SilicIATests
//
//  Tests for Foundation Models tools: CalculatorTool evaluation & loop guards,
//  ToolCallGovernor loop breaker & budgets, ToolTranscriptRecorder,
//  RAGSearchTool token budgeting, and ToolKit source activation matrix.
//

import XCTest
@testable import SilicIA

final class ToolKitTests: XCTestCase {

    override func setUp() {
        super.setUp()
        CalculatorTool.resetLoopGuardForTesting()
    }

    func testCalculatorEvaluationAndLoopGuard() async throws {
        let tool = CalculatorTool()

        // Valid arithmetic, comma decimal, and factorials
        let cases: [(String, String)] = [
            ("2 + 3", "5"),
            ("12 * 12", "144"),
            ("10 / 4", "2.5"),
            ("1,5 * 2", "3"),
            ("64,24 * 2", "128.48"),
            ("5!", "120"),
            ("0!", "1"),
            ("15!", "1307674368000")
        ]
        for (expression, expected) in cases {
            let output = try await tool.call(arguments: .init(expression: expression))
            XCTAssertEqual(output, expected, "Failed for '\(expression)'")
        }

        // Precision cap (16!) and invalid syntax
        let overCap = try await tool.call(arguments: .init(expression: "16!"))
        XCTAssertTrue(overCap.hasPrefix("Error"))

        let invalid = try await tool.call(arguments: .init(expression: "self.value"))
        XCTAssertTrue(invalid.hasPrefix("Error"))

        // Loop guard engages on repeated identical bad calls
        let bad = "abc!"
        var sawStop = false
        for _ in 0..<6 {
            let output = try await tool.call(arguments: .init(expression: bad))
            if output.contains("STOP CALLING THIS TOOL") {
                sawStop = true
                break
            }
        }
        XCTAssertTrue(sawStop)
    }

    func testToolCallGovernorAndTranscriptRecorder() async throws {
        let governor = ToolCallGovernor(maxTotalCalls: 5, maxExpensiveToolCalls: 1, expensiveToolName: "searchSources")

        // Allowance & duplicate refusal
        let first = await governor.evaluate(tool: "searchContext", arguments: "factorial")
        XCTAssertEqual(first, .allow)
        XCTAssertNil(first.refusalMessage)

        _ = await governor.evaluate(tool: "searchSources", arguments: "how to calculate factorial n")
        let dup = await governor.evaluate(tool: "searchSources", arguments: "  How To Calculate Factorial N ")
        XCTAssertEqual(dup, .duplicate(count: 2))
        XCTAssertNotNil(dup.refusalMessage)

        // Expensive tool budget cap (searchSources capped at 1 call)
        let secondSearch = await governor.evaluate(tool: "searchSources", arguments: "new query")
        XCTAssertEqual(secondSearch, .toolBudgetReached(tool: "searchSources", cap: 1))

        // Total budget ceiling (max 5 calls)
        _ = await governor.evaluate(tool: "calculate", arguments: "2 + 2")
        _ = await governor.evaluate(tool: "calculate", arguments: "3 + 3")
        let over = await governor.evaluate(tool: "currentDateTime", arguments: "iso")
        XCTAssertEqual(over, .totalBudgetReached(cap: 5))
        XCTAssertNotNil(over.refusalMessage)

        // ToolTranscriptRecorder budgeting & FIFO eviction
        let emptyRecorder = ToolTranscriptRecorder()
        let emptyRendered = await emptyRecorder.renderedTranscript(characterBudget: 200)
        XCTAssertEqual(emptyRendered, "")

        let recorder = ToolTranscriptRecorder(maxEntries: 3)
        await recorder.record(tool: "searchContext", arguments: "equation 6", result: "Nc is the number of carbons.")
        await recorder.record(tool: "calculate", arguments: "log(2)", result: "0.6931471806")
        await recorder.record(tool: "currentDateTime", arguments: "date", result: "Saturday, June 28, 2026")

        let rendered = await recorder.renderedTranscript(characterBudget: 220, maxRenderedEntries: 2)
        XCTAssertTrue(rendered.contains("calculate") || rendered.contains("currentDateTime"))
        XCTAssertFalse(rendered.contains("searchContext"), "Oldest entry should be dropped first")
        XCTAssertLessThanOrEqual(rendered.count, 220)

        // Duplicate error thrown when transcript recorder is present
        var recordedTool = CalculatorTool()
        recordedTool.governor = ToolCallGovernor()
        recordedTool.transcriptRecorder = ToolTranscriptRecorder()
        _ = try await recordedTool.call(arguments: .init(expression: "10 / 4"))
        do {
            _ = try await recordedTool.call(arguments: .init(expression: "10 / 4"))
            XCTFail("Expected duplicate ToolError")
        } catch let error as ToolError {
            guard case .duplicate(let toolName, let count) = error else {
                return XCTFail("Expected duplicate ToolError, got \(error)")
            }
            XCTAssertEqual(toolName, "calculate")
            XCTAssertEqual(count, 2)
        }
    }

    @MainActor
    private func makeConfig(
        webSearchAvailable: Bool,
        hasCorpus: Bool = true,
        useDuckDuckGo: Bool = true,
        useWikipedia: Bool = true
    ) -> ToolKit.Configuration {
        let chunks: [RAGChunk] = hasCorpus ? [
            RAGChunk(source: "document.pdf", text: "Sample document passage.", url: nil, pdfPage: 1)
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

    @MainActor
    func testToolKitAssemblyAndSourceActivationMatrix() async throws {
        // Assembly and sizing with token budgets
        let (tools, budget, _) = ToolKit.assemble(
            config: makeConfig(webSearchAvailable: true),
            responseTokens: 500
        )
        let searchSourcesTool = tools.first { $0.name == "searchSources" }
        let ragTool = tools.compactMap { $0 as? RAGSearchTool }.first
        XCTAssertNotNil(searchSourcesTool)
        XCTAssertNotNil(ragTool)
        XCTAssertEqual(ragTool?.tokenBudget, budget)

        // RAGSearchTool honours token budget
        let filler = String(repeating: "Background filler text that should not dominate the reply. ", count: 120)
        let target = "Equation 4 defines the osmotic coefficient for the solute in DPD units."
        let chunk = RAGChunk(source: "PDF: fixture page 5", text: filler + target + filler, url: nil, pdfPage: 5)
        var standaloneRAGTool = RAGSearchTool(chunks: [chunk], tokenBudget: 200)
        standaloneRAGTool.governor = ToolCallGovernor()
        let ragOutput = try await standaloneRAGTool.call(arguments: .init(query: "equation 4", maxResults: 1))
        XCTAssertLessThanOrEqual(
            ragOutput.count,
            TokenBudgeting.estimatedContextCharacters(forTokens: 200),
            "searchContext reply exceeded token budget"
        )
        XCTAssertTrue(ragOutput.localizedCaseInsensitiveContains("equation 4"))

        // Source activation matrix
        // Both enabled -> SearchSourcesTool
        let (bothTools, _, _) = ToolKit.assemble(
            config: makeConfig(webSearchAvailable: true, hasCorpus: false, useDuckDuckGo: true, useWikipedia: true),
            responseTokens: 500
        )
        XCTAssertFalse(bothTools.compactMap { $0 as? SearchSourcesTool }.isEmpty)

        // DDG only -> WebSourcesTool
        let (ddgTools, _, _) = ToolKit.assemble(
            config: makeConfig(webSearchAvailable: true, hasCorpus: false, useDuckDuckGo: true, useWikipedia: false),
            responseTokens: 500
        )
        XCTAssertFalse(ddgTools.compactMap { $0 as? WebSourcesTool }.isEmpty)

        // Wiki only -> WikiSourcesTool
        let (wikiTools, _, _) = ToolKit.assemble(
            config: makeConfig(webSearchAvailable: true, hasCorpus: false, useDuckDuckGo: false, useWikipedia: true),
            responseTokens: 500
        )
        XCTAssertFalse(wikiTools.compactMap { $0 as? WikiSourcesTool }.isEmpty)

        // Offline mode (both false) -> offline tools only
        let (offlineTools, _, _) = ToolKit.assemble(
            config: makeConfig(webSearchAvailable: true, hasCorpus: false, useDuckDuckGo: false, useWikipedia: false),
            responseTokens: 500
        )
        XCTAssertFalse(offlineTools.contains { $0.name == "searchSources" })
        let toolNames = offlineTools.map(\.name)
        XCTAssertTrue(toolNames.contains("currentDateTime"))
        XCTAssertTrue(toolNames.contains("calculate"))
    }
}
