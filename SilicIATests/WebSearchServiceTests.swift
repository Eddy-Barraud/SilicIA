//
//  WebSearchServiceTests.swift
//  SilicIATests
//
//  Tests for web search retrieval, article extraction, HTML security limits,
//  URL scheme validation, Wikipedia article keys & query cleaning, and scoring.
//

import XCTest
@testable import SilicIA

final class WebSearchServiceTests: XCTestCase {

    @MainActor
    func testWebSearchLiveRetrieval() async throws {
        let service = WebSearchService()
        let query = "Swift programming language Apple"

        let results: [SearchResult]
        do {
            results = try await service.search(
                query: query,
                maxDuckDuckGoResults: 2,
                maxWikipediaResults: 0,
                language: .english,
                useDuckDuckGo: true,
                useWikipedia: false
            )
        } catch SearchError.botChallengeDetected {
            throw XCTSkip("DuckDuckGo returned a bot-detection challenge on this IP — skipping.")
        } catch {
            throw XCTSkip("Network search unavailable — skipping: \(error)")
        }

        if results.isEmpty {
            throw XCTSkip("DuckDuckGo returned 0 results on this network.")
        }
        guard let first = results.first else { return }

        XCTAssertFalse(first.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(first.url.hasPrefix("http://") || first.url.hasPrefix("https://"))
        XCTAssertFalse(first.snippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        let combined = results.map { "\($0.title) \($0.snippet)" }.joined(separator: " ").lowercased()
        XCTAssertTrue(
            combined.contains("swift") || combined.contains("apple") || combined.contains("programming") || combined.contains("language"),
            "DuckDuckGo results should contain relevant topic keywords"
        )
    }

    @MainActor
    func testReeeedHTMLArticleExtractionAndReaderView() async throws {
        let scraper = WebScrapingService()
        let baseURL = URL(string: "https://silicia.app/article")!
        let sampleHTML = """
        <!DOCTYPE html>
        <html>
        <head><title>SilicIA Neural Engine Architecture</title></head>
        <body>
            <header><nav><a href="/home">Home</a></nav></header>
            <main>
                <article>
                    <h1>SilicIA Neural Engine Architecture</h1>
                    <figure>
                        <img src="https://silicia.app/images/architecture.png" alt="SilicIA Architecture" />
                        <figcaption>Figure 1: SilicIA On-Device Architecture</figcaption>
                    </figure>
                    <p>SilicIA leverages Apple Silicon Neural Accelerators for private, on-device intelligence.</p>
                    <p>With inline formula $E = mc^2$ and local RAG.</p>
                </article>
            </main>
            <footer><p>&copy; 2026 SilicIA</p></footer>
        </body>
        </html>
        """

        let (title, markdown) = try await scraper.extractMarkdown(from: sampleHTML, baseURL: baseURL)
        XCTAssertTrue(title.contains("SilicIA") || markdown.contains("SilicIA"))
        XCTAssertTrue(markdown.contains("Apple Silicon"))
        XCTAssertFalse(markdown.contains("&copy;"))

        let reader = try await scraper.extractReaderHTML(from: sampleHTML, baseURL: baseURL)
        XCTAssertEqual(reader.baseURL, baseURL)
        XCTAssertTrue(reader.styledHTML.contains("<img"))
        XCTAssertTrue(reader.styledHTML.contains("architecture.png"))
        XCTAssertTrue(reader.styledHTML.contains("MathJax-script"))
        XCTAssertTrue(reader.plainText.contains("SilicIA leverages Apple Silicon"))
    }

    @MainActor
    func testDeeplyNestedHTMLRejectionAndSecuritySchemes() async throws {
        let scraper = WebScrapingService()
        let baseURL = URL(string: "https://silicia.app/nested")!

        // Pathological HTML with 250 nested blockquotes
        let deepNesting = 250
        let openTags = String(repeating: "<blockquote><p>Nested quote</p>", count: deepNesting)
        let closeTags = String(repeating: "</blockquote>", count: deepNesting)
        let pathologicalHTML = """
        <!DOCTYPE html><html><head><title>Deep</title></head><body><article>
        <h1>Deep</h1>\(openTags)<pre><code>let crash = false</code></pre>\(closeTags)
        </article></body></html>
        """

        do {
            _ = try await scraper.extractMarkdown(from: pathologicalHTML, baseURL: baseURL)
            XCTFail("Expected deeply nested HTML (250 levels) to throw excessiveDOMDepth")
        } catch let error as WebScrapingService.HTMLConversionError {
            if case .excessiveDOMDepth(let depth) = error {
                XCTAssertGreaterThan(depth, WebScrapingService.maxDOMNestingDepth)
            } else {
                XCTFail("Expected excessiveDOMDepth, got \(error)")
            }
        }

        XCTAssertTrue(WebScrapingService.convertHTMLToMarkdown(pathologicalHTML).isEmpty)

        // Moderately nested HTML (20 levels) succeeds
        let safeOpen = String(repeating: "<div>", count: 20)
        let safeClose = String(repeating: "</div>", count: 20)
        let safeHTML = "<!DOCTYPE html><html><body><article><h1>Safe</h1>\(safeOpen)<p>Safe text.</p>\(safeClose)</article></body></html>"
        let (_, markdown) = try await scraper.extractMarkdown(from: safeHTML, baseURL: baseURL)
        XCTAssertTrue(markdown.contains("Safe text."))

        // Unsafe schemes rejected
        let unsafeURLs = [
            URL(fileURLWithPath: "/etc/passwd"),
            URL(string: "file://en.wikipedia.org/wiki/Swift")!,
            URL(string: "custom://en.wikipedia.org/wiki/Swift")!,
            URL(string: "data:text/html,<h1>Hello</h1>")!
        ]
        for url in unsafeURLs {
            do {
                _ = try await scraper.extractMarkdown(from: url)
                XCTFail("Expected failure for unsafe URL: \(url)")
            } catch let error as URLError {
                XCTAssertEqual(error.code, .unsupportedURL)
            } catch {}
        }
    }

    func testWikipediaArticleKeyCleaningAndRelevanceThresholds() {
        // Wikipedia article key extraction
        let frURL = "https://fr.wikipedia.org/wiki/Quatri%C3%A8me_R%C3%A9publique_(France)#Historique"
        let frResult = WebSearchService.extractWikipediaArticleKey(from: frURL)
        XCTAssertEqual(frResult?.language, .french)
        XCTAssertEqual(frResult?.key, "Quatrième_République_(France)")

        let enURL = "https://en.wikipedia.org/wiki/Vincent_Auriol"
        let enResult = WebSearchService.extractWikipediaArticleKey(from: enURL)
        XCTAssertEqual(enResult?.language, .english)
        XCTAssertEqual(enResult?.key, "Vincent_Auriol")

        let ignoredSpecial = "https://fr.wikipedia.org/wiki/Sp%C3%A9cial:Recherche"
        XCTAssertNil(WebSearchService.extractWikipediaArticleKey(from: ignoredSpecial))

        // Wikipedia query cleaning across EN, FR, ES and edge cases
        let cleaningCases: [(String, String)] = [
            ("Who was the first president of the United States?", "first president United States"),
            ("What is photosynthesis?", "photosynthesis"),
            ("Where is the Eiffel Tower located?", "Eiffel Tower located"),
            ("Qu'est-ce que la relativité générale ?", "relativité générale"),
            ("Qui est Marie Curie ?", "Marie Curie"),
            ("¿Quién fue Simón Bolívar?", "Simón Bolívar"),
            ("The Who", "The Who"),
            ("", ""),
            ("« Tour Eiffel »!", "Tour Eiffel")
        ]
        for (raw, expected) in cleaningCases {
            XCTAssertEqual(WikipediaQueryCleaner.clean(raw), expected, "Failed for '\(raw)'")
        }
        let q = "Who was the first president of the United States?"
        XCTAssertEqual(WikipediaQueryCleaner.clean(q), WikipediaQueryCleaner.clean(WikipediaQueryCleaner.clean(q)))

        // Snippet similarity
        let threshold = WebSearchService.minimumSnippetSimilarityThreshold
        let relevantScore = WebSearchService.snippetSimilarity(
            query: "de quoi est constitué l'ADN",
            snippet: "L'acide désoxyribonucléique (ADN) est une macromolécule constituée de nucléotides.",
            language: .french
        )
        XCTAssertGreaterThanOrEqual(relevantScore, threshold)

        let irrelevantScore = WebSearchService.snippetSimilarity(
            query: "de quoi est constitué l'ADN",
            snippet: "Horaires d'ouverture de la mairie de Lyon.",
            language: .french
        )
        XCTAssertLessThan(irrelevantScore, threshold)
    }

    @MainActor
    func testAIServiceSourceFilteringAndScrapingLimits() async {
        let aiService = AIService()

        let validSource = SearchResult(
            title: "Valid Apple Silicon Source",
            url: "https://valid.example.com/apple-silicon",
            snippet: "Valid snippet about Apple Silicon unified memory.",
            retrievedContent: "# Apple Silicon\nApple Silicon integrates CPU, GPU, and Neural Engine."
        )

        let unconvertibleSource = SearchResult(
            title: "Unconvertible Broken Source",
            url: "http://127.0.0.1:1/unconvertible-deep-html",
            snippet: "Fallback snippet."
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
            onMatchingScores: { reportedScores = $0 },
            onValidSourcesUpdated: { updatedValidSources = $0 }
        )

        XCTAssertEqual(updatedValidSources?.count, 1)
        XCTAssertEqual(updatedValidSources?.first?.url, validSource.url)
        XCTAssertNil(reportedScores[unconvertibleSource.url])
    }

    @MainActor
    func testDuckDuckGoRequestPacerStaggersConcurrentRequests() async throws {
        let service = WebSearchService()
        let start = Date()
        try await withThrowingTaskGroup(of: Date.self) { group in
            for _ in 0..<3 {
                group.addTask {
                    try await service.waitForDuckDuckGoRequestSlot()
                    return Date()
                }
            }
            var timestamps: [Date] = []
            for try await ts in group {
                timestamps.append(ts)
            }
            timestamps.sort()
            XCTAssertEqual(timestamps.count, 3)
            let totalElapsed = Date().timeIntervalSince(start)
            XCTAssertLessThan(totalElapsed, 4.5)
        }
    }
}
