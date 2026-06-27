//
//  RAGSearchTool.swift
//  SilicIA
//
//  Foundation Models tool that exposes the user's RAG corpus
//  (PDFs / images / web scrapes) as an on-demand search.
//
//  Why convert RAG to a tool:
//
//  In the existing flow we stuff the top-K chunks into the system prompt
//  on every turn, whether the model needs them or not, and we pick the
//  chunks ourselves via a fixed relevance score. Two problems:
//
//  - Wrong chunks shipped on follow-up questions: the user's first turn
//    might be "summarize" (general chunks) but the second is "what's
//    line item 3" (table chunks) — both turns get the same pre-baked
//    selection. Tool calling lets the model re-query as the
//    conversation evolves.
//
//  - The model can't ask for *more* context when its first answer is
//    incomplete. With a tool it can call `searchContext` again with a
//    refined query (e.g. add the line-item code it saw in the first
//    result).
//
//  This implementation keeps the existing chunker / scorer; the tool
//  just makes them callable on demand.
//

import Foundation
import FoundationModels

/// On-demand search over the user's pre-chunked context corpus.
///
/// `chunks` is fixed for the lifetime of the tool instance — built once
/// per conversation turn by `ChatService` before the model runs, mirroring
/// the existing pre-analysis cache. The tool then runs the same RAG
/// relevance scoring + budget filter the prompt-stuffing path uses, so
/// answer quality should be no worse than the baseline, with the upside
/// that the model picks the query string.
struct RAGSearchTool: Tool {

    @Generable
    struct Arguments {
        @Guide(description: "A focused search query — use the user's exact terms plus any concrete numbers, units, currency, dates, or proper nouns from their question. Short, precise queries return better results than verbose ones.")
        let query: String

        @Guide(description: "Maximum number of passages to return. Use 1-3 for a quick fact lookup, 5 for richer context. Defaults to 3 when unspecified.")
        let maxResults: Int?
    }

    let name = "searchContext"
    let description = """
    Search the user's attached documents (PDFs, images, web pages) for \
    passages relevant to a query. Returns a list of passages with their \
    source. Use this whenever the user's question depends on information \
    from the documents — do NOT guess from memory when a search would \
    give you the exact text. You may call this tool multiple times in a \
    single turn with refined queries if the first result was incomplete.
    """

    let chunks: [RAGChunk]

    /// Token budget for the chunks returned to the model on a single call.
    /// Caller-supplied so it scales with the conversation's response cap
    /// (see `TokenBudgeting.toolOutputTokenBudget(forResponseTokens:)`).
    /// Falls back to a sensible default when constructed via the
    /// memberwise init without a budget — useful for tests.
    var tokenBudget: Int = 1500

    /// Shared per-generation loop breaker. Refuses duplicate / over-budget
    /// calls. Optional so direct callers / tests are unaffected.
    var governor: ToolCallGovernor?
    /// Records successful tool replies so a later context-window overflow
    /// can recover from the last known-good tool state.
    var transcriptRecorder: ToolTranscriptRecorder?

    /// Default cap when the model doesn't supply `maxResults`. Three is
    /// a good baseline: enough to surface the right row + its header +
    /// some neighbouring context, but not so many that the tool reply
    /// overruns the model's context window.
    private static let defaultMaxResults = 3
    private static let perResultSeparator = "\n\n"

    func call(arguments: Arguments) async throws -> String {
        #if DEBUG
        print("[Tool:searchContext] called with query=\"\(arguments.query)\" maxResults=\(arguments.maxResults.map(String.init) ?? "default") corpusSize=\(chunks.count)")
        #endif

        if let governor {
            let decision = await governor.evaluate(tool: name, arguments: arguments.query)
            if case .allow = decision {
                // continue
            } else if transcriptRecorder != nil {
                switch decision {
                case .allow:
                    break
                case .duplicate(let count):
                    throw ToolError.duplicate(tool: name, count: count)
                case .toolBudgetReached(let tool, let cap):
                    throw ToolError.toolBudgetReached(tool: tool, cap: cap)
                case .totalBudgetReached(let cap):
                    throw ToolError.totalBudgetReached(cap: cap)
                }
            } else if let refusal = decision.refusalMessage {
                return refusal
            }
        }

        let trimmed = arguments.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Error: empty query"
        }
        guard !chunks.isEmpty else {
            return "No documents are attached to this conversation."
        }

