//
//  RAGContextService.swift
//  SilicIA
//
//  Created by Eddy Barraud on 27/03/2026.
//

import Foundation

/// Represents a retrieval chunk and its source metadata.
struct RAGChunk: Identifiable {
    let id = UUID()
    let source: String
    let text: String
    let url: String?
    let pdfPage: Int?
}

/// Splits long context text into overlapping retrieval chunks.
///
/// Chunk boundaries are sentence/paragraph-aware: when the ideal byte-count
/// boundary would land mid-sentence, the chunker walks back up to ~20% of the
/// chunk size to find a paragraph break (`\n\n`), a sentence terminator
/// (`. ` / `! ` / `? `), or a table-row break (`\n`). If no such boundary is
/// available, it still avoids splitting inside a multi-digit number sequence
/// (e.g. `"8,432,567"`, `"105.4 km²"`) — small models silently mangle numbers
/// when a chunk boundary slices through the middle of them.
struct RAGChunker {
    static let avgCharsPerToken = 3
    private static let minimumChunkCharacters = 200

    /// Cached regex collapsing horizontal whitespace runs (spaces, tabs,
    /// non-breaking spaces, Unicode whitespace) to a single space. Newlines
    /// are intentionally preserved — paragraph and table-row breaks make
    /// ideal chunk boundaries. Swift string-literal Unicode escapes embed
    /// the actual characters in the pattern, because NSRegularExpression's
    /// ICU flavor does not recognise `\u{XXXX}` syntax inside a pattern.
    private static let horizontalWhitespaceRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "[ \t\u{00A0}\u{2000}-\u{200A}\u{202F}\u{205F}\u{3000}]+",
        options: []
    )
    /// Cached regex collapsing runs of 3+ newlines down to a double newline.
    private static let verticalWhitespaceRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "\n{3,}",
        options: []
    )
    /// Cached regex matching blank-with-whitespace lines — `\n   \n   \n`
    /// patterns left behind when HTML scraping replaces `<br>` runs with
    /// single spaces. Without this collapse, a typical news article reaches
    /// the chunker with dozens of newline-space-newline-space sequences
    /// that each survive as their own line and silently burn tokens.
    private static let blankLineRunRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "(\\n[ \t]*){2,}\\n",
        options: []
    )
    /// Cached regex stripping a single trailing horizontal-whitespace run
    /// from each line. Combined with `blankLineRunRegex`, lines that
    /// contained only whitespace become genuinely empty.
    private static let trailingLineWhitespaceRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "[ \t]+\n",
        options: []
    )

    /// Chunks text with overlap while preserving non-empty slices.
    func chunk(
        text: String,
        source: String,
        maxChunkTokens: Int,
        overlapTokens: Int,
        url: String? = nil,
        pdfPage: Int? = nil
    ) -> [RAGChunk] {
        let cleanText = Self.normalizeWhitespace(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanText.isEmpty else { return [] }

        let maxChunkChars = max(Self.minimumChunkCharacters, maxChunkTokens * Self.avgCharsPerToken)
        let overlapChars = min(maxChunkChars / 2, max(0, overlapTokens * Self.avgCharsPerToken))

        var chunks: [RAGChunk] = []
        var start = cleanText.startIndex

        while start < cleanText.endIndex {
            let hardEnd = cleanText.index(start, offsetBy: maxChunkChars, limitedBy: cleanText.endIndex) ?? cleanText.endIndex
            let end = hardEnd == cleanText.endIndex
                ? hardEnd
                : Self.safeChunkBoundary(in: cleanText, from: start, idealEnd: hardEnd)

            var piece = cleanText[start..<end]
            while let first = piece.first, first.isWhitespace { piece = piece.dropFirst() }
            while let last = piece.last, last.isWhitespace { piece = piece.dropLast() }
            if !piece.isEmpty {
                chunks.append(RAGChunk(source: source, text: String(piece), url: url, pdfPage: pdfPage))
            }

            if end >= cleanText.endIndex { break }
            // Slide the window so the next chunk starts `overlapChars` before
            // the boundary we just used. Anchoring overlap to the *chosen*
            // boundary (rather than a fixed stride from `start`) keeps the
            // overlap meaningful when the boundary walks back from `hardEnd`.
            let candidate = cleanText.index(end, offsetBy: -overlapChars, limitedBy: start) ?? start
            // Always make forward progress: if walkback brought us back to
            // `start` (tiny final chunk) advance by at least one character.
            start = candidate <= start
                ? (cleanText.index(start, offsetBy: 1, limitedBy: cleanText.endIndex) ?? cleanText.endIndex)
                : candidate
        }

        return Self.preserveTableHeadersAcrossChunks(chunks)
    }

    /// Post-process chunks so that Markdown table headers survive across
    /// chunk boundaries. Without this, a table that spans multiple chunks
    /// loses its column labels in every chunk except the first — the model
    /// then sees rows like
    ///
    ///     | AR00002 | Amortisseurs | 2,00 | 77,08 | 154,17 | 20,00 |
    ///
    /// with no way to know which column is "unit price" vs "total" vs "TVA".
    ///
    /// Two fixes per chunk:
    ///   1. Drop a leading orphan separator line (`| --- | --- |`) — these
    ///      appear when the previous chunk's overlap clipped a *different*
    ///      table's separator into the current chunk. Wrong column count,
    ///      pure noise for the model.
    ///   2. If the chunk contains data rows but no header+separator pair,
    ///      prepend the most recently seen header from earlier chunks.
    ///      The header column count is tracked so a wider items-table
    ///      header is preferred over a stale narrow header from a sibling
    ///      table on the same page.
    nonisolated static func preserveTableHeadersAcrossChunks(_ chunks: [RAGChunk]) -> [RAGChunk] {
        guard chunks.count > 1 else { return chunks }

        // Keyed by column count so a 5-column ID table and a 6-column items
        // table coexisting on the same page don't clobber each other. When a
        // later chunk carries N-column data rows, we look up the N-column
        // header — not "whichever header came last".
        var recentHeaders: [Int: (header: String, separator: String)] = [:]

        var result: [RAGChunk] = []
        result.reserveCapacity(chunks.count)

        for chunk in chunks {
            var lines = chunk.text.components(separatedBy: "\n")

            // 1. Drop leading orphan separator(s) — overlap artifacts from
            //    a different table whose header isn't in this chunk.
            while let first = lines.first?.trimmingCharacters(in: .whitespaces),
                  isMarkdownTableSeparator(first) {
                lines.removeFirst()
            }

            // 2. Locate the first data row in the chunk and check whether a
            //    matching header+separator pair already sits above it. If
            //    it does, the chunk is self-sufficient — no propagation.
            let firstDataRow = findFirstDataRow(in: lines)
            let hasHeaderAboveData: Bool = {
                guard let dataIndex = firstDataRow.index, dataIndex > 0 else {
                    return false
                }
                // Scan everything before the first data row for a
                // header+separator pair whose column count matches.
                var i = 0
                while i < dataIndex - 1 {
                    let line = lines[i].trimmingCharacters(in: .whitespaces)
                    let next = lines[i + 1].trimmingCharacters(in: .whitespaces)
                    if isMarkdownTableRow(line), !isMarkdownTableSeparator(line),
                       isMarkdownTableSeparator(next),
                       markdownColumnCount(in: line) == firstDataRow.columnCount {
                        return true
                    }
                    i += 1
                }
                return false
            }()

            // 3. No matching header above the first data row → prepend the
            //    cached header for that column count, if we have one.
            if !hasHeaderAboveData,
               let dataCount = firstDataRow.columnCount,
               let header = recentHeaders[dataCount] {
                lines = [header.header, header.separator] + lines
            }

            // 4. Update the header cache with every header+separator pair
            //    visible in this (possibly already-modified) chunk, so the
            //    next chunk picks up the most recent N-column header.
            collectHeaders(in: lines, into: &recentHeaders)

            result.append(RAGChunk(
                source: chunk.source,
                text: lines.joined(separator: "\n"),
                url: chunk.url,
                pdfPage: chunk.pdfPage
            ))
        }
        return result
    }

    /// Scans `lines` and returns the position + column count of the first
    /// non-separator table row, or `(nil, nil)` if there isn't one.
    private nonisolated static func findFirstDataRow(in lines: [String]) -> (index: Int?, columnCount: Int?) {
        for (idx, raw) in lines.enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if isMarkdownTableRow(trimmed), !isMarkdownTableSeparator(trimmed) {
                return (idx, markdownColumnCount(in: trimmed))
            }
        }
        return (nil, nil)
    }

    /// Walks `lines` and records every header+separator pair found, keyed
    /// by column count. Later pairs replace earlier ones at the same key,
    /// so the cache always reflects the most-recently-seen header for that
    /// column shape.
    private nonisolated static func collectHeaders(
        in lines: [String],
        into cache: inout [Int: (header: String, separator: String)]
    ) {
        guard lines.count >= 2 else { return }
        var i = 0
        while i < lines.count - 1 {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            let next = lines[i + 1].trimmingCharacters(in: .whitespaces)
            if isMarkdownTableRow(line), !isMarkdownTableSeparator(line),
               isMarkdownTableSeparator(next) {
                cache[markdownColumnCount(in: line)] = (lines[i], lines[i + 1])
                i += 2
            } else {
                i += 1
            }
        }
    }

    private nonisolated static func isMarkdownTableRow(_ line: String) -> Bool {
        line.hasPrefix("|") && line.hasSuffix("|") && line.count >= 3
    }

    private nonisolated static func isMarkdownTableSeparator(_ line: String) -> Bool {
        guard isMarkdownTableRow(line) else { return false }
        let cells = line.split(separator: "|", omittingEmptySubsequences: true)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return false }
            return trimmed.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private nonisolated static func markdownColumnCount(in row: String) -> Int {
        // A row "| a | b | c |" has 4 pipes — 3 cells. Be defensive about
        // rows that start or end without a pipe.
        let pipes = row.filter { $0 == "|" }.count
        if row.hasPrefix("|"), row.hasSuffix("|") {
            return max(pipes - 1, 1)
        }
        return max(pipes, 1)
    }

    /// Detects rows in plain text where columns are aligned by 2+ spaces
    /// or tabs and converts them to Markdown pipe tables. Designed for PDF
    /// extraction: PDFKit's `page.string` preserves visual spacing between
    /// columns but the chunker's `normalizeWhitespace` would otherwise
    /// collapse them, leaving a row like
    ///
    ///     Amortisseurs    2    64,24    20%    77,08    154,17
    ///
    /// as the flat `"Amortisseurs 2 64,24 20% 77,08 154,17"` — the model
    /// can no longer tell which number sits under which header, so a
    /// "price of Amortisseurs" query lands on the VAT percentage instead
    /// of the total.
    ///
    /// Heuristic: a "table row" is a line with at least 3 cells separated
    /// by runs of 2+ spaces/tabs. Consecutive table rows whose cell counts
    /// agree (give or take one) are grouped into a single Markdown block,
    /// with a `| --- |` separator inserted after the first row (treated as
    /// the header). Standalone rows (≤2 cells) are passed through verbatim.
    ///
    /// Call this BEFORE `normalizeWhitespace` — once horizontal runs are
    /// collapsed, the column boundaries are unrecoverable.
    nonisolated static func convertWhitespaceAlignedTables(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var output: [String] = []
        var pending: [[String]] = []

        func flushTable() {
            guard !pending.isEmpty else { return }
            // Require at least 2 rows of ≥3 cells to count as a table —
            // otherwise we'd reformat any prose line that happens to have
            // a few wide gaps.
            if pending.count >= 2,
               let columnCount = pending.map(\.count).max(),
               columnCount >= 3 {
                let padded = pending.map { row -> [String] in
                    row.count >= columnCount
                        ? row
                        : row + Array(repeating: "", count: columnCount - row.count)
                }
                output.append("| " + padded[0].joined(separator: " | ") + " |")
                output.append("|" + String(repeating: " --- |", count: columnCount))
                for row in padded.dropFirst() {
                    output.append("| " + row.joined(separator: " | ") + " |")
                }
            } else {
                for row in pending {
                    output.append(row.joined(separator: " "))
                }
            }
            pending = []
        }

        for line in lines {
            let cells = splitTabularLine(line)
            if cells.count >= 3 {
                pending.append(cells)
            } else {
                flushTable()
                output.append(line)
            }
        }
        flushTable()

        return output.joined(separator: "\n")
    }

    /// Splits a line on runs of 2+ horizontal whitespace (space/tab/NBSP).
    /// Single spaces stay inside the cell so multi-word headers like
    /// `"Prix HT"` survive. Returns empty when the line is whitespace-only
    /// or has fewer than 2 horizontal-whitespace-run separators.
    private nonisolated static func splitTabularLine(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return [] }

        var cells: [String] = []
        var current = ""
        var spaceRun = 0
        var inLeading = true

        let separators: Set<Character> = [" ", "\t", "\u{00A0}"]
        for char in line {
            if separators.contains(char) {
                if !inLeading { spaceRun += 1 }
            } else {
                if spaceRun >= 2, !current.isEmpty {
                    cells.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                } else if spaceRun >= 1, !current.isEmpty {
                    current.append(" ")
                }
                current.append(char)
                spaceRun = 0
                inLeading = false
            }
        }
        if !current.isEmpty {
            cells.append(current.trimmingCharacters(in: .whitespaces))
        }
        return cells.filter { !$0.isEmpty }
    }

    /// Collapses whitespace runs while preserving structural newlines.
    /// Horizontal runs (spaces, tabs, NBSP) → single space.
    /// Vertical runs of 3+ newlines → double newline (paragraph break).
    static func normalizeWhitespace(_ text: String) -> String {
        var result = text
        if let regex = horizontalWhitespaceRegex {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: " ")
        }
        // Strip horizontal whitespace immediately before a newline so lines
        // that contained only whitespace become genuinely empty.
        if let regex = trailingLineWhitespaceRegex {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "\n")
        }
        // Collapse `\n   \n   \n` blank-line runs to a single paragraph
        // break. HTML scraping leaves these all over the place because
        // `<br>` translates to a space, then between two real text lines
        // we end up with one newline → space → newline → space → newline.
        if let regex = blankLineRunRegex {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "\n\n")
        }
        if let regex = verticalWhitespaceRegex {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "\n\n")
        }
        return result
    }

    /// Finds the best split point at or before `idealEnd`, walking back at
    /// most 20% of the chunk size to find a paragraph break, sentence end,
    /// or single newline. Falls back to a non-mid-number position so a chunk
    /// boundary never bisects a digit sequence with its thousands/decimal
    /// separators (e.g. `8,432,567` or `105.4`).
    static func safeChunkBoundary(
        in text: String,
        from start: String.Index,
        idealEnd: String.Index
    ) -> String.Index {
        let totalChars = text.distance(from: start, to: idealEnd)
        let maxWalkback = max(1, totalChars / 5)
        let walkbackStart = text.index(idealEnd, offsetBy: -maxWalkback, limitedBy: start) ?? start

        // Pass 1: scan walkback range for the strongest boundary closest
        // to `idealEnd`. Paragraph (`\n\n`) beats sentence end beats single
        // newline.
        var paragraphHit: String.Index? = nil
        var sentenceHit: String.Index? = nil
        var newlineHit: String.Index? = nil

        var cursor = walkbackStart
        while cursor < idealEnd {
            let next = text.index(after: cursor)
            let c = text[cursor]

            if c == "\n" {
                if next < idealEnd, text[next] == "\n" {
                    paragraphHit = text.index(after: next)
                } else {
                    newlineHit = next
                }
                cursor = next
                continue
            }

            if (c == "." || c == "!" || c == "?"),
               next < idealEnd, text[next].isWhitespace,
               !isLikelyDecimalSeparator(text: text, periodIndex: cursor) {
                sentenceHit = next
            }

            cursor = next
        }

        if let paragraphHit { return paragraphHit }
        if let sentenceHit { return sentenceHit }
        if let newlineHit { return newlineHit }

        // Pass 2: no strong boundary found. Step back from `idealEnd` while
        // we'd be bisecting a digit/separator cluster — e.g. the middle of
        // "1,234.56" or "3.14159". A bisection means chars on both sides of
        // `fallback` belong to `[0-9.,]` and at least one is a real digit
        // (so we never mistake "..." for a number).
        var fallback = idealEnd
        while fallback > walkbackStart {
            let prev = text.index(before: fallback)
            let cPrev = text[prev]
            let prevIsNumeric = cPrev.isNumber || cPrev == "." || cPrev == ","
            guard prevIsNumeric else { break }
            guard fallback < text.endIndex else { break }
            let cAt = text[fallback]
            let atIsNumeric = cAt.isNumber || cAt == "." || cAt == ","
            if atIsNumeric, cPrev.isNumber || cAt.isNumber {
                fallback = prev
                continue
            }
            // European thousands separator: "10 000".
            if cPrev.isNumber, cAt == " " {
                let next = text.index(after: fallback)
                if next < text.endIndex, text[next].isNumber {
                    fallback = prev
                    continue
                }
            }
            break
        }
        return fallback
    }

    /// True when the period at `periodIndex` is sandwiched between digits
    /// (e.g. the `.` in `"1.234"` or `"105.4"`). Such periods are not
    /// sentence boundaries.
    private static func isLikelyDecimalSeparator(text: String, periodIndex: String.Index) -> Bool {
        guard periodIndex > text.startIndex else { return false }
        let prev = text.index(before: periodIndex)
        let next = text.index(after: periodIndex)
        guard next < text.endIndex else { return false }
        return text[prev].isNumber && text[next].isNumber
    }
}

