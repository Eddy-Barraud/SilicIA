//
//  WebScrapingService.swift
//  SilicIA
//
//  Created by Claude on 23/03/2026.
//

import Foundation
import Combine
#if os(iOS)
import UIKit
#endif

@MainActor
/// Fetches and extracts readable text content from web pages.
class WebScrapingService: ObservableObject {
    /// App-specific User-Agent identifying SilicIA. Update version/contact as needed.
    /// Format recommendation: AppName/Version (Platform; Device) Engine; +ContactURL
    private static let userAgent: String = {
        // You can optionally make these dynamic using Bundle info and UIDevice.
        let appName = "SilicIA"
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
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
    private static let overfetchCount = 3

    // MARK: - Cached HTML regexes (compiled once, reused per scrape)

    /// Strips `<script>`, `<style>`, `<nav>`, `<header>`, and `<footer>` blocks (and content) in one pass.
    private static let nonContentBlockRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "<(script|style|nav|header|footer)[^>]*>[\\s\\S]*?</\\1>",
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
    func scrapeContent(from urlString: String, maxCharacters: Int = 5000) async -> String? {
        guard let url = URL(string: urlString) else { return nil }

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
    func scrapeMultiplePages(urls: [String], limit: Int = 10, maxCharacters: Int = 5000) async -> [String: String] {
        isScrapingContent = true
        defer { isScrapingContent = false }

        let targetSuccessCount = max(0, limit)
        guard targetSuccessCount > 0 else { return [:] }

        let fetchCount = targetSuccessCount + Self.overfetchCount
        let limitedURLs = Array(urls.prefix(fetchCount))
        var results: [String: String] = [:]
        var urlIterator = limitedURLs.makeIterator()
        let initialWorkers = min(Self.scrapeConcurrency, limitedURLs.count)

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
                        let content = await self.scrapeContent(from: nextURL, maxCharacters: maxCharacters)
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
            poolSize: Self.scrapeConcurrency,
            overfetchCount: Self.overfetchCount,
            didEarlyCancel: didEarlyCancel,
            elapsedSeconds: Date().timeIntervalSince(scrapeStart)
        )
        #endif

        return results
    }

    /// Extract readable text content from HTML using cached regexes.
    private func extractTextFromHTML(_ html: String, maxCharacters: Int = 5000) -> String {
        var text = html

        // 1. Strip script/style/nav/header/footer blocks (and their content) in one alternation pass.
        text = Self.applyRegex(Self.nonContentBlockRegex, to: text, replacement: "")
        // 2. Strip HTML comments.
        text = Self.applyRegex(Self.htmlCommentRegex, to: text, replacement: "")
        // 3. Strip any remaining tags, replacing them with a space so adjacent words don't merge.
        text = Self.applyRegex(Self.htmlTagRegex, to: text, replacement: " ")
        // 4. Decode common HTML entities (named + numeric + hex) in a single pass.
        text = Self.decodeHTMLEntities(text)
        // 5. Collapse whitespace runs.
        text = Self.applyRegex(Self.whitespaceRunRegex, to: text, replacement: " ")
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

