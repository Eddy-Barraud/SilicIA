//
//  RAGChunkerTests.swift
//  SilicIATests
//

import XCTest
@testable import SilicIA

final class RAGChunkerTests: XCTestCase {

    private let chunker = RAGChunker()

    func testEmptyInputReturnsEmpty() {
        let chunks = chunker.chunk(text: "", source: "test", maxChunkTokens: 100, overlapTokens: 10)
        XCTAssertTrue(chunks.isEmpty)
    }

    func testWhitespaceOnlyReturnsEmpty() {
        let chunks = chunker.chunk(text: "   \n\t  ", source: "test", maxChunkTokens: 100, overlapTokens: 10)
        XCTAssertTrue(chunks.isEmpty)
    }

    func testVeryLongInputProducesMultipleChunks() {
        let word = "word "
        let longText = String(repeating: word, count: 1000)
        let maxChunkTokens = 50
        let chunks = chunker.chunk(text: longText, source: "test", maxChunkTokens: maxChunkTokens, overlapTokens: 0)
        XCTAssertGreaterThan(chunks.count, 1)
    }

    func testEachChunkRespectMaxSize() {
        let longText = String(repeating: "x", count: 3000)
        let maxChunkTokens = 100
        let chunks = chunker.chunk(text: longText, source: "test", maxChunkTokens: maxChunkTokens, overlapTokens: 0)
        let maxChunkChars = max(200, maxChunkTokens * 3)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.text.count, maxChunkChars,
                "Chunk size \(chunk.text.count) exceeds max \(maxChunkChars)")
        }
    }

    func testOverlapHonored() {
        let text = String(repeating: "a", count: 600)
        let maxChunkTokens = 50
        let overlapTokens = 10
        let overlapChars = overlapTokens * 3
        let chunks = chunker.chunk(text: text, source: "test", maxChunkTokens: maxChunkTokens, overlapTokens: overlapTokens)
        guard chunks.count >= 2 else {
            XCTFail("Expected at least 2 chunks for overlap test")
            return
        }
        for i in 0..<(chunks.count - 1) {
            let tail = String(chunks[i].text.suffix(overlapChars))
            let head = String(chunks[i + 1].text.prefix(overlapChars))
            XCTAssertEqual(tail, head, "Overlap mismatch at chunk \(i)")
        }
    }

    func testShortInputProducesSingleChunk() {
        let text = "Hello world"
        let chunks = chunker.chunk(text: text, source: "test", maxChunkTokens: 200, overlapTokens: 10)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].text, text)
    }

    func testSourceAndMetadataPreserved() {
        let text = "Some content here."
        let url = "https://example.com"
        let chunks = chunker.chunk(text: text, source: "mysource", maxChunkTokens: 200, overlapTokens: 0, url: url, pdfPage: 3)
        XCTAssertEqual(chunks[0].source, "mysource")
        XCTAssertEqual(chunks[0].url, url)
        XCTAssertEqual(chunks[0].pdfPage, 3)
    }
}
