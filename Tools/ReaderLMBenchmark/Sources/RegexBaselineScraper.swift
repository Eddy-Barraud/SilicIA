import Foundation

/// Fast baseline HTML-to-text / pipe-table converter reflecting SilicIA's WebScrapingService
public enum RegexBaselineScraper {
    private static let nonContentBlockRegex = try? NSRegularExpression(
        pattern: "<(script|style|nav|header|footer)[^>]*>[\\s\\S]*?</\\1>",
        options: [.caseInsensitive]
    )
    /// Non-content elements including heavy inline SVG icon sprites and document heads.
    /// Stripping SVG is critical: modern web pages embed 200KB+ of SVG icon paths inside `<body>`
    /// before the actual article text begins.
    private static let precleanBlockRegex = try? NSRegularExpression(
        pattern: "<(script|style|nav|header|footer|svg|head)[^>]*>[\\s\\S]*?</\\1>",
        options: [.caseInsensitive]
    )
    private static let tableBlockRegex = try? NSRegularExpression(
        pattern: "<table[^>]*>([\\s\\S]*?)</table>",
        options: [.caseInsensitive]
    )
    private static let tableRowRegex = try? NSRegularExpression(
        pattern: "<tr[^>]*>([\\s\\S]*?)</tr>",
        options: [.caseInsensitive]
    )
    private static let tableCellRegex = try? NSRegularExpression(
        pattern: "<(t[dh])[^>]*>([\\s\\S]*?)</\\1>",
        options: [.caseInsensitive]
    )
    private static let htmlCommentRegex = try? NSRegularExpression(
        pattern: "<!--[\\s\\S]*?-->",
        options: []
    )
    private static let htmlTagRegex = try? NSRegularExpression(
        pattern: "<[^>]+>",
        options: []
    )
    private static let whitespaceRunRegex = try? NSRegularExpression(
        pattern: "\\s+",
        options: []
    )
    private static let htmlEntityRegex = try? NSRegularExpression(
        pattern: "&(#[0-9]+|#x[0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]+);",
        options: []
    )
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

    /// Strips non-content boilerplate (scripts, styles, SVGs, head, comments) while preserving
    /// complete article HTML structure (headings, paragraphs, lists, tables, images, links).
    /// Does not truncate by character length when maxCharacters is 0.
    public static func precleanHTMLForMarkdown(_ html: String, maxCharacters: Int = 0) -> String {
        var text = html
        text = applyRegex(precleanBlockRegex, to: text, replacement: "")
        text = applyRegex(htmlCommentRegex, to: text, replacement: "")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if maxCharacters > 0 && text.count > maxCharacters {
            text = String(text.prefix(maxCharacters))
        }
        return text
    }

    public static func extractMarkdown(from html: String, maxCharacters: Int = 10000) -> String {
        var text = html
        text = extractAndReplaceTables(text)
        text = applyRegex(nonContentBlockRegex, to: text, replacement: "")
        text = applyRegex(htmlCommentRegex, to: text, replacement: "")
        text = applyRegex(htmlTagRegex, to: text, replacement: " ")
        text = decodeHTMLEntities(text)
        text = applyRegex(whitespaceRunRegex, to: text, replacement: " ")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > maxCharacters {
            text = String(text.prefix(maxCharacters))
        }
        return text
    }

    private static func extractAndReplaceTables(_ html: String) -> String {
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

    private static func convertTableToMarkdown(_ tableInnerHTML: String) -> String {
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

    private static func sanitizeCellText(_ text: String) -> String {
        var t = text
        t = applyRegex(htmlTagRegex, to: t, replacement: " ")
        t = decodeHTMLEntities(t)
        t = applyRegex(whitespaceRunRegex, to: t, replacement: " ")
        t = t.replacingOccurrences(of: "|", with: "\\|")
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func applyRegex(_ regex: NSRegularExpression?, to text: String, replacement: String) -> String {
        guard let regex else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }

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
            guard let codePoint = UInt32(digits),
                  let scalar = Unicode.Scalar(codePoint) else {
                return nil
            }
            return String(scalar)
        }
        return namedHTMLEntities[token]
    }
}
