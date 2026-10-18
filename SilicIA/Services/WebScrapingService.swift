//
//  WebScrapingService.swift
//  SilicIA
//
//  Created by Claude on 23/03/2026.
//

import Foundation
import Combine
import CoreGraphics
#if os(iOS)
import UIKit
#endif
import Reeeed
import HTMLToMarkdown

private struct SilicIAReeeedLogger: Logger {
    func info(_ string: String) {
        #if DEBUG
        if !string.hasPrefix("Successfully extracted:") {
            print("[Reeeed] \(string)")
        }
        #endif
    }
    func error(_ string: String) {
        #if DEBUG
        print("[Reeeed] 🚨 \(string)")
        #endif
    }
}

@MainActor
/// Fetches and extracts readable text content from web pages.
class WebScrapingService: ObservableObject {
    nonisolated private static var userAgent: String {
        NetworkConstants.defaultUserAgent
    }

    enum HTMLConversionError: Error, LocalizedError {
        case inputTooLarge(Int)
        case excessiveDOMDepth(Int)
        case excessiveElementCount(Int)
        case emptyContent
        case conversionFailed

        var errorDescription: String? {
            switch self {
            case .inputTooLarge(let bytes):
                return "HTML input exceeds memory limit (\(bytes) bytes)"
            case .excessiveDOMDepth(let depth):
                return "HTML DOM nesting depth exceeds safe recursion limit (\(depth))"
            case .excessiveElementCount(let count):
                return "HTML element count exceeds memory budget (\(count))"
            case .emptyContent:
                return "Converted Markdown content is empty"
            case .conversionFailed:
                return "Failed to reduce HTML content to Markdown"
            }
        }
    }

    nonisolated static let maxRawHTMLBytes = 4 * 1024 * 1024
    nonisolated static let maxMarkdownInputBytes = 2 * 1024 * 1024
    nonisolated static let maxDOMNestingDepth = 64
    nonisolated static let maxDOMElementCount = 10_000
    nonisolated static let markdownThreadStackSize = 4 * 1024 * 1024

    @Published var isScrapingContent = false
    @Published private(set) var lastFailedURLs: Set<String> = []

    #if DEBUG
    struct ScrapeDebugStats {
        let requestedLimit: Int
        let candidateURLCount: Int
        let launchedTasks: Int
        let completedTasks: Int
        let succeededPages: Int
        let canceledTasks: Int
        let poolSize: Int
        let overfetchCount: Int
        let didEarlyCancel: Bool
        let elapsedSeconds: Double
    }

    @Published var lastDebugStats: ScrapeDebugStats?
    #endif

    private let session: URLSession
    private static let scrapeConcurrency = 8
    private static let overfetchCount = 3

    // MARK: - Cached HTML regexes (compiled once, reused per scrape)

