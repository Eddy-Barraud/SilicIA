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

    func testDroppedFileStorePathTraversalMitigation() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let sampleFile = tempDir.appendingPathComponent("sample_\(UUID().uuidString).txt")
        try "safe content".write(to: sampleFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: sampleFile) }

        let store = DroppedFileStore(
            folderName: "SilicIASecurityTest",
            defaultExtension: "txt",
            allowedExtensions: ["txt"]
        )
        defer { store.clearAll() }

        // Attempt directory traversal via preferredFileName
        let persisted = store.persist(sampleFile, preferredFileName: "../../../etc/traversal.txt")
        XCTAssertNotNil(persisted, "Persist should succeed with sanitized filename")
        if let persisted {
            // Must reside strictly directly within storageDirectory
            XCTAssertEqual(
                persisted.standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent().path,
                store.storageDirectory.standardizedFileURL.resolvingSymlinksInPath().path,
                "Persisted file path \(persisted.path) must stay inside storageDirectory \(store.storageDirectory.path)"
            )
            XCTAssertFalse(persisted.path.contains(".."))
            XCTAssertFalse(persisted.lastPathComponent.contains("/"))
            XCTAssertFalse(persisted.lastPathComponent.contains("\\"))
        }

        // Attempt nested traversal
        let persistedNested = store.persist(sampleFile, preferredFileName: "....//....//evil.txt")
        XCTAssertNotNil(persistedNested)
        if let persistedNested {
            XCTAssertEqual(
                persistedNested.standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent().path,
                store.storageDirectory.standardizedFileURL.resolvingSymlinksInPath().path
            )
            XCTAssertFalse(persistedNested.lastPathComponent.contains(".."))
        }
    }

    func testWebScrapingServiceRejectsUnsafeSchemes() async {
        let scraper = WebScrapingService()

        // Local file scheme
        let fileURL = URL(fileURLWithPath: "/etc/passwd")
        do {
            _ = try await scraper.extractMarkdown(from: fileURL)
            XCTFail("extractMarkdown should throw for file:// URLs")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .unsupportedURL)
        } catch {
            XCTFail("Expected URLError.unsupportedURL, got \(error)")
        }

        // Wikipedia-shaped URL with unsafe scheme (must not bypass scheme check via parseWikipediaURL)
        if let wikiFileURL = URL(string: "file://en.wikipedia.org/wiki/Swift_(programming_language)") {
            do {
                _ = try await scraper.extractMarkdown(from: wikiFileURL)
                XCTFail("extractMarkdown should reject file:// even with a wikipedia host")
            } catch let error as URLError {
                XCTAssertEqual(error.code, .unsupportedURL)
            } catch {
                XCTFail("Expected URLError.unsupportedURL, got \(error)")
            }
        }

        // Custom scheme with wikipedia host
        if let customWikiURL = URL(string: "custom://en.wikipedia.org/wiki/Swift") {
            do {
                _ = try await scraper.extractMarkdown(from: customWikiURL)
                XCTFail("extractMarkdown should reject custom:// scheme")
            } catch let error as URLError {
                XCTAssertEqual(error.code, .unsupportedURL)
            } catch {
                XCTFail("Expected URLError.unsupportedURL, got \(error)")
            }
        }

        // Data scheme
        if let dataURL = URL(string: "data:text/html,<h1>Hello</h1>") {
            do {
                _ = try await scraper.extractReaderHTML(from: dataURL)
                XCTFail("extractReaderHTML should throw for data: URLs")
            } catch let error as URLError {
                XCTAssertEqual(error.code, .unsupportedURL)
            } catch {
                XCTFail("Expected URLError.unsupportedURL, got \(error)")
            }
        }
    }

    @MainActor
    func testCollectChunksPreservesInputOrder() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let doc1 = tempDir.appendingPathComponent("1_alpha_\(UUID().uuidString).txt")
        let doc2 = tempDir.appendingPathComponent("2_beta_\(UUID().uuidString).txt")
        let doc3 = tempDir.appendingPathComponent("3_gamma_\(UUID().uuidString).txt")

        try "Alpha document content.".write(to: doc1, atomically: true, encoding: .utf8)
        try "Beta document content.".write(to: doc2, atomically: true, encoding: .utf8)
        try "Gamma document content.".write(to: doc3, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: doc1)
            try? FileManager.default.removeItem(at: doc2)
            try? FileManager.default.removeItem(at: doc3)
        }

        let chatService = ChatService()
        let chunks = await chatService.collectChunks(
            contextInput: "",
            pdfURLs: [doc1, doc2, doc3],
            imageURLs: [],
            includeWebSearch: false,
            currentMessage: "test order",
            maxDuckDuckGoResults: 0,
            maxWikipediaResults: 0,
            maxContextTokens: 2000
        )

        let sources = chunks.map(\.source)
        XCTAssertEqual(sources, [
            "File: \(doc1.lastPathComponent)",
            "File: \(doc2.lastPathComponent)",
            "File: \(doc3.lastPathComponent)"
        ], "Documents must retain deterministic input order")
    }

    func testMarkdownBlockIdentityAndHashing() {
        let hr1 = MarkdownBlock.horizontalRule
        let hr2 = MarkdownBlock.horizontalRule
        XCTAssertEqual(hr1.id, hr2.id, "Horizontal rule ID must be deterministic")
        XCTAssertEqual(hr1, hr2, "MarkdownBlocks must be Equatable and Hashable")

        let set: Set<MarkdownBlock> = [hr1, hr2]
        XCTAssertEqual(set.count, 1)

        let p1 = MarkdownBlock.paragraph("Hello")
        let p2 = MarkdownBlock.paragraph("Hello")
        XCTAssertEqual(p1, p2)
        XCTAssertEqual(p1.id, p2.id)
    }
}
