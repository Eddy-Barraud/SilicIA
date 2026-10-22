//
//  MathAccuracyTests.swift
//  SilicIATests
//
//  Regression suite for deterministic math-accuracy and document structure pipelines:
//  number integrity during chunking, table extraction, header propagation, and
//  relevance scoring.
//

import XCTest
@testable import SilicIA

final class MathAccuracyTests: XCTestCase {

    // MARK: - Chunker Number & Boundary Integrity

    func testChunkerNumberAndBoundaryIntegrity() {
        // 1. Multi-digit number with thousands separator
        let thousandsText = "The company reported 8,432,567 units sold this fiscal year."
        let thousandsChunks = RAGChunker.chunkParagraphs(text: thousandsText, source: "test")
        XCTAssertTrue(thousandsChunks.contains { $0.text.contains("8,432,567") })

        // 2. Decimal number
        let decimalText = "The constant value is approximately 3.14159265 in Euclidean geometry."
        let decimalChunks = RAGChunker.chunkParagraphs(text: decimalText, source: "test")
        XCTAssertTrue(decimalChunks.contains { $0.text.contains("3.14159265") })

        // 3. Paragraph boundaries preserved
        let p1 = "Paragraph one fills with content for the test. Paragraph one ends clean."
        let p2 = "Paragraph two has more content here."
        let paragraphChunks = RAGChunker.chunkParagraphs(text: "\(p1)\n\n\(p2)", source: "test")
        XCTAssertEqual(paragraphChunks.count, 2)
        XCTAssertTrue(paragraphChunks.first?.text.hasSuffix("clean.") == true)
    }

    // MARK: - Whitespace Normalization

    func testNormalizeWhitespace() {
        // Preserves single and double newlines
        let inputNewlines = "row 1\nrow 2\n\nrow 3"
        let normNewlines = RAGChunker.normalizeWhitespace(inputNewlines)
        XCTAssertTrue(normNewlines.contains("row 1\nrow 2"))
        XCTAssertTrue(normNewlines.contains("row 2\n\nrow 3"))

        // Collapses blank lines containing only whitespace
        XCTAssertEqual(RAGChunker.normalizeWhitespace("line A\n \n \n \nline B"), "line A\n\nline B")

        // Preserves single paragraph break
        XCTAssertEqual(RAGChunker.normalizeWhitespace("para 1\n\npara 2"), "para 1\n\npara 2")

        // Collapses horizontal spaces and tabs
        XCTAssertEqual(RAGChunker.normalizeWhitespace("lots\t  of    \t spaces"), "lots of spaces")
    }

    // MARK: - Numeric & Reference Relevance Scoring

    func testNumericAndReferenceRelevanceBoosts() {
        let options = RAGSelectionOptions.default

        // Exact numeric match boosts score
        let numQuery = "What is the population in 2020 according to the census?"
        let withNum = "The 2020 census recorded a population total of 67432198 residents."
        let withoutNum = "The census reported population data covering many years and demographics."
        XCTAssertGreaterThan(
            RAGContextService.numericRelevanceBoost(text: withNum, query: numQuery, options: options),
            RAGContextService.numericRelevanceBoost(text: withoutNum, query: numQuery, options: options)
        )

        // General numerical intent boost
        let intentQuery = "How many residents live there on average?"
        XCTAssertGreaterThan(
            RAGContextService.numericRelevanceBoost(text: withNum, query: intentQuery, options: options),
            RAGContextService.numericRelevanceBoost(text: withoutNum, query: intentQuery, options: options)
        )

        // Non-numeric query gets 0 boost
        XCTAssertEqual(
            RAGContextService.numericRelevanceBoost(text: "Photosynthesis converts light.", query: "What is photosynthesis", options: options),
            0, accuracy: 0.0001
        )

        // Equation reference boost
        let eqMatching = "eq 5 for ionic surfactants: ln(CMC) = ln(CMC_0) - A ln(1 + BC_ion)"
        let eqNonMatching = "Table 1 methodology. Equation 2 defines a different parameter."
        XCTAssertGreaterThan(
            RAGContextService.equationRelevanceBoost(text: eqMatching, query: "explain equation 5", options: options),
            RAGContextService.equationRelevanceBoost(text: eqNonMatching, query: "explain equation 5", options: options)
        )

        // Figure reference boost
        let figQuery = "describe figure 5 on page 8"
        let exactChunk = RAGChunk(source: "PDF p8", text: "Figure 5. Chain length dependence.", url: nil, pdfPage: 8)
        let wrongPageChunk = RAGChunk(source: "PDF p7", text: "Figure 5. Chain length dependence.", url: nil, pdfPage: 7)
        let wrongFigChunk = RAGChunk(source: "PDF p8", text: "Figure 4. Evolution of CMC.", url: nil, pdfPage: 8)
        let exactBoost = RAGContextService.figureRelevanceBoost(chunk: exactChunk, query: figQuery, options: options)
        XCTAssertGreaterThan(exactBoost, RAGContextService.figureRelevanceBoost(chunk: wrongPageChunk, query: figQuery, options: options))
        XCTAssertGreaterThan(exactBoost, RAGContextService.figureRelevanceBoost(chunk: wrongFigChunk, query: figQuery, options: options))
    }

    // MARK: - Intent Detection