    /// Strips `<script>`, `<style>`, `<nav>`, `<header>`, and `<footer>` blocks (and content) in one pass.
    nonisolated private static let nonContentBlockRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "<(script|style|nav|header|footer|svg|noscript|template|iframe)[^>]*>[\\s\\S]*?</\\1>",
        options: [.caseInsensitive]
    )
    /// Strips semantic-free inline wrapper tags (`<span>`, `<font>`) to flatten DOM depth before Markdown conversion.
    nonisolated private static let inlineWrapperTagRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "</?(span|font)(\\s[^>]*)?>",
        options: [.caseInsensitive]
    )
    /// Void HTML tags that do not push onto the DOM nesting stack.
    nonisolated private static let voidHTMLTags: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr"
    ]
    /// Matches a whole `<table>...</table>` block. Used to extract tables
    /// *before* the generic tag stripper destroys their structure, so we can
    /// emit a Markdown pipe table the model can actually read.
    nonisolated static let tableBlockRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "<table[^>]*>([\\s\\S]*?)</table>",
        options: [.caseInsensitive]
    )
    /// Matches a `<tr>...</tr>` row inside a table block.
    nonisolated static let tableRowRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "<tr[^>]*>([\\s\\S]*?)</tr>",
        options: [.caseInsensitive]
    )
    /// Matches a `<td>...</td>` or `<th>...</th>` cell inside a row.
    nonisolated static let tableCellRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "<(t[dh])[^>]*>([\\s\\S]*?)</\\1>",
        options: [.caseInsensitive]
    )
    /// Strips HTML comments.
    nonisolated private static let htmlCommentRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "<!--[\\s\\S]*?-->",
        options: []
    )
    /// Strips remaining HTML tags.
    nonisolated private static let htmlTagRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "<[^>]+>",
        options: []
    )
    /// Collapses any whitespace run into a single space.
    nonisolated private static let whitespaceRunRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "\\s+",
        options: []
    )
    /// Captures any HTML entity reference: named, decimal numeric, or hex numeric.
    nonisolated private static let htmlEntityRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "&(#[0-9]+|#x[0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]+);",
        options: []
    )
    /// Lookup table for the small set of named HTML entities the scraper supports.
    nonisolated private static let namedHTMLEntities: [String: String] = [
        "nbsp": " ",
        "amp": "&",
        "lt": "<",
        "gt": ">",
        "quot": "\"",
        "apos": "'",
        "mdash": "\u{2014}",
        "ndash": "\u{2013}",
        "hellip": "\u{2026}"
    ]


    /// Creates a scraping session configured for resilient low-overhead requests.
    init() {
        // Configure URLSession for efficient scraping
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.waitsForConnectivity = false
        config.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: config)

        Reeeed.logger = SilicIAReeeedLogger()
        Reeeed.warmup(extractor: .readability)
        Reeeed.warmup(extractor: .mercury)
    }

    /// Validates HTML byte size, strips non-content blocks and inline wrapper tags,
    /// and verifies in a single non-recursive O(N) pass that DOM nesting depth and element count
    /// stay within safe bounds before SwiftSoup / HTMLToMarkdown recursive traversal.
    nonisolated static func validateAndPrepareHTMLForMarkdown(
        _ html: String,
        maxInputBytes: Int = maxMarkdownInputBytes,
        maxElements: Int = maxDOMElementCount
    ) throws -> String {
        let rawBytes = html.utf8.count
        guard rawBytes <= maxRawHTMLBytes else {
            throw HTMLConversionError.inputTooLarge(rawBytes)
        }

        var cleaned = html
        if let commentRegex = htmlCommentRegex {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = commentRegex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }
        if let blockRegex = nonContentBlockRegex {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = blockRegex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }
        if let wrapperRegex = inlineWrapperTagRegex {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = wrapperRegex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }

        let cleanedBytes = cleaned.utf8.count
        guard cleanedBytes <= maxInputBytes else {
            throw HTMLConversionError.inputTooLarge(cleanedBytes)
        }

        let bytes = Array(cleaned.utf8)
        let count = bytes.count
        var i = 0
        var openStack: [String] = []
        openStack.reserveCapacity(maxDOMNestingDepth + 1)
        var elementCount = 0

        while i < count {
            if bytes[i] == 0x3C { // '<'
                let nextIdx = i + 1
                guard nextIdx < count else { break }
                let firstChar = bytes[nextIdx]

                // Skip '<!' or '<?' declarations
                if firstChar == 0x21 || firstChar == 0x3F {
                    i = nextIdx + 1
                    while i < count && bytes[i] != 0x3E { i += 1 }
                    i += 1
                    continue
                }

                let isClosing = (firstChar == 0x2F) // '/'
                var nameStart = isClosing ? nextIdx + 1 : nextIdx
                while nameStart < count && (bytes[nameStart] == 0x20 || bytes[nameStart] == 0x09 || bytes[nameStart] == 0x0A || bytes[nameStart] == 0x0D) {
                    nameStart += 1
                }

                var nameEnd = nameStart
                while nameEnd < count {
                    let b = bytes[nameEnd]
                    let isAlphaNum = (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || (b >= 0x30 && b <= 0x39)
                    if !isAlphaNum { break }
                    nameEnd += 1
                }

                guard nameEnd > nameStart else {
                    i += 1
                    continue
                }

                var tagChars = [UInt8]()
                tagChars.reserveCapacity(nameEnd - nameStart)
                for idx in nameStart..<nameEnd {
                    let b = bytes[idx]
                    tagChars.append((b >= 0x41 && b <= 0x5A) ? (b + 32) : b)
                }
                let tagName = String(decoding: tagChars, as: UTF8.self)

                // Advance to '>'
                var tagClose = nameEnd
                var isSelfClosing = false
                while tagClose < count && bytes[tagClose] != 0x3E {
                    if bytes[tagClose] == 0x2F {
                        isSelfClosing = true
                    } else if bytes[tagClose] != 0x20 && bytes[tagClose] != 0x09 && bytes[tagClose] != 0x0A && bytes[tagClose] != 0x0D {
                        isSelfClosing = false
                    }
                    tagClose += 1
                }
                i = min(count, tagClose + 1)

                if isClosing {
                    if let matchIdx = openStack.lastIndex(of: tagName) {
                        openStack.removeSubrange(matchIdx..<openStack.count)
                    }
                } else {
                    elementCount += 1
                    if elementCount > maxElements {
                        throw HTMLConversionError.excessiveElementCount(elementCount)
                    }
                    if !isSelfClosing && !voidHTMLTags.contains(tagName) {
                        // Apply HTML5 implicit sibling close rules so valid unclosed <p>/<li>/<td>/<tr> don't inflate depth
                        if (tagName == "p" && openStack.last == "p")
                            || (tagName == "li" && openStack.last == "li")
                            || ((tagName == "td" || tagName == "th") && (openStack.last == "td" || openStack.last == "th"))
                            || (tagName == "tr" && openStack.last == "tr")
                            || ((tagName == "dd" || tagName == "dt") && (openStack.last == "dd" || openStack.last == "dt")) {
                            openStack.removeLast()
                        }
                        openStack.append(tagName)
                        if openStack.count > maxDOMNestingDepth {
                            throw HTMLConversionError.excessiveDOMDepth(openStack.count)
                        }
                    }
                }
            } else {
                i += 1
            }
        }

        return cleaned
    }

    /// Executes HTML-to-Markdown conversion on a dedicated Thread with an explicit 4 MB stack
    /// after validating memory and DOM nesting limits.
    nonisolated static func runHTMLToMarkdownOnBoundedThread(_ html: String) async throws -> String {
        let prepared = try validateAndPrepareHTMLForMarkdown(html)
        return try await withCheckedThrowingContinuation { continuation in
            let thread = Thread {
                autoreleasepool {
                    do {
                        let markdown = try HTMLToMarkdown.convert(prepared, plugins: [
                            BasePlugin(),
                            CommonmarkPlugin(),
                            GFMPlugin()
                        ]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if markdown.isEmpty {
                            continuation.resume(throwing: HTMLConversionError.emptyContent)
                        } else {
                            continuation.resume(returning: markdown)
                        }
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            thread.stackSize = Self.markdownThreadStackSize
            thread.qualityOfService = .userInitiated
            thread.name = "fr.trevalim.silicia.html2md"
            thread.start()
        }
    }

    /// Synchronous helper with memory/depth validation (returns empty string if HTML cannot be safely reduced to Markdown).
    nonisolated static func convertHTMLToMarkdown(_ html: String) -> String {
        guard let prepared = try? validateAndPrepareHTMLForMarkdown(html),
              let markdown = try? HTMLToMarkdown.convert(prepared, plugins: [
                  BasePlugin(),
                  CommonmarkPlugin(),
                  GFMPlugin()
              ]) else {
            return ""
        }
        return markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Checks if a URL points to a Wikipedia article and returns its host and article title/slug.
    private func parseWikipediaURL(_ url: URL) -> (host: String, title: String)? {
        guard let host = url.host?.lowercased(),
              host.contains("wikipedia.org"),
              url.path.hasPrefix("/wiki/") else {
            return nil
        }
        let rawSlug = String(url.path.dropFirst("/wiki/".count))
        guard !rawSlug.isEmpty, !rawSlug.contains(":") else {
            // Skip special Wikipedia pages (Special:, File:, Talk:, etc.)
            return nil
        }
        let decodedTitle = rawSlug.removingPercentEncoding ?? rawSlug
        return (host, decodedTitle)
    }

    /// Fetches Wikipedia article HTML directly via MediaWiki action=parse API and converts it to Markdown.
    private func fetchWikipediaMarkdownViaAPI(host: String, title: String, originalURL: URL) async throws -> (title: String, markdown: String) {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/w/api.php"
        components.queryItems = [
            URLQueryItem(name: "action", value: "parse"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "page", value: title),
            URLQueryItem(name: "prop", value: "text"),
            URLQueryItem(name: "redirects", value: "1")
        ]

        guard let apiURL = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: apiURL)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await self.session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        struct MediaWikiParseResponse: Decodable {
            struct ParseContent: Decodable {
                let title: String?
                let text: [String: String]?
            }
            let parse: ParseContent?
        }

        let decoded = try JSONDecoder().decode(MediaWikiParseResponse.self, from: data)
        guard let parse = decoded.parse,
              let htmlText = parse.text?["*"],
              !htmlText.isEmpty else {
            throw URLError(.cannotDecodeContentData)
        }

        let parsedTitle = parse.title ?? title.replacingOccurrences(of: "_", with: " ")
        let (_, markdown) = try await self.extractMarkdown(from: htmlText, baseURL: originalURL)
        return (parsedTitle, markdown)
    }

    /// Extracts clean article Markdown from a URL using Reeeed and html-to-markdown-swift,
    /// with resilient URLSession fetching, Wikipedia API acceleration, and a strict timeout.
    func extractMarkdown(from url: URL, timeoutSeconds: Double = 4.0) async throws -> (title: String, markdown: String) {
        // Fast path: if the URL is a Wikipedia article, use MediaWiki's action=parse API
        if let wiki = parseWikipediaURL(url) {
            do {
                let result = try await fetchWikipediaMarkdownViaAPI(host: wiki.host, title: wiki.title, originalURL: url)
                if !result.markdown.isEmpty {
                    return result
                }
            } catch {
                // If the Wikipedia API request fails, fall through to regular webpage scraping
            }
        }

        return try await withThrowingTaskGroup(of: (title: String, markdown: String).self) { group in
            group.addTask {
                var request = URLRequest(url: url)
                request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
                let (data, response) = try await self.session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                guard data.count <= Self.maxRawHTMLBytes else {
                    throw HTMLConversionError.inputTooLarge(data.count)
                }
                guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                    throw URLError(.cannotDecodeContentData)
                }
                return try await self.extractMarkdown(from: html, baseURL: url)
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                throw URLError(.timedOut)
            }

            guard let firstResult = try await group.next() else {
                throw URLError(.cannotDecodeContentData)
            }
            group.cancelAll()
            return firstResult
        }
    }

    /// Extracts clean article Markdown from raw HTML using Reeeed (Readability with Mercury fallback)
    /// and bounded-stack html-to-markdown-swift conversion with DOM depth/memory limits.
    func extractMarkdown(from html: String, baseURL: URL? = nil) async throws -> (title: String, markdown: String) {
        // Pre-validate raw HTML size and DOM nesting depth before running Readability/Mercury or SwiftSoup.
        _ = try Self.validateAndPrepareHTMLForMarkdown(
            html,
            maxInputBytes: Self.maxRawHTMLBytes,
            maxElements: Self.maxDOMElementCount * 3
        )

        let dummyURL = baseURL ?? URL(string: "https://localhost")!

        var extracted: ExtractedContent?
        do {
            extracted = try await Reeeed.extractArticleContent(url: dummyURL, html: html, extractor: .readability)
        } catch {
            extracted = try? await Reeeed.extractArticleContent(url: dummyURL, html: html, extractor: .mercury)
        }

        if let extracted = extracted {
            let title = extracted.title ?? ""
            let rawContent = extracted.content ?? ""

            if !rawContent.isEmpty {
                let markdown = try await Self.runHTMLToMarkdownOnBoundedThread(rawContent)
                return (title, markdown)
            }
        }

        // Only attempt direct conversion if the HTML itself passes strict size, element count, and DOM depth checks.
        let directMarkdown = try await Self.runHTMLToMarkdownOnBoundedThread(html)
        return ("", directMarkdown)
    }

    struct ReaderWebPageContent: Sendable {
        let title: String
        let styledHTML: String
        let plainText: String
        let baseURL: URL
    }

    private static let readerAdditionalCSS = """
    body {
        background-color: transparent !important;
    }
    #__content {
        padding: 0.25em 0.1em !important;
        max-width: 100% !important;
        opacity: 1 !important;
    }
    #__footer {
        display: none !important;
    }
    mjx-container[jax="CHTML"][display="true"] {
        overflow-x: auto;
        overflow-y: hidden;
        max-width: 100%;
    }
    """

    private static let readerMathJaxSnippet = """
    <script>
    window.MathJax = {
      tex: {
        inlineMath: [['$', '$'], ['\\\\(', '\\\\)']],
        displayMath: [['$$', '$$'], ['\\\\[', '\\\\]']],
        processEscapes: true,
        processEnvironments: true
      },
      options: {
        skipHtmlTags: ['script', 'noscript', 'style', 'textarea', 'pre', 'code'],
        ignoreHtmlClass: 'tex2jax_ignore'
      },
      startup: {
        pageReady: function() {
          return MathJax.startup.defaultPageReady().then(function() {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.heightChange) {
              var h = Math.max(document.body.scrollHeight, document.documentElement.scrollHeight);
              window.webkit.messageHandlers.heightChange.postMessage(h);
            }
          });
        }
      }
    };
    </script>
    <script id="MathJax-script" async src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-chtml.js"></script>
    """

    /// Injects the MathJax configuration and script into a Reader HTML document so inline and display LaTeX formulas render properly.
    nonisolated static func injectMathJax(into html: String) -> String {
        guard !html.contains("MathJax-script") else { return html }
        if let headCloseRange = html.range(of: "</head>", options: .caseInsensitive) {
            var modified = html
            modified.insert(contentsOf: "\n" + readerMathJaxSnippet + "\n", at: headCloseRange.lowerBound)
            return modified
        } else if let bodyCloseRange = html.range(of: "</body>", options: .caseInsensitive) {
            var modified = html
            modified.insert(contentsOf: "\n" + readerMathJaxSnippet + "\n", at: bodyCloseRange.lowerBound)
            return modified
        } else {
            return readerMathJaxSnippet + "\n" + html
        }
    }

    /// Extracts styled Reader HTML (preserving images and layout via Reeeed's ReadableDoc)
    /// along with plain text for AI summarization in a single pass.
    func extractReaderHTML(from url: URL, timeoutSeconds: Double = 6.0) async throws -> ReaderWebPageContent {
        return try await withThrowingTaskGroup(of: ReaderWebPageContent.self) { group in
            group.addTask {
                var request = URLRequest(url: url)
                request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
                let (data, response) = try await self.session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode),
                      let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                    throw URLError(.badServerResponse)
                }
                let baseURL = response.url ?? url
                return try await self.extractReaderHTML(from: html, baseURL: baseURL)
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                throw URLError(.timedOut)
            }

            guard let firstResult = try await group.next() else {
                throw URLError(.cannotDecodeContentData)
            }
            group.cancelAll()
            return firstResult
        }
    }

    /// Extracts styled Reader HTML and plain text from raw HTML using Reeeed's ReadableDoc.
    func extractReaderHTML(from html: String, baseURL: URL) async throws -> ReaderWebPageContent {
        var extracted: ExtractedContent?
        do {
            extracted = try await Reeeed.extractArticleContent(url: baseURL, html: html, extractor: .readability)
        } catch {
            extracted = try? await Reeeed.extractArticleContent(url: baseURL, html: html, extractor: .mercury)
        }

        if let extracted, let rawContent = extracted.content, !rawContent.isEmpty {
            let metadata = (try? await SiteMetadata.extractMetadata(fromHTML: html, baseURL: baseURL)) ?? SiteMetadata(url: baseURL)
            let theme = ReaderTheme(additionalCSS: Self.readerAdditionalCSS)
            let rawStyledHTML: String
            if let doc = ReadableDoc(
                extracted: extracted,
                insertHeroImage: nil,
                metadata: metadata,
                date: extracted.datePublished
            ) {
                rawStyledHTML = doc.html(includeExitReaderButton: false, theme: theme)
            } else {
                rawStyledHTML = rawContent
            }
            let styledHTML = Self.injectMathJax(into: rawStyledHTML)
            let title = extracted.title ?? metadata.title ?? ""
            let plainText = extracted.extractPlainText.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackText = plainText.isEmpty ? HTMLSanitizer.htmlToPlainText(rawContent) : plainText
            return ReaderWebPageContent(
                title: title,
                styledHTML: styledHTML,
                plainText: fallbackText,
                baseURL: baseURL
            )
        }

        throw URLError(.cannotDecodeContentData)
    }

    /// Scrape content from a single URL into clean Markdown.
    /// Returns `nil` if the page cannot be fetched or safely reduced to Markdown within memory/depth limits.
    func scrapeContent(from urlString: String, maxCharacters: Int? = 5000) async -> String? {
        guard let url = URL(string: urlString) else { return nil }

        #if DEBUG
        let pageStart = Date()
        #endif

        do {
            let (title, markdown) = try await extractMarkdown(from: url)
            let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                #if DEBUG
                print("[WebScrapingService] Ignoring source \(urlString): empty Markdown after conversion")
                #endif
                return nil
            }
            #if DEBUG
            let elapsed = Date().timeIntervalSince(pageStart)
            print(String(format: "[Timing][Webpage] Downloaded & converted %@ to markdown in %.3f s (%d chars)", urlString, elapsed, trimmed.count))
            DebugRAGStorage.shared.saveDownloadedWebpage(markdown: trimmed, title: title, url: url)
            #endif
            if let maxCharacters, trimmed.count > maxCharacters {
                return String(trimmed.prefix(maxCharacters))
            }
            return trimmed
        } catch {
            #if DEBUG
            let elapsed = Date().timeIntervalSince(pageStart)
            print(String(format: "[Timing][Webpage] Ignoring source %@ (failed in %.3f s: %@)", urlString, elapsed, error.localizedDescription))
            #endif
            return nil
        }
    }

    /// Scrape content from multiple URLs concurrently into clean Markdown.
    /// Sources that fail or exceed memory/DOM depth limits are omitted from the returned dictionary
    /// and recorded in `lastFailedURLs`.
    func scrapeMultiplePages(urls: [String], limit: Int = 10, maxCharacters: Int? = 5000) async -> [String: String] {
        isScrapingContent = true
        lastFailedURLs = []
        defer { isScrapingContent = false }

        let targetSuccessCount = max(0, limit)
        guard targetSuccessCount > 0 else { return [:] }

        let fetchCount = targetSuccessCount + Self.overfetchCount
        let limitedURLs = Array(urls.prefix(fetchCount))
        var results: [String: String] = [:]
        var failedURLs: Set<String> = []
        var urlIterator = limitedURLs.makeIterator()
        let concurrency = Self.scrapeConcurrency
        let initialWorkers = min(concurrency, limitedURLs.count)

        #if DEBUG
        let scrapeStart = Date()
        var launchedTasks = 0
        var completedTasks = 0
        var didEarlyCancel = false
        #endif

        await withTaskGroup(of: (String, String?).self) { group in
            for _ in 0..<initialWorkers {
                guard let nextURL = urlIterator.next() else { break }
                #if DEBUG
                launchedTasks += 1
                #endif
                group.addTask {
                    let content = await self.scrapeContent(from: nextURL, maxCharacters: maxCharacters)
                    return (nextURL, content)
                }
            }

            for await (url, content) in group {
                #if DEBUG
                completedTasks += 1
                #endif

                if let content = content, !content.isEmpty {
                    results[url] = content
                    // Keep the fastest successful pages only.
                    if results.count >= targetSuccessCount {
                        #if DEBUG
                        didEarlyCancel = completedTasks < limitedURLs.count
                        #endif
                        group.cancelAll()
                        break
                    }
                } else {
                    failedURLs.insert(url)
                }

                if let nextURL = urlIterator.next() {
                    #if DEBUG
                    launchedTasks += 1
                    #endif
                    group.addTask {
                        let content = await self.scrapeContent(from: nextURL, maxCharacters: maxCharacters)
                        return (nextURL, content)
                    }
                }
            }
        }

        lastFailedURLs = failedURLs

        #if DEBUG
        let canceledTasks = max(launchedTasks - completedTasks, 0)
        lastDebugStats = ScrapeDebugStats(
            requestedLimit: targetSuccessCount,
            candidateURLCount: limitedURLs.count,
            launchedTasks: launchedTasks,
            completedTasks: completedTasks,
            succeededPages: results.count,
            canceledTasks: canceledTasks,
            poolSize: concurrency,
            overfetchCount: Self.overfetchCount,
            didEarlyCancel: didEarlyCancel,
            elapsedSeconds: Date().timeIntervalSince(scrapeStart)
        )
        #endif

        return results
    }

    /// Finds every `<table>` in `html`, converts it to a Markdown pipe table,
    /// and splices the result back into the document — surrounded by blank
    /// lines so it forms its own paragraph block. Surviving `\n` characters
    /// later guide the RAG chunker toward row-aligned split points.
    nonisolated static func extractAndReplaceTables(_ html: String) -> String {
        guard let tableRegex = tableBlockRegex else { return html }
        let nsRange = NSRange(html.startIndex..., in: html)
        let matches = tableRegex.matches(in: html, options: [], range: nsRange)
        guard !matches.isEmpty else { return html }

        var result = ""
        result.reserveCapacity(html.count)
        var cursor = html.startIndex
        for match in matches {
            guard let full = Range(match.range, in: html),
                  let inner = Range(match.range(at: 1), in: html) else {
                continue
            }
            if cursor < full.lowerBound {
                result.append(contentsOf: html[cursor..<full.lowerBound])
            }
            let markdown = convertTableToMarkdown(String(html[inner]))
            if !markdown.isEmpty {
                result.append("\n\n")
                result.append(markdown)
                result.append("\n\n")
            }
            cursor = full.upperBound
        }
        if cursor < html.endIndex {
            result.append(contentsOf: html[cursor...])
        }
        return result
    }

    /// Converts the inner HTML of a `<table>` element to a Markdown pipe
    /// table. Empty input → empty output. Uneven row lengths are padded.
    /// Cell text has nested tags stripped and pipe characters escaped so the
    /// resulting Markdown is well-formed.
    nonisolated static func convertTableToMarkdown(_ tableInnerHTML: String) -> String {
        guard let rowRegex = tableRowRegex, let cellRegex = tableCellRegex else { return "" }
        let nsRange = NSRange(tableInnerHTML.startIndex..., in: tableInnerHTML)
        let rowMatches = rowRegex.matches(in: tableInnerHTML, options: [], range: nsRange)
        var rows: [[String]] = []
        for rowMatch in rowMatches {
            guard let inner = Range(rowMatch.range(at: 1), in: tableInnerHTML) else { continue }
            let rowText = String(tableInnerHTML[inner])
            let rowNSRange = NSRange(rowText.startIndex..., in: rowText)
            let cellMatches = cellRegex.matches(in: rowText, options: [], range: rowNSRange)
            var cells: [String] = []
            for cellMatch in cellMatches {
                guard let cellRange = Range(cellMatch.range(at: 2), in: rowText) else { continue }
                cells.append(sanitizeCellText(String(rowText[cellRange])))
            }
            // Skip rows where every cell is empty — common in layout tables
            // used as spacers, and they generate "| | | | |" lines that
            // burn tokens without conveying anything.
            let hasAnyContent = cells.contains { !$0.isEmpty }
            if hasAnyContent {
                rows.append(cells)
            }
        }
        guard !rows.isEmpty else { return "" }

        let columnCount = rows.map(\.count).max() ?? 0
        guard columnCount > 0 else { return "" }
        let padded = rows.map { row -> [String] in
            row.count == columnCount ? row : row + Array(repeating: "", count: columnCount - row.count)
        }
        var lines: [String] = []
        lines.append("| " + padded[0].joined(separator: " | ") + " |")
        lines.append("|" + String(repeating: " --- |", count: columnCount))
        for row in padded.dropFirst() {
            lines.append("| " + row.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }

    /// Strips nested tags, decodes entities, collapses whitespace, escapes
    /// stray pipes so they don't break the surrounding Markdown table.
    nonisolated private static func sanitizeCellText(_ text: String) -> String {
        var t = text
        t = applyRegex(htmlTagRegex, to: t, replacement: " ")
        t = decodeHTMLEntities(t)
        t = applyRegex(whitespaceRunRegex, to: t, replacement: " ")
        t = t.replacingOccurrences(of: "|", with: "\\|")
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Applies a cached regex with `replacement` over the full string. No-op when the regex is nil.
    nonisolated private static func applyRegex(_ regex: NSRegularExpression?, to text: String, replacement: String) -> String {
        guard let regex else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }

    /// Single-pass entity decoder: walks `&...;` references in order and
    /// substitutes named, decimal-numeric (`&#nnn;`), and hex-numeric
    /// (`&#xNN;`) entities. Unknown references pass through unchanged.
    /// Single-pass entity decoder: delegates to HTMLSanitizer.
    nonisolated private static func decodeHTMLEntities(_ text: String) -> String {
        guard let regex = htmlEntityRegex else { return text }
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)
        guard !matches.isEmpty else { return text }

        var result = ""
        result.reserveCapacity(text.count)
        var cursor = text.startIndex

        for match in matches {
            guard let fullRange = Range(match.range, in: text),
                  let groupRange = Range(match.range(at: 1), in: text) else {
                continue
            }
            // Append the slice between the previous cursor and this match.
            if cursor < fullRange.lowerBound {
                result.append(contentsOf: text[cursor..<fullRange.lowerBound])
            }

            let token = String(text[groupRange])
            let decoded = decodeEntityToken(token) ?? String(text[fullRange])
            result.append(decoded)
            cursor = fullRange.upperBound
        }

        if cursor < text.endIndex {
            result.append(contentsOf: text[cursor...])
        }
        return result
    }

    /// Decodes a single entity body (the part between `&` and `;`).
    /// Returns nil when the entity is unrecognized so the caller can preserve the original text.
    nonisolated private static func decodeEntityToken(_ token: String) -> String? {
        if token.hasPrefix("#x") || token.hasPrefix("#X") {
            let hex = token.dropFirst(2)
            guard let codePoint = UInt32(hex, radix: 16),
                  let scalar = Unicode.Scalar(codePoint) else {
                return nil
            }
            return String(scalar)
        }
        if token.hasPrefix("#") {
            let digits = token.dropFirst()
            guard let codePoint = UInt32(digits, radix: 10),
                  let scalar = Unicode.Scalar(codePoint) else {
                return nil
            }
            return String(scalar)
        }
        return namedHTMLEntities[token]
    }
}
