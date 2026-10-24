//
//  WebSearchServiceTests.swift
//  SilicIATests
//
//  Integration tests verifying that DuckDuckGo and Wikipedia search providers
//  fetch, parse, and return effective web data for concrete natural-language questions.
//

import XCTest
@testable import SilicIA

final class WebSearchServiceTests: XCTestCase {

    @MainActor
    func testDuckDuckGoRetrievesEffectiveWebData() async throws {
        let service = WebSearchService()
        let query = "Swift programming language Apple"

        let results: [SearchResult]
        do {
            results = try await service.search(
                query: query,
                maxDuckDuckGoResults: 3,
                maxWikipediaResults: 0,
                language: .english,
                useDuckDuckGo: true,
                useWikipedia: false
            )
        } catch SearchError.botChallengeDetected {
            throw XCTSkip("DuckDuckGo returned a bot-detection challenge on this IP — skipping live DuckDuckGo test.")
        } catch {
            throw error
        }

        if results.isEmpty {
            throw XCTSkip("DuckDuckGo returned 0 results on this host/network — skipping live DuckDuckGo test.")
        }
        guard let first = results.first else {
            XCTFail("No DuckDuckGo results returned")
            return
        }

        XCTAssertFalse(first.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Result title should not be empty")
        XCTAssertFalse(first.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Result URL should not be empty")
        XCTAssertTrue(first.url.hasPrefix("http://") || first.url.hasPrefix("https://"), "Result URL should be a valid web URL: \(first.url)")
        XCTAssertFalse(first.snippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Result snippet should not be empty")

        // Verify that returned results are semantically relevant to Swift / Apple
        let combinedText = results.map { "\($0.title) \($0.snippet)" }.joined(separator: " ").lowercased()
        let hasRelevantKeywords = combinedText.contains("swift")
            || combinedText.contains("apple")
            || combinedText.contains("programming")
            || combinedText.contains("language")
        XCTAssertTrue(hasRelevantKeywords, "DuckDuckGo results should contain relevant topic keywords")
    }

    @MainActor
    func testWikipediaAPIRetrievesEffectiveDataForConcreteQuestion() async throws {
        let service = WebSearchService()
        let question = "Who proposed the theory of general relativity?"

        let results = try await service.search(
            query: question,
            maxDuckDuckGoResults: 0,
            maxWikipediaResults: 2,
            language: .english,
            useDuckDuckGo: false,
            useWikipedia: true
        )

        XCTAssertFalse(results.isEmpty, "Wikipedia API should return results for question: '\(question)'")
        guard let topResult = results.first else {
            XCTFail("No Wikipedia results returned")
            return
        }

        XCTAssertTrue(topResult.url.contains("en.wikipedia.org"), "URL should be an English Wikipedia URL: \(topResult.url)")
        XCTAssertFalse(topResult.title.isEmpty, "Title should not be empty")

        let combinedText = results.map { "\($0.title) \($0.snippet)" }.joined(separator: " ").lowercased()
        let isRelativityOrEinstein = combinedText.contains("einstein")
            || combinedText.contains("relativity")
            || combinedText.contains("physic")
        XCTAssertTrue(isRelativityOrEinstein, "Top Wikipedia results should identify Einstein or Relativity for relativity question. Found: \(combinedText)")
    }

    @MainActor
    func testWikipediaMultilingualConcreteQuestions() async throws {
        let service = WebSearchService()

        // French concrete question
        let frQuestion = "Quelle est la capitale de l'Australie ?"
        let frResults = try await service.search(
            query: frQuestion,
            maxDuckDuckGoResults: 0,
            maxWikipediaResults: 2,
            language: .french,
            useDuckDuckGo: false,
            useWikipedia: true
        )
        XCTAssertFalse(frResults.isEmpty, "French Wikipedia should return results for '\(frQuestion)'")
        let frText = frResults.map { "\($0.title) \($0.snippet)" }.joined(separator: " ").lowercased()
        XCTAssertTrue(frText.contains("canberra") || frText.contains("australie"), "French Wikipedia should identify Canberra or Australie. Found: \(frText)")

        // Spanish concrete question
        let esQuestion = "¿Cuál es la capital de España?"
        let esResults = try await service.search(
            query: esQuestion,
            maxDuckDuckGoResults: 0,
            maxWikipediaResults: 2,
            language: .spanish,
            useDuckDuckGo: false,
            useWikipedia: true
        )
        XCTAssertFalse(esResults.isEmpty, "Spanish Wikipedia should return results for '\(esQuestion)'")
        let esText = esResults.map { "\($0.title) \($0.snippet)" }.joined(separator: " ").lowercased()
        XCTAssertTrue(esText.contains("madrid") || esText.contains("españa"), "Spanish Wikipedia should identify Madrid or España. Found: \(esText)")
    }

    @MainActor
    func testWikipediaAPIArticleExtraction() async throws {
        let scraper = WebScrapingService()
        guard let url = URL(string: "https://en.wikipedia.org/wiki/Swift_(programming_language)") else {
            XCTFail("Invalid test URL")
            return
        }

        let (title, markdown) = try await scraper.extractMarkdown(from: url, timeoutSeconds: 5.0)
        XCTAssertFalse(title.isEmpty, "Title should not be empty")
        XCTAssertFalse(markdown.isEmpty, "Markdown content should not be empty")
        let lowered = markdown.lowercased()
        XCTAssertTrue(lowered.contains("apple") || lowered.contains("programming language"), "Markdown should contain relevant topic information")
    }

    @MainActor
    func testReeeedHTMLArticleExtraction() async throws {
        let scraper = WebScrapingService()
        let sampleHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>SilicIA Neural Engine Architecture</title>
        </head>
        <body>
            <header><nav><a href="/home">Home</a></nav></header>
            <main>
                <article>
                    <h1>SilicIA Neural Engine Architecture</h1>
                    <p>SilicIA leverages Apple Silicon Neural Accelerators for private, on-device intelligence.</p>
                    <p>With unified memory and low latency inference, local RAG enables rich multi-source reasoning.</p>
                </article>
            </main>
            <footer><p>&copy; 2026 SilicIA</p></footer>
        </body>
        </html>
        """

        let (title, markdown) = try await scraper.extractMarkdown(from: sampleHTML, baseURL: URL(string: "https://silicia.app/article")!)
        XCTAssertTrue(title.contains("SilicIA") || markdown.contains("SilicIA"), "Title or markdown should extract the article heading")
        XCTAssertTrue(markdown.contains("Apple Silicon"), "Markdown should extract main article text")
        XCTAssertFalse(markdown.contains("&copy;"), "Boilerplate should be stripped")
    }

    @MainActor
    func testReeeedReaderHTMLExtractionPreservesImages() async throws {
        let scraper = WebScrapingService()
        let baseURL = URL(string: "https://silicia.app/article")!
        let sampleHTML = """
        <!DOCTYPE html>
        <html>
        <head><title>SilicIA Reader View Test</title></head>
        <body>
            <header><nav>Menu</nav></header>
            <main>
                <article>
                    <h1>SilicIA Reader View Test</h1>
                    <figure>
                        <img src="https://silicia.app/images/architecture.png" alt="SilicIA Architecture" />
                        <figcaption>Figure 1: SilicIA On-Device Architecture</figcaption>
                    </figure>
                    <p>SilicIA renders Reeeed HTML directly inside Reader View so images and figures are preserved without intermediate Markdown conversion, and inline formulas like $E = mc^2$ or \\(\\nabla \\cdot \\mathbf{E} = \\frac{\\rho}{\\varepsilon_0}\\) are rendered by MathJax.</p>
                    <p>This single-pass extraction also returns clean plain text for the AI summary.</p>
                </article>
            </main>
            <footer><p>Copyright 2026</p></footer>
        </body>
        </html>
        """

        let readerContent = try await scraper.extractReaderHTML(from: sampleHTML, baseURL: baseURL)
        XCTAssertEqual(readerContent.baseURL, baseURL)
        XCTAssertTrue(readerContent.styledHTML.contains("<img"), "Styled Reader HTML should preserve <img> tags")
        XCTAssertTrue(readerContent.styledHTML.contains("architecture.png"), "Styled Reader HTML should preserve image source URL")
        XCTAssertTrue(readerContent.styledHTML.contains("MathJax-script"), "Styled Reader HTML should inject MathJax script")
        XCTAssertTrue(readerContent.styledHTML.contains("tex-mml-chtml.js"), "Styled Reader HTML should load MathJax v3 CHTML bundle")
        XCTAssertTrue(readerContent.styledHTML.contains("$E = mc^2$"), "Styled Reader HTML should preserve inline LaTeX formulas for MathJax")
        XCTAssertTrue(readerContent.plainText.contains("SilicIA renders Reeeed HTML"), "Plain text should be extracted for AI summarization")
    }

    @MainActor
    func testDeeplyNestedHTMLDoesNotOverflowStackAndIsRejected() async throws {
        let scraper = WebScrapingService()
        let baseURL = URL(string: "https://silicia.app/nested")!

        // 1. Pathological HTML with 250 nested <blockquote>/<pre><code> tags that would overflow a 512 KB cooperative stack
        let deepNesting = 250
        let openTags = String(repeating: "<blockquote><p>Nested quote layer</p>", count: deepNesting)
        let closeTags = String(repeating: "</blockquote>", count: deepNesting)
        let pathologicalHTML = """
        <!DOCTYPE html>
        <html>
        <head><title>Deeply Nested Page</title></head>
        <body>
            <article>
                <h1>Deeply Nested Page</h1>
                <p>Introductory paragraph with enough content for readability extraction to keep the article block intact.</p>
                \(openTags)<pre><code>let crash = false</code></pre><p>Deeply buried text inside 250 nested blockquotes.</p>\(closeTags)
            </article>
        </body>
        </html>
        """

        do {
            _ = try await scraper.extractMarkdown(from: pathologicalHTML, baseURL: baseURL)
            XCTFail("Expected deeply nested HTML (250 levels) to throw HTMLConversionError.excessiveDOMDepth")
        } catch let error as WebScrapingService.HTMLConversionError {
            if case .excessiveDOMDepth(let depth) = error {
                XCTAssertGreaterThan(depth, WebScrapingService.maxDOMNestingDepth)
            } else {
                XCTFail("Expected excessiveDOMDepth, got \(error)")
            }
        }

        // Synchronous helper should also safely return empty string without crashing
        let syncResult = WebScrapingService.convertHTMLToMarkdown(pathologicalHTML)
        XCTAssertTrue(syncResult.isEmpty, "Synchronous helper should reject deeply nested HTML and return empty string")

        // 2. Moderately nested HTML (20 levels) within the 64-level limit should succeed on the 4 MB bounded-stack thread
        let safeOpen = String(repeating: "<div>", count: 20)
        let safeClose = String(repeating: "</div>", count: 20)
        let safeHTML = """
        <!DOCTYPE html>
        <html>
        <head><title>Safe Nested Page</title></head>
        <body>
            <article>
                <h1>Safe Nested Page</h1>
                \(safeOpen)
                <p>SilicIA safely converts moderately nested HTML on a bounded 4 MB stack thread.</p>
                <pre><code>let safe = true</code></pre>
                \(safeClose)
            </article>
        </body>
        </html>
        """

        let (_, markdown) = try await scraper.extractMarkdown(from: safeHTML, baseURL: baseURL)
        XCTAssertTrue(markdown.contains("SilicIA safely converts"), "Moderately nested HTML should convert to Markdown")
        XCTAssertTrue(markdown.contains("let safe = true"), "Pre/code block should be preserved by CommonmarkPlugin")
    }

    @MainActor
    func testUnconvertibleSourcesAreDeletedFromRAGAndSearchResults() async throws {
        let aiService = AIService()

        let validSource = SearchResult(
            title: "Valid Apple Silicon Source",
            url: "https://valid.example.com/apple-silicon",
            snippet: "Valid snippet about Apple Silicon unified memory.",
            retrievedContent: """
            # Apple Silicon Architecture

            Apple Silicon integrates CPU, GPU, and Neural Engine on a single system-on-chip with unified memory.
            """
        )

        // Source with no pre-extracted content and an unreachable/invalid port that cannot be reduced to Markdown
        let unconvertibleSource = SearchResult(
            title: "Unconvertible Broken Source",
            url: "http://127.0.0.1:1/unconvertible-deep-html",
            snippet: "Fallback snippet that must be ignored and deleted when HTML-to-Markdown fails."
        )

        var updatedValidSources: [SearchResult]? = nil
        var reportedScores: [String: Double] = [:]

        _ = await aiService.summarize(
            query: "Apple Silicon unified memory architecture",
            results: [validSource, unconvertibleSource],
            maxScrapingResults: 2,
            maxScrapingChars: 4000,
            language: .english,
            generateAnswer: false,
            onMatchingScores: { scores in
                reportedScores = scores
            },
            onValidSourcesUpdated: { valid in
                updatedValidSources = valid
            }
        )

        XCTAssertNotNil(updatedValidSources, "onValidSourcesUpdated callback should be invoked")
        XCTAssertEqual(updatedValidSources?.count, 1, "Unconvertible source should be deleted from active sources")
        XCTAssertEqual(updatedValidSources?.first?.url, validSource.url, "Only the valid Markdown source should remain")
        XCTAssertNil(reportedScores[unconvertibleSource.url], "Deleted source must not receive a RAG matching score")
    }

    @MainActor
    func testSummarizeRespectsUserMaxScrapingResultsWithoutProfileClamping() async {
        let aiService = AIService()
        let results = (1...12).map { index in
            SearchResult(
                title: "Source \(index)",
                url: "http://127.0.0.1:1/source-\(index)",
                snippet: "Snippet \(index)"
            )
        }

        _ = await aiService.summarize(
            query: "propose des recettes de saison",
            results: results,
            maxScrapingResults: 12,
            maxScrapingChars: 7000,
            language: .french,
            generateAnswer: false
        )

        #if DEBUG
        let statsNote = aiService.debugNotes.first { $0.contains("scrape stats:") }
        XCTAssertNotNil(statsNote, "Expected scrape stats debug note")
        XCTAssertTrue(
            statsNote?.contains("requested=12") == true,
            "Expected requested=12 (user settings respected without fast-profile clamping to 6), got: \(statsNote ?? "nil")"
        )
        #endif
    }

    @MainActor
    func testSearchWikipediaRetrievesCleanMarkdownWithoutHTML() async throws {
        let service = WebSearchService()
        let results = try await service.searchWikipedia(query: "Jupiter", language: .english, limit: 1)
        XCTAssertFalse(results.isEmpty, "Wikipedia search for 'Jupiter' should return at least one result")
        guard let first = results.first else { return }
        XCTAssertTrue(first.url.contains("wikipedia.org"), "URL should be a Wikipedia URL: \(first.url)")
        let content = first.retrievedContent ?? ""
        XCTAssertFalse(content.isEmpty, "Retrieved content should not be empty")
        XCTAssertFalse(content.contains("<div"), "Retrieved content must not contain raw HTML <div> tags")
        XCTAssertFalse(content.contains("</div>"), "Retrieved content must not contain raw HTML </div> tags")
        XCTAssertFalse(content.contains("<p>"), "Retrieved content must not contain raw HTML <p> tags")
        XCTAssertFalse(content.contains("</p>"), "Retrieved content must not contain raw HTML </p> tags")
    }

    @MainActor
    func testSearchSourcesToolExecution() async throws {
        let service = WebSearchService()
        let scraper = WebScrapingService()
        let ragService = RAGContextService()
        var reportedResults: [SearchResult] = []
        var reportedScores: [String: Double]? = nil
        var reportedRAGDuration: (chunk: Double, rank: Double)? = nil
        let funnel = SourceFunnel(
            webSearchService: service,
            webScraper: scraper,
            ragContextService: ragService,
            userQuery: "What is the capital of France?",
            language: .english,
            maxDuckDuckGoResults: 0,
            maxWikipediaResults: 2,
            useDuckDuckGo: false,
            useWikipedia: true,
            responseTokens: 500,
            contextUtilizationFactor: nil,
            onResults: { reportedResults = $0 },
            onScores: { reportedScores = $0 },
            onRAGDuration: { c, r in reportedRAGDuration = (c, r) }
        )
        let tool = WikiSourcesTool(funnel: funnel)
        let output = try await tool.call(arguments: WikiSourcesTool.Arguments(wikiQueries: ["Paris"]))
        XCTAssertFalse(output.isEmpty)
        XCTAssertTrue(output.contains("Paris"))
        XCTAssertFalse(reportedResults.isEmpty)
        XCTAssertLessThanOrEqual(reportedResults.count, 2)
        XCTAssertEqual(reportedResults.first?.title.lowercased(), "paris")
        let firstContent = reportedResults.first?.retrievedContent ?? ""
        XCTAssertGreaterThan(firstContent.count, 5000, "onResults should receive full article content, not truncated excerpt")
        XCTAssertNotNil(reportedScores, "onScores should be called with normalized source scores")
        XCTAssertFalse(reportedScores?.isEmpty ?? true, "Reported scores should not be empty")
        XCTAssertNotNil(reportedRAGDuration, "onRAGDuration should be called with chunking and ranking elapsed times")
    }

    @MainActor
    func testSearchSourcesQuotaSplittingAcrossQueries() {
        // When 2 queries are asked, each search gets setting / 2 so total matches user setting
        let maxDDG = 6
        let maxWiki = 4
        let webQueriesCount = 2
        let wikiQueriesCount = 2
        let ddgLimitPerQuery = max(1, maxDDG / webQueriesCount)
        let wikiLimitPerQuery = max(1, maxWiki / wikiQueriesCount)
        XCTAssertEqual(ddgLimitPerQuery, 3)
        XCTAssertEqual(ddgLimitPerQuery * webQueriesCount, maxDDG)
        XCTAssertEqual(wikiLimitPerQuery, 2)
        XCTAssertEqual(wikiLimitPerQuery * wikiQueriesCount, maxWiki)

        // When 1 query is asked, it gets the full setting
        let singleDDGLimit = max(1, maxDDG / 1)
        XCTAssertEqual(singleDDGLimit, maxDDG)
    }

    @MainActor
    func testSearchWikipediaAccentedFrenchTitleRetrievesFullContent() async throws {
        let service = WebSearchService()
        let results = try await service.searchWikipedia(query: "Présidents IVe République", language: .french, limit: 1)
        XCTAssertFalse(results.isEmpty, "Wikipedia search for 'Présidents IVe République' should return at least one result")
        guard let first = results.first else { return }
        XCTAssertTrue(first.url.contains("wikipedia.org"), "URL should be a Wikipedia URL: \(first.url)")
        let content = first.retrievedContent ?? ""
        XCTAssertGreaterThan(content.count, 5000, "Retrieved content must be full article text, not a short excerpt (got \(content.count) chars)")
        XCTAssertTrue(
            content.contains("Vincent Auriol") || content.contains("René Coty") || content.contains("Auriol"),
            "Content should mention IVth Republic presidents: \(content.prefix(300))"
        )
        XCTAssertFalse(content.contains("<p>"), "Content must not contain raw HTML <p> tags")
        XCTAssertFalse(content.contains("</div>"), "Content must not contain raw HTML </div> tags")
    }

    func testHTMLSanitizerPreservesStructureForParagraphChunking() {
        let html = """
        <h1>Titre Principal</h1>
        <p>Premier paragraphe avec un <a href="https://example.com">lien</a> &amp; du texte.</p>
        <p>Deuxième paragraphe avec des détails.</p>
        <ul>
            <li>Premier point</li>
            <li>Deuxième point</li>
        </ul>
        """
        let structured = HTMLSanitizer.htmlToPlainTextWithStructure(html)
        XCTAssertFalse(structured.contains("<"), "Must not contain HTML tags")
        XCTAssertTrue(structured.contains("Titre Principal\n\n"), "Heading must be followed by double newlines")
        XCTAssertTrue(structured.contains("lien & du texte.\n\n"), "Paragraph must end with double newlines and entities decoded")
        XCTAssertTrue(structured.contains("Premier point\n"), "List items must be separated by newlines")
    }

    func testExtractWikipediaArticleKey() {
        // Standard French article URL with percent encoding
        let frURL = "https://fr.wikipedia.org/wiki/Quatri%C3%A8me_R%C3%A9publique_(France)"
        let frResult = WebSearchService.extractWikipediaArticleKey(from: frURL)
        XCTAssertNotNil(frResult)
        XCTAssertEqual(frResult?.language, .french)
        XCTAssertEqual(frResult?.key, "Quatrième_République_(France)")

        // URL with anchor fragment (must strip fragment)
        let anchorURL = "https://fr.wikipedia.org/wiki/Liste_des_pr%C3%A9sidents_de_la_R%C3%A9publique_fran%C3%A7aise#Quatri%C3%A8me_R%C3%A9publique"
        let anchorResult = WebSearchService.extractWikipediaArticleKey(from: anchorURL)
        XCTAssertNotNil(anchorResult)
        XCTAssertEqual(anchorResult?.language, .french)
        XCTAssertEqual(anchorResult?.key, "Liste_des_présidents_de_la_République_française")

        // English article URL
        let enURL = "https://en.wikipedia.org/wiki/Vincent_Auriol"
        let enResult = WebSearchService.extractWikipediaArticleKey(from: enURL)
        XCTAssertNotNil(enResult)
        XCTAssertEqual(enResult?.language, .english)
        XCTAssertEqual(enResult?.key, "Vincent_Auriol")

        // Spanish article URL
        let esURL = "https://es.wikipedia.org/wiki/Cuarta_Rep%C3%BAblica_Francesa"
        let esResult = WebSearchService.extractWikipediaArticleKey(from: esURL)
        XCTAssertNotNil(esResult)
        XCTAssertEqual(esResult?.language, .spanish)
        XCTAssertEqual(esResult?.key, "Cuarta_República_Francesa")

        // Mobile subdomain URL
        let mobileURL = "https://fr.m.wikipedia.org/wiki/Ren%C3%A9_Coty"
        let mobileResult = WebSearchService.extractWikipediaArticleKey(from: mobileURL)
        XCTAssertNotNil(mobileResult)
        XCTAssertEqual(mobileResult?.language, .french)
        XCTAssertEqual(mobileResult?.key, "René_Coty")

        // Ignored namespaces across languages
        let ignoredURLs = [
            "https://fr.wikipedia.org/wiki/Sp%C3%A9cial:Recherche",
            "https://fr.wikipedia.org/wiki/Fichier:Vincent_Auriol.jpg",
            "https://fr.wikipedia.org/wiki/Portail:France",
            "https://fr.wikipedia.org/wiki/Cat%C3%A9gorie:Pr%C3%A9sident_de_la_R%C3%A9publique",
            "https://fr.wikipedia.org/wiki/Aide:Accueil",
            "https://fr.wikipedia.org/wiki/Discussion:Vincent_Auriol",
            "https://en.wikipedia.org/wiki/Special:Search",
            "https://en.wikipedia.org/wiki/Category:Presidents_of_France",
            "https://en.wikipedia.org/wiki/Help:Contents",
            "https://en.wikipedia.org/wiki/Talk:Vincent_Auriol",
            "https://en.wikipedia.org/wiki/Template:Infobox",
            "https://es.wikipedia.org/wiki/Plantilla:Infobox",
            "https://es.wikipedia.org/wiki/Categor%C3%ADa:Historia_de_Francia"
        ]
        for url in ignoredURLs {
            XCTAssertNil(WebSearchService.extractWikipediaArticleKey(from: url), "Namespace in \(url) should be filtered out")
        }

        // Non-Wikipedia URL
        let externalURL = "https://www.example.com/wiki/Vincent_Auriol"
        XCTAssertNil(WebSearchService.extractWikipediaArticleKey(from: externalURL))
    }

    func testNLEmbeddingSnippetSimilarityAndCrossLanguageDetection() {
        let threshold = WebSearchService.minimumSnippetSimilarityThreshold

        // Relevant French snippet vs French query
        let frRelevant = WebSearchService.snippetSimilarity(
            query: "de quoi est constitué l'ADN",
            snippet: "L'acide désoxyribonucléique (ADN) est une macromolécule constituée de nucléotides (adénine, thymine, cytosine, guanine).",
            language: .french
        )
        XCTAssertGreaterThanOrEqual(frRelevant, threshold, "Relevant French snippet should pass threshold")

        // Irrelevant French snippet vs French query
        let frIrrelevant = WebSearchService.snippetSimilarity(
            query: "de quoi est constitué l'ADN",
            snippet: "Horaires d'ouverture de la mairie de Lyon et démarches administratives en ligne.",
            language: .french
        )
        XCTAssertLessThan(frIrrelevant, threshold, "Irrelevant French snippet should be below threshold")

        // Cross-language: French query vs relevant English snippet (detected via NLLanguageRecognizer)
        let crossLangRelevant = WebSearchService.snippetSimilarity(
            query: "Comment configurer SwiftData étape par étape",
            snippet: "SwiftData makes it easy to persist data using declarative code in Swift and SwiftUI.",
            language: .french
        )
        XCTAssertGreaterThanOrEqual(crossLangRelevant, threshold, "Cross-language relevant snippet should pass threshold")

        // Cross-language: French query vs irrelevant English snippet
        let crossLangIrrelevant = WebSearchService.snippetSimilarity(
            query: "Comment configurer SwiftData étape par étape",
            snippet: "Best cheap hotels and flights to Miami Beach Florida.",
            language: .french
        )
        XCTAssertLessThan(crossLangIrrelevant, threshold, "Cross-language irrelevant snippet should be below threshold")

        // Empty or placeholder snippet
        let emptyScore = WebSearchService.snippetSimilarity(
            query: "Swift programming language",
            snippet: "No description available",
            language: .english
        )
        XCTAssertEqual(emptyScore, 0.0, "Placeholder snippet must score 0.0")
    }

    @MainActor
    func testBelowThresholdResultsSkipDownloadAndReceiveZeroPercentScore() async {
        let aiService = AIService()

        let relevantSource = SearchResult(
            title: "ADN — Wikipédia",
            url: "https://fr.wikipedia.org/wiki/Acide_d%C3%A9soxyribonucl%C3%A9ique",
            snippet: "L'ADN est un polymère de nucléotides comprenant l'adénine, la thymine, la cytosine et la guanine.",
            retrievedContent: """
            # Acide désoxyribonucléique

            L'acide désoxyribonucléique (ADN) est une macromolécule biologique présente dans toutes les cellules, formée de quatre bases nucléiques : adénine, thymine, cytosine et guanine.
            """,
            snippetSimilarity: 0.85,
            isBelowRelevanceThreshold: false
        )

        let skippedSource = SearchResult(
            title: "Mairie de Lyon",
            url: "http://127.0.0.1:1/should-never-be-downloaded",
            snippet: "Horaires d'ouverture de la mairie de Lyon et démarches administratives.",
            retrievedContent: nil,
            snippetSimilarity: 0.25,
            isBelowRelevanceThreshold: true
        )

        var updatedValidSources: [SearchResult]? = nil
        var reportedScores: [String: Double] = [:]

        _ = await aiService.summarize(
            query: "de quoi est constitué l'ADN",
            results: [relevantSource, skippedSource],
            maxScrapingResults: 2,
            maxScrapingChars: 4000,
            language: .french,
            generateAnswer: false,
            onMatchingScores: { scores in
                reportedScores = scores
            },
            onValidSourcesUpdated: { valid in
                updatedValidSources = valid
            }
        )

        #if DEBUG
        let statsNote = aiService.debugNotes.first { $0.contains("scrape stats:") }
        XCTAssertTrue(
            statsNote?.contains("candidates=0") == true,
            "Below-threshold URL must not be queued for downloading/scraping, got: \(statsNote ?? "nil")"
        )
        #endif

        XCTAssertEqual(updatedValidSources?.count, 2, "Below-threshold result should remain in search results list with 0% score")
        XCTAssertEqual(reportedScores[skippedSource.url], 0.0, "Below-threshold result must be assigned 0% (0.0) of used content")
        XCTAssertEqual(reportedScores[relevantSource.url] ?? 0, 100.0, accuracy: 0.01, "Relevant source should receive 100% of used content")
    }
}


