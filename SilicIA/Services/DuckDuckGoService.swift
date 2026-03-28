//
//  DuckDuckGoService.swift
//  SilicIA
//
//  Created by Claude on 23/03/2026.
//

import Foundation
import Combine

/// Strip HTML tags and decode common HTML entities from a raw HTML string.
private func htmlToPlainText(_ html: String) -> String {
    // Remove all HTML tags
    var result = html
    if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
        result = regex.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: ""
        )
    }
    // Decode HTML entities
    let entities: [(String, String)] = [
        ("&amp;",  "&"),
        ("&lt;",   "<"),
        ("&gt;",   ">"),
        ("&quot;", "\""),
        ("&#x27;", "'"),
        ("&#39;",  "'"),
        ("&apos;", "'"),
        ("&nbsp;", " "),
        ("&mdash;", "—"),
        ("&ndash;", "–"),
        ("&hellip;", "…"),
        ("&laquo;", "«"),
        ("&raquo;", "»"),
    ]
    for (entity, char) in entities {
        result = result.replacingOccurrences(of: entity, with: char)
    }
    // Decode numeric decimal entities like &#8230;
    if let numericRegex = try? NSRegularExpression(pattern: "&#(\\d+);", options: []) {
        let matches = numericRegex.matches(
            in: result,
            range: NSRange(result.startIndex..., in: result)
        ).reversed()
        for match in matches {
            if let range = Range(match.range(at: 1), in: result),
               let codePoint = Int(result[range]),
               let scalar = Unicode.Scalar(codePoint) {
                let fullRange = Range(match.range, in: result)!
                result = result.replacingCharacters(in: fullRange, with: String(scalar))
            }
        }
    }
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Extract the inner HTML for the first element matching a class name and tag.
private func extractInnerHTML(in html: String, className: String, tagName: String) -> String? {
    let escapedClassName = NSRegularExpression.escapedPattern(for: className)
    let escapedTagName = NSRegularExpression.escapedPattern(for: tagName)
    let pattern = "<\(escapedTagName)[^>]*class=\"[^\"]*\\b\(escapedClassName)\\b[^\"]*\"[^>]*>([\\s\\S]*?)</\(escapedTagName)>"

    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
        return nil
    }
    let range = NSRange(html.startIndex..., in: html)
    guard let match = regex.firstMatch(in: html, options: [], range: range),
          let contentRange = Range(match.range(at: 1), in: html) else {
        return nil
    }
    return String(html[contentRange])
}

@MainActor
/// Performs DuckDuckGo HTML search and parses result cards.
class DuckDuckGoService: ObservableObject {
    @Published var isSearching = false
    @Published var error: Error?

    private let session: URLSession

    /// Creates a search session configured for efficient DuckDuckGo requests.
    init() {
        // Configure URLSession for efficient power usage
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = true
        config.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: config)
    }

    /// Search DuckDuckGo using their HTML API
    func search(query: String, maxResults: Int = 10) async throws -> [SearchResult] {
        guard !query.isEmpty else { return [] }

        isSearching = true
        defer { isSearching = false }

        // Use DuckDuckGo HTML search (more efficient than scraping)
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://html.duckduckgo.com/html/?q=\(encodedQuery)"

        guard let url = URL(string: urlString) else {
            throw SearchError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SearchError.invalidResponse
        }

        // Parse HTML results
        let results = try parseHTMLResults(from: data, query: query)
        return Array(results.prefix(maxResults)) // Limit to user-configured max results
    }

    /// Parse DuckDuckGo HTML response
    private func parseHTMLResults(from data: Data, query: String) throws -> [SearchResult] {
        guard let html = String(data: data, encoding: .utf8) else {
            throw SearchError.parsingFailed
        }

        var results: [SearchResult] = []

        // Simple HTML parsing - look for result blocks
        // DuckDuckGo HTML structure: results are in divs with class "result"
        let components = html.components(separatedBy: "class=\"result__a\"")

        for i in 1..<min(components.count, 11) {
            let component = components[i]

            // Extract URL
            guard let hrefRange = component.range(of: "href=\""),
                  let hrefEndRange = component.range(of: "\"", range: hrefRange.upperBound..<component.endIndex) else {
                continue
            }
            let url = String(component[hrefRange.upperBound..<hrefEndRange.lowerBound])

            // Extract title
            guard let titleStart = component.range(of: ">"),
                  let titleEnd = component.range(of: "</a>", range: titleStart.upperBound..<component.endIndex) else {
                continue
            }
            let title = htmlToPlainText(String(component[titleStart.upperBound..<titleEnd.lowerBound]))

            // Extract snippet. The snippet may include nested tags (<b>, <span>, etc.);
            // capture the full element content instead of stopping at the first closing tag.
            let snippetHTML = extractInnerHTML(in: component, className: "result__snippet", tagName: "a")
                ?? extractInnerHTML(in: component, className: "result__snippet", tagName: "div")
                ?? ""
            let snippet = htmlToPlainText(snippetHTML)

            // Clean up URL (DuckDuckGo redirects)
            let cleanURL = url.hasPrefix("//duckduckgo.com/l/?") ? extractActualURL(from: url) : url

            results.append(SearchResult(
                title: title.isEmpty ? "Result \(i)" : title,
                url: cleanURL,
                snippet: snippet.isEmpty ? "No description available" : snippet
            ))
        }

        return results
    }

    /// Extract actual URL from DuckDuckGo redirect
    private func extractActualURL(from ddgURL: String) -> String {
        guard let uddParam = ddgURL.components(separatedBy: "uddg=").last,
              let actualURL = uddParam.components(separatedBy: "&").first,
              let decoded = actualURL.removingPercentEncoding else {
            return ddgURL
        }
        return decoded
    }
}

/// Enumerates high-level search failure categories.
enum SearchError: LocalizedError {
    case invalidURL
    case invalidResponse
    case parsingFailed
    case networkError

    /// Provides user-facing descriptions for search errors.
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid search URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .parsingFailed:
            return "Failed to parse search results"
        case .networkError:
            return "Network error occurred"
        }
    }
}
