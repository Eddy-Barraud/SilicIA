//
//  MathAccuracyTests.swift
//  SilicIATests
//
//  Regression suite for the deterministic pieces of the math-accuracy
//  pipeline:
//
//  - RAGChunker preserves multi-digit numbers across chunk boundaries.
//  - RAGChunker prefers sentence / paragraph boundaries when within range.
//  - RAGContextService's numeric-aware scoring boosts chunks that share
//    concrete numeric tokens with the query.
//  - WebScrapingService converts `<table>` blocks to Markdown pipe tables
//    instead of flattening them to space-separated rubble.
//
//  These tests are intentionally CPU-only and deterministic so they can
//  run on every PR via GitHub Actions — they do not require the on-device
//  Foundation Model, network access, or any Apple-platform-specific
//  feature beyond Foundation + XCTest.
//

import XCTest
@testable import SilicIA

final class MathAccuracyTests: XCTestCase {

    // MARK: - Chunker: number-integrity

    /// A multi-digit number with thousands separators must not be split
    /// across two chunks — the model silently corrupts numbers when half
    /// of the digits land in a different chunk.
    func testChunkerKeepsThousandsSeparatedNumberIntact() {
        let chunker = RAGChunker()
        // Pre/post strings sized to force the ideal boundary near the
        // middle of "8,432,567".
        let prefix = String(repeating: "x", count: 200)
        let suffix = String(repeating: "y", count: 200)
        let text = "\(prefix) 8,432,567 \(suffix)"
        let chunks = chunker.chunk(
            text: text,
            source: "test",
            maxChunkTokens: 70,           // → ~210 chars per chunk
            overlapTokens: 0
        )
        // Verify the literal "8,432,567" appears intact in at least one chunk.
        let numberAppears = chunks.contains { $0.text.contains("8,432,567") }
        XCTAssertTrue(numberAppears,
                      "Multi-digit number was bisected across chunks. Chunks: \(chunks.map(\.text))")
        // And that no chunk contains a fragmented half like "8,432," at its tail
        // followed by a non-digit, which would indicate a mid-number split.
        for chunk in chunks {
            let trimmed = chunk.text.trimmingCharacters(in: .whitespaces)
            XCTAssertFalse(
                trimmed.hasSuffix(",") || trimmed.hasSuffix("."),
                "Chunk ended with a number separator, suggesting a mid-number split: \(trimmed)"
            )
        }
    }

    /// Decimal numbers ("105.4", "3.14159") must not be split at the
    /// decimal point.
    func testChunkerKeepsDecimalNumberIntact() {
        let chunker = RAGChunker()
        let prefix = String(repeating: "a", count: 200)
        let suffix = String(repeating: "b", count: 200)
        let text = "\(prefix) 3.14159265 \(suffix)"
        let chunks = chunker.chunk(text: text, source: "test", maxChunkTokens: 70, overlapTokens: 0)
        let intact = chunks.contains { $0.text.contains("3.14159265") }
        XCTAssertTrue(intact, "Decimal number was split. Chunks: \(chunks.map(\.text))")
    }

    /// When a sentence-ending period sits within the walkback range, the
    /// chunker should prefer it over a mid-sentence split.
    func testChunkerPrefersSentenceBoundary() {
        let chunker = RAGChunker()
        // Build text where the byte-count ideal end lands mid-second-sentence,
        // but a sentence boundary exists ~10% earlier.
        let s1 = "The first sentence has some content here that goes on for a while to fill space."
        let s2 = "Now begins a fresh second sentence with completely different unrelated content."
        let text = s1 + " " + s2
        let chunks = chunker.chunk(text: text, source: "test", maxChunkTokens: 30, overlapTokens: 0)
        // The first chunk should end at the s1/s2 boundary (period + space).
        guard let first = chunks.first else {
            XCTFail("No chunks produced")
            return
        }
        XCTAssertTrue(first.text.hasSuffix("."),
                      "First chunk should end on a sentence boundary; got: '\(first.text)'")
    }

