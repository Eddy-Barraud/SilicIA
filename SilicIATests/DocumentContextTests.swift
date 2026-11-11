//
//  DocumentContextTests.swift
//  SilicIATests
//
//  Tests for document context ingestion, dropped file persistence,
//  and PDF context budgeting & batching.
//

import XCTest
import FoundationModels
@testable import SilicIA

final class DocumentContextTests: XCTestCase {

    @MainActor
    func testTextAndMarkdownFileIngestionAndPersistence() async throws {
        // Chunk generation from markdown and plain text
        let md = "# Title\n\n| Feature | Value |\n|---|---|\n| Privacy | Local |\n\nConclusion."
        let mdChunks = ChatService.makeTextFileChunks(text: md, fileName: "overview.md")
        XCTAssertFalse(mdChunks.isEmpty)
        XCTAssertTrue(mdChunks.allSatisfy { $0.source == "File: overview.md" })
        XCTAssertTrue(mdChunks.contains { $0.text.contains("Local") })

        let plain = "First paragraph.\n\nSecond paragraph."
        let plainChunks = ChatService.makeTextFileChunks(text: plain, fileName: "notes.txt")
        XCTAssertEqual(plainChunks.count, 2)

        // Ingestion & deterministic ordering through collectChunks
        let tempDir = FileManager.default.temporaryDirectory
        let doc1 = tempDir.appendingPathComponent("1_alpha_\(UUID().uuidString).txt")
        let doc2 = tempDir.appendingPathComponent("2_beta_\(UUID().uuidString).txt")
        try "Alpha content.".write(to: doc1, atomically: true, encoding: .utf8)
        try "Beta content.".write(to: doc2, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: doc1)
            try? FileManager.default.removeItem(at: doc2)
        }

        let chatService = ChatService()
        let chunks = await chatService.collectChunks(
            contextInput: "",
            pdfURLs: [doc1, doc2],
            imageURLs: [],
            includeWebSearch: false,
            currentMessage: "test order",
            maxDuckDuckGoResults: 0,
            maxWikipediaResults: 0,
            maxContextTokens: 2000
        )
        XCTAssertEqual(chunks.map(\.source), ["File: \(doc1.lastPathComponent)", "File: \(doc2.lastPathComponent)"])

