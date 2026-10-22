//
//  RAGContextService.swift
//  SilicIA
//
//  Created by Eddy Barraud on 27/03/2026.
//

import Foundation
import NaturalLanguage
import Accelerate

/// Represents a retrieval chunk and its source metadata.
struct RAGChunk: Identifiable {
    let id = UUID()
    let source: String
    let text: String
    let url: String?
    let pdfPage: Int?
}

/// Chunks structured markdown and text into clean retrieval chunks.
///
/// Chunker architecture:
/// 1. Markdown tables are isolated first and preserved as atomic tabular chunks.
/// 2. Formatting noise (titles/headings `#...` and link URLs `[text](url)` -> `text`)
///    is stripped via `removeMarkdownFormatting`.
/// 3. Source input language is detected over the first 500 characters using `NLLanguageRecognizer`.
/// 4. Natural paragraphs are extracted using `NLTokenizer(unit: .paragraph)` configured with
///    the detected source language.
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

    private enum MarkdownSegment {
        case table(String)
        case prose(String)
    }

    /// Strips Markdown headings (#...), converts Markdown links [name](url) into "name",
    /// and flattens image tags ![alt](url) into "alt" using fast linear-time scanners.
    static func removeMarkdownFormatting(from text: String) -> String {
        // 1. Remove lines of titles and subtitles (starting with #)
        let lines = text.components(separatedBy: "\n")
        let filteredLines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.hasPrefix("#")
        }
        let withoutTitles = filteredLines.joined(separator: "\n")

        // 2. Strip images ![alt](url) -> alt first, so nested linked images [![alt](img)](link) simplify cleanly
        let withoutImages = stripMarkdownImages(from: withoutTitles)

        // 3. Strip links [name](url) -> name
        return stripMarkdownLinks(from: withoutImages)
    }

    /// Single-pass linear scanner replacing markdown images ![alt](url) -> alt.
    /// Handles balanced parentheses in URLs without catastrophic regex backtracking.
    static func stripMarkdownImages(from text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)

        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "!" && text.index(after: i) < text.endIndex && text[text.index(after: i)] == "[" {
                let bracketStart = text.index(after: i)
                let contentStart = text.index(after: bracketStart)

                var bracketEnd: String.Index? = nil
                var scan = contentStart
                while scan < text.endIndex {
                    let c = text[scan]
                    if c == "\n" { break }
                    if c == "]" {
                        bracketEnd = scan
                        break
                    }
                    scan = text.index(after: scan)
                }

                if let bEnd = bracketEnd,
                   text.index(after: bEnd) < text.endIndex,
                   text[text.index(after: bEnd)] == "(" {
                    let parenStart = text.index(after: bEnd)
                    let urlStart = text.index(after: parenStart)
                    var parenEnd: String.Index? = nil
                    var parenDepth = 1
                    var pScan = urlStart

                    while pScan < text.endIndex {
                        let c = text[pScan]
                        if c == "\n" { break }
                        if c == "(" {
                            parenDepth += 1
                        } else if c == ")" {
                            parenDepth -= 1
                            if parenDepth == 0 {
                                parenEnd = pScan
                                break
                            }
                        }
                        pScan = text.index(after: pScan)
                    }

                    if let pEnd = parenEnd {
                        let label = text[contentStart..<bEnd]
                        result.append(contentsOf: label)
                        i = text.index(after: pEnd)
                        continue
                    }
                }
            }

            result.append(text[i])
            i = text.index(after: i)
        }

        return result
    }

    /// Single-pass linear scanner replacing markdown links [name](url) -> name.
    /// Handles balanced parentheses in URLs (e.g. Wikipedia article titles) without catastrophic regex backtracking.
    static func stripMarkdownLinks(from text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)

        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "[" {
                let contentStart = text.index(after: i)

                var bracketEnd: String.Index? = nil
                var scan = contentStart
                while scan < text.endIndex {
                    let c = text[scan]
                    if c == "\n" { break }
                    if c == "]" {
                        bracketEnd = scan
                        break
                    }
                    scan = text.index(after: scan)
                }

                if let bEnd = bracketEnd,
                   text.index(after: bEnd) < text.endIndex,
                   text[text.index(after: bEnd)] == "(" {
                    let parenStart = text.index(after: bEnd)
                    let urlStart = text.index(after: parenStart)
                    var parenEnd: String.Index? = nil
                    var parenDepth = 1
                    var pScan = urlStart

                    while pScan < text.endIndex {
                        let c = text[pScan]
                        if c == "\n" { break }
                        if c == "(" {
                            parenDepth += 1
                        } else if c == ")" {
                            parenDepth -= 1
                            if parenDepth == 0 {
                                parenEnd = pScan
                                break
                            }
                        }
                        pScan = text.index(after: pScan)
                    }

                    if let pEnd = parenEnd {
                        let label = text[contentStart..<bEnd]
                        result.append(contentsOf: label)
                        i = text.index(after: pEnd)
                        continue
                    }
                }
            }

            result.append(text[i])
            i = text.index(after: i)
        }

        return result
    }

    /// Splits markdown text into retrieval chunks:
    /// - Markdown tables are preserved intact as separate chunks first.
    /// - Non-table prose has Markdown titles stripped and links converted to plain names,
    ///   then is chunked into paragraphs using NLTokenizer(unit: .paragraph)
    ///   with its language determined by NLLanguageRecognizer over the first 500 characters.
    static func chunkParagraphs(
        text: String,
        source: String,
        url: String? = nil,
        pdfPage: Int? = nil
    ) -> [RAGChunk] {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return [] }

        // Determine language of the source input over the first 500 characters using NLLanguageRecognizer
        let prefix = String(cleanText.prefix(500))
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(prefix)
        let sourceLanguage = recognizer.dominantLanguage

        // Extract tables as separate chunks first
        let segments = segmentMarkdownTablesAndProse(cleanText)
        var chunks: [RAGChunk] = []

        let tokenizer = NLTokenizer(unit: .paragraph)
        if let lang = sourceLanguage, lang != .undetermined {
            tokenizer.setLanguage(lang)
        }

        for segment in segments {
            switch segment {
            case .table(let tableText):
                let trimmedTable = tableText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedTable.isEmpty {
                    chunks.append(RAGChunk(source: source, text: trimmedTable, url: url, pdfPage: pdfPage))
                }
            case .prose(let proseText):
                let cleanedProse = removeMarkdownFormatting(from: proseText)
                let trimmedProse = cleanedProse.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedProse.isEmpty else { continue }
                tokenizer.string = trimmedProse
                tokenizer.enumerateTokens(in: trimmedProse.startIndex..<trimmedProse.endIndex) { range, _ in
                    let paragraph = trimmedProse[range].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !paragraph.isEmpty {
                        chunks.append(RAGChunk(source: source, text: paragraph, url: url, pdfPage: pdfPage))
                    }
                    return true
                }
            }
        }

        return chunks
    }

    private static func segmentMarkdownTablesAndProse(_ markdown: String) -> [MarkdownSegment] {
        let lines = markdown.components(separatedBy: "\n")
        var segments: [MarkdownSegment] = []
        var currentProse: [String] = []
        var currentTable: [String] = []

        func flushTable() {
            guard !currentTable.isEmpty else { return }
            let hasSep = currentTable.contains(where: { isMarkdownTableSeparator($0) })
            if hasSep && currentTable.count >= 2 {
                if !currentProse.isEmpty {
                    segments.append(.prose(currentProse.joined(separator: "\n")))
                    currentProse.removeAll(keepingCapacity: true)
                }
                segments.append(.table(currentTable.joined(separator: "\n")))
            } else {
                currentProse.append(contentsOf: currentTable)
            }
            currentTable.removeAll(keepingCapacity: true)
        }

        func flushProse() {
            guard !currentProse.isEmpty else { return }
            segments.append(.prose(currentProse.joined(separator: "\n")))
            currentProse.removeAll(keepingCapacity: true)
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isMarkdownTableRow(trimmed) {
                currentTable.append(line)
            } else {
                flushTable()
                currentProse.append(line)
            }
        }

        flushTable()
        flushProse()

        return segments
    }

    private nonisolated static func isMarkdownTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.count >= 3
    }

    private nonisolated static func isMarkdownTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard isMarkdownTableRow(trimmed) else { return false }
        let cells = trimmed.split(separator: "|", omittingEmptySubsequences: true)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let trimmedCell = cell.trimmingCharacters(in: .whitespaces)
            guard !trimmedCell.isEmpty else { return false }
            return trimmedCell.allSatisfy { $0 == "-" || $0 == ":" }
        }
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
               let maxCount = pending.map(\.count).max(),
               maxCount >= 3 {
                // Use the modal (most frequent) column count as the canonical
                // table width. When Vision OCR splits a table cell — most
                // commonly an equation column that has subscripts/symbols
                // recognized as separate text fragments — that row ends up
                // with more cells than the others. Using the max would widen
                // the whole table to that outlier, producing empty cells
                // everywhere and confusing the model. Using the mode keeps the
                // canonical structure intact and merges any excess cells in
                // the outlier row back into the last column.
                var counts: [Int: Int] = [:]
                for row in pending { counts[row.count, default: 0] += 1 }
                let columnCount = counts
                    .filter { $0.key >= 3 }
                    .max { a, b in a.value == b.value ? a.key > b.key : a.value < b.value }?.key ?? maxCount
                let normalized = pending.map { row -> [String] in
                    if row.count == columnCount {
                        return row
                    } else if row.count < columnCount {
                        return row + Array(repeating: "", count: columnCount - row.count)
                    } else {
                        // Merge excess cells back into the last column so a
                        // single equation that Vision split into N fragments
                        // ("a_ww =", "k_BT/(2α)", "(κ^−1 N_m − 1)") becomes
                        // one contiguous cell in the Markdown table.
                        let head = Array(row.prefix(columnCount - 1))
                        let tail = row.dropFirst(columnCount - 1).joined(separator: " ")
                        return head + [tail]
                    }
                }
                output.append("| " + normalized[0].joined(separator: " | ") + " |")
                output.append("|" + String(repeating: " --- |", count: columnCount))
                for row in normalized.dropFirst() {
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
    /// Strong bonus when an equation-oriented query ("equation 5", "eq. 12")
    /// and a chunk reference the same numbered equation.
    let equationReferenceMatchBonus: Double
    /// Extra nudge for chunks that both reference the requested equation and
    /// visibly contain formula syntax (`=`, `ln(`, etc.).
    let equationFormulaBonus: Double
    /// Small fallback bonus for formula-bearing chunks when the query asks
    /// about an equation but names no specific equation number.
    let equationPresenceBonus: Double
    /// Strong bonus when a figure-oriented query ("figure 5", "fig. 3")
    /// and a chunk reference the same numbered figure.
    let figureReferenceMatchBonus: Double
    /// Extra nudge for chunks that both match the requested figure/page and
    /// visibly contain a figure cue in the text/caption.
    let figureCaptionBonus: Double
    /// Strong bonus when a figure-oriented query names an explicit PDF page
    /// and the chunk comes from that page.
    let figurePageMatchBonus: Double
    /// Small fallback bonus for chunks that contain a figure cue when the
    /// query asks about a figure but does not carry stronger signals.
    let figurePresenceBonus: Double
    /// Cosine pre-filtering threshold (score > 0.7) for two-stage ranking
    let cosinePreFilterThreshold: Double
    /// Minimum candidate chunks retained after pre-filtering
    let minimumFilterCandidates: Int
    /// Character length prefix used for fast cosine pre-filtering
    let cosinePreFilterSampleLength: Int

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
        numericPresenceBonus: 0.3,
        equationReferenceMatchBonus: 2.5,
        equationFormulaBonus: 0.5,
        equationPresenceBonus: 0.2,
        figureReferenceMatchBonus: 2.5,
        figureCaptionBonus: 0.5,
        figurePageMatchBonus: 2.0,
        figurePresenceBonus: 0.2,
        cosinePreFilterThreshold: 0.9,
        minimumFilterCandidates: 8,
        cosinePreFilterSampleLength: 350
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

/// Shared context selection and semantic relevance ranking service for chat and search.
///
/// Implements a 2-stage ranking pipeline:
/// - Stage 1 (Fast Pre-filtering): Candidate chunks are pre-scored via Discrete Cosine Transform (DCT)
///   hash embeddings and cosine similarity against the query. Top candidates fitting within twice the
///   target context budget (<= 2x token budget) are retained for deep semantic scoring.
/// - Stage 2 (Semantic Ranking): Candidates are ranked using NaturalLanguage `NLEmbedding` sentence embeddings
///   (with word embedding fallback) matched to the query's detected language, augmented with numeric/factual intent boosts.
///   The top-scoring chunks fitting within the remaining 4096-token context budget (<= 1x budget) are returned.
actor RAGContextService {
    /// In-memory cache of sentence embeddings by language to avoid repeated disk reads.
    private var embeddingCache: [NLLanguage: NLEmbedding] = [:]
    /// In-memory cache of word embeddings by language for languages where sentence embeddings are unavailable.
    private var wordEmbeddingCache: [NLLanguage: NLEmbedding] = [:]

    /// Stop words excluded from lexical/stem and word-embedding term vectors so grammatical articles
    /// (e.g. "des", "les", "the") do not dilute topical terms.
    private nonisolated static let rankingStopWords: Set<String> = [
        // French
        "les", "des", "une", "dans", "pour", "par", "sur", "avec", "sans", "sous",
        "aux", "ces", "ses", "nos", "vos", "leur", "leurs", "cet", "cette", "mon", "ton", "son",
        "mais", "donc", "car", "que", "qui", "quoi", "dont", "ou", "comment", "pourquoi", "quand",
        "quel", "quelle", "quels", "quelles", "est", "sont", "etre", "avoir", "fait", "faire",
        "plus", "moins", "tres", "tout", "tous", "toute", "toutes", "comme", "aussi", "meme",
        "entre", "vers", "chez", "depuis", "pendant", "avant", "apres", "alors", "ainsi",
        "propose", "proposer", "donne", "donner", "explique", "expliquer",
        // English
        "the", "and", "for", "with", "that", "this", "from", "are", "was", "were", "been",
        "have", "has", "had", "not", "but", "what", "which", "who", "whom", "whose",
        "when", "where", "why", "how", "can", "could", "would", "should", "will", "shall",
        "into", "onto", "upon", "about", "above", "below", "between", "through", "during",
        "before", "after", "more", "most", "some", "such", "than", "too", "very", "also",
        // Spanish
        "los", "las", "una", "unos", "unas", "del", "por", "para", "con", "sin", "sobre",
        "entre", "hasta", "desde", "como", "pero", "mas", "menos", "muy", "todo", "toda",
        "todos", "todas", "este", "esta", "estos", "estas", "ese", "esa", "esos", "esas",
        "que", "quien", "quienes", "cual", "cuales", "cuando", "donde", "porque", "son", "esta"
    ]

    init() {
        // Preload commonly used language embeddings in background
        Task { [weak self] in
            await self?.preloadEmbeddings()
        }
    }

    /// Preloads sentence and word embeddings for supported languages into memory.
    func preloadEmbeddings() {
        let defaultLanguages: [NLLanguage] = [.english, .french, .spanish]
        for lang in defaultLanguages {
            if embeddingCache[lang] == nil, let emb = NLEmbedding.sentenceEmbedding(for: lang) {
                embeddingCache[lang] = emb
            }
            if wordEmbeddingCache[lang] == nil, let wordEmb = NLEmbedding.wordEmbedding(for: lang) {
                wordEmbeddingCache[lang] = wordEmb
            }
        }
    }

    /// Detects the dominant language of the user query using `NLLanguageRecognizer`,
    /// falling back to `fallback` (or `.english`) only when the query itself is undetermined or ambiguous.
    nonisolated static func detectQueryLanguage(for query: String, fallback: ModelLanguage? = nil) -> NLLanguage {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return fallback?.nlLanguage ?? .english
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        if let dominant = recognizer.dominantLanguage,
           dominant != .undetermined,
           let confidence = hypotheses[dominant],
           confidence >= 0.45 {
            return dominant
        }

        // Lexical cue check for short queries where NLLanguageRecognizer confidence can be split
        let words = Set(tokenizeStatic(trimmed))
        let frenchCues: Set<String> = [
            "les", "des", "une", "dans", "pour", "avec", "sur", "aux", "est", "sont",
            "quel", "quelle", "quels", "quelles", "comment", "pourquoi", "recette", "recettes", "saison"
        ]
        let spanishCues: Set<String> = [
            "los", "las", "una", "unos", "unas", "del", "para", "con", "sobre",
            "cual", "cuales", "como", "donde", "porque"
        ]
        let englishCues: Set<String> = [
            "the", "and", "with", "from", "what", "which", "where", "when", "why", "how", "famous", "works"
        ]

        let frCount = words.intersection(frenchCues).count
        let esCount = words.intersection(spanishCues).count
        let enCount = words.intersection(englishCues).count
        if frCount > esCount && frCount > enCount {
            return .french
        }
        if esCount > frCount && esCount > enCount {
            return .spanish
        }
        if enCount > frCount && enCount > esCount {
            return .english
        }

        if let dominant = recognizer.dominantLanguage,
           dominant != .undetermined,
           let confidence = hypotheses[dominant],
           confidence >= 0.30 {
            return dominant
        }

        return fallback?.nlLanguage ?? .english
    }

    /// - Parameter query: User query to rank against.
    /// - Parameter historyTokens: Tokens consumed by conversation history.
    /// - Parameter maxOutputTokens: Requested response-token budget used to compute remaining context space.
    /// - Parameter contextUtilizationFactor: Optional context budget multiplier.
    ///   When nil, `options.contextUtilizationFactor` is used.
    /// - Parameter queries: When provided (Deep search), chunks are ranked by cosine similarity
    ///   against a combined TF vector built from every query (user + derived queries).
    /// - Parameter language: Optional fallback language if the query language cannot be determined.
    func selectContext(
        chunks: [RAGChunk],
        query: String,
        historyTokens: Int = 0,
        maxOutputTokens: Int,
        contextUtilizationFactor: Double? = nil,
        queries: [String]? = nil,
        language: ModelLanguage? = nil,
        options: RAGSelectionOptions = .default
    ) async -> RAGSelectionResult {
        guard !chunks.isEmpty else {
            return RAGSelectionResult(
                selectedContext: "",
                rankedChunks: [],
                selectedChunks: []
            )
        }

        let utilization = contextUtilizationFactor ?? options.contextUtilizationFactor
        let maxContextChars = calculate4096BudgetedContextCharacters(
            query: query,
            historyTokens: historyTokens,
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
        let embedding = resolveEmbedding(for: query, language: language)
        let wordEmbedding = resolveWordEmbedding(for: query, language: language)
        let queryEmbeddingInfo: (unitVector: [Double], query: String, embedding: NLEmbedding)? = {
            guard let embedding, let rawVec = embedding.vector(for: query) else { return nil }
            let norm = sqrt(rawVec.map { $0 * $0 }.reduce(0, +))
            guard norm > 0 else { return nil }
            return (rawVec.map { $0 / norm }, query, embedding)
        }()

        #if DEBUG
        let rankingStart = Date()
        #endif

        let allQueries = (queries?.isEmpty == false) ? queries! : [query]
        let stage1QueryVector = combinedQueryVector ?? combinedTermVector(from: allQueries)
        let stage1QueryDCT = dctUnitVector(for: numericQueryString)
        let maxStage2Chars = maxContextChars * 2

        struct ChunkCandidate {
            let index: Int
            let chunk: RAGChunk
            let baseScore: Double
        }

        // Stage 1: Fast Discrete Cosine Transform (DCT) & Lexical Cosine Ranking
        var candidates: [ChunkCandidate] = []
        candidates.reserveCapacity(chunks.count)

        for (idx, chunk) in chunks.enumerated() {
            let baseScore = dctCosineRelevanceScore(
                chunk: chunk,
                queryVector: stage1QueryVector,
                queryDCTVector: stage1QueryDCT,
                numericQueryString: numericQueryString,
                options: options
            )
            candidates.append(ChunkCandidate(index: idx, chunk: chunk, baseScore: baseScore))
        }

        // Sort chunks by Stage 1 DCT/cosine score descending
        candidates.sort { lhs, rhs in
            if lhs.baseScore == rhs.baseScore {
                return lhs.chunk.text.count > rhs.chunk.text.count
            }
            return lhs.baseScore > rhs.baseScore
        }

        // Keep only the top portion of sorted chunks such that cumulative chunk size
        // does not exceed 2x the token budget (2 * maxContextChars).
        var topCosineCandidates: [ChunkCandidate] = []
        topCosineCandidates.reserveCapacity(min(candidates.count, 32))
        var accumulatedStage2Chars = 0
        for candidate in candidates {
            let chunkChars = candidate.chunk.text.count
            if !topCosineCandidates.isEmpty && accumulatedStage2Chars + chunkChars > maxStage2Chars {
                break
            }
            topCosineCandidates.append(candidate)
            accumulatedStage2Chars += chunkChars
        }

        #if DEBUG
        print("[RAGContextService] Stage 1 (DCT/Cosine): \(chunks.count) chunks -> \(topCosineCandidates.count) candidates kept (\(accumulatedStage2Chars)/\(maxStage2Chars) chars, <= 2x token budget)")
        #endif

        var ranked: [RankedRAGChunk] = []
        ranked.reserveCapacity(topCosineCandidates.count)

        // Stage 2: Deep NLEmbedding evaluation only on the top bounded portion
        if let qInfo = queryEmbeddingInfo {
            for candidate in topCosineCandidates {
                var semanticScore = nlEmbeddingRelevanceScore(
                    chunk: candidate.chunk,
                    query: qInfo.query,
                    unitQueryVector: qInfo.unitVector,
                    embedding: qInfo.embedding,
                    options: options
                )
                if let wordEmbedding {
                    let wordScore = wordEmbeddingSemanticScore(
                        chunk: candidate.chunk,
                        query: query,
                        wordEmbedding: wordEmbedding
                    )
                    semanticScore = semanticScore * 0.75 + wordScore * 0.25
                }
                let combinedScore = semanticScore + candidate.baseScore * 0.35
                ranked.append(RankedRAGChunk(chunk: candidate.chunk, relevanceScore: combinedScore))
            }
        } else if let embedding {
            for candidate in topCosineCandidates {
                var semanticScore = nlEmbeddingRelevanceScore(
                    chunk: candidate.chunk,
                    query: query,
                    unitQueryVector: nil,
                    embedding: embedding,
                    options: options
                )
                if let wordEmbedding {
                    let wordScore = wordEmbeddingSemanticScore(
                        chunk: candidate.chunk,
                        query: query,
                        wordEmbedding: wordEmbedding
                    )
                    semanticScore = semanticScore * 0.75 + wordScore * 0.25
                }
                let combinedScore = semanticScore + candidate.baseScore * 0.35
                ranked.append(RankedRAGChunk(chunk: candidate.chunk, relevanceScore: combinedScore))
            }
        } else if let wordEmbedding {
            for candidate in topCosineCandidates {
                let wordScore = wordEmbeddingSemanticScore(
                    chunk: candidate.chunk,
                    query: query,
                    wordEmbedding: wordEmbedding,
                    includeBoostsWithOptions: options
                )
                let combinedScore = wordScore + candidate.baseScore * 0.45
                ranked.append(RankedRAGChunk(chunk: candidate.chunk, relevanceScore: combinedScore))
            }
        } else {
            for candidate in topCosineCandidates {
                ranked.append(RankedRAGChunk(chunk: candidate.chunk, relevanceScore: candidate.baseScore))
            }
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

        let finalSelectedChunks = selectedChunks.isEmpty && !ranked.isEmpty ? [ranked[0]] : selectedChunks

        #if DEBUG
        let rankingElapsed = Date().timeIntervalSince(rankingStart)
        print(String(format: "[Timing][RAGContextService] Ranked %d chunks in %.3f s (%.2f ms)", chunks.count, rankingElapsed, rankingElapsed * 1000.0))
        print("[RAGContextService] Stage 2 (NLEmbedding): \(ranked.count) candidates -> \(finalSelectedChunks.count) chunks kept after semantic ranking (\(currentChars)/\(maxContextChars) chars, <= 1x token budget)")
        let debugRanked = finalSelectedChunks.enumerated().map { index, r in
            (rank: index + 1, score: r.relevanceScore, source: r.chunk.source, text: r.chunk.text)
        }
        await DebugRAGStorage.shared.saveRankedChunks(query: query, chunks: debugRanked)
        #endif

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

    private func calculate4096BudgetedContextCharacters(
        query: String,
        historyTokens: Int,
        maxOutputTokens: Int,
        contextUtilizationFactor: Double,
        options: RAGSelectionOptions
    ) -> Int {
        let queryTokens = TokenBudgeting.estimatedTokens(forApproxCharacters: query.count)
        let effectiveOutputTokens = TokenBudgeting.clampedOutputTokens(
            requestedMaxTokens: maxOutputTokens,
            instructionTokens: options.instructionTokens,
            promptOverheadTokens: options.promptOverheadTokens,
            minContextTokens: options.minContextTokens
        )
        let nonContextTokens = queryTokens + historyTokens + options.instructionTokens + options.promptOverheadTokens + effectiveOutputTokens
        let availableTokens = max(0, TokenBudgeting.contextWindowLimit - nonContextTokens)
        let budgetedTokens = Int(Double(availableTokens) * min(max(contextUtilizationFactor, 0.1), 1.0))
        return max(options.minContextTokens * options.avgCharsPerToken, budgetedTokens * options.avgCharsPerToken)
    }

    /// Resolves the `NLEmbedding` sentence embedding matching the detected user query language.
    /// Does not fall back to `.english` when the query is in another language so non-English queries
    /// are never scored with an English sentence embedding.
    func resolveEmbedding(for query: String, language: ModelLanguage? = nil) -> NLEmbedding? {
        let targetLanguage = Self.detectQueryLanguage(for: query, fallback: language)

        if let cached = embeddingCache[targetLanguage] {
            return cached
        }
        if let loaded = NLEmbedding.sentenceEmbedding(for: targetLanguage) {
            embeddingCache[targetLanguage] = loaded
            return loaded
        }
        return nil
    }

    /// Resolves the `NLEmbedding` word embedding matching the detected user query language.
    func resolveWordEmbedding(for query: String, language: ModelLanguage? = nil) -> NLEmbedding? {
        let targetLanguage = Self.detectQueryLanguage(for: query, fallback: language)

        if let cached = wordEmbeddingCache[targetLanguage] {
            return cached
        }
        if let loaded = NLEmbedding.wordEmbedding(for: targetLanguage) {
            wordEmbeddingCache[targetLanguage] = loaded
            return loaded
        }
        return nil
    }

    /// Computes semantic similarity between `query` and `chunk` using the query language's `NLEmbedding.wordEmbedding`.
    private func wordEmbeddingSemanticScore(
        chunk: RAGChunk,
        query: String,
        wordEmbedding: NLEmbedding,
        includeBoostsWithOptions options: RAGSelectionOptions? = nil
    ) -> Double {
        let queryTerms = contentTokens(from: query)
        let chunkTerms = contentTokens(from: "\(chunk.source) \(chunk.text)")
        guard !queryTerms.isEmpty, !chunkTerms.isEmpty else {
            if let options {
                return relevanceScore(chunk: chunk, query: query, options: options)
            }
            return 0
        }

        // For each query term, find its best semantic match among chunk terms in the target language's word embedding space.
        var totalSimilarity = 0.0
        var evaluatedQueryTerms = 0

        let uniqueChunkTerms = Array(Set(chunkTerms).prefix(64))
        for qTerm in Set(queryTerms) {
            let qStem = Self.stemStatic(qTerm)
            var bestTermSim = 0.0
            let hasQVector = wordEmbedding.contains(qTerm) || wordEmbedding.contains(qStem)
            let qLookup = wordEmbedding.contains(qTerm) ? qTerm : qStem

            for cTerm in uniqueChunkTerms {
                let cStem = Self.stemStatic(cTerm)
                if qStem == cStem {
                    bestTermSim = 1.0
                    break
                }
                if hasQVector {
                    let cLookup = wordEmbedding.contains(cTerm) ? cTerm : (wordEmbedding.contains(cStem) ? cStem : nil)
                    if let cLookup {
                        let dist = wordEmbedding.distance(between: qLookup, and: cLookup, distanceType: .cosine)
                        if !dist.isNaN {
                            let sim = max(0.0, 1.0 - dist / 2.0)
                            if sim > bestTermSim {
                                bestTermSim = sim
                            }
                        }
                    }
                }
            }
            totalSimilarity += bestTermSim
            evaluatedQueryTerms += 1
        }

        var score = evaluatedQueryTerms > 0 ? (totalSimilarity / Double(evaluatedQueryTerms)) * 2.0 : 0.0
        if let options {
            if chunk.text.count > options.longChunkCharacterThreshold {
                score += options.longChunkBonusScore
            }
            score += Self.numericRelevanceBoost(text: chunk.text, query: query, options: options)
            score += Self.equationRelevanceBoost(text: chunk.text, query: query, options: options)
            score += Self.figureRelevanceBoost(chunk: chunk, query: query, options: options)
        }
        return score
    }

    private func nlEmbeddingRelevanceScore(
        chunk: RAGChunk,
        query: String,
        unitQueryVector: [Double]?,
        embedding: NLEmbedding,
        options: RAGSelectionOptions
    ) -> Double {
        let distance: Double
        if let unitQueryVector, let chunkVector = embedding.vector(for: chunk.text) {
            let chunkNorm = sqrt(chunkVector.map { $0 * $0 }.reduce(0, +))
            if chunkNorm > 0 {
                var diffSq = 0.0
                let count = min(unitQueryVector.count, chunkVector.count)
                for i in 0..<count {
                    let d = unitQueryVector[i] - (chunkVector[i] / chunkNorm)
                    diffSq += d * d
                }
                distance = sqrt(diffSq)
            } else {
                distance = embedding.distance(between: query, and: chunk.text, distanceType: .cosine)
            }
        } else {
            distance = embedding.distance(between: query, and: chunk.text, distanceType: .cosine)
        }

        guard !distance.isNaN else {
            return relevanceScore(chunk: chunk, query: query, options: options)
        }
        var score = max(0.0, 2.0 - distance)
        if chunk.text.count > options.longChunkCharacterThreshold {
            score += options.longChunkBonusScore
        }
        score += Self.numericRelevanceBoost(text: chunk.text, query: query, options: options)
        score += Self.equationRelevanceBoost(text: chunk.text, query: query, options: options)
        score += Self.figureRelevanceBoost(chunk: chunk, query: query, options: options)
        return score
    }

    private func relevanceScore(chunk: RAGChunk, query: String, options: RAGSelectionOptions) -> Double {
        let queryWords = Set(contentTokens(from: query).map(Self.stemStatic))
        guard !queryWords.isEmpty else { return 0 }

        let text = chunk.text
        let textWords = Set(contentTokens(from: "\(chunk.source) \(text)").map(Self.stemStatic))
        var score = 0.0
        for word in queryWords where textWords.contains(word) {
            score += 1.0
        }
        if text.count > options.longChunkCharacterThreshold {
            score += options.longChunkBonusScore
        }
        score += Self.numericRelevanceBoost(text: text, query: query, options: options)
        score += Self.equationRelevanceBoost(text: text, query: query, options: options)
        score += Self.figureRelevanceBoost(chunk: chunk, query: query, options: options)
        return score
    }

    /// Builds a stem-frequency vector from the union of content query tokens.
    private func combinedTermVector(from queries: [String]) -> [String: Double] {
        var vector: [String: Double] = [:]
        for query in queries {
            for term in contentTokens(from: query) {
                let stem = Self.stemStatic(term)
                vector[stem, default: 0] += 1
            }
        }
        return vector
    }

    /// Cosine similarity between a chunk and a precomputed query term vector,
    /// with sublinear TF scaling and multi-term coverage bonus to prevent single-word polysemous hijacking.
    private func cosineRelevanceScore(
        chunk: RAGChunk,
        queryVector: [String: Double],
        numericQueryString: String,
        options: RAGSelectionOptions
    ) -> Double {
        guard !queryVector.isEmpty else { return 0 }

        let text = chunk.text
        var textVector: [String: Double] = [:]
        for term in contentTokens(from: "\(chunk.source) \(text)") {
            let stem = Self.stemStatic(term)
            textVector[stem, default: 0] += 1
        }
        guard !textVector.isEmpty else { return 0 }

        var dot = 0.0
        var matchedQueryTerms = 0
        for (term, weight) in queryVector {
            if let rawCount = textVector[term], rawCount > 0 {
                // Sublinear TF scaling (1 + ln(tf)) prevents a single repeated polysemous word (e.g. "saison")
                // from dominating chunks that match multiple distinct query terms.
                let scaledTextWeight = 1.0 + log(rawCount)
                dot += weight * scaledTextWeight
                matchedQueryTerms += 1
            }
        }

        let queryNorm = sqrt(queryVector.values.reduce(0) { $0 + $1 * $1 })
        let textNorm = sqrt(textVector.values.reduce(0) {
            let scaled = 1.0 + log(max(1.0, $1))
            return $0 + scaled * scaled
        })
        guard queryNorm > 0, textNorm > 0 else { return 0 }

        var score = dot / (queryNorm * textNorm)
        if queryVector.count >= 2 {
            let coverageRatio = Double(matchedQueryTerms) / Double(queryVector.count)
            score += coverageRatio * 0.45
        }
        if text.count > options.longChunkCharacterThreshold {
            score += options.longChunkBonusScore
        }
        score += Self.numericRelevanceBoost(text: text, query: numericQueryString, options: options)
        score += Self.equationRelevanceBoost(text: text, query: numericQueryString, options: options)
        score += Self.figureRelevanceBoost(chunk: chunk, query: numericQueryString, options: options)
        return score
    }

    // MARK: - Discrete Cosine Transform (DCT) Stage 1 Pre-Ranking

    private nonisolated static let dctLength = 64
    private nonisolated static let dctSetup = vDSP.DCT(count: dctLength, transformType: .II)

    /// Deterministic FNV-1a 64-bit hash for projecting tokens and character stems into a fixed signal.
    @inline(__always)
    private nonisolated static func fnv1aHash(_ bytes: String.UTF8View) -> UInt64 {
        var hash: UInt64 = 14695981039346656037
        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }

    /// Projects text tokens and stems into a fixed-length signal, transforms via 1D Type-II
    /// Discrete Cosine Transform (`vDSP.DCT`), and returns an L2-normalized frequency vector.
    private func dctUnitVector(for text: String) -> [Float]? {
        guard let dct = Self.dctSetup else { return nil }
        let terms = tokenize(text).filter { $0.count > 2 }
        guard !terms.isEmpty else { return nil }

        var signal = [Float](repeating: 0, count: Self.dctLength)
        let mask = UInt64(Self.dctLength - 1)

        for term in terms {
            let h = Self.fnv1aHash(term.utf8)
            let bin = Int(h & mask)
            let sign: Float = ((h >> 32) & 1) == 0 ? 1.0 : -1.0
            signal[bin] += sign

            // Project 4-character prefix stem so morphological variants share spectral energy
            if term.count > 4 {
                let stem = String(term.prefix(4))
                let sh = Self.fnv1aHash(stem.utf8)
                let sBin = Int(sh & mask)
                let sSign: Float = ((sh >> 32) & 1) == 0 ? 0.5 : -0.5
                signal[sBin] += sSign
            }
        }

        var spectrum = [Float](repeating: 0, count: Self.dctLength)
        dct.transform(signal, result: &spectrum)

        var sumSquares: Float = 0
        vDSP_svesq(spectrum, 1, &sumSquares, vDSP_Length(Self.dctLength))
        let norm = sqrt(sumSquares)
        guard norm > 0 else { return nil }

        var scale = 1.0 / norm
        var unitSpectrum = [Float](repeating: 0, count: Self.dctLength)
        vDSP_vsmul(spectrum, 1, &scale, &unitSpectrum, 1, vDSP_Length(Self.dctLength))
        return unitSpectrum
    }

    /// Fast Stage 1 relevance score combining Discrete Cosine Transform (DCT) spectral cosine similarity
    /// and lexical term-frequency cosine similarity with numeric, equation, and figure boosts.
    private func dctCosineRelevanceScore(
        chunk: RAGChunk,
        queryVector: [String: Double],
        queryDCTVector: [Float]?,
        numericQueryString: String,
        options: RAGSelectionOptions
    ) -> Double {
        var score = cosineRelevanceScore(
            chunk: chunk,
            queryVector: queryVector,
            numericQueryString: numericQueryString,
            options: options
        )

        if let queryDCTVector, let chunkDCTVector = dctUnitVector(for: chunk.text) {
            var dctDot: Float = 0
            vDSP_dotpr(queryDCTVector, 1, chunkDCTVector, 1, &dctDot, vDSP_Length(Self.dctLength))
            let dctCosine = max(0.0, Double(dctDot))
            score += dctCosine * 0.5
        }

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
    /// Matches explicit equation references such as "equation 5", "eq 5",
    /// "eq. 5", and numbered display-equation markers like "(5)".
    private nonisolated static let equationReferenceRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "(?:\\b(?:eq(?:uation)?s?\\.?)\\s*(?:no\\.?\\s*)?\\(?\\s*(\\d{1,3})\\s*\\)?)|(?:\\((\\d{1,3})\\))",
        options: [.caseInsensitive]
    )
    /// Matches explicit figure references such as "figure 5", "fig 5",
    /// and "fig. 5".
    private nonisolated static let figureReferenceRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "\\b(?:fig(?:ure)?s?\\.?)\\s*(?:no\\.?\\s*)?\\(?\\s*(\\d{1,3})\\s*\\)?",
        options: [.caseInsensitive]
    )
    /// Matches explicit page references such as "page 8" or "p. 8".
    private nonisolated static let pageReferenceRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "\\b(?:page|pages|p\\.)\\s*(\\d{1,3})\\b",
        options: [.caseInsensitive]
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

    nonisolated static func hasEquationIntent(_ query: String) -> Bool {
        let tokens = tokenizeStatic(query)
        return tokens.contains("equation") || tokens.contains("equations") || tokens.contains("eq")
    }

    nonisolated static func hasFigureIntent(_ query: String) -> Bool {
        let tokens = tokenizeStatic(query)
        return tokens.contains("figure") || tokens.contains("fig") || tokens.contains("figures")
    }

    /// Heuristic: does the query look like it needs *recent / current*
    /// information rather than encyclopedic background? Detects EN/FR/ES
    /// cues for "today", "this week", "current", "news", "trending", etc.
    /// — Wikipedia almost never has useful content for these so callers
    /// can skip it. Keep the list tight; widening it would mis-flag
    /// definitional queries that happen to mention a date.
    nonisolated static func hasTemporalIntent(_ query: String) -> Bool {
        let lowered = query.lowercased()
        let cues = [
            // English
            "today", "now", "this week", "this month", "this year",
            "recent", "latest", "current", "currently", "breaking",
            "news", "yesterday", "tomorrow", "trending", "live",
            // French
            "aujourd'hui", "aujourd hui", "actualité", "actualités",
            "récent", "récente", "récemment", "dernière", "dernières",
            "cette semaine", "ce mois", "cette année", "hier",
            "demain", "tendance", "tendances", "en direct", "live",
            // Spanish
            "hoy", "actualidad", "noticias", "reciente", "última",
            "últimas", "esta semana", "este mes", "este año", "ayer",
            "mañana", "tendencia", "en vivo"
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

    nonisolated static func extractEquationReferenceNumbers(_ text: String) -> Set<String> {
        guard let regex = equationReferenceRegex else { return [] }
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)
        var references: Set<String> = []
        references.reserveCapacity(matches.count)
        for match in matches {
            for rangeIndex in 1..<match.numberOfRanges {
                guard let range = Range(match.range(at: rangeIndex), in: text) else { continue }
                let digits = String(text[range]).filter(\.isNumber)
                if !digits.isEmpty {
                    references.insert(digits)
                }
            }
        }
        if !references.isEmpty {
            return references
        }
        guard hasEquationIntent(text) else { return [] }
        return extractNumericTokens(text).filter { token in
            !token.isEmpty && token.allSatisfy(\.isNumber) && token.count <= 3
        }
    }

    nonisolated static func extractFigureReferenceNumbers(_ text: String) -> Set<String> {
        guard let regex = figureReferenceRegex else { return [] }
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)
        var references: Set<String> = []
        references.reserveCapacity(matches.count)
        for match in matches {
            guard let range = Range(match.range(at: 1), in: text) else { continue }
            let digits = String(text[range]).filter(\.isNumber)
            if !digits.isEmpty {
                references.insert(digits)
            }
        }
        return references
    }

    nonisolated static func extractRequestedPageNumbers(_ text: String) -> Set<String> {
        guard let regex = pageReferenceRegex else { return [] }
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)
        var pages: Set<String> = []
        pages.reserveCapacity(matches.count)
        for match in matches {
            guard let range = Range(match.range(at: 1), in: text) else { continue }
            let digits = String(text[range]).filter(\.isNumber)
            if !digits.isEmpty {
                pages.insert(digits)
            }
        }
        return pages
    }

    nonisolated static func textContainsFormulaSyntax(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("=")
            || lowered.contains("ln(")
            || lowered.contains("log(")
            || lowered.contains("exp(")
            || lowered.contains("sqrt")
            || lowered.contains("∑")
            || lowered.contains("∫")
    }

    nonisolated static func textContainsFigureCue(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("figure") || lowered.contains("fig.")
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

    nonisolated static func equationRelevanceBoost(
        text: String,
        query: String,
        options: RAGSelectionOptions
    ) -> Double {
        guard hasEquationIntent(query) else { return 0 }

        let queryReferences = extractEquationReferenceNumbers(query)
        if !queryReferences.isEmpty {
            let textReferences = extractEquationReferenceNumbers(text)
            let overlapCount = queryReferences.intersection(textReferences).count
            guard overlapCount > 0 else { return 0 }

            var score = Double(overlapCount) * options.equationReferenceMatchBonus
            if textContainsFormulaSyntax(text) {
                score += options.equationFormulaBonus
            }
            return score
        }

        return textContainsFormulaSyntax(text) ? options.equationPresenceBonus : 0
    }

    nonisolated static func figureRelevanceBoost(
        chunk: RAGChunk,
        query: String,
        options: RAGSelectionOptions
    ) -> Double {
        guard hasFigureIntent(query) else { return 0 }

        let text = chunk.text
        var score = 0.0

        let queryFigureReferences = extractFigureReferenceNumbers(query)
        if !queryFigureReferences.isEmpty {
            let textFigureReferences = extractFigureReferenceNumbers(text)
            let overlapCount = queryFigureReferences.intersection(textFigureReferences).count
            if overlapCount > 0 {
                score += Double(overlapCount) * options.figureReferenceMatchBonus
                if textContainsFigureCue(text) {
                    score += options.figureCaptionBonus
                }
            }
        }

        let requestedPages = extractRequestedPageNumbers(query)
        if let pdfPage = chunk.pdfPage,
           !requestedPages.isEmpty,
           requestedPages.contains(String(pdfPage)) {
            score += options.figurePageMatchBonus
            if textContainsFigureCue(text) {
                score += options.figureCaptionBonus
            }
        }

        if score > 0 {
            return score
        }

        return textContainsFigureCue(text) ? options.figurePresenceBonus : 0
    }

    private func tokenize(_ text: String) -> [String] {
        Self.tokenizeStatic(text)
    }

    private func contentTokens(from text: String) -> [String] {
        Self.tokenizeStatic(text).filter { token in
            guard token.count > 2 else { return false }
            let folded = token.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return !Self.rankingStopWords.contains(token) && !Self.rankingStopWords.contains(folded)
        }
    }

    nonisolated static func stemStatic(_ token: String) -> String {
        var str = token.lowercased()
        guard str.count > 3 else { return str }
        if str.hasSuffix("ies") && str.count > 4 {
            str.removeLast(3)
            str.append("y")
            return str
        }
        if (str.hasSuffix("sses") || str.hasSuffix("xes") || str.hasSuffix("shes") || str.hasSuffix("ches")) && str.count > 4 {
            str.removeLast(2)
            return str
        }
        if str.hasSuffix("aux") && str.count > 4 {
            str.removeLast(2)
            str.append("l")
            return str
        }
        if (str.hasSuffix("s") && !str.hasSuffix("ss")) || str.hasSuffix("x") {
            str.removeLast()
        }
        return str
    }

    private nonisolated static func tokenizeStatic(_ text: String) -> [String] {
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