    /// Paragraph breaks (`\n\n`) should beat sentence breaks when both are
    /// in the walkback window. Fixture sized so the byte-count ideal end
    /// lands inside paragraph 2 but the paragraph break sits inside the
    /// 20% walkback window.
    func testChunkerPrefersParagraphBoundary() {
        let chunker = RAGChunker()
        // p1 ~213 chars, p2 ~148 chars; \n\n at offset 213-214.
        let p1 = String(repeating: "Paragraph one fills with content for the test. ", count: 4)
            + "Paragraph one ends clean."
        let p2 = String(repeating: "Paragraph two has more content here. ", count: 4)
        let text = p1 + "\n\n" + p2
        // maxChunkChars = max(200, 80*3) = 240 — hardEnd lands ~26 chars
        // into p2; walkback = 240/5 = 48 chars, which reaches the \n\n.
        let chunks = chunker.chunk(text: text, source: "test", maxChunkTokens: 80, overlapTokens: 0)
        guard let first = chunks.first else {
            XCTFail("No chunks produced")
            return
        }
        XCTAssertTrue(first.text.hasSuffix("clean."),
                      "First chunk should end at the paragraph break; got: '\(first.text)'")
    }

    // MARK: - Whitespace normalization

    /// Single newlines must survive `normalizeWhitespace` so the chunker
    /// can use them as table-row boundaries.
    func testNormalizeWhitespacePreservesNewlines() {
        let input = "row 1\nrow 2\n\nrow 3"
        let normalized = RAGChunker.normalizeWhitespace(input)
        XCTAssertTrue(normalized.contains("row 1\nrow 2"),
                      "Single newline between rows should survive normalization")
        XCTAssertTrue(normalized.contains("row 2\n\nrow 3"),
                      "Double newline between paragraphs should survive normalization")
    }

    /// Runs of horizontal whitespace are still collapsed to a single space.
    func testNormalizeWhitespaceCollapsesHorizontalRuns() {
        let input = "lots\t  of    \t spaces"
        let normalized = RAGChunker.normalizeWhitespace(input)
        XCTAssertEqual(normalized, "lots of spaces")
    }

    // MARK: - Numeric relevance scoring

    /// A query mentioning a specific number prefers a chunk that contains
    /// that exact number over an otherwise-equivalent chunk that doesn't.
    func testNumericTokenMatchBoostsRelevantChunk() {
        let query = "What is the population in 2020 according to the census?"
        let withNumber = "The 2020 census recorded a population total of 67432198 residents."
        let withoutNumber = "The census reported population data covering many years and demographics."

        let options = RAGSelectionOptions.default
        let boostA = RAGContextService.numericRelevanceBoost(text: withNumber, query: query, options: options)
        let boostB = RAGContextService.numericRelevanceBoost(text: withoutNumber, query: query, options: options)

        XCTAssertGreaterThan(boostA, boostB,
                             "Chunk containing the queried year should score higher than one without it")
    }

    /// A query with numerical intent but no specific number ("how many",
    /// "average", etc.) still lifts chunks containing any number.
    func testNumericIntentBoostsAnyNumericChunk() {
        let query = "How many residents live there on average?"
        let withNumber = "Studies report an average of 4321 residents in the area."
        let withoutNumber = "Studies generally report that many residents live in the area."

        let options = RAGSelectionOptions.default
        let boostA = RAGContextService.numericRelevanceBoost(text: withNumber, query: query, options: options)
        let boostB = RAGContextService.numericRelevanceBoost(text: withoutNumber, query: query, options: options)

        XCTAssertGreaterThan(boostA, boostB,
                             "Query with numerical intent should prefer the chunk that contains a number")
        XCTAssertEqual(boostB, 0, accuracy: 0.0001,
                       "Non-numeric chunk should get no numeric boost")
    }

