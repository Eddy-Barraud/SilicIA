//
//  HTMLSanitizer.swift
//  SilicIA
//
//  Created by Copilot on 21/09/2026.
//

import Foundation

/// Fast HTML tag stripper and entity decoder shared across WebSearchService and WebScrapingService.
enum HTMLSanitizer: Sendable {

    private nonisolated static let htmlCommentRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "<!--[\\s\\S]*?-->",
        options: []
    )

    private nonisolated static let htmlTagRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "<[^>]+>",
        options: []
    )

    private nonisolated static let htmlEntityRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "&(#[0-9]+|#x[0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]+);",
        options: []
    )

    private nonisolated static let htmlBlockTagRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "</?(?:p|div|section|article|header|footer|h[1-6]|table|tr|blockquote)[^>]*>",
        options: [.caseInsensitive]
    )

    private nonisolated static let htmlBreakTagRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "<br\\s*/?>|</?li[^>]*>",
        options: [.caseInsensitive]
    )

    private nonisolated static let multipleNewlineRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "\n{3,}",
        options: []
    )

    private nonisolated static let namedEntities: [String: String] = [
        "nbsp": " ",
        "amp": "&",
        "lt": "<",
        "gt": ">",
        "quot": "\"",
        "apos": "'",
        "copy": "©",
        "reg": "®",
        "trade": "™",
        "mdash": "—",
        "ndash": "–",
        "hellip": "…",
        "laquo": "«",
        "raquo": "»",
        "lsquo": "‘",
        "rsquo": "’",
        "ldquo": "“",
        "rdquo": "”",
        "deg": "°",
        "plusmn": "±",
        "times": "×",
        "divide": "÷",
        "ne": "≠",
        "le": "≤",
        "ge": "≥",
        "infin": "∞",
        "para": "¶",
        "sect": "§",
        "bull": "•",
        "euro": "€",
        "pound": "£",
        "yen": "¥",
        "cent": "¢"
    ]

    /// Decodes HTML entities (named, decimal-numeric &#nnn;, and hex-numeric &#xNN;) in a single pass.
    nonisolated static func decodeEntities(_ text: String) -> String {
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

    private nonisolated static func decodeEntityToken(_ token: String) -> String? {
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
        return namedEntities[token]
    }

    /// Strips HTML comments and tags, replacing tags with spaces, and decodes HTML entities.
    nonisolated static func htmlToPlainText(_ html: String) -> String {
        var text = html
        if let commentRegex = htmlCommentRegex {
            text = commentRegex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: ""
            )
        }
        if let tagRegex = htmlTagRegex {
            text = tagRegex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: " "
            )
        }
        return decodeEntities(text)
    }

    /// Strips HTML comments and tags while converting block tags into newlines,
    /// preserving paragraph and list structure suitable for RAG chunking.
    nonisolated static func htmlToPlainTextWithStructure(_ html: String) -> String {
        var text = html
        if let commentRegex = htmlCommentRegex {
            text = commentRegex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: ""
            )
        }
        if let breakRegex = htmlBreakTagRegex {
            text = breakRegex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: "\n"
            )
        }
        if let blockRegex = htmlBlockTagRegex {
            text = blockRegex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: "\n\n"
            )
        }
        if let tagRegex = htmlTagRegex {
            text = tagRegex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: " "
            )
        }
        text = decodeEntities(text)
        let lines = text.components(separatedBy: "\n").map { line in
            line.replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        text = lines.joined(separator: "\n")
        if let newlineRegex = multipleNewlineRegex {
            text = newlineRegex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: "\n\n"
            )
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strips HTML tags only.
    nonisolated static func stripTags(_ text: String, replacement: String = "") -> String {
        guard let tagRegex = htmlTagRegex else { return text }
        return tagRegex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: replacement
        )
    }
}

