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

    /// Default cap when the model doesn't supply `maxResults`. Three is
    /// a good baseline: enough to surface the right row + its header +
    /// some neighbouring context, but not so many that the tool reply
    /// overruns the model's context window.
    private static let defaultMaxResults = 3

    func call(arguments: Arguments) async throws -> String {
        #if DEBUG
        print("[Tool:searchContext] called with query=\"\(arguments.query)\" maxResults=\(arguments.maxResults.map(String.init) ?? "default") corpusSize=\(chunks.count)")
        #endif
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

        // Render each chunk with its source header so the model can cite
        // accurately and decide whether a follow-up call to a different
        // source is needed.
        let rendered = top.enumerated().map { idx, ranked -> String in
            var header = "--- Result \(idx + 1): \(ranked.chunk.source)"
            if let page = ranked.chunk.pdfPage { header += " (page \(page))" }
            if let url = ranked.chunk.url { header += " — \(url)" }
            header += " ---"
            return "\(header)\n\(ranked.chunk.text)"
        }
        #if DEBUG
        print("[Tool:searchContext] returning \(top.count) chunk(s), totalChars=\(rendered.map(\.count).reduce(0, +))")
        #endif
        return rendered.joined(separator: "\n\n")
    }
}
