//
//  RAGChunkerTests.swift
//  SilicIATests
//
//  Tests for RAG paragraph chunking, number integrity, markdown stripping,
//  table preservation/conversions, two-stage ranking, relevance boosts, and intent detection.
//

import XCTest
@testable import SilicIA

final class RAGChunkerTests: XCTestCase {

    func testParagraphChunkingNumberIntegrityAndFormatting() {
        // Empty & whitespace inputs
        XCTAssertTrue(RAGChunker.chunkParagraphs(text: "", source: "test").isEmpty)
        XCTAssertTrue(RAGChunker.chunkParagraphs(text: "   \n\t  ", source: "test").isEmpty)

        // Single and multi-paragraph
        let p1 = "First paragraph discussing modern natural language processing."
        let p2 = "Second paragraph elaborating on vector embeddings."
        let chunks = RAGChunker.chunkParagraphs(text: "\(p1)\n\n\(p2)", source: "doc", url: "https://example.com", pdfPage: 3)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].text, p1)
        XCTAssertEqual(chunks[1].text, p2)
        XCTAssertEqual(chunks[0].source, "doc")
        XCTAssertEqual(chunks[0].url, "https://example.com")
        XCTAssertEqual(chunks[0].pdfPage, 3)

        // Multi-digit numbers and decimals
        let numText = "The company reported 8,432,567 units sold. Constant is approximately 3.14159265."
        let numChunks = RAGChunker.chunkParagraphs(text: numText, source: "test")
        XCTAssertTrue(numChunks.contains { $0.text.contains("8,432,567") })
        XCTAssertTrue(numChunks.contains { $0.text.contains("3.14159265") })

        // Whitespace normalization
        let raw = "line A\n \n \nline B\n\nline C"
        let normalized = RAGChunker.normalizeWhitespace(raw)
        XCTAssertEqual(normalized, "line A\n\nline B\n\nline C")
        XCTAssertEqual(RAGChunker.normalizeWhitespace("lots\t  of    \t spaces"), "lots of spaces")

        // Markdown stripping
        let rawMarkdown = """
        # Main Title
        ## Subtitle
        En [mathématiques](https://fr.wikipedia.org/wiki/Math) la **distance**.
        ![Diagram](https://upload.wikimedia.org/diagram.png)
        Formule CO<sub>2</sub> et Mg<sup>2+</sup>.
        """
        let cleaned = RAGChunker.removeMarkdownFormatting(from: rawMarkdown)
        XCTAssertFalse(cleaned.contains("# Main Title"))
        XCTAssertFalse(cleaned.contains("## Subtitle"))
        XCTAssertFalse(cleaned.contains("https://"))
        XCTAssertFalse(cleaned.contains("<sub>"))
        XCTAssertTrue(cleaned.contains("En mathématiques la **distance**."))
        XCTAssertTrue(cleaned.contains("Diagram"))
        XCTAssertTrue(cleaned.contains("CO2"))

        // Performance check
        var largeText = ""
        for i in 1...200 {
            largeText += "Paragraphe \(i): [Lien \(i)](https://fr.wikipedia.org/wiki/Article_\(i)) avec ![Img](https://img/\(i).png).\n\n"
        }
        let start = Date()
        let cleanedLarge = RAGChunker.removeMarkdownFormatting(from: largeText)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 0.5)
        XCTAssertFalse(cleanedLarge.contains("https://"))
    }

    func testTablePreservationConversionAndNavboxFiltering() {
        // Markdown table preserved as single chunk
        let markdown = """
        Introduction:

        | Président | Début | Fin |
        | --- | --- | --- |
        | Vincent Auriol | 1947 | 1954 |
        | René Coty | 1954 | 1959 |

        Conclusion.
        """
        let chunks = RAGChunker.chunkParagraphs(text: markdown, source: "IVe", url: "https://wikipedia.org")
        XCTAssertEqual(chunks.count, 3)
        let tableChunk = chunks[1]
        XCTAssertTrue(tableChunk.text.contains("| Vincent Auriol | 1947 | 1954 |"))
        XCTAssertTrue(tableChunk.text.contains("| René Coty | 1954 | 1959 |"))

        // Navbox filtering
        let navboxMD = """
        | Part of a series | Politics |
        | --- | --- |
        | * v * t * e | |

        Real article text about democracy.
        """
        let navboxChunks = RAGChunker.chunkParagraphs(text: navboxMD, source: "Gov", url: nil)
        XCTAssertFalse(navboxChunks.contains { $0.text.contains("* v * t * e") })
        XCTAssertTrue(navboxChunks.contains { $0.text.contains("Real article text") })

        // Consecutive short chunk merging
        let c1 = RAGChunk(source: "S", text: "The double factorial is defined as:", url: nil, pdfPage: nil)
        let c2 = RAGChunk(source: "S", text: "n!! = n * (n - 2) * ... * 2", url: nil, pdfPage: nil)
        let merged = RAGChunker.mergeShortConsecutiveChunks([c1, c2])
        XCTAssertEqual(merged.count, 1)
        XCTAssertTrue(merged[0].text.contains("defined as:"))

        // HTML table conversion
        let html = "<table><tr><th>Year</th><th>Value</th></tr><tr><td>2020</td><td>105.4</td></tr></table>"
        let convertedHTML = WebScrapingService.extractAndReplaceTables(html)
        XCTAssertTrue(convertedHTML.contains("| Year | Value |"))
        XCTAssertTrue(convertedHTML.contains("105.4"))

        // Whitespace-aligned invoice table
        let invoice = """
        Description           Qté   Prix HT   TVA   Prix TTC   Total
        Amortisseurs          2     64,24     20%   77,08      154,17
        Triangles             1     120,00    20%   144,00     144,00
        """
        let convertedInvoice = RAGChunker.convertWhitespaceAlignedTables(invoice)
        XCTAssertTrue(convertedInvoice.contains("| Description | Qté | Prix HT | TVA | Prix TTC | Total |"))
        XCTAssertTrue(convertedInvoice.contains("| Amortisseurs | 2 | 64,24 | 20% | 77,08 | 154,17 |"))

        let invoiceChunks = RAGChunker.chunkParagraphs(text: convertedInvoice, source: "test")
        let priceChunk = invoiceChunks.first { $0.text.contains("Amortisseurs") }
        XCTAssertNotNil(priceChunk)
        XCTAssertTrue(priceChunk?.text.contains("154,17") == true)

        let prose = "This is a paragraph.  It has two sentences with spaces."
        XCTAssertFalse(RAGChunker.convertWhitespaceAlignedTables(prose).contains("|"))
    }

    func testTwoStageRankingRelevanceBoostsAndIntent() async {
        let service = RAGContextService()
        let relevantChunk = RAGChunk(
            source: "Nobel Winner",
            text: "The Nobel Prize in Chemistry 2017 was awarded for developing cryo-electron microscopy.",
            url: "https://nobel.org",
            pdfPage: nil
        )
        let fillerChunk = RAGChunk(
            source: "Cooking",
            text: "Gardening tips for spring roses and baking chocolate cakes.",
            url: "https://cooking.org",
            pdfPage: nil
        )

        let result = await service.selectContext(
            chunks: [fillerChunk, relevantChunk],
            query: "Who won the Nobel Prize in Chemistry in 2017?",
            historyTokens: 0,
            maxOutputTokens: 500
        )

        XCTAssertFalse(result.rankedChunks.isEmpty)
        XCTAssertEqual(result.rankedChunks.first?.chunk.source, "Nobel Winner")
        XCTAssertEqual(result.selectedChunks.last?.chunk.source, "Nobel Winner", "Most relevant chunk placed at end for attention focus")

        // Relevance boosts
        let options = RAGSelectionOptions.default
        let numQuery = "What is the population in 2020?"
        let withNum = "The 2020 census recorded a population total of 67432198 residents."
        let withoutNum = "The census reported population data covering many years."
        XCTAssertGreaterThan(
            RAGContextService.numericRelevanceBoost(text: withNum, query: numQuery, options: options),
            RAGContextService.numericRelevanceBoost(text: withoutNum, query: numQuery, options: options)
        )

        let eqMatching = "eq 5 for ionic surfactants: ln(CMC) = ln(CMC_0) - A ln(1 + BC_ion)"
        let eqNonMatching = "Table 1 methodology. Equation 2 defines a different parameter."
        XCTAssertGreaterThan(
            RAGContextService.equationRelevanceBoost(text: eqMatching, query: "explain equation 5", options: options),
            RAGContextService.equationRelevanceBoost(text: eqNonMatching, query: "explain equation 5", options: options)
        )

        let figQuery = "describe figure 5 on page 8"
        let exactChunk = RAGChunk(source: "PDF p8", text: "Figure 5. Chain length dependence.", url: nil, pdfPage: 8)
        let wrongPageChunk = RAGChunk(source: "PDF p7", text: "Figure 5. Chain length dependence.", url: nil, pdfPage: 7)
        XCTAssertGreaterThan(
            RAGContextService.figureRelevanceBoost(chunk: exactChunk, query: figQuery, options: options),
            RAGContextService.figureRelevanceBoost(chunk: wrongPageChunk, query: figQuery, options: options)
        )

        // Intent detection
        XCTAssertTrue(RAGContextService.hasTemporalIntent("what's the latest news"))
        XCTAssertFalse(RAGContextService.hasTemporalIntent("what is photosynthesis"))
        XCTAssertTrue(RAGContextService.hasNumericalIntent("how many people live there"))
        XCTAssertFalse(RAGContextService.hasNumericalIntent("what is an apple"))

        // Query requires tools heuristics & morphological similarity
        XCTAssertFalse(AIService.queryRequiresTools("est-ce que la morille est un champignon toxique"))
        XCTAssertFalse(AIService.queryRequiresTools("quelle est la demi-vie du carbone 14 ?"))
        XCTAssertTrue(AIService.queryRequiresTools("15 * 24"))
        XCTAssertTrue(AIService.queryRequiresTools("combien font 12 + 14 ?"))
        XCTAssertTrue(AIService.queryRequiresTools("quelle est la date d'aujourd'hui ?"))
        XCTAssertTrue(SearchSourcesTool.isSimilarQuery("President of Ukraine", "Ukrainian President", distance: 0.819))
    }
}
