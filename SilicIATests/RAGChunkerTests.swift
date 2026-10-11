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

    func testParagraphChunkingUsingNLTokenizer() {
        let sampleMarkdown = """
        # Title of Article

        First paragraph about artificial intelligence and swift readability. It contains several sentences.

        Second paragraph explaining NaturalLanguage NLTokenizer and embeddings.

        Third paragraph with conclusion.
        """

        let chunks = RAGChunker.chunkParagraphs(text: sampleMarkdown, source: "Web: Example", url: "https://example.com")
        XCTAssertEqual(chunks.count, 4)
        XCTAssertEqual(chunks[0].text, "# Title of Article")
        XCTAssertTrue(chunks[1].text.contains("First paragraph"))
        XCTAssertTrue(chunks[2].text.contains("Second paragraph"))
        XCTAssertTrue(chunks[3].text.contains("Third paragraph"))
        XCTAssertEqual(chunks[0].url, "https://example.com")
    }

    func testRAGContextServiceRankingAnd4096Budgeting() async {
        let service = RAGContextService()
        let chunks = [
            RAGChunk(source: "Page 1", text: "Photosynthesis is the biological process by which plants convert light energy into chemical energy.", url: "https://p1.com", pdfPage: nil),
            RAGChunk(source: "Page 2", text: "Quantum computing utilizes superposition and entanglement to perform calculations.", url: "https://p2.com", pdfPage: nil),
            RAGChunk(source: "Page 3", text: "Chlorophyll in plant leaves absorbs sunlight during photosynthesis.", url: "https://p3.com", pdfPage: nil)
        ]

        let query = "How does photosynthesis work in plants?"
        let historyTokens = 200
        let result = await service.selectContext(
            chunks: chunks,
            query: query,
            historyTokens: historyTokens,
            maxOutputTokens: 1000
        )

        XCTAssertFalse(result.rankedChunks.isEmpty)
        // Photosynthesis chunks should rank higher than quantum computing
        let topChunk = result.rankedChunks.first
        XCTAssertTrue(topChunk?.chunk.text.contains("Photosynthesis") == true || topChunk?.chunk.text.contains("Chlorophyll") == true)

        // Ensure selectedContext is non-empty and fits context window
        XCTAssertFalse(result.selectedContext.isEmpty)
        let estimatedTokens = TokenBudgeting.estimatedTokens(forApproxCharacters: result.selectedContext.count)
        // Check that combined prompt elements fit 4096
        let totalTurnTokens = estimatedTokens + historyTokens + 100 + 80 + 1000
        XCTAssertLessThanOrEqual(totalTurnTokens, TokenBudgeting.contextWindowLimit + 500)
    }

    func testTwoStageCosinePreFiltering() async {
        let service = RAGContextService()
        // Create 20 chunks: 3 highly relevant chunks, 17 irrelevant filler chunks
        var chunks: [RAGChunk] = [
            RAGChunk(source: "Winner 1", text: "The Nobel Prize in Chemistry 2017 was awarded to Jacques Dubochet, Joachim Frank and Richard Henderson for developing cryo-electron microscopy.", url: "https://nobel.org/1", pdfPage: nil),
            RAGChunk(source: "Winner 2", text: "The Nobel Prize in Chemistry winners for 2017 developed cryo-electron microscopy for the high-resolution structure determination of biomolecules.", url: "https://nobel.org/2", pdfPage: nil),
            RAGChunk(source: "Winner 3", text: "In 2017, Richard Henderson was awarded the Nobel Prize in Chemistry for using an electron microscope to generate 3D structures.", url: "https://nobel.org/3", pdfPage: nil)
        ]

        for i in 1...17 {
            chunks.append(RAGChunk(
                source: "Filler \(i)",
                text: "Unrelated topic \(i): We talk about gardening, cooking pasta, soccer league results, weather forecasts, and bicycle maintenance.",
                url: "https://filler\(i).com",
                pdfPage: nil
            ))
        }

        let query = "Who won the Nobel Prize in Chemistry in 2017?"
        let options = RAGSelectionOptions(
            avgCharsPerToken: TokenBudgeting.avgCharsPerToken,
            instructionTokens: TokenBudgeting.instructionTokens,
            promptOverheadTokens: TokenBudgeting.promptOverheadTokens,
            minContextTokens: TokenBudgeting.minContextTokens,
            contextUtilizationFactor: 0.8,
            minimumFallbackContextCharacters: 200,
            longChunkCharacterThreshold: 300,
            longChunkBonusScore: 0.2,
            numericTokenMatchBonus: 0.6,
            numericPresenceBonus: 0.3,
            equationReferenceMatchBonus: 2.5,
            equationFormulaBonus: 0.5,
            equationPresenceBonus: 0.2,
            figureReferenceMatchBonus: 2.5,
            figureCaptionBonus: 0.5,
            figurePageMatchBonus: 2.0,
            figurePresenceBonus: 0.2,
            cosinePreFilterThreshold: 0.7,
            minimumFilterCandidates: 5,
            cosinePreFilterSampleLength: 350
        )

        let result = await service.selectContext(
            chunks: chunks,
            query: query,
            historyTokens: 0,
            maxOutputTokens: 500,
            options: options
        )

        XCTAssertEqual(result.rankedChunks.count, 20)
        // Top chunks should contain the chemistry Nobel prize chunks
        let top3 = result.rankedChunks.prefix(3)
        for ranked in top3 {
            XCTAssertTrue(ranked.chunk.source.hasPrefix("Winner"), "Expected Winner in top 3 but got \(ranked.chunk.source) with score \(ranked.relevanceScore)")
            XCTAssertGreaterThan(ranked.relevanceScore, 0.7)
        }
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
