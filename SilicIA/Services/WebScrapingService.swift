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
#if canImport(WebKit)
import WebKit
#endif

@MainActor
/// Fetches and extracts readable text content from web pages.
class WebScrapingService: ObservableObject {
    /// App-specific User-Agent identifying SilicIA. Update version/contact as needed.
    /// Format recommendation: AppName/Version (Platform; Device) Engine; +ContactURL
    private static let userAgent: String = {
        // You can optionally make these dynamic using Bundle info and UIDevice.
        let appName = "SilicIA"
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2"
        #if os(iOS)
        let platform = "iOS"
        #elseif os(macOS)
        let platform = "macOS"
        #elseif os(watchOS)
        let platform = "watchOS"
        #elseif os(tvOS)
        let platform = "tvOS"
        #elseif os(visionOS)
        let platform = "visionOS"
        #else
        let platform = "AppleOS"
        #endif
        let device = {
            #if os(iOS)
            return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
            #elseif os(macOS)
            return "Mac"
            #elseif os(watchOS)
            return "AppleWatch"
            #elseif os(tvOS)
            return "AppleTV"
            #elseif os(visionOS)
            return "visionOS"
            #else
            return "Device"
            #endif
        }()
        // Include WebKit engine hint and a contact URL per good scraping etiquette
        let engine = "AppleWebKit/605.1.15"
        let contact = "+https://github.com/Eddy-Barraud/SilicIA/discussions"
        return "\(appName)/\(appVersion) (\(platform); \(device)) \(engine); \(contact)"
    }()

    @Published var isScrapingContent = false

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
    private static let renderedScrapeConcurrency = 2
    private static let overfetchCount = 3
    private static let webVisionViewport = CGSize(width: 1280, height: 1600)
    private static let webVisionMaxRenderedPages: CGFloat = 3
    private static let webVisionLoadTimeoutNanoseconds: UInt64 = 15_000_000_000
    private static let webVisionSettleNanoseconds: UInt64 = 800_000_000

    // MARK: - Cached HTML regexes (compiled once, reused per scrape)