        let limit = max(1, min(arguments.maxResults ?? Self.defaultMaxResults, 10))

        let service = RAGContextService()
        let result = await service.selectContext(
            chunks: chunks,
            query: trimmed,
            maxOutputTokens: tokenBudget
        )

        let top = Array(result.selectedChunks.prefix(limit))
        guard !top.isEmpty else {
            return "No relevant passages found for query: '\(trimmed)'."
        }

        let characterBudget = max(1, TokenBudgeting.estimatedContextCharacters(forTokens: tokenBudget))
        // Render each chunk with its source header so the model can cite
        // accurately and decide whether a follow-up call to a different
        // source is needed.
        var rendered: [String] = []
        var remainingChars = characterBudget
        for (idx, ranked) in top.enumerated() {
            var header = "--- Result \(idx + 1): \(ranked.chunk.source)"
            if let page = ranked.chunk.pdfPage { header += " (page \(page))" }
            if let url = ranked.chunk.url { header += " — \(url)" }
            header += " ---"
            let separatorChars = rendered.isEmpty ? 0 : Self.perResultSeparator.count
            let availableForResult = remainingChars - separatorChars
            guard availableForResult > header.count + 32 else { break }

            let excerptBudget = availableForResult - header.count - 1
            let body = excerpt(of: ranked.chunk.text, query: trimmed, characterBudget: excerptBudget)
            let block = "\(header)\n\(body)"
            rendered.append(block)
            remainingChars -= separatorChars + block.count
            if remainingChars <= 0 { break }
        }
        guard !rendered.isEmpty else {
            return "No relevant passages found for query: '\(trimmed)'."
        }
        #if DEBUG
        print("[Tool:searchContext] returning \(top.count) chunk(s), totalChars=\(rendered.map(\.count).reduce(0, +))")
        #endif
        let joined = rendered.joined(separator: Self.perResultSeparator)
        let output: String
        if joined.count <= characterBudget {
            output = joined
        } else {
            output = String(joined.prefix(characterBudget)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let transcriptRecorder {
            await transcriptRecorder.record(tool: name, arguments: trimmed, result: output)
        }
        return output
    }

    private func excerpt(of text: String, query: String, characterBudget: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > characterBudget else { return trimmed }
        guard characterBudget > 0 else { return "" }

        let loweredText = trimmed.lowercased()
        let loweredNSString = loweredText as NSString
        let terms = queryTerms(from: query)
        let focusIndex = terms.compactMap { term in
            let range = loweredNSString.range(of: term)
            return range.location == NSNotFound ? nil : range.location
        }.min() ?? 0

        let leadingRoom = max(characterBudget / 3, 0)
        let startOffset = max(0, focusIndex - leadingRoom)
        let startIndex = trimmed.index(trimmed.startIndex, offsetBy: min(startOffset, trimmed.count))
        let rawEndIndex = trimmed.index(startIndex, offsetBy: min(characterBudget, trimmed.distance(from: startIndex, to: trimmed.endIndex)))
        let snippet = String(trimmed[startIndex..<rawEndIndex]).trimmingCharacters(in: .whitespacesAndNewlines)

        if startIndex == trimmed.startIndex {
            return snippet
        }
        return "…\(snippet)"
    }

    private func queryTerms(from query: String) -> [String] {
        query
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs < rhs
                }
                return lhs.count > rhs.count
            }
    }
}