/// Parameters used to keep retrieved context within the model context window.
struct RAGSelectionOptions {
    let avgCharsPerToken: Int
    let instructionTokens: Int
    let promptOverheadTokens: Int
    let minContextTokens: Int
    let contextUtilizationFactor: Double
    let minimumFallbackContextCharacters: Int
    let longChunkCharacterThreshold: Int
    let longChunkBonusScore: Double
    /// Score added per numeric/unit token shared between the query and the
    /// chunk. Numbers carry concrete factual weight — when the query asks
    /// about "5km" or "1990", a chunk containing that exact token is far
    /// more likely to hold the answer than one that merely shares some
    /// bag-of-words overlap.
    let numericTokenMatchBonus: Double
    /// Smaller score added once when the query has numerical intent
    /// ("how many", "how much", "%", a unit, a comparison) and the chunk
    /// contains any number at all. Lifts stats-bearing paragraphs above
    /// boilerplate when the user hasn't named a specific number.
    let numericPresenceBonus: Double

    nonisolated static let `default` = RAGSelectionOptions(
        avgCharsPerToken: TokenBudgeting.avgCharsPerToken,
        instructionTokens: TokenBudgeting.instructionTokens,
        promptOverheadTokens: TokenBudgeting.promptOverheadTokens,
        minContextTokens: TokenBudgeting.minContextTokens,
        contextUtilizationFactor: 0.8,
        minimumFallbackContextCharacters: 200,
        longChunkCharacterThreshold: 300,
        longChunkBonusScore: 0.2,
        numericTokenMatchBonus: 0.6,
        numericPresenceBonus: 0.3
    )
}

