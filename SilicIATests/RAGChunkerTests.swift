//
//  RAGChunkerTests.swift
//  SilicIATests
//

import XCTest
import PDFKit
#if os(macOS)
import AppKit
#endif
@testable import SilicIA

final class RAGChunkerTests: XCTestCase {

    private let chunker = RAGChunker()

    func testBasicChunkingBoundaries() async {
        // Empty & whitespace inputs return empty chunks
        let empty = await chunker.chunk(text: "", source: "test", maxChunkTokens: 100, overlapTokens: 10)
        XCTAssertTrue(empty.isEmpty)

        let whitespace = await chunker.chunk(text: "   \n\t  ", source: "test", maxChunkTokens: 100, overlapTokens: 10)
        XCTAssertTrue(whitespace.isEmpty)

        // Short input produces a single chunk
        let text = "Hello world"
        let short = await chunker.chunk(text: text, source: "test", maxChunkTokens: 200, overlapTokens: 10)
        XCTAssertEqual(short.count, 1)
        XCTAssertEqual(short.first?.text, text)
    }

    func testLongInputProducesBoundedChunks() async {
        let word = "word "
        let longText = String(repeating: word, count: 1000)
        let maxChunkTokens = 50
        let chunks = await chunker.chunk(text: longText, source: "test", maxChunkTokens: maxChunkTokens, overlapTokens: 0)
        XCTAssertGreaterThan(chunks.count, 1)

        let maxChunkChars = max(200, maxChunkTokens * 3)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.text.count, maxChunkChars)
        }
    }

    func testSentenceBoundaryHandling() async {
        let text = """
        Sentence one uses enough extra words to consume part of the chunk budget without filling it completely.
        Sentence two carries the chargedrepulsiveparameters keyword and should become the overlapping sentence.
        Sentence three adds enough trailing content to force another chunk after the first two sentences.
        """
        let chunks = await chunker.chunk(text: text, source: "test", maxChunkTokens: 18, overlapTokens: 20)
        guard chunks.count >= 2 else {
            return XCTFail("Expected at least 2 chunks for overlap test")
        }
        XCTAssertTrue(chunks[0].text.hasSuffix("."))
        XCTAssertTrue(chunks[1].text.hasPrefix("Sentence two carries the chargedrepulsiveparameters keyword"))

        // Avoid mid-word heads
        let filler = String(repeating: "aa ", count: 53)
        let midWordText = "\(filler)chargedrepulsiveparameters tailword.\nNext sentence adds enough trailing text."
        let midChunks = await chunker.chunk(text: midWordText, source: "test", maxChunkTokens: 70, overlapTokens: 10)
        XCTAssertGreaterThanOrEqual(midChunks.count, 2)
        XCTAssertFalse(midChunks.dropFirst().contains(where: {
            $0.text.hasPrefix("chargedrepulsiveparameters") || $0.text.hasPrefix("epulsiveparameters")
        }))
    }

    func testSourceAndMetadataPreserved() async {
        let text = "Some content here."
        let url = "https://example.com"
        let chunks = await chunker.chunk(text: text, source: "mysource", maxChunkTokens: 200, overlapTokens: 0, url: url, pdfPage: 3)
        XCTAssertEqual(chunks[0].source, "mysource")
        XCTAssertEqual(chunks[0].url, url)
        XCTAssertEqual(chunks[0].pdfPage, 3)
    }

    func testFixturePDFDoesNotRestartMidWordOrTableCell() async {
        let pdfURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("2025.PFAS.CMC.page.3.pdf")

        guard let document = PDFDocument(url: pdfURL),
              let page = document.page(at: 0),
              let cgImage = renderedTestCGImage(for: page),
              let analysis = ImageAnalysisService.analyzePDFPage(cgImage: cgImage),
              !analysis.recognizedText.isEmpty else {
            return XCTFail("Failed to analyze fixture PDF at \(pdfURL.path)")
        }

        let chunks = await chunker.chunk(
            text: analysis.recognizedText,
            source: "fixture",
            maxChunkTokens: 220,
            overlapTokens: 30,
            pdfPage: 1
        )

        XCTAssertGreaterThanOrEqual(chunks.count, 2)
        XCTAssertTrue(chunks.contains { $0.text.contains("|") })
        XCTAssertFalse(chunks.dropFirst().contains {
            $0.text.hasPrefix("epulsion parameters") || $0.text.hasPrefix("bAE/RT |")
        })
    }

    private func renderedTestCGImage(for page: PDFPage) -> CGImage? {
        let pageBounds = page.bounds(for: .mediaBox)
        let pageSize = pageBounds.size
        let nativeLonger = max(pageSize.width, pageSize.height)
        let targetLonger: CGFloat = 2500
        let maxLonger: CGFloat = 4096
        let scale = nativeLonger < targetLonger
            ? targetLonger / nativeLonger
            : (nativeLonger > maxLonger ? maxLonger / nativeLonger : 1)
        let targetSize = CGSize(
            width: max(1, pageSize.width * scale),
            height: max(1, pageSize.height * scale)
        )
        let image = page.thumbnail(of: targetSize, for: .mediaBox)
        #if os(macOS)
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        return image.cgImage
        #endif
    }
}
