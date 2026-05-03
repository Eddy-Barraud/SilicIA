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
struct RAGChunker {
    private static let avgCharsPerToken = 3
    private static let whitespacePattern = "\\s+"
    private static let minimumChunkCharacters = 200

    /// Chunks text with overlap while preserving non-empty slices.
    func chunk(
        text: String,
        source: String,
        maxChunkTokens: Int,
        overlapTokens: Int,
        url: String? = nil,
        pdfPage: Int? = nil
    ) -> [RAGChunk] {
        let cleanText = text
            .replacingOccurrences(of: Self.whitespacePattern, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanText.isEmpty else { return [] }

        let maxChunkChars = max(Self.minimumChunkCharacters, maxChunkTokens * Self.avgCharsPerToken)
        let overlapChars = min(maxChunkChars / 2, max(0, overlapTokens * Self.avgCharsPerToken))
        let stride = max(1, maxChunkChars - overlapChars)

        var chunks: [RAGChunk] = []
        var start = cleanText.startIndex

        while start < cleanText.endIndex {
            let end = cleanText.index(start, offsetBy: maxChunkChars, limitedBy: cleanText.endIndex) ?? cleanText.endIndex
            let piece = String(cleanText[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty {
                chunks.append(RAGChunk(source: source, text: piece, url: url, pdfPage: pdfPage))
            }

            if end == cleanText.endIndex { break }
            start = cleanText.index(start, offsetBy: stride, limitedBy: cleanText.endIndex) ?? cleanText.endIndex
        }

        return chunks
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

    nonisolated static let `default` = RAGSelectionOptions(
        avgCharsPerToken: TokenBudgeting.avgCharsPerToken,
        instructionTokens: TokenBudgeting.instructionTokens,
        promptOverheadTokens: TokenBudgeting.promptOverheadTokens,
        minContextTokens: TokenBudgeting.minContextTokens,
        contextUtilizationFactor: 0.8,
        minimumFallbackContextCharacters: 200,
        longChunkCharacterThreshold: 300,
        longChunkBonusScore: 0.2
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

    var topChunks: [RankedRAGChunk] {
        Array(rankedChunks.prefix(3))
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
                rankedChunks: []
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

        var ranked: [RankedRAGChunk] = []
        ranked.reserveCapacity(chunks.count)
        for chunk in chunks {
            let score: Double
            if let combinedQueryVector {
                score = cosineRelevanceScore(
                    text: chunk.text,
                    queryVector: combinedQueryVector,
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
        var currentChars = 0
        let separator = "\n\n---\n\n"
        for rankedChunk in ranked {
            let chunkEntry = "Source: \(rankedChunk.chunk.source)\n\(rankedChunk.chunk.text)"
            let separatorChars = selected.isEmpty ? 0 : separator.count
            if currentChars + separatorChars + chunkEntry.count > maxContextChars {
                continue
            }
            selected.append(chunkEntry)
            currentChars += separatorChars + chunkEntry.count
        }

        if selected.isEmpty, let first = ranked.first {
            let fallback = "Source: \(first.chunk.source)\n\(first.chunk.text)"
            return RAGSelectionResult(
                selectedContext: String(fallback.prefix(max(options.minimumFallbackContextCharacters, maxContextChars))),
                rankedChunks: ranked
            )
        }

        return RAGSelectionResult(
            selectedContext: selected.joined(separator: separator),
            rankedChunks: ranked
        )
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
        return score
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
