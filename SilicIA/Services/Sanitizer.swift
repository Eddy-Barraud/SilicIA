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
        sanitized = insertBoundarySpacesForKnownCommands(in: sanitized)
        sanitized = replacingDigitPowers(in: sanitized)
        // sanitized = closeUnbalancedMathDelimiters(in: sanitized)
        sanitized = replacingMarkdownTitles(in: sanitized)
        return sanitized
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
    /// Rule (open/close aware): we scan left-to-right tracking whether we are
    /// inside an inline `$ … $` span. A `$` is escaped ONLY when it is NOT a
    /// math delimiter:
    ///   - if inline math is OPEN, the next `$` is its CLOSING delimiter —
    ///     never escaped, even when it follows a digit (e.g. the closing `$`
    ///     in `$a_3$`). This is the bug the old digit-adjacency regex caused:
    ///     it escaped `a_3$`'s closing `$`, mis-pairing every following span
    ///     and garbling the render.
    ///   - if math is CLOSED, a `$` adjacent to a digit (`$5`, `5$`) is
    ///     currency → escaped; otherwise it OPENS a math span.
    /// `$$` (display math) and already-escaped `\$` are passed through.
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
