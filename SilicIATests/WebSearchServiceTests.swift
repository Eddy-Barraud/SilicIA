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

        let results = try await service.search(
            query: query,
            maxDuckDuckGoResults: 3,
            maxWikipediaResults: 0,
            language: .english,
            useDuckDuckGo: true,
            useWikipedia: false
        )

        XCTAssertFalse(results.isEmpty, "DuckDuckGo should return results for '\(query)'")
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
                    <p>SilicIA renders Reeeed HTML directly inside Reader View so images and figures are preserved without intermediate Markdown conversion.</p>
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
        XCTAssertTrue(readerContent.plainText.contains("SilicIA renders Reeeed HTML"), "Plain text should be extracted for AI summarization")
    }
}

