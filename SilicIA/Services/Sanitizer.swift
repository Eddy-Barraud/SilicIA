//
//  Sanitizer.swift
//  SilicIA
//
//  Created by Claude on [date].
//

import Foundation

/// Sanitizes LaTeX output to ensure proper rendering in the UI.
enum ModelOutputLaTeXSanitizer {
    
    // MARK: - Precompiled Regexes

    private static let knownCommandsAlternation = "per|mathrm|text|frac|sqrt|sum|int|lim|infty|partial|nabla|cdot|times|pm|mp|geq|leq|neq|approx|equiv|alpha|beta|gamma|delta|theta|lambda|mu|pi|sigma|phi"

    private static let commandLeadingBoundaryRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?<!\s)(\\(?:"# + knownCommandsAlternation + #"))"#,
        options: []
    )

    private static let commandTrailingBoundaryRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(\\(?:"# + knownCommandsAlternation + #"))(?=[A-Za-z0-9])"#,
        options: []
    )

    private static let markdownTitleRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?m)^\s*#{1,6}\s*(.+?)\s*#{0,6}\s*$"#,
        options: []
    )

    private static let documentClassRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?m)^\s*\\documentclass(?:\[[^\]]*\])?\{[^}]*\}\s*$"#,
        options: []
    )

    private static let usePackageRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?m)^\s*\\usepackage(?:\[[^\]]*\])?\{[^}]*\}\s*$"#,
        options: []
    )

    // MARK: - Public API

    /// Final sanitization of accumulated text
    static func finalizeSanitizedText(_ text: String) -> String {
        var sanitized = unwrapProseArrayEnvironments(in: text)
        // Escape currency `$` BEFORE any other transformation so subsequent
        // passes don't accidentally treat `$1025.75` as the start of an
        // unterminated inline-math block (which silently swallows the rest
        // of the message into garbled math).
        sanitized = escapeCurrencyDollars(in: sanitized)
        sanitized = insertBoundarySpacesForKnownCommands(in: sanitized)
        sanitized = replacingDigitPowers(in: sanitized)
        sanitized = replacingMarkdownTitles(in: sanitized)
        return sanitized
    }

    /// Removes full LaTeX document wrappers and unwraps fake prose array environments.
    static func sanitizeLaTeXDocumentWrappers(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = unwrapProseArrayEnvironments(in: cleaned)

        if let beginRange = cleaned.range(of: "\\begin{document}"),
           let endRange = cleaned.range(of: "\\end{document}"),
           beginRange.upperBound <= endRange.lowerBound {
            cleaned = String(cleaned[beginRange.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        cleaned = applyRegex(documentClassRegex, to: cleaned)
        cleaned = applyRegex(usePackageRegex, to: cleaned)
        cleaned = cleaned.replacingOccurrences(of: "\\begin{document}", with: "")
        cleaned = cleaned.replacingOccurrences(of: "\\end{document}", with: "")

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Unwraps fake LaTeX math arrays that models sometimes use to wrap ordinary prose or bullet points
    /// (e.g. `\[\begin{array}{l} \text{...} \\ \text{...} \end{array}\]`).
    static func unwrapProseArrayEnvironments(in text: String) -> String {
        guard text.contains("\\begin{array}") else { return text }
        let pattern = #"(?s)(?:\\\[\s*)?\\begin\{array\}\{[^}]*\}\s*(.*?)\s*(?:\\end\{array\}\s*(?:\\\])?|\\\])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return text }

        var output = text
        for match in matches.reversed() {
            guard let contentRange = Range(match.range(at: 1), in: output),
                  let wholeRange = Range(match.range(at: 0), in: output) else { continue }
            let body = String(output[contentRange])
            guard body.contains(#"\text{"#) || body.contains(#"\bullet"#) else { continue }

            let rows = body.components(separatedBy: "\\\\")
            var unwrappedRows: [String] = []
            for row in rows {
                var cleanedRow = row.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanedRow.isEmpty else { continue }
                let isBullet = cleanedRow.contains(#"\bullet"#)
                cleanedRow = cleanedRow.replacingOccurrences(of: #"\bullet"#, with: "")

                cleanedRow = unwrapTextCommands(in: cleanedRow)
                cleanedRow = cleanedRow.replacingOccurrences(of: #"\}+\s*$"#, with: "", options: .regularExpression)
                cleanedRow = cleanedRow.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanedRow.isEmpty else { continue }

                if isBullet {
                    unwrappedRows.append("- \(cleanedRow)")
                } else {
                    unwrappedRows.append(cleanedRow)
                }
            }
            let replacement = unwrappedRows.joined(separator: "\n\n")
            output.replaceSubrange(wholeRange, with: replacement)
        }
        return output
    }

    private static func unwrapTextCommands(in text: String) -> String {
        let pattern = #"\\text\{((?:[^{}]|\{[^{}]*\})*)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        while let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)) {
            guard let contentRange = Range(match.range(at: 1), in: result),
                  let wholeRange = Range(match.range(at: 0), in: result) else { break }
            let content = String(result[contentRange])
            result.replaceSubrange(wholeRange, with: content)
        }
        return result
    }

    /// Escapes `$` characters that the model used as a currency symbol next
    /// to a digit, so the LaTeX renderer doesn't interpret them as inline
    /// math delimiters. Without this, a turn like
    ///
    ///     The total is **$1025.75**.
    ///
    /// renders the rest of the message as malformed math because the LaTeX
    /// parser opens an inline-math block at `$1025.75` and never finds the
    /// matching close.
    static func escapeCurrencyDollars(in text: String) -> String {
        let chars = Array(text)
        var output = ""
        output.reserveCapacity(text.count + 8)
        var inlineOpen = false
        var i = 0
        while i < chars.count {
            let c = chars[i]

            // Already-escaped `\$` — emit both, untouched.
            if c == "\\", i + 1 < chars.count, chars[i + 1] == "$" {
                output.append("\\$")
                i += 2
                continue
            }
            // `$$` display-math delimiter — pass through verbatim.
            if c == "$", i + 1 < chars.count, chars[i + 1] == "$" {
                output.append("$$")
                i += 2
                continue
            }
            if c == "$" {
                if inlineOpen {
                    // Closing delimiter — keep as-is regardless of neighbours.
                    inlineOpen = false
                    output.append("$")
                } else {
                    let prev = i > 0 ? chars[i - 1] : " "
                    let next = i + 1 < chars.count ? chars[i + 1] : " "
                    if prev.isNumber || next.isNumber {
                        // Currency (e.g. `$5`, `5$`) — escape it.
                        output.append("\\$")
                    } else {
                        // Opening delimiter of an inline math span.
                        inlineOpen = true
                        output.append("$")
                    }
                }
                i += 1
                continue
            }

            output.append(c)
            i += 1
        }
        return output
    }

    // MARK: - Private Helpers

    private static func insertBoundarySpacesForKnownCommands(in text: String) -> String {
        var output = text
        output = replacingRegex(in: output, regex: commandLeadingBoundaryRegex, with: " $1")
        output = replacingRegex(in: output, regex: commandTrailingBoundaryRegex, with: "$1 ")
        return output
    }

    private static func replacingMarkdownTitles(in text: String) -> String {
        replacingRegex(
            in: text,
            regex: markdownTitleRegex,
            with: "**$1**"
        )
    }

    private static func replacingDigitPowers(in text: String) -> String {
        var output = text
        output = replacingDigitPowerMatches(in: output, pattern: #"(?<!\\mathrm\{)(\d+)\^\{([^{}]+)\}"#)
        output = replacingDigitPowerMatches(in: output, pattern: #"(?<!\\mathrm\{)(\d+)\^(-?\d+)"#)
        return output
    }

    private static func replacingDigitPowerMatches(in text: String, pattern: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return text }

        var output = text
        for match in matches.reversed() {
            guard match.numberOfRanges >= 3,
                  let wholeRange = Range(match.range(at: 0), in: output),
                  let baseRange = Range(match.range(at: 1), in: output),
                  let exponentRange = Range(match.range(at: 2), in: output) else {
                continue
            }

            let base = String(output[baseRange])
            let exponent = String(output[exponentRange])
            output.replaceSubrange(wholeRange, with: "\\mathrm{\\(base)}^\\mathrm{\\(exponent)}")
        }
        return output
    }

    private static func replacingRegex(in text: String, regex: NSRegularExpression?, with template: String) -> String {
        guard let regex = regex else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    private static func applyRegex(_ regex: NSRegularExpression?, to text: String) -> String {
        guard let regex = regex else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }
}