    /// Strips `<script>`, `<style>`, `<nav>`, `<header>`, and `<footer>` blocks (and content) in one pass.
    private static let nonContentBlockRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "<(script|style|nav|header|footer)[^>]*>[\\s\\S]*?</\\1>",
        options: [.caseInsensitive]
    )
    /// Matches a whole `<table>...</table>` block. Used to extract tables
    /// *before* the generic tag stripper destroys their structure, so we can
    /// emit a Markdown pipe table the model can actually read.
    static let tableBlockRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "<table[^>]*>([\\s\\S]*?)</table>",
        options: [.caseInsensitive]
    )
    /// Matches a `<tr>...</tr>` row inside a table block.
    static let tableRowRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "<tr[^>]*>([\\s\\S]*?)</tr>",
        options: [.caseInsensitive]
    )
    /// Matches a `<td>...</td>` or `<th>...</th>` cell inside a row.
    static let tableCellRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "<(t[dh])[^>]*>([\\s\\S]*?)</\\1>",
        options: [.caseInsensitive]
    )
    /// Strips HTML comments.
    private static let htmlCommentRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "<!--[\\s\\S]*?-->",
        options: []
    )
    /// Strips remaining HTML tags.
    private static let htmlTagRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "<[^>]+>",
        options: []
    )
    /// Collapses any whitespace run into a single space.
    private static let whitespaceRunRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "\\s+",
        options: []
    )
    /// Captures any HTML entity reference: named, decimal numeric, or hex numeric.
    private static let htmlEntityRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "&(#[0-9]+|#x[0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]+);",
        options: []
    )
    /// Lookup table for the small set of named HTML entities the scraper supports.
    private static let namedHTMLEntities: [String: String] = [
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
    }

    /// Scrape content from a single URL
    func scrapeContent(from urlString: String, maxCharacters: Int = 5000, useVision: Bool = false) async -> String? {
        guard let url = URL(string: urlString) else { return nil }

        if useVision, let rendered = await scrapeRenderedContent(from: url, maxCharacters: maxCharacters) {
            return rendered
        }

        do {
            var request = URLRequest(url: url)
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else {
                return nil
            }

            // Extract text content from HTML
            return extractTextFromHTML(html, maxCharacters: maxCharacters)
        } catch {
            return nil
        }
    }

    /// Scrape content from multiple URLs concurrently
    func scrapeMultiplePages(urls: [String], limit: Int = 10, maxCharacters: Int = 5000, useVision: Bool = false) async -> [String: String] {
        isScrapingContent = true
        defer { isScrapingContent = false }

        let targetSuccessCount = max(0, limit)
        guard targetSuccessCount > 0 else { return [:] }

        let fetchCount = targetSuccessCount + Self.overfetchCount
        let limitedURLs = Array(urls.prefix(fetchCount))
        var results: [String: String] = [:]
        var urlIterator = limitedURLs.makeIterator()
        let concurrency = useVision ? Self.renderedScrapeConcurrency : Self.scrapeConcurrency
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
                    let content = await self.scrapeContent(from: nextURL, maxCharacters: maxCharacters, useVision: useVision)
                    return (nextURL, content)
                }
            }

            for await (url, content) in group {
                #if DEBUG
                completedTasks += 1
                #endif

                if let content = content {
                    results[url] = content
                    // Keep the fastest successful pages only.
                    if results.count >= targetSuccessCount {
                        #if DEBUG
                        didEarlyCancel = completedTasks < limitedURLs.count
                        #endif
                        group.cancelAll()
                        break
                    }
                }

                if let nextURL = urlIterator.next() {
                    #if DEBUG
                    launchedTasks += 1
                    #endif
                    group.addTask {
                        let content = await self.scrapeContent(from: nextURL, maxCharacters: maxCharacters, useVision: useVision)
                        return (nextURL, content)
                    }
                }
            }
        }

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

    static func renderedPageText(
        from analyses: [ImageAnalysisService.PDFPageAnalysisResult],
        maxCharacters: Int
    ) -> String {
        var sections: [String] = []
        for (pageIndex, analysis) in analyses.enumerated() {
            var pageSections: [String] = []
            let recognizedText = analysis.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !recognizedText.isEmpty {
                pageSections.append(recognizedText)
            }
            if !analysis.labels.isEmpty {
                let labelText = analysis.labels
                    .map { String(format: "%@ (%.2f)", $0.label, $0.confidence) }
                    .joined(separator: ", ")
                pageSections.append("Visual content: \(labelText)")
            }
            guard !pageSections.isEmpty else { continue }
            sections.append("[Rendered webpage page \(pageIndex + 1)]\n" + pageSections.joined(separator: "\n\n"))
        }

        var text = RAGChunker.convertWhitespaceAlignedTables(sections.joined(separator: "\n\n"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > maxCharacters {
            text = String(text.prefix(maxCharacters))
        }
        return text
    }

    /// Extract readable text content from HTML using cached regexes.
    private func extractTextFromHTML(_ html: String, maxCharacters: Int = 5000) -> String {
        var text = html

        // 0. Convert `<table>` blocks to Markdown pipe tables *before* the
        //    generic tag stripper flattens them. Numeric stats pages rely
        //    almost entirely on tables, and the model handles `| col |`
        //    layouts far better than space-separated rubble.
        text = Self.extractAndReplaceTables(text)
        // 1. Strip script/style/nav/header/footer blocks (and their content) in one alternation pass.
        text = Self.applyRegex(Self.nonContentBlockRegex, to: text, replacement: "")
        // 2. Strip HTML comments.
        text = Self.applyRegex(Self.htmlCommentRegex, to: text, replacement: "")
        // 3. Strip any remaining tags, replacing them with a space so adjacent words don't merge.
        text = Self.applyRegex(Self.htmlTagRegex, to: text, replacement: " ")
        // 4. Decode common HTML entities (named + numeric + hex) in a single pass.
        text = Self.decodeHTMLEntities(text)
        // 5. Collapse whitespace runs. Use the chunker's whitespace normaliser
        //    so newlines (paragraph + table-row boundaries) survive the
        //    pipeline — the chunker uses those as preferred split points.
        text = RAGChunker.normalizeWhitespace(text)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 6. Cap length. `String.prefix(_:)` operates on extended grapheme
        // clusters in Swift's `String`, so this slice is grapheme-safe and
        // never splits a Unicode cluster — do not downgrade this to UTF-16
        // or UnicodeScalar slicing.
        if text.count > maxCharacters {
            text = String(text.prefix(maxCharacters))
        }

        return text
    }

    /// Finds every `<table>` in `html`, converts it to a Markdown pipe table,
    /// and splices the result back into the document — surrounded by blank
    /// lines so it forms its own paragraph block. Surviving `\n` characters
    /// later guide the RAG chunker toward row-aligned split points.
    static func extractAndReplaceTables(_ html: String) -> String {
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

    #if canImport(WebKit)
    private enum RenderedScrapeError: Error {
        case loadTimedOut
        case invalidDocumentMetrics
    }

    private final class NavigationDelegate: NSObject, WKNavigationDelegate {
        var continuation: CheckedContinuation<Void, Error>?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            resume(.success(()))
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            guard !Self.isBenignNavigationCancellation(error) else { return }
            resume(.failure(error))
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            guard !Self.isBenignNavigationCancellation(error) else { return }
            resume(.failure(error))
        }

        private func resume(_ result: Result<Void, Error>) {
            guard let continuation else { return }
            self.continuation = nil
            switch result {
            case .success:
                continuation.resume()
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }

        private static func isBenignNavigationCancellation(_ error: Error) -> Bool {
            let nsError = error as NSError
            return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
        }
    }

    private func scrapeRenderedContent(from url: URL, maxCharacters: Int) async -> String? {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: CGRect(origin: .zero, size: Self.webVisionViewport), configuration: configuration)
        webView.customUserAgent = Self.userAgent

        do {
            try await load(webView: webView, url: url)
            try await Task.sleep(nanoseconds: Self.webVisionSettleNanoseconds)
            let contentRect = try await renderedContentRect(for: webView)
            let pdfData = try await createPDF(from: webView, rect: contentRect)
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("pdf")
            defer {
                try? FileManager.default.removeItem(at: tempURL)
            }
            try pdfData.write(to: tempURL, options: .atomic)

            let analyses = await ImageAnalysisService.extractPDFPageAnalyses(from: tempURL)
            let rendered = Self.renderedPageText(from: analyses, maxCharacters: maxCharacters)
            return rendered.isEmpty ? nil : rendered
        } catch {
            guard !Self.isBenignRenderedScrapeError(error) else {
                return nil
            }
            #if DEBUG
            print("[WebScrapingService] Rendered scrape failed for \(url.absoluteString): \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    private func load(webView: WKWebView, url: URL) async throws {
        let delegate = NavigationDelegate()
        webView.navigationDelegate = delegate

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                try await withCheckedThrowingContinuation { continuation in
                    delegate.continuation = continuation
                    var request = URLRequest(url: url)
                    request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
                    webView.load(request)
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: Self.webVisionLoadTimeoutNanoseconds)
                throw RenderedScrapeError.loadTimedOut
            }

            do {
                _ = try await group.next()
                group.cancelAll()
            } catch {
                await MainActor.run {
                    webView.stopLoading()
                    delegate.continuation?.resume(throwing: error)
                    delegate.continuation = nil
                }
                group.cancelAll()
                throw error
            }
        }
    

    private func renderedContentRect(for webView: WKWebView) async throws -> CGRect {
        let raw = try await evaluateJavaScript(
            on: webView,
            script: """
            [
              Math.max(document.documentElement.scrollWidth, document.body ? document.body.scrollWidth : 0, window.innerWidth),
              Math.max(document.documentElement.scrollHeight, document.body ? document.body.scrollHeight : 0, window.innerHeight)
            ]
            """
        )
        guard let metrics = raw as? [NSNumber], metrics.count == 2 else {
            throw RenderedScrapeError.invalidDocumentMetrics
        }
        return CGRect(
            origin: .zero,
            size: CGSize(
                width: max(CGFloat(truncating: metrics[0]), Self.webVisionViewport.width),
                height: min(
                    max(CGFloat(truncating: metrics[1]), Self.webVisionViewport.height),
                    Self.webVisionViewport.height * Self.webVisionMaxRenderedPages
                )
            )
        )
    }

    private func evaluateJavaScript(on webView: WKWebView, script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    private func createPDF(from webView: WKWebView, rect: CGRect) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let configuration = WKPDFConfiguration()
            configuration.rect = rect
            webView.createPDF(configuration: configuration) { result in
                switch result {
                case .success(let data):
                    continuation.resume(returning: data)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func isBenignRenderedScrapeError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return true
        }

        return false
    }
    #endif

    /// Converts the inner HTML of a `<table>` element to a Markdown pipe
    /// table. Empty input → empty output. Uneven row lengths are padded.
    /// Cell text has nested tags stripped and pipe characters escaped so the
    /// resulting Markdown is well-formed.
    static func convertTableToMarkdown(_ tableInnerHTML: String) -> String {
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
    private static func sanitizeCellText(_ text: String) -> String {
        var t = text
        t = applyRegex(htmlTagRegex, to: t, replacement: " ")
        t = decodeHTMLEntities(t)
        t = applyRegex(whitespaceRunRegex, to: t, replacement: " ")
        t = t.replacingOccurrences(of: "|", with: "\\|")
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Applies a cached regex with `replacement` over the full string. No-op when the regex is nil.
    private static func applyRegex(_ regex: NSRegularExpression?, to text: String, replacement: String) -> String {
        guard let regex else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }

    /// Single-pass entity decoder: walks `&...;` references in order and
    /// substitutes named, decimal-numeric (`&#nnn;`), and hex-numeric
    /// (`&#xNN;`) entities. Unknown references pass through unchanged.
    private static func decodeHTMLEntities(_ text: String) -> String {
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
    private static func decodeEntityToken(_ token: String) -> String? {
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