/// One ranked chunk returned by relevance scoring.
struct RankedRAGChunk {
    let chunk: RAGChunk
    let relevanceScore: Double
}

/// Output of the shared context selection pipeline.
struct RAGSelectionResult {
    let selectedContext: String
    let rankedChunks: [RankedRAGChunk]
    /// Subset of `rankedChunks` that actually survived the greedy budget
    /// filter and ended up inside `selectedContext`. Empty if no chunks
    /// were selected (including the "fallback chunk" branch — see
    /// `RAGContextService.selectContext` for the exception).
    let selectedChunks: [RankedRAGChunk]

    /// Default number of top-ranked chunks surfaced for citation rendering.
    /// Centralized so callers (and the convenience accessor below) share one source of truth.
    static let defaultTopChunkCount = 3

    /// Returns the top `limit` ranked chunks (by relevance score, then length).
    func topChunks(limit: Int) -> [RankedRAGChunk] {
        Array(rankedChunks.prefix(max(0, limit)))
    }

    /// Compatibility accessor preserved for existing callers in other files.
    /// Delegates to `topChunks(limit:)` so the magic "3" lives in one place.
    var topChunks: [RankedRAGChunk] {
        topChunks(limit: Self.defaultTopChunkCount)
    }

    /// Multi-line human-readable dump of the chunks that actually made it
    /// into `selectedContext`, intended for `print()` from a debug guard.
    /// Shows source, page/URL provenance, score, length, and the chunk's
    /// full text — so you can verify *exactly* what the model was given,
    /// without having to grep through the prompt itself.
    func debugDescription(label: String) -> String {
        var lines: [String] = []
        lines.append("┏━ \(label): \(selectedChunks.count) chunk(s) sent to model ━━")
        for (index, ranked) in selectedChunks.enumerated() {
            var provenance = ranked.chunk.source
            if let url = ranked.chunk.url { provenance += " | url=\(url)" }
            if let page = ranked.chunk.pdfPage { provenance += " | page=\(page)" }
            lines.append("┃")
            lines.append("┃ [\(index + 1)] score=\(String(format: "%.3f", ranked.relevanceScore)) chars=\(ranked.chunk.text.count)")
            lines.append("┃     \(provenance)")
            lines.append("┃ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄")
            for textLine in ranked.chunk.text.split(separator: "\n", omittingEmptySubsequences: false) {
                lines.append("┃ \(textLine)")
            }
        }
        lines.append("┗━ end of \(label) ━━")
        return lines.joined(separator: "\n")
    }
}