        // DroppedFileStore persistence & collision renaming
        let sampleFile = tempDir.appendingPathComponent("source_\(UUID().uuidString).txt")
        try "safe content".write(to: sampleFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: sampleFile) }

        let store = DroppedFileStore(folderName: "SilicIASecurityTest", defaultExtension: "txt", allowedExtensions: ["txt"])
        defer { store.clearAll() }

        guard let p1 = store.persist(sampleFile, preferredFileName: "note.txt") else {
            return XCTFail("Failed to persist file")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: p1.path))
        let p2 = store.persist(sampleFile, preferredFileName: "note.txt")
        XCTAssertNotEqual(p1.path, p2?.path)

        // Directory traversal mitigation
        let traversal = store.persist(sampleFile, preferredFileName: "../../../etc/traversal.txt")
        XCTAssertNotNil(traversal)
        if let traversal {
            XCTAssertEqual(
                traversal.standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent().path,
                store.storageDirectory.standardizedFileURL.resolvingSymlinksInPath().path
            )
            XCTAssertFalse(traversal.path.contains(".."))
        }
    }

    func testPDFContextBudgetingAndBatching() async {
        // 1. Token budget calculations across reasoning levels
        XCTAssertEqual(TokenBudgeting.reasoningTokens(for: .light), 200)
        XCTAssertEqual(TokenBudgeting.reasoningTokens(for: .moderate), 400)
        XCTAssertEqual(TokenBudgeting.reasoningTokens(for: .deep), 800)
        XCTAssertEqual(TokenBudgeting.maxTotalTokensLimit, 4000)

        let maxOutputTokens = 600
        let staticOverhead = TokenBudgeting.instructionTokens + TokenBudgeting.promptOverheadTokens

        let lightInputTokens = TokenBudgeting.maxPDFInputContextTokens(maxOutputTokens: maxOutputTokens, reasoningLevel: .light)
        let modInputTokens = TokenBudgeting.maxPDFInputContextTokens(maxOutputTokens: maxOutputTokens, reasoningLevel: .moderate)
        let deepInputTokens = TokenBudgeting.maxPDFInputContextTokens(maxOutputTokens: maxOutputTokens, reasoningLevel: .deep)

        XCTAssertEqual(lightInputTokens, 3020)
        XCTAssertEqual(modInputTokens, 2820)
        XCTAssertEqual(deepInputTokens, 2420)

        XCTAssertEqual(lightInputTokens + 200 + maxOutputTokens + staticOverhead, 4000)
        XCTAssertEqual(modInputTokens + 400 + maxOutputTokens + staticOverhead, 4000)
        XCTAssertEqual(deepInputTokens + 800 + maxOutputTokens + staticOverhead, 4000)

        let modChars = TokenBudgeting.maxPDFInputContextCharacters(maxOutputTokens: maxOutputTokens, reasoningLevel: .moderate)
        XCTAssertEqual(modChars, modInputTokens * TokenBudgeting.avgCharsPerToken)

        let nonPDFBudget = RAGContextService.calculate4096BudgetedContextCharacters(
            maxOutputTokens: maxOutputTokens, isPDFSource: false, reasoningLevel: .moderate
        )
        let pdfBudget = RAGContextService.calculate4096BudgetedContextCharacters(
            maxOutputTokens: maxOutputTokens, isPDFSource: true, reasoningLevel: .moderate
        )
        XCTAssertEqual(pdfBudget, modChars)
        XCTAssertGreaterThan(pdfBudget, nonPDFBudget)

        // 2. ChatService PDF page batching
        let p1 = "Single page text about surfactant chemistry."
        let single = ChatService.makePDFPageBatches(pages: [p1])
        XCTAssertEqual(single.count, 1)
        XCTAssertFalse(single[0].isMerged)
        XCTAssertEqual(single[0].pageNumbers, [1])

        let short1 = String(repeating: "Page 1 chemical analysis. ", count: 60)
        let short2 = String(repeating: "Page 2 experimental results. ", count: 60)
        let merged = ChatService.makePDFPageBatches(pages: [short1, short2], maxMergedTokens: 3500)
        XCTAssertEqual(merged.count, 1)
        XCTAssertTrue(merged[0].isMerged)
        XCTAssertEqual(merged[0].pageNumbers, [1, 2])

        let long1 = String(repeating: "Page 1 lengthy discussion of results. ", count: 160)
        let long2 = String(repeating: "Page 2 lengthy thermodynamic proofs. ", count: 160)
        let separate = ChatService.makePDFPageBatches(pages: [long1, long2], maxMergedTokens: 3500)
        XCTAssertEqual(separate.count, 2)
        XCTAssertFalse(separate[0].isMerged)

        let hugePage = String(repeating: "Huge text string filling the page. ", count: 500)
        let capped = ChatService.makePDFPageBatches(pages: [hugePage], maxSingleTokens: 4000)
        XCTAssertEqual(capped.count, 1)
        XCTAssertEqual(capped[0].combinedContent.count, 4000 * TokenBudgeting.avgCharsPerToken)

        // 3. ChatService PDF page chunks
        let pageText = "Thermodynamically, the CMC manifests as a distinct change in the slope of the osmotic pressure."
        let singleChunks = await ChatService.makePDFPageChunks(
            text: pageText,
            source: "PDF: fixture page 1",
            pdfPage: 1,
            maxContextTokens: 2916
        )
        XCTAssertEqual(singleChunks.count, 1)
        XCTAssertEqual(singleChunks.first?.text, pageText)
    }
}
