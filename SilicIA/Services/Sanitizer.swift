//
//  Sanitizer.swift
//  SilicIA
//
//  Created by Claude on [date].
//

import Foundation

/// Sanitizes LaTeX output to ensure proper rendering in the UI.
enum ModelOutputLaTeXSanitizer {
    
    /// Final sanitization of accumulated text
    static func finalizeSanitizedText(_ text: String) -> String {
        var sanitized = text
        // Escape currency `$` BEFORE any other transformation so subsequent
        // passes don't accidentally treat `$1025.75` as the start of an
        // unterminated inline-math block (which silently swallows the rest
        // of the message into garbled math).
        sanitized = escapeCurrencyDollars(in: sanitized)
        // Unwrap inline math whose content is "trivial" (digits, parens,
        // commas, basic operators — no letters/sub/superscripts). LaTeXSwiftUI
        // scales inline math by the rendered x-height, which it miscomputes
        // for content with no x-height letters (e.g. `\((0, 0), (1, 1)\)`),
        // rendering it oversized. Such content reads identically as plain
        // text, so we strip the delimiters and dodge the scaling bug.
        sanitized = unwrapTrivialInlineMath(in: sanitized)
        sanitized = insertBoundarySpacesForKnownCommands(in: sanitized)
        sanitized = replacingDigitPowers(in: sanitized)
        // sanitized = closeUnbalancedMathDelimiters(in: sanitized)
        sanitized = replacingMarkdownTitles(in: sanitized)
        return sanitized
    }

    /// Characters allowed in "trivial" inline math (renders identically as
    /// plain text). Excludes letters, `^`, `_`, `{`, `}`, `\` — anything that
    /// genuinely needs math typesetting (variables, sub/superscripts, frac…).
    private static let trivialMathCharacters = CharacterSet(charactersIn: "0123456789 \t(),.-+=*/:|")

    /// Matches an inline `\( ... \)` block (non-greedy). The inner parens are
    /// plain `(` `)`, distinct from the `\(` `\)` delimiters, so the lazy
    /// match stops at the first `\)`.
    private static let inlineParenMathRegex = try? NSRegularExpression(
        pattern: #"\\\((.*?)\\\)"#,
        options: [.dotMatchesLineSeparators]
    )

    /// Replaces `\(trivial\)` inline math with its bare content; leaves any
    /// inline math that needs real typesetting untouched.
    static func unwrapTrivialInlineMath(in text: String) -> String {
        guard let regex = inlineParenMathRegex else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }

