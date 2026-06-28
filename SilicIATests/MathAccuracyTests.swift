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
    func testChunkerKeepsThousandsSeparatedNumberIntact() async {
        let chunker = RAGChunker()
        // Pre/post strings sized to force the ideal boundary near the
        // middle of "8,432,567".
        let prefix = String(repeating: "x", count: 200)
        let suffix = String(repeating: "y", count: 200)
        let text = "\(prefix) 8,432,567 \(suffix)"
        let chunks = await chunker.chunk(
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
    func testChunkerKeepsDecimalNumberIntact() async {
        let chunker = RAGChunker()
        let prefix = String(repeating: "a", count: 200)
        let suffix = String(repeating: "b", count: 200)
        let text = "\(prefix) 3.14159265 \(suffix)"
        let chunks = await chunker.chunk(text: text, source: "test", maxChunkTokens: 70, overlapTokens: 0)
        let intact = chunks.contains { $0.text.contains("3.14159265") }
        XCTAssertTrue(intact, "Decimal number was split. Chunks: \(chunks.map(\.text))")
    }

    /// When a sentence-ending period sits within the walkback range, the
    /// chunker should prefer it over a mid-sentence split.
    func testChunkerPrefersSentenceBoundary() async {
        let chunker = RAGChunker()
        // Build text where the byte-count ideal end lands mid-second-sentence,
        // but a sentence boundary exists ~10% earlier.
        let s1 = "The first sentence has some content here that goes on for a while to fill space."
        let s2 = "Now begins a fresh second sentence with completely different unrelated content."
        let text = s1 + " " + s2
        let chunks = await chunker.chunk(text: text, source: "test", maxChunkTokens: 30, overlapTokens: 0)
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
    func testChunkerPrefersParagraphBoundary() async {
        let chunker = RAGChunker()
        // p1 ~213 chars, p2 ~148 chars; \n\n at offset 213-214.
        let p1 = String(repeating: "Paragraph one fills with content for the test. ", count: 4)
            + "Paragraph one ends clean."
        let p2 = String(repeating: "Paragraph two has more content here. ", count: 4)
        let text = p1 + "\n\n" + p2
        // maxChunkChars = max(200, 80*3) = 240 — hardEnd lands ~26 chars
        // into p2; walkback = 240/5 = 48 chars, which reaches the \n\n.
        let chunks = await chunker.chunk(text: text, source: "test", maxChunkTokens: 80, overlapTokens: 0)
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

    /// HTML scraping leaves `\n   \n   \n` patterns when `<br>` translates
    /// to a space — each blank-looking line survived as its own newline and
    /// silently burned tokens. `normalizeWhitespace` must collapse them to
    /// a single paragraph break.
    func testNormalizeWhitespaceCollapsesBlankWhitespaceLines() {
        let input = "line A\n \n \n \nline B"
        let normalized = RAGChunker.normalizeWhitespace(input)
        XCTAssertEqual(normalized, "line A\n\nline B",
                       "Blank lines containing only whitespace should collapse to a single paragraph break, got: \(normalized.debugDescription)")
    }

    /// A single intentional blank line (paragraph break) must SURVIVE so
    /// the chunker keeps it as a high-quality boundary candidate.
    func testNormalizeWhitespacePreservesSingleParagraphBreak() {
        let input = "para 1\n\npara 2"
        let normalized = RAGChunker.normalizeWhitespace(input)
        XCTAssertEqual(normalized, "para 1\n\npara 2")
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

    /// Equation-number lookups should strongly prefer chunks that reference
    /// the same numbered equation, not just any chunk that mentions the word
    /// "equation" or contains unrelated numbers.
    func testEquationReferenceBoostPrefersMatchingEquationNumber() {
        let query = "explain equation 5"
        let matching = """
        The CMC-NaCl concentration curve follows the relationship of eq 5 for ionic surfactants.
        ln(CMC) = ln(CMC_0) - A ln(1 + BC_ion)
        """
        let nonMatching = """
        Table 1 summarizes the methodology and equation terms used throughout the paper.
        Equation 2 defines a different interaction parameter.
        """

        let options = RAGSelectionOptions.default
        let boostA = RAGContextService.equationRelevanceBoost(text: matching, query: query, options: options)
        let boostB = RAGContextService.equationRelevanceBoost(text: nonMatching, query: query, options: options)

        XCTAssertGreaterThan(boostA, boostB,
                             "Chunk referencing eq 5 should outrank one that only mentions other equations")
    }

    /// Figure-number and explicit page cues should steer ranking toward the
    /// chunk that actually contains the requested figure or lives on the
    /// requested page.
    func testFigureBoostPrefersMatchingFigureAndPage() {
        let query = "describe figure 5 on page 8"
        let matching = RAGChunk(
            source: "PDF: fixture page 8",
            text: "Figure 5. Chain length dependence of CMC values for several surfactant families.",
            url: nil,
            pdfPage: 8
        )
        let wrongFigure = RAGChunk(
            source: "PDF: fixture page 8",
            text: "Figure 4. Evolution of the SNS CMC with the salting effect of NaCl.",
            url: nil,
            pdfPage: 8
        )
        let wrongPage = RAGChunk(
            source: "PDF: fixture page 7",
            text: "Figure 5. Chain length dependence of CMC values for several surfactant families.",
            url: nil,
            pdfPage: 7
        )

        let options = RAGSelectionOptions.default
        let exact = RAGContextService.figureRelevanceBoost(chunk: matching, query: query, options: options)
        let figureOnly = RAGContextService.figureRelevanceBoost(chunk: wrongPage, query: query, options: options)
        let pageOnly = RAGContextService.figureRelevanceBoost(chunk: wrongFigure, query: query, options: options)

        XCTAssertGreaterThan(exact, figureOnly,
                             "Chunk matching both figure number and page should outrank figure-only match")
        XCTAssertGreaterThan(exact, pageOnly,
                             "Chunk matching both figure number and page should outrank page-only match")
    }

    // MARK: - Temporal intent detection

    /// "actualité ... cette semaine" / "today" / "este mes" must flag so
    /// the WebSearchTool knows to suppress Wikipedia for the call —
    /// Wikipedia would happily return historical / encyclopedic content
    /// (e.g. "Crise des subprimes") for a query about "this week" because
    /// of bag-of-words keyword overlap.
    func testTemporalIntentDetectedAcrossLanguages() {
        XCTAssertTrue(RAGContextService.hasTemporalIntent("what's the latest news"))
        XCTAssertTrue(RAGContextService.hasTemporalIntent("breaking story today"))
        XCTAssertTrue(RAGContextService.hasTemporalIntent("actualité des marchés financiers cette semaine"))
        XCTAssertTrue(RAGContextService.hasTemporalIntent("dernières tendances IA"))
        XCTAssertTrue(RAGContextService.hasTemporalIntent("noticias de hoy sobre el clima"))
        XCTAssertTrue(RAGContextService.hasTemporalIntent("últimas tendencias en moda"))
    }

    /// Pure definitional queries (Wikipedia's sweet spot) must NOT trip
    /// the temporal heuristic, otherwise we'd suppress Wikipedia on
    /// content it's actually well-suited for.
    func testDefinitionalQueriesAreNotTemporal() {
        XCTAssertFalse(RAGContextService.hasTemporalIntent("what is photosynthesis"))
        XCTAssertFalse(RAGContextService.hasTemporalIntent("qu'est-ce qu'un masque chirurgical"))
        XCTAssertFalse(RAGContextService.hasTemporalIntent("definición de macroeconomía"))
        XCTAssertFalse(RAGContextService.hasTemporalIntent("how does an internal combustion engine work"))
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

    // MARK: - Whitespace-aligned table detection (PDF path)

    /// A multi-column invoice row aligned with multi-space gaps should
    /// convert to a Markdown pipe table — exactly the regression motivating
    /// the fix: a PDF row like
    ///   `Amortisseurs    2    64,24    20%    77,08    154,17`
    /// must no longer collapse to a flat sequence of numbers the model
    /// can't map back to column headers.
    func testWhitespaceAlignedTableConvertsToMarkdown() {
        let pdf = """
        Description           Qté   Prix HT   TVA   Prix TTC   Total
        Amortisseurs          2     64,24     20%   77,08      154,17
        Triangles             1     120,00    20%   144,00     144,00
        """
        let converted = RAGChunker.convertWhitespaceAlignedTables(pdf)
        XCTAssertTrue(converted.contains("| Description | Qté | Prix HT | TVA | Prix TTC | Total |"),
                      "Header row missing pipes in: \n\(converted)")
        XCTAssertTrue(converted.contains("| Amortisseurs | 2 | 64,24 | 20% | 77,08 | 154,17 |"),
                      "Amortisseurs row missing or mis-aligned in: \n\(converted)")
        XCTAssertTrue(converted.contains("| --- |"),
                      "Markdown header-separator missing in: \n\(converted)")
    }

    /// Multi-word cell headers ("Prix HT", "Prix TTC") must survive — the
    /// splitter has to glue on single spaces and only break on 2+ spaces.
    func testTabularSplitGluesSingleSpacesIntoCells() {
        let pdf = """
        Article          Prix HT   TVA
        Amortisseurs     64,24     20%
        Triangles        120,00    20%
        """
        let converted = RAGChunker.convertWhitespaceAlignedTables(pdf)
        XCTAssertTrue(converted.contains("| Article | Prix HT | TVA |"),
                      "Multi-word header 'Prix HT' got split on its internal space: \n\(converted)")
    }

    /// Plain prose with occasional double-spaces must NOT get reformatted
    /// as a table — false positives would mangle ordinary reading text.
    func testProseIsNotConvertedToTable() {
        let prose = "This is a paragraph.  It has two sentences with a double space.\nA second line follows."
        let converted = RAGChunker.convertWhitespaceAlignedTables(prose)
        XCTAssertFalse(converted.contains("|"),
                       "Prose paragraph was wrongly converted to a Markdown table: \n\(converted)")
    }

    /// Single tabular row alone (no peer row) shouldn't trigger conversion —
    /// would produce a header without data.
    func testStandaloneTabularLineIsNotConverted() {
        let line = "Field 1    Field 2    Field 3"
        let converted = RAGChunker.convertWhitespaceAlignedTables(line)
        XCTAssertFalse(converted.contains("|"),
                       "Standalone wide-gap line was wrongly converted: \n\(converted)")
    }

    /// End-to-end through the chunker: after conversion + chunking, the
    /// Amortisseurs row remains a contiguous unit and the price "154,17"
    /// sits in the same chunk as the row's other cells.
    func testAmortisseursRowSurvivesChunkingIntact() async {
        let pdf = """
        Devis voiture 208

        Description           Qté   Prix HT   TVA   Prix TTC   Total
        Amortisseurs          2     64,24     20%   77,08      154,17
        Triangles             1     120,00    20%   144,00     144,00

        Total TTC: 298,17
        """
        let converted = RAGChunker.convertWhitespaceAlignedTables(pdf)
        let chunks = await RAGChunker().chunk(
            text: converted,
            source: "test",
            maxChunkTokens: 200,
            overlapTokens: 20
        )
        let priceChunk = chunks.first { $0.text.contains("Amortisseurs") }
        XCTAssertNotNil(priceChunk, "No chunk contains the Amortisseurs row")
        XCTAssertTrue(priceChunk?.text.contains("154,17") == true,
                      "Amortisseurs total price 154,17 missing from its chunk: \(priceChunk?.text ?? "nil")")
        XCTAssertTrue(priceChunk?.text.contains("| Description | Qté | Prix HT | TVA | Prix TTC | Total |") == true,
                      "Header row missing from the same chunk as Amortisseurs row — model loses column context: \(priceChunk?.text ?? "nil")")
    }

    // MARK: - Table header propagation across chunks

    /// A chunk containing only data rows should get the most-recent table
    /// header prepended, so the model can still tell which column is which.
    func testHeaderPropagatesToChunkWithOnlyDataRows() {
        let withHeader = RAGChunk(
            source: "test", text: """
            | Code | Description | Qté | P.U. HT | Montant HT | TVA |
            | --- | --- | --- | --- | --- | --- |
            | AR1 | Triangles | 2,00 | 63,33 | 126,65 | 20,00 |
            """,
            url: nil, pdfPage: 1
        )
        let onlyRows = RAGChunk(
            source: "test", text: """
            | AR2 | Amortisseurs | 2,00 | 77,08 | 154,17 | 20,00 |
            | AR3 | Coupelles | 2,00 | 33,33 | 66,65 | 20,00 |
            """,
            url: nil, pdfPage: 1
        )
        let result = RAGChunker.preserveTableHeadersAcrossChunks([withHeader, onlyRows])
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result[1].text.hasPrefix("| Code | Description | Qté | P.U. HT | Montant HT | TVA |"),
                      "Header was not prepended to the chunk with only data rows: \n\(result[1].text)")
        XCTAssertTrue(result[1].text.contains("| AR2 | Amortisseurs | 2,00 | 77,08 | 154,17 | 20,00 |"),
                      "Amortisseurs row missing from propagated chunk: \n\(result[1].text)")
    }

    /// An orphan separator at the top of a chunk (overlap artifact from a
    /// different table) must be dropped, not mistaken for a header.
    func testOrphanLeadingSeparatorIsDropped() {
        let withHeader = RAGChunk(
            source: "test", text: """
            | A | B | C |
            | --- | --- | --- |
            | 1 | 2 | 3 |
            """,
            url: nil, pdfPage: 1
        )
        // The overlap dragged in this 3-col separator, but the rest of the
        // chunk is from a different 6-col items table that the previous
        // chunk had the header for.
        let orphan = RAGChunk(
            source: "test", text: """
            | --- | --- | --- |
            | X | Y | Z | 1 | 2 | 3 |
            """,
            url: nil, pdfPage: 1
        )
        let result = RAGChunker.preserveTableHeadersAcrossChunks([withHeader, orphan])
        XCTAssertFalse(result[1].text.hasPrefix("| --- |"),
                       "Orphan leading separator wasn't stripped: \n\(result[1].text)")
        XCTAssertTrue(result[1].text.contains("| X | Y | Z | 1 | 2 | 3 |"))
    }

    /// Regression: when the same page contains both a small 5-column ID
    /// table AND the 6-column items table, the propagation must pick the
    /// items header for chunks of 6-column data rows — NOT the first-seen
    /// header. This is the bug that made the model answer with the wrong
    /// column (6,65 € for "prix coupelle") even though chunks looked good.
    func testHeaderPropagationPicksMatchingColumnCount() {
        let withTwoHeaders = RAGChunk(
            source: "test", text: """
            Header info before any tables.

            | Numéro | Date | Code | Mode | TVA |
            | --- | --- | --- | --- | --- |
            | DE001 | 21/01 | CL01 | 30j | FR25 |

            Référence intermédiaire entre deux tables.

            | Code | Description | Qté | P.U. HT | Montant HT | TVA |
            | --- | --- | --- | --- | --- | --- |
            | AR1 | Triangles | 2,00 | 63,33 | 126,65 | 20,00 |
            """,
            url: nil, pdfPage: 1
        )
        // Next chunk = nothing but 6-column items rows.
        let itemsOnly = RAGChunk(
            source: "test", text: """
            | AR2 | Amortisseurs | 2,00 | 77,08 | 154,17 | 20,00 |
            | AR3 | Coupelles | 2,00 | 33,33 | 66,65 | 20,00 |
            """,
            url: nil, pdfPage: 1
        )
        let result = RAGChunker.preserveTableHeadersAcrossChunks([withTwoHeaders, itemsOnly])
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result[1].text.hasPrefix("| Code | Description | Qté | P.U. HT | Montant HT | TVA |"),
                      "Wrong header propagated — expected the 6-col items header, got: \n\(result[1].text)")
        XCTAssertFalse(result[1].text.contains("| Numéro | Date | Code | Mode | TVA |"),
                       "5-col ID header leaked into a 6-col data-row chunk: \n\(result[1].text)")
    }

    /// A chunk with neither header nor data rows is left alone — no
    /// spurious header inserted into prose.
    func testProseChunkUnchanged() {
        let withHeader = RAGChunk(
            source: "test", text: """
            | A | B |
            | --- | --- |
            | 1 | 2 |
            """,
            url: nil, pdfPage: 1
        )
        let prose = RAGChunk(
            source: "test", text: "Just a paragraph of text with no table content.",
            url: nil, pdfPage: 1
        )
        let result = RAGChunker.preserveTableHeadersAcrossChunks([withHeader, prose])
        XCTAssertEqual(result[1].text, "Just a paragraph of text with no table content.",
                       "Prose chunk was wrongly modified: \(result[1].text)")
    }

    // MARK: - Scientific table: OCR-split equation cells

    /// When Vision OCR splits a table's equation cell into multiple
    /// observations (e.g. "aww =" and "kBT/(2a0)(k-1Nm - 1)" become
    /// separate fragments joined by 4 spaces), the reconstructed row has
    /// more cells than the canonical 3-column table. The converter must
    /// use the modal column count (3) rather than the max (4+) and merge
    /// the excess equation fragments back into the last cell, so the
    /// resulting Markdown table has the correct column shape.
    func testScientificTableEquationCellsAreNotSplit() {
        // Simulates Vision OCR output for a scientific methods table where
        // the equation column is partially split into separate observations.
        // "aww =" and "kBT/(2a0)(k^-1Nm - 1)" are two fragments from the
        // same equation cell, joined by 4 spaces by reconstructLayout.
        let visionOCROutput = """
        repulsive parameter    origin    equation
        water/water    water compressibility    aww =    kBT/(2a0)(k^-1Nm - 1)
        like/like    same as water    aii = aww
        tail/water    fitted with CMC using osmotic pressure    -
        """
        let converted = RAGChunker.convertWhitespaceAlignedTables(visionOCROutput)
        // The table must have exactly 3 columns — equation fragments merged.
        let separatorLine = converted.components(separatedBy: "\n").first { $0.hasPrefix("|") && $0.contains("---") }
        // Count columns from the separator row: "| --- | --- | --- |" → 4 pipes = 3 columns
        let pipeCount = separatorLine.map { $0.filter { $0 == "|" }.count } ?? 0
        XCTAssertEqual(pipeCount, 4, // 4 pipes = 3 columns
                       "Table should have 3 columns (4 pipes); separator: \(separatorLine ?? "nil")")
        // The header row must be present.
        XCTAssertTrue(converted.contains("| repulsive parameter | origin | equation |"),
                      "Header row missing or mis-formatted: \n\(converted)")
        // The water/water row equation fragments must be merged into one cell.
        XCTAssertTrue(converted.contains("| water/water | water compressibility |"),
                      "water/water row missing: \n\(converted)")
        XCTAssertFalse(converted.contains("| aww = |"),
                       "Equation was split into a separate column: \n\(converted)")
        // The merged equation cell must contain both fragments.
        let waterRow = converted.components(separatedBy: "\n").first { $0.contains("water/water") }
        XCTAssertTrue(waterRow?.contains("aww =    kBT/(2a0)(k^-1Nm - 1)") == true ||
                      waterRow?.contains("aww = kBT/(2a0)(k^-1Nm - 1)") == true,
                      "Equation fragments not merged in row: \(waterRow ?? "nil")")
    }

    /// A table where all rows have a consistent column count must still
    /// produce the correct Markdown — modal == max in this case.
    func testScientificTableWithConsistentColumnCount() {
        let visionOCROutput = """
        repulsive parameter    origin    equation
        water/water    water compressibility    aww = kBT/(2a0)(k^-1 Nm - 1)
        like/like    same as water    aii = aww
        tail/water    fitted with CMC    -
        """
        let converted = RAGChunker.convertWhitespaceAlignedTables(visionOCROutput)
        XCTAssertTrue(converted.contains("| repulsive parameter | origin | equation |"),
                      "Header missing: \n\(converted)")
        XCTAssertTrue(converted.contains("| --- | --- | --- |") ||
                      converted.contains("| --- |") ,
                      "Separator row missing: \n\(converted)")
        XCTAssertTrue(converted.contains("| water/water | water compressibility | aww = kBT/(2a0)(k^-1 Nm - 1) |"),
                      "water/water row malformed: \n\(converted)")
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
