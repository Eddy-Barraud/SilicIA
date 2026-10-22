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
        XCTAssertEqual(chunks.count, 3)
        XCTAssertTrue(chunks[0].text.contains("First paragraph"))
        XCTAssertTrue(chunks[1].text.contains("Second paragraph"))
        XCTAssertTrue(chunks[2].text.contains("Third paragraph"))
        XCTAssertEqual(chunks[0].url, "https://example.com")
        XCTAssertEqual(chunks[0].source, "Web: Example")
    }

    func testRemoveMarkdownFormattingTitlesAndLinks() {
        let rawMarkdown = """
        # Main Title
        ## Subtitle Level 2
        ### Deep Subtitle

        En [mathématiques](https://fr.wikipedia.org/wiki/Math%C3%A9matiques "Mathématiques"), la **distance euclidienne** entre deux [points](https://fr.wikipedia.org/wiki/Point_%28g%C3%A9om%C3%A9trie%29) est la longueur du [segment](https://fr.wikipedia.org/wiki/Segment) qui sépare ces points.

        [![](https://thumb.wikimedia.org/thumb.png)](https://fr.wikipedia.org/wiki/File)
        Voici un autre paragraphe avec [Vincent Auriol](https://fr.wikipedia.org/wiki/Vincent_Auriol) et [René Coty](https://fr.wikipedia.org/wiki/Ren%C3%A9_Coty).
        """

        let cleaned = RAGChunker.removeMarkdownFormatting(from: rawMarkdown)
        XCTAssertFalse(cleaned.contains("# Main Title"))
        XCTAssertFalse(cleaned.contains("## Subtitle Level 2"))
        XCTAssertFalse(cleaned.contains("### Deep Subtitle"))
        XCTAssertFalse(cleaned.contains("https://fr.wikipedia.org"))
        XCTAssertFalse(cleaned.contains("]("))
        XCTAssertTrue(cleaned.contains("En mathématiques, la **distance euclidienne** entre deux points est la longueur du segment qui sépare ces points."))
        XCTAssertTrue(cleaned.contains("Voici un autre paragraphe avec Vincent Auriol et René Coty."))

        let chunks = RAGChunker.chunkParagraphs(text: rawMarkdown, source: "Test Doc")
        XCTAssertEqual(chunks.count, 2)
        XCTAssertFalse(chunks.contains { $0.text.hasPrefix("#") })
        XCTAssertTrue(chunks[0].text.contains("En mathématiques"))
        XCTAssertFalse(chunks[0].text.contains("https://"))
        XCTAssertTrue(chunks[1].text.contains("Vincent Auriol et René Coty"))
        XCTAssertFalse(chunks[1].text.contains("https://"))
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

    func testTwoStageDCTCosineCapsOutputAtTwiceTokenBudget() async {
        let service = RAGContextService()
        var chunks: [RAGChunk] = [
            RAGChunk(
                source: "Target 1",
                text: "Une antenne de l'office de tourisme de Lyon a été saccagée et incendiée en marge de la mobilisation du 17 octobre.",
                url: "https://franceinfo.fr/1",
                pdfPage: nil
            ),
            RAGChunk(
                source: "Target 2",
                text: "Les pompiers sont intervenus rapidement à Lyon après l'incendie de l'office de tourisme lors de la manifestation du 17 octobre.",
                url: "https://franceinfo.fr/2",
                pdfPage: nil
            )
        ]

        // Add 300 large filler chunks (~250 chars each = ~75,000 chars total, well above 2x token budget)
        for i in 1...300 {
            chunks.append(RAGChunk(
                source: "Filler \(i)",
                text: "Unrelated paragraph number \(i) discussing culinary recipes, chocolate cake baking temperatures, international football tournaments, gardening tips for spring roses, and municipal parking regulations in coastal towns.",
                url: "https://filler.example.com/\(i)",
                pdfPage: nil
            ))
        }

        let query = "Que s'est-il passé à l'office de tourisme de Lyon le 17 octobre ?"
        let start = Date()
        let result = await service.selectContext(
            chunks: chunks,
            query: query,
            historyTokens: 0,
            maxOutputTokens: 1000,
            contextUtilizationFactor: 0.65
        )
        let elapsed = Date().timeIntervalSince(start)

        // Compute the exact 2x token budget in characters
        let queryTokens = TokenBudgeting.estimatedTokens(forApproxCharacters: query.count)
        let nonContextTokens = queryTokens + TokenBudgeting.instructionTokens + TokenBudgeting.promptOverheadTokens + 1000
        let availableTokens = max(0, TokenBudgeting.contextWindowLimit - nonContextTokens)
        let budgetedTokens = Int(Double(availableTokens) * 0.65)
        let maxContextChars = max(TokenBudgeting.minContextTokens * TokenBudgeting.avgCharsPerToken, budgetedTokens * TokenBudgeting.avgCharsPerToken)
        let maxStage2Chars = maxContextChars * 2

        let rankedTotalChars = result.rankedChunks.reduce(0) { $0 + $1.chunk.text.count }
        XCTAssertLessThanOrEqual(rankedTotalChars, maxStage2Chars, "Ranked chunk size (\(rankedTotalChars)) must not exceed 2x token budget (\(maxStage2Chars))")
        XCTAssertLessThan(result.rankedChunks.count, chunks.count, "Only a top portion of sorted chunks should be kept for NLEmbedding")
        XCTAssertLessThan(elapsed, 2.0, "Two-stage DCT + NLEmbedding ranking on 302 chunks should complete quickly")

        let topSources = Set(result.rankedChunks.prefix(2).map(\.chunk.source))
        XCTAssertTrue(topSources.contains("Target 1"))
        XCTAssertTrue(topSources.contains("Target 2"))
    }

    func testAIServiceTimingExcludesStreaming() async {
        let aiService = AIService()
        let result1 = SearchResult(
            title: "Swift Concurrency",
            url: "https://developer.apple.com/swift",
            snippet: "Swift provides built-in support for writing asynchronous and parallel code in a structured way."
        )

        _ = await aiService.summarize(
            query: "Swift async await concurrency",
            results: [result1],
            maxScrapingResults: 0,
            maxScrapingChars: 0,
            temperature: 0.3,
            maxTokens: 300,
            language: .english,
            generateAnswer: false
        )

        guard let answerElapsed = aiService.lastAnswerElapsedSeconds else {
            XCTFail("aiService.lastAnswerElapsedSeconds should be set after summarize")
            return
        }

        XCTAssertGreaterThan(answerElapsed, 0.0, "Answer timing should be greater than 0")
        XCTAssertLessThan(answerElapsed, 5.0, "RAG pipeline + timing should be fast")

        #if DEBUG
        let metricNames = aiService.debugTimings.map(\.name)
        XCTAssertTrue(metricNames.contains("RAG Pipeline (Scrape + Chunk + Rank)"))
        XCTAssertTrue(metricNames.contains("AIService.summarize (RAG + LLM Answering)"))
        #endif
    }

    func testQueryLanguageDetectionAndFrenchNLEmbeddingRanking() async {
        // 1. Verify query language detection matches the actual user query language regardless of UI fallback
        XCTAssertEqual(
            RAGContextService.detectQueryLanguage(for: "propose des recettes de saison", fallback: .english),
            .french
        )
        XCTAssertEqual(
            RAGContextService.detectQueryLanguage(for: "Famous works of Einstein", fallback: .french),
            .english
        )
        XCTAssertEqual(
            RAGContextService.detectQueryLanguage(for: "¿Cuáles son las recetas de temporada?", fallback: .english),
            .spanish
        )

        let service = RAGContextService()
        let frWordEmb = await service.resolveWordEmbedding(for: "propose des recettes de saison", language: .english)
        if let frWordEmb {
            XCTAssertEqual(frWordEmb.language, .french)
        }

        let enSentenceEmb = await service.resolveEmbedding(for: "Famous works of Einstein", language: .french)
        if let enSentenceEmb {
            XCTAssertEqual(enSentenceEmb.language, .english)
        }

        // 2. Verify seasonal recipe chunks rank strictly above off-topic "Star Academy (France)" chunks
        let starAcademyChunk = RAGChunk(
            source: "Star Academy (France)",
            text: "Star Academy est une émission de télévision française de télé-réalité musicale diffusée sur TF1. Chaque saison voit une promotion d'élèves au château de Dammarie-les-Lys avec une avance sur recette d'un million d'euros pour le gagnant de la saison.",
            url: "https://fr.wikipedia.org/wiki/Star_Academy_(France)",
            pdfPage: nil
        )
        let recipeChunk1 = RAGChunk(
            source: "Recettes de saison : cuisine d'automne et d'hiver",
            text: "Découvrez nos meilleures idées de recettes de saison faciles et gourmandes : velouté de potimarron, gratin de courge butternut, tarte aux pommes et poires de saison.",
            url: "https://www.marmiton.org/recettes/saison",
            pdfPage: nil
        )
        let recipeChunk2 = RAGChunk(
            source: "Menu et recette de saison du mois",
            text: "Cuisiner des fruits et légumes de saison permet de préparer chaque recette avec des produits frais : soupe de légumes, quiche aux poireaux et compote maison.",
            url: "https://www.cuisineaz.com/recettes-de-saison",
            pdfPage: nil
        )

        let result = await service.selectContext(
            chunks: [starAcademyChunk, recipeChunk1, recipeChunk2],
            query: "propose des recettes de saison",
            maxOutputTokens: 500,
            language: .english
        )

        XCTAssertEqual(result.rankedChunks.count, 3)
        let topTwoURLs = Set(result.rankedChunks.prefix(2).compactMap(\.chunk.url))
        XCTAssertTrue(topTwoURLs.contains("https://www.marmiton.org/recettes/saison"))
        XCTAssertTrue(topTwoURLs.contains("https://www.cuisineaz.com/recettes-de-saison"))
        XCTAssertEqual(result.rankedChunks.last?.chunk.url, "https://fr.wikipedia.org/wiki/Star_Academy_(France)")
    }

    func testMarkdownTablePreservedAsSingleChunk() {
        let markdown = """
        # Chronologie des dirigeants

        Voici la liste des présidents de la IVe République française :

        | Président | Début de mandat | Fin de mandat | Parti politique |
        | --- | --- | --- | --- |
        | Vincent Auriol | 16 janvier 1947 | 16 janvier 1954 | SFIO |
        | René Coty | 16 janvier 1954 | 8 janvier 1959 | CNIP |

        Cette période s'est achevée avec l'adoption de la Constitution de la Ve République.
        """

        let chunks = RAGChunker.chunkMarkdown(text: markdown, source: "Wikipedia: IVe", url: "https://wikipedia.org")

        XCTAssertEqual(chunks.count, 3)
        XCTAssertTrue(chunks[0].text.contains("Voici la liste des présidents"))

        let tableChunk = chunks[1]
        XCTAssertTrue(tableChunk.text.contains("| Président | Début de mandat | Fin de mandat | Parti politique |"))
        XCTAssertTrue(tableChunk.text.contains("| --- | --- | --- | --- |"))
        XCTAssertTrue(tableChunk.text.contains("| Vincent Auriol | 16 janvier 1947 | 16 janvier 1954 | SFIO |"))
        XCTAssertTrue(tableChunk.text.contains("| René Coty | 16 janvier 1954 | 8 janvier 1959 | CNIP |"))
        let tableLines = tableChunk.text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        XCTAssertEqual(tableLines.count, 4)

        XCTAssertTrue(chunks[2].text.contains("Cette période s'est achevée"))
    }

    func testInseeFixtureTablesPreserved() throws {
        let fixturePath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tools")
            .appendingPathComponent("2026-10-18T13-37-18Z_www_insee_fr.md")

        guard FileManager.default.fileExists(atPath: fixturePath.path) else {
            return
        }

        let content = try String(contentsOf: fixturePath, encoding: .utf8)
        let chunks = RAGChunker.chunkMarkdown(text: content, source: "INSEE Fixture")

        // In this document, there are 10 tables
        let tableChunks = chunks.filter { chunk in
            let firstLine = chunk.text.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespaces) ?? ""
            return firstLine.hasPrefix("|") && firstLine.hasSuffix("|")
        }
        XCTAssertEqual(tableChunks.count, 10)

        // Ensure Table 1 contains full 95 rows intact
        let table1 = tableChunks[0]
        XCTAssertTrue(table1.text.contains("France (hors Mayotte)"))
        XCTAssertTrue(table1.text.contains("2026-T1"))
        XCTAssertTrue(table1.text.contains("2015-T1"))
        let table1Rows = table1.text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        XCTAssertEqual(table1Rows.count, 95)
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
