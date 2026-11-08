//
//  ChatServiceTextFileContextTests.swift
//  SilicIATests
//
//  Created by Antigravity on 08/11/2026.
//

import XCTest
@testable import SilicIA

final class ChatServiceTextFileContextTests: XCTestCase {

    func testMakeTextFileChunksWithMarkdown() {
        let markdownText = """
        # Project SilicIA Overview

        SilicIA is an on-device local intelligence workspace for macOS and iOS.
        It runs entirely on Apple Neural Engine and local foundation models.

        ## Feature Comparison Table

        | Feature | SilicIA | Cloud LLMs |
        |---|---|---|
        | Privacy | 100% on-device | Data leaves device |
        | Latency | Instant prefill | Network dependent |
        | Offline | Fully functional | Requires internet |

        ### Final Thoughts
        This demonstrates direct streaming of structured Markdown without Vision OCR.
        """

        let chunks = ChatService.makeTextFileChunks(text: markdownText, fileName: "overview.md")
        XCTAssertFalse(chunks.isEmpty, "Should produce RAG chunks from Markdown")
        XCTAssertTrue(chunks.allSatisfy { $0.source == "File: overview.md" })
        XCTAssertTrue(chunks.allSatisfy { $0.url == nil })
        XCTAssertTrue(chunks.contains { $0.text.contains("100% on-device") }, "Should capture tabular contents")
        XCTAssertTrue(chunks.contains { $0.text.contains("Apple Neural Engine") }, "Should capture prose contents")
    }

    func testMakeTextFileChunksWithPlainText() {
        let plainText = """
        First paragraph describing the laboratory measurements. The temperature was held constant at 25 degrees Celsius.

        Second paragraph detailing the observed viscosity changes when adding non-ionic surfactants.
        """

        let chunks = ChatService.makeTextFileChunks(text: plainText, fileName: "lab_notes.txt")
        XCTAssertEqual(chunks.count, 2, "Should produce one chunk per distinct paragraph")
        XCTAssertEqual(chunks[0].source, "File: lab_notes.txt")
        XCTAssertTrue(chunks[0].text.contains("laboratory measurements"))
        XCTAssertTrue(chunks[1].text.contains("viscosity changes"))
    }

    func testDroppedTextFileStorePersistenceAndCleanup() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let originalURL = tempDir.appendingPathComponent("source_notes_\(UUID().uuidString).md")
        let sampleContent = "# Test Document\n\nTesting persistence in DroppedTextFileStore."
        try sampleContent.write(to: originalURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: originalURL) }

        // Test persistence
        guard let persistedURL = DroppedTextFileStore.persist(originalURL, preferredFileName: "persisted_notes.md") else {
            XCTFail("DroppedTextFileStore failed to persist file")
            return
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: persistedURL.path))
        XCTAssertEqual(persistedURL.lastPathComponent, "persisted_notes.md")
        XCTAssertTrue(persistedURL.path.contains("SilicIADroppedTextFiles"))

        // Test collision renaming
        let persistedURL2 = DroppedTextFileStore.persist(originalURL, preferredFileName: "persisted_notes.md")
        XCTAssertNotNil(persistedURL2)
        XCTAssertNotEqual(persistedURL.path, persistedURL2?.path)
        XCTAssertEqual(persistedURL2?.lastPathComponent, "persisted_notes (2).md")

        // Test clearAll
        let cleared = DroppedTextFileStore.clearAll()
        XCTAssertTrue(cleared)
        XCTAssertFalse(FileManager.default.fileExists(atPath: persistedURL.path))
        if let p2 = persistedURL2 {
            XCTAssertFalse(FileManager.default.fileExists(atPath: p2.path))
        }
    }

    @MainActor
    func testCollectChunksWithTextAndMarkdownFiles() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let mdURL = tempDir.appendingPathComponent("spec_\(UUID().uuidString).md")
        let txtURL = tempDir.appendingPathComponent("data_\(UUID().uuidString).txt")

        let mdContent = """
        ## System Specifications
        The processor includes 16 Neural Engine cores capable of executing quantized matrix multiplications.
        """
        let txtContent = """
        Calibration measurements recorded at 100 Hz frequency across 3 sensor channels.
        """

        try mdContent.write(to: mdURL, atomically: true, encoding: .utf8)
        try txtContent.write(to: txtURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: mdURL)
            try? FileManager.default.removeItem(at: txtURL)
        }

        let chatService = ChatService()
        let chunks = await chatService.collectChunks(
            contextInput: "",
            pdfURLs: [mdURL, txtURL],
            imageURLs: [],
            includeWebSearch: false,
            currentMessage: "What are the specs?",
            language: .english,
            maxDuckDuckGoResults: 0,
            maxWikipediaResults: 0,
            maxContextTokens: 2000,
            reportProgress: false
        )

        XCTAssertFalse(chunks.isEmpty, "collectChunks should ingest text and markdown files")
        XCTAssertTrue(chunks.contains { $0.source == "File: \(mdURL.lastPathComponent)" })
        XCTAssertTrue(chunks.contains { $0.source == "File: \(txtURL.lastPathComponent)" })
        XCTAssertTrue(chunks.contains { $0.text.contains("16 Neural Engine cores") })
        XCTAssertTrue(chunks.contains { $0.text.contains("Calibration measurements") })
    }
}