    func testIntentDetection() {
        // Temporal intent
        XCTAssertTrue(RAGContextService.hasTemporalIntent("what's the latest news"))
        XCTAssertTrue(RAGContextService.hasTemporalIntent("actualité des marchés cette semaine"))
        XCTAssertTrue(RAGContextService.hasTemporalIntent("noticias de hoy sobre el clima"))

        // Definitional (non-temporal)
        XCTAssertFalse(RAGContextService.hasTemporalIntent("what is photosynthesis"))
        XCTAssertFalse(RAGContextService.hasTemporalIntent("qu'est-ce qu'un masque chirurgical"))
        XCTAssertFalse(RAGContextService.hasTemporalIntent("definición de macroeconomía"))

        // Numerical intent
        XCTAssertTrue(RAGContextService.hasNumericalIntent("how many people live there"))
        XCTAssertTrue(RAGContextService.hasNumericalIntent("combien d'habitants"))
        XCTAssertTrue(RAGContextService.hasNumericalIntent("cuántos habitantes hay"))
        XCTAssertFalse(RAGContextService.hasNumericalIntent("what is the definition of an apple"))
    }

    // MARK: - HTML Table Extraction

    func testHTMLTableConversion() {
        let html = """
        <html><body>
        <p>Stats follow.</p>
        <table>
          <tr><th>Year</th><th>Population</th></tr>
          <tr><td>2010</td><td>8,432,567</td></tr>
          <tr><td>2020</td><td>105.4</td></tr>
        </table>
        </body></html>
        """
        let converted = WebScrapingService.extractAndReplaceTables(html)
        XCTAssertTrue(converted.contains("| Year | Population |"))
        XCTAssertTrue(converted.contains("| --- | --- |"))
        XCTAssertTrue(converted.contains("8,432,567"))
        XCTAssertTrue(converted.contains("105.4"))

        // Passthrough when no tables
        let prose = "<p>Just a paragraph.</p>"
        XCTAssertEqual(WebScrapingService.extractAndReplaceTables(prose), prose)
    }

    // MARK: - Whitespace-Aligned Table Conversion

    func testWhitespaceAlignedTableConversion() {
        let pdf = """
        Description           Qté   Prix HT   TVA   Prix TTC   Total
        Amortisseurs          2     64,24     20%   77,08      154,17
        Triangles             1     120,00    20%   144,00     144,00
        """
        let converted = RAGChunker.convertWhitespaceAlignedTables(pdf)
        XCTAssertTrue(converted.contains("| Description | Qté | Prix HT | TVA | Prix TTC | Total |"))
        XCTAssertTrue(converted.contains("| Amortisseurs | 2 | 64,24 | 20% | 77,08 | 154,17 |"))
        XCTAssertTrue(converted.contains("| --- |"))

        // Prose with occasional double space must not convert
        let prose = "This is a paragraph.  It has two sentences with a double space.\nA second line follows."
        XCTAssertFalse(RAGChunker.convertWhitespaceAlignedTables(prose).contains("|"))

        // Standalone tabular line without peer row must not convert
        XCTAssertFalse(RAGChunker.convertWhitespaceAlignedTables("Field 1    Field 2    Field 3").contains("|"))
    }

    // MARK: - End-to-End Amortisseurs Row Survival

    func testAmortisseursRowSurvivesChunkingIntact() async {
        let pdf = """
        Devis voiture 208

        Description           Qté   Prix HT   TVA   Prix TTC   Total
        Amortisseurs          2     64,24     20%   77,08      154,17
        Triangles             1     120,00    20%   144,00     144,00

        Total TTC: 298,17
        """
        let converted = RAGChunker.convertWhitespaceAlignedTables(pdf)
        let chunks = RAGChunker.chunkParagraphs(text: converted, source: "test")
        let priceChunk = chunks.first { $0.text.contains("Amortisseurs") }
        XCTAssertNotNil(priceChunk)
        XCTAssertTrue(priceChunk?.text.contains("154,17") == true)
        XCTAssertTrue(priceChunk?.text.contains("| Description | Qté | Prix HT | TVA | Prix TTC | Total |") == true)
    }

    // MARK: - Scientific OCR Table Conversion

    func testScientificTableConversion() {
        // Equation cell fragments merged into modal 3 columns
        let splitEquation = """
        repulsive parameter    origin    equation
        water/water    water compressibility    aww =    kBT/(2a0)(k^-1Nm - 1)
        like/like    same as water    aii = aww
        tail/water    fitted with CMC using osmotic pressure    -
        """
        let converted = RAGChunker.convertWhitespaceAlignedTables(splitEquation)
        XCTAssertTrue(converted.contains("| repulsive parameter | origin | equation |"))
        XCTAssertTrue(converted.contains("| water/water | water compressibility |"))
        XCTAssertFalse(converted.contains("| aww = |"))

        // Consistent column count produces proper table
        let consistent = """
        repulsive parameter    origin    equation
        water/water    water compressibility    aww = kBT/(2a0)(k^-1 Nm - 1)
        like/like    same as water    aii = aww
        """
        let convConsistent = RAGChunker.convertWhitespaceAlignedTables(consistent)
        XCTAssertTrue(convConsistent.contains("| repulsive parameter | origin | equation |"))
        XCTAssertTrue(convConsistent.contains("| water/water | water compressibility | aww = kBT/(2a0)(k^-1 Nm - 1) |"))
    }
}