        var result = ""
        var cursor = 0
        for match in matches {
            let full = match.range
            result += ns.substring(with: NSRange(location: cursor, length: full.location - cursor))
            let inner = ns.substring(with: match.range(at: 1))
            if isTrivialMath(inner) {
                result += inner
            } else {
                result += ns.substring(with: full)
            }
            cursor = full.location + full.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    /// Trivial = at least one digit and every character drawn from
    /// `trivialMathCharacters` (so no variables, fractions, or scripts).
    private static func isTrivialMath(_ inner: String) -> Bool {
        guard inner.contains(where: { $0.isNumber }) else { return false }
        return inner.unicodeScalars.allSatisfy { trivialMathCharacters.contains($0) }
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
    ///
    /// Rule: a `$` is treated as currency (and escaped) when it sits
    /// immediately adjacent to a digit on either side, AND it's not already
    /// escaped (`\$`) nor part of a `$$` display-math marker. This catches
    /// the common forms `$1025`, `1025$`, `$1.50`, and `**$100**` while
    /// leaving genuine math `$x + 2$`, `$\frac{1}{2}$`, and `$$E = mc^2$$`
    /// alone.
    static func escapeCurrencyDollars(in text: String) -> String {
        var output = text
        // Prefix form: `$<digit>` — e.g. `$1025.75`.
        // `(?<![\\$])` excludes `\$` (already escaped) and the trailing `$`
        // of a display-math `$$` opener.
        output = replacingRegex(
            in: output,
            pattern: #"(?<![\\$])\$(?=\d)"#,
            with: #"\\$"#
        )
        // Suffix form: `<digit>$` — common in French (`1025$`).
        // `(?![\\$\d])` excludes `$\` (a math command), `$$` (display-math
        // close), and `$<digit>` (already handled by the prefix pass which
        // would have escaped it; re-matching would double-escape).
        output = replacingRegex(
            in: output,
            pattern: #"(?<=\d)\$(?![\\$\d])"#,
            with: #"\\$"#
        )
        return output
    }

    private static func insertBoundarySpacesForKnownCommands(in text: String) -> String {
        var output = text
        let commands = ["per", "mathrm", "text", "frac", "sqrt", "sum", "int", "lim", "infty", "partial", "nabla", "cdot", "times", "pm", "mp", "geq", "leq", "neq", "approx", "equiv", "alpha", "beta", "gamma", "delta", "theta", "lambda", "mu", "pi", "sigma", "phi"]

        for command in commands {
            output = replacingRegex(
                in: output,
                pattern: #"(?<!\s)(\\"# + command + #")"#,
                with: " $1"
            )
            output = replacingRegex(
                in: output,
                pattern: #"(\\"# + command + #")(?=[A-Za-z0-9])"#,
                with: "$1 "
            )
        }

        return output
    }

    
    private static func replacingMarkdownTitles(in text: String) -> String {
        var output = text
        // Replace markdown titles like ## Title ## with **Title**
        output = replacingRegex(
            in: output,
            pattern: #"(?m)^\s*#{1,6}\s*(.+?)\s*#{0,6}\s*$"#,
            with: "**$1**"
        )
        // Replace markdown titles like # Title with **Title**
        output = replacingRegex(
            in: output,
            pattern: #"(?m)^\s*#{1,6}\s*(.+?)\s*$"#,
            with: "**$1**"
        )

        return output
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
            output.replaceSubrange(wholeRange, with: "\\mathrm{\(base)}^\\mathrm{\(exponent)}")
        }
        return output
    }

    private static func closeUnbalancedMathDelimiters(in text: String) -> String {
        var singleDollarCount = 0
        var doubleDollarCount = 0
        var openParenCount = 0
        var closeParenCount = 0
        var openBracketCount = 0
        var closeBracketCount = 0

        let characters = Array(text)
        var index = 0

        while index < characters.count {
            let current = characters[index]

            if current == "\\" {
                if index + 1 < characters.count {
                    let next = characters[index + 1]
                    if next == "(" {
                        openParenCount += 1
                        index += 2
                        continue
                    }
                    if next == ")" {
                        closeParenCount += 1
                        index += 2
                        continue
                    }
                    if next == "[" {
                        openBracketCount += 1
                        index += 2
                        continue
                    }
                    if next == "]" {
                        closeBracketCount += 1
                        index += 2
                        continue
                    }
                    if next == "$" {
                        index += 2
                        continue
                    }
                }
                index += 1
                continue
            }

            if current == "$" {
                if index + 1 < characters.count, characters[index + 1] == "$" {
                    doubleDollarCount += 1
                    index += 2
                } else {
                    singleDollarCount += 1
                    index += 1
                }
                continue
            }

            index += 1
        }

        var output = text
        if doubleDollarCount % 2 != 0 {
            output += "$$"
        }
        if singleDollarCount % 2 != 0 {
            output += "$"
        }
        if openParenCount > closeParenCount {
            output += String(repeating: "\\)", count: openParenCount - closeParenCount)
        }
        if openBracketCount > closeBracketCount {
            output += String(repeating: "\\]", count: openBracketCount - closeBracketCount)
        }

        return output
    }

    private static func replacingRegex(in text: String, pattern: String, with template: String) -> String {
        text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
    }
    
}
