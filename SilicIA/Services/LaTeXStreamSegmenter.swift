//
//  LaTeXStreamSegmenter.swift
//  SilicIA
//
//  Finds "safe cut points" in a partially-streamed model answer — positions
//  up to which the text can be handed to the LaTeX renderer without it
//  choking on a half-written `$...$` / `\[...\]` delimiter.
//
//  A cut point is a sentence/segment boundary (a sentence terminator
//  `. ! ?` followed by whitespace/end, a newline, or the close of a display
//  block) that sits OUTSIDE any open math and where every math delimiter
//  opened so far is balanced. `StreamingLaTeXText` reveals the text one such
//  segment at a time, so each chunk it renders as LaTeX is guaranteed to
//  have well-formed math.
//

import Foundation

enum LaTeXStreamSegmenter {

    /// Returns the end offsets (character counts from the start) of each
    /// safe-to-render segment in `text`, in increasing order. The prefix
    /// `text.prefix(boundary)` is always math-balanced and ends at a natural
    /// boundary. An empty result means no complete segment exists yet (the
    /// first sentence is still streaming).
    static func safeBoundaries(_ text: String) -> [Int] {
        let chars = Array(text)
        var boundaries: [Int] = []

        var i = 0
        var bracketDepth = 0          // \[ ... \]
        var parenDepth = 0            // \( ... \)
        var inlineDollarOpen = false  // $ ... $
        var displayDollarOpen = false // $$ ... $$

        func mathOpen() -> Bool {
            bracketDepth > 0 || parenDepth > 0 || inlineDollarOpen || displayDollarOpen
        }

        func isDigit(_ c: Character) -> Bool { c.isNumber }

        while i < chars.count {
            let c = chars[i]

            // Escaped command: `\[`, `\]`, `\(`, `\)` toggle display/inline
            // math; `\$` is a literal dollar; any other `\x` is skipped whole.
            if c == "\\", i + 1 < chars.count {
                let n = chars[i + 1]
                switch n {
                case "[": bracketDepth += 1
                case "]": if bracketDepth > 0 { bracketDepth -= 1 }
                case "(": parenDepth += 1
                case ")": if parenDepth > 0 { parenDepth -= 1 }
                default: break
                }
                i += 2
                // A closed display block is itself a safe boundary even
                // without a trailing sentence terminator.
                if n == "]", !mathOpen() {
                    boundaries.append(i)
                }
                continue
            }

            if c == "$" {
                // `$$` display delimiter.
                if i + 1 < chars.count && chars[i + 1] == "$" {
                    displayDollarOpen.toggle()
                    i += 2
                    if !displayDollarOpen, !mathOpen() {
                        boundaries.append(i)
                    }
                    continue
                }
                // Single `$`. If inline math is already OPEN, this `$` is its
                // closing delimiter — always close, even if adjacent to a
                // digit (e.g. the trailing `$` in `$x = 1$`). Only when math
                // is closed do we apply the currency heuristic to decide
                // whether this `$` OPENS math or is a literal currency symbol
                // (mirroring `ModelOutputLaTeXSanitizer.escapeCurrencyDollars`,
                // which escapes `$` adjacent to a digit like `$5.00` / `5$`).
                if inlineDollarOpen {
                    inlineDollarOpen = false
                } else {
                    let prev = i > 0 ? chars[i - 1] : " "
                    let next = i + 1 < chars.count ? chars[i + 1] : " "
                    let isCurrency = isDigit(prev) || isDigit(next)
                    if !isCurrency {
                        inlineDollarOpen = true
                    }
                }
                i += 1
                continue
            }

            // Sentence terminator outside math, followed by whitespace/end.
            if (c == "." || c == "!" || c == "?"), !mathOpen() {
                let next = i + 1 < chars.count ? chars[i + 1] : " "
                let atBoundary = next == " " || next == "\n" || next == "\r" || next == "\t" || i + 1 == chars.count
                if atBoundary {
                    boundaries.append(i + 1)
                }
                i += 1
                continue
            }

            // Hard line break outside math is also a safe boundary.
            if c == "\n", !mathOpen() {
                boundaries.append(i + 1)
                i += 1
                continue
            }

            i += 1
        }

        // De-duplicate while preserving order (a `.` immediately before a
        // `\n`, or a display close at a sentence end, can register twice).
        var seen = Set<Int>()
        return boundaries.filter { seen.insert($0).inserted }
    }
}