/// Shared context selection/relevance service for chat and search.
actor RAGContextService {
    /// Selects the highest-ranked chunks that fit the context budget.
    /// - Parameter maxOutputTokens: Requested response-token budget used to compute remaining context space.
    /// - Parameter contextUtilizationFactor: Optional context budget multiplier.
    ///   When nil, `options.contextUtilizationFactor` is used.
    /// - Parameter queries: When provided (Deep search), chunks are ranked by cosine similarity
    ///   against a combined TF vector built from every query (user + derived queries).
    func selectContext(
        chunks: [RAGChunk],
        query: String,
        maxOutputTokens: Int,
        contextUtilizationFactor: Double? = nil,
        queries: [String]? = nil,
        options: RAGSelectionOptions = .default
    ) async -> RAGSelectionResult {
        guard !chunks.isEmpty else {
            return RAGSelectionResult(
                selectedContext: "No additional context provided.",
                rankedChunks: [],
                selectedChunks: []
            )
        }

        let utilization = contextUtilizationFactor ?? options.contextUtilizationFactor
        let maxContextChars = await calculateMaxContextCharacters(
            maxOutputTokens: maxOutputTokens,
            contextUtilizationFactor: utilization,
            options: options
        )

        let combinedQueryVector: [String: Double]?
        if let queries, queries.count > 1 {
            combinedQueryVector = combinedTermVector(from: queries)
        } else {
            combinedQueryVector = nil
        }

        // Combined query string used by the numeric-aware boost — for deep
        // search we concatenate every derived query so the boost catches
        // numeric tokens introduced by query expansion, not just the user's
        // original wording.
        let numericQueryString = (queries?.joined(separator: " ")).map { $0.isEmpty ? query : $0 } ?? query

        var ranked: [RankedRAGChunk] = []
        ranked.reserveCapacity(chunks.count)
        for chunk in chunks {
            let score: Double
            if let combinedQueryVector {
                score = cosineRelevanceScore(
                    text: chunk.text,
                    queryVector: combinedQueryVector,
                    numericQueryString: numericQueryString,
                    options: options
                )
            } else {
                score = relevanceScore(text: chunk.text, query: query, options: options)
            }
            ranked.append(RankedRAGChunk(chunk: chunk, relevanceScore: score))
        }

        ranked.sort { lhs, rhs in
            if lhs.relevanceScore == rhs.relevanceScore {
                return lhs.chunk.text.count > rhs.chunk.text.count
            }
            return lhs.relevanceScore > rhs.relevanceScore
        }

        var selected: [String] = []
        var selectedChunks: [RankedRAGChunk] = []
        var currentChars = 0
        let separator = "\n\n---\n\n"
        for rankedChunk in ranked {
            let chunkEntry = "Source: \(rankedChunk.chunk.source)\n\(rankedChunk.chunk.text)"
            let separatorChars = selected.isEmpty ? 0 : separator.count
            if currentChars + separatorChars + chunkEntry.count > maxContextChars {
                continue
            }
            selected.append(chunkEntry)
            selectedChunks.append(rankedChunk)
            currentChars += separatorChars + chunkEntry.count
        }

        if selected.isEmpty, let first = ranked.first {
            let fallback = "Source: \(first.chunk.source)\n\(first.chunk.text)"
            return RAGSelectionResult(
                selectedContext: String(fallback.prefix(max(options.minimumFallbackContextCharacters, maxContextChars))),
                rankedChunks: ranked,
                selectedChunks: [first]
            )
        }

        return RAGSelectionResult(
            selectedContext: selected.joined(separator: separator),
            rankedChunks: ranked,
            selectedChunks: selectedChunks
        )
    }

    /// Computes normalised per-source match-score percentages from a
    /// `RAGSelectionResult`. Selected chunks are grouped by `chunk.url`,
    /// their `relevanceScore` summed, then expressed as percentages of the
    /// grand total so the returned values sum to 100. Sources whose chunks
    /// did not survive the budget filter are absent from the dictionary —
    /// callers should treat missing keys as 0%.
    nonisolated static func normalizedSourceScores(from result: RAGSelectionResult) -> [String: Double] {
        var sums: [String: Double] = [:]
        for ranked in result.selectedChunks {
            guard let url = ranked.chunk.url else { continue }
            sums[url, default: 0] += max(0, ranked.relevanceScore)
        }
        let total = sums.values.reduce(0, +)
        guard total > 0 else { return [:] }
        return sums.mapValues { ($0 / total) * 100 }
    }

    private func calculateMaxContextCharacters(
        maxOutputTokens: Int,
        contextUtilizationFactor: Double,
        options: RAGSelectionOptions
    ) async -> Int {
        await MainActor.run {
            TokenBudgeting.maxContextCharacters(
                maxOutputTokens: maxOutputTokens,
                contextUtilizationFactor: contextUtilizationFactor,
                instructionTokens: options.instructionTokens,
                promptOverheadTokens: options.promptOverheadTokens,
                minContextTokens: options.minContextTokens,
                avgCharsPerToken: options.avgCharsPerToken
            )
        }
    }

    private func relevanceScore(text: String, query: String, options: RAGSelectionOptions) -> Double {
        let queryWords = Set(tokenize(query).filter { $0.count > 2 })
        guard !queryWords.isEmpty else { return 0 }

        let textWords = Set(tokenize(text))
        var score = 0.0
        for word in queryWords where textWords.contains(word) {
            score += 1.0
        }
        if text.count > options.longChunkCharacterThreshold {
            score += options.longChunkBonusScore
        }
        score += Self.numericRelevanceBoost(text: text, query: query, options: options)
        return score
    }

    /// Builds a term-frequency vector from the union of query tokens.
    private func combinedTermVector(from queries: [String]) -> [String: Double] {
        var vector: [String: Double] = [:]
        for query in queries {
            for term in tokenize(query) where term.count > 2 {
                vector[term, default: 0] += 1
            }
        }
        return vector
    }

    /// Cosine similarity between a chunk and a precomputed query term vector,
    /// with the legacy long-chunk bonus preserved for tie-breaking.
    private func cosineRelevanceScore(
        text: String,
        queryVector: [String: Double],
        numericQueryString: String,
        options: RAGSelectionOptions
    ) -> Double {
        guard !queryVector.isEmpty else { return 0 }

        var textVector: [String: Double] = [:]
        for term in tokenize(text) where term.count > 2 {
            textVector[term, default: 0] += 1
        }
        guard !textVector.isEmpty else { return 0 }

        var dot = 0.0
        for (term, weight) in queryVector {
            if let textWeight = textVector[term] {
                dot += weight * textWeight
            }
        }

        let queryNorm = sqrt(queryVector.values.reduce(0) { $0 + $1 * $1 })
        let textNorm = sqrt(textVector.values.reduce(0) { $0 + $1 * $1 })
        guard queryNorm > 0, textNorm > 0 else { return 0 }

        var score = dot / (queryNorm * textNorm)
        if text.count > options.longChunkCharacterThreshold {
            score += options.longChunkBonusScore
        }
        // Apply the same numeric-aware nudge as the bag-of-words path so the
        // two scorers behave consistently when the query mentions concrete
        // values. Without this, deep-search (cosine path) was systematically
        // worse than fast-search at picking stat-heavy chunks.
        score += Self.numericRelevanceBoost(text: text, query: numericQueryString, options: options)
        return score
    }

    /// Compiled once and reused. Matches a contiguous number token, possibly
    /// signed, with thousands separators (`,`, `.`, narrow spaces) and a
    /// decimal portion. Captures common trailing units inline so they're part
    /// of the same token: `5km`, `12%`, `100°C`, `$100`, `1990s`.
    private nonisolated static let numericTokenRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "[-+]?\\d+(?:[\\.,\\u{00A0}\\u{202F} ]\\d+)*(?:%|°[CcFfKk]?|[a-zA-Z]{1,4})?",
        options: []
    )
    /// Matches any single digit — used as a cheap "does this chunk carry
    /// numbers at all" check.
    private nonisolated static let anyDigitRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "\\d",
        options: []
    )

    /// Lowercased numeric/unit tokens found in `text`. Whitespace in
    /// thousands separators is normalized to a single space so European
    /// (`"10 000"`) and Anglo (`"10,000"`) formats can be compared after a
    /// further `,`/`.` strip if needed.
    nonisolated static func extractNumericTokens(_ text: String) -> Set<String> {
        guard let regex = numericTokenRegex else { return [] }
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)
        var tokens: Set<String> = []
        tokens.reserveCapacity(matches.count)
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            let raw = String(text[range]).lowercased()
            tokens.insert(raw)
            // Also insert the digits-only normalization so "1,234" and
            // "1.234" and "1 234" collapse to the same comparable key.
            let digitsOnly = raw.filter { $0.isNumber }
            if !digitsOnly.isEmpty {
                tokens.insert(digitsOnly)
            }
        }
        return tokens
    }

    /// Heuristic: does the query look like it needs numerical reasoning?
    /// True when the query contains digits, a `%`, currency, a comparative
    /// keyword ("more than", "less", "combien", "cuánto"), or a quantity
    /// question phrase ("how many", "how much").
    nonisolated static func hasNumericalIntent(_ query: String) -> Bool {
        let lowered = query.lowercased()
        if let regex = anyDigitRegex {
            let nsRange = NSRange(lowered.startIndex..., in: lowered)
            if regex.firstMatch(in: lowered, options: [], range: nsRange) != nil {
                return true
            }
        }
        if lowered.contains("%") || lowered.contains("$") || lowered.contains("€") || lowered.contains("£") {
            return true
        }
        // EN + FR + ES cues. Keep this list tight; widening it dilutes the
        // signal.
        let cues = [
            "how many", "how much", "average", "percent", "ratio", "compared",
            "more than", "less than", "at least", "at most", "between",
            "combien", "pourcent", "moyenne", "ratio", "plus de", "moins de",
            "cuánto", "cuántos", "cuántas", "promedio", "porcentaje", "más de", "menos de"
        ]
        for cue in cues where lowered.contains(cue) {
            return true
        }
        return false
    }

    nonisolated static func textContainsAnyNumber(_ text: String) -> Bool {
        guard let regex = anyDigitRegex else { return false }
        let nsRange = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: nsRange) != nil
    }

    /// Number-aware boost shared by both relevance scorers.
    ///
    /// - Strong: per numeric token shared between query and chunk
    ///   (`numericTokenMatchBonus` each). When the query says "5 km" or
    ///   "1990", a chunk carrying the same value is much more likely to
    ///   hold the answer than one that merely shares prose vocabulary.
    /// - Weak: a single `numericPresenceBonus` when the query has numerical
    ///   intent but no specific number, and the chunk contains any digit.
    ///   Lifts stats-bearing paragraphs above boilerplate.
    nonisolated static func numericRelevanceBoost(
        text: String,
        query: String,
        options: RAGSelectionOptions
    ) -> Double {
        let queryNumerics = extractNumericTokens(query)
        if !queryNumerics.isEmpty {
            let textNumerics = extractNumericTokens(text)
            let overlap = queryNumerics.intersection(textNumerics).count
            return Double(overlap) * options.numericTokenMatchBonus
        }
        if hasNumericalIntent(query), textContainsAnyNumber(text) {
            return options.numericPresenceBonus
        }
        return 0
    }

    private func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }
}

/// Formats source evidence shown under generated answers.
enum RAGCitationFormatter {
    static func citationBlock(from chunks: [RankedRAGChunk], language: ModelLanguage? = nil) -> String {
        guard !chunks.isEmpty else { return "" }

        let pageLabel = language == .french ? "Page PDF" : "PDF Page"

        let lines = chunks.enumerated().map { index, ranked -> String in
            var itemLines: [String] = []

            if let url = ranked.chunk.url {
                itemLines.append("\(index + 1). [\(url)](\(url))")
            } else {
                itemLines.append("\(index + 1). \(ranked.chunk.source)")
            }

            if let page = ranked.chunk.pdfPage {
                itemLines.append("   \(pageLabel): \(page)")
            }

            return itemLines.joined(separator: "\n")
        }

        return lines.joined(separator: "\n\n")
    }
}