    /// Queries with no numerical content and no numeric intent should not
    /// receive any numeric boost — keeps the score signal honest on
    /// "what is" / "define X" / conceptual lookups.
    func testNoBoostForNonNumericQuery() {
        let query = "What is photosynthesis"
        let text = "Photosynthesis is a process by which plants convert light into energy."
        let options = RAGSelectionOptions.default
        let boost = RAGContextService.numericRelevanceBoost(text: text, query: query, options: options)
        XCTAssertEqual(boost, 0, accuracy: 0.0001)
    }

    /// `hasNumericalIntent` should fire on EN/FR/ES quantity cues so the
    /// boost works across the supported languages.
    func testNumericalIntentDetectionMultilingual() {
        XCTAssertTrue(RAGContextService.hasNumericalIntent("how many people live there"))
        XCTAssertTrue(RAGContextService.hasNumericalIntent("combien d'habitants"))
        XCTAssertTrue(RAGContextService.hasNumericalIntent("cuántos habitantes hay"))
        XCTAssertTrue(RAGContextService.hasNumericalIntent("price is at least 50"))
        XCTAssertFalse(RAGContextService.hasNumericalIntent("what is the definition of an apple"))
    }

    // MARK: - WebScraping: HTML tables → Markdown

    /// A standalone `<table>` block converts to a Markdown pipe table with
    /// a header separator row, preserving cell text verbatim.
    func testHTMLTableConvertsToMarkdownPipeTable() {
        let html = """
        <table>
          <tr><th>Year</th><th>Population</th></tr>
          <tr><td>2010</td><td>1,234,567</td></tr>
          <tr><td>2020</td><td>1,432,890</td></tr>
        </table>
        """
        let markdown = WebScrapingService.convertTableToMarkdown(
            extractTableInner(html)
        )
        XCTAssertTrue(markdown.contains("| Year | Population |"),
                      "Header row missing or malformed in: \n\(markdown)")
        XCTAssertTrue(markdown.contains("| --- | --- |"),
                      "Header separator row missing in: \n\(markdown)")
        XCTAssertTrue(markdown.contains("| 2010 | 1,234,567 |"),
                      "First data row missing or malformed in: \n\(markdown)")
        XCTAssertTrue(markdown.contains("| 2020 | 1,432,890 |"),
                      "Second data row missing or malformed in: \n\(markdown)")
    }

    /// Numeric values must survive the table → markdown conversion with
    /// their separators (commas, decimals) intact.
    func testTableNumbersSurviveExtraction() {
        let html = """
        <html><body>
        <p>Stats follow.</p>
        <table>
          <tr><th>Metric</th><th>Value</th></tr>
          <tr><td>Population</td><td>8,432,567</td></tr>
          <tr><td>Area km²</td><td>105.4</td></tr>
        </table>
        </body></html>
        """
        let replaced = WebScrapingService.extractAndReplaceTables(html)
        XCTAssertTrue(replaced.contains("8,432,567"),
                      "Thousands-separated number lost during table extraction: \n\(replaced)")
        XCTAssertTrue(replaced.contains("105.4"),
                      "Decimal number lost during table extraction: \n\(replaced)")
        XCTAssertTrue(replaced.contains("|"),
                      "Markdown pipe markers missing from extracted table: \n\(replaced)")
    }

    /// HTML without a `<table>` block is passed through unchanged so we
    /// don't pay any cost on pages that have no tables.
    func testTableExtractionPassthroughWhenNoTables() {
        let html = "<p>Just a paragraph. No tables here.</p>"
        let result = WebScrapingService.extractAndReplaceTables(html)
        XCTAssertEqual(result, html)
    }

    // MARK: - Test helpers

    /// Extracts the inner HTML of the first `<table>...</table>` block,
    /// so `convertTableToMarkdown` (which expects the *inner* HTML, not
    /// the wrapper tag) can be exercised directly from a test fixture.
    private func extractTableInner(_ html: String) -> String {
        guard let regex = WebScrapingService.tableBlockRegex else { return "" }
        let nsRange = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: nsRange),
              let inner = Range(match.range(at: 1), in: html) else {
            return ""
        }
        return String(html[inner])
    }
}
