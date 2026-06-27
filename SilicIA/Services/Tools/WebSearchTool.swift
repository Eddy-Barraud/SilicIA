//
//  WebSearchTool.swift
//  SilicIA
//
//  Foundation Models tool that exposes DuckDuckGo + Wikipedia search and
//  page scraping as an on-demand call. When tool-calling mode is enabled
//  the model crafts the query itself from the user's question and decides
//  whether the answer requires fresh / external information at all.
//
//  Why a tool instead of the existing auto-prefetch path:
//
//  - The model knows the question's actual intent, so it can compose a
//    more focused query than `currentMessage + contextInput`. "Who won
//    the 2024 Wimbledon final?" → query "2024 Wimbledon final winner",
//    not the whole user turn verbatim.
//  - The model decides whether to search at all. "What is 2+2" should
//    never hit the network.
//  - Multiple follow-up calls: the model can refine after seeing the
//    first set of results, e.g. switching from a general topic to a
//    specific person it discovered.
//

import Foundation
import FoundationModels

struct WebSearchTool: Tool {

    @Generable
    struct Arguments {
        @Guide(description: "The search query — focused keywords, not the user's full question. Strip filler words; keep proper nouns, numbers, dates, and any unit the user mentioned. Examples: '2024 Wimbledon men final winner', 'Apple Foundation Models tool calling API', 'Paris population 2023'.")
        let query: String

        @Guide(description: "Number of results to return (3–5). Prefer 4 by default so the user gets a range of sources and your answer can triangulate; use 5 for broader topic surveys. The minimum 3 ensures the user always sees several perspectives.")
        let maxResults: Int?
    }

    let name = "webSearch"
    let description = """
    Search the web (DuckDuckGo + Wikipedia) and return the top results' \
    titles, URLs, and scraped content. Use this whenever the question \
    requires current information, recent events, or details beyond your \
    training data — and only when needed; do NOT call this for arithmetic, \
    definitions, or anything you can answer directly. You may call multiple \
    times in a single turn with refined queries if the first batch was \
    incomplete.
    """

    /// Injected by ChatService so the tool reuses the existing scraping
    /// + search machinery (rate limits, locale, custom UA, etc.).
    let webSearchService: WebSearchService
    let webScraper: WebScrapingService
    let maxDuckDuckGoResults: Int
    let maxWikipediaResults: Int
    let useDuckDuckGo: Bool
    let useWikipedia: Bool
    let language: ModelLanguage

    /// Optional sink that receives the URLs / titles / scraped content the
    /// model has actually consulted. SearchView wires this into AIService
    /// so the results can be surfaced as cards in the UI with RAG match
    /// scores, mirroring the prompt-stuffing path's card behavior. Fires
    /// once per tool invocation with the slice of `[SearchResult]` that
    /// the model received as the tool reply.
    var onResults: (@Sendable ([SearchResult]) -> Void)? = nil

    /// Token budget for the entire tool reply (titles + URLs + scraped
    /// content). Caller-supplied so it scales with the conversation's
    /// response cap. Divided by `defaultMaxResults` to derive the
    /// per-page character cap.
    var tokenBudget: Int = 1500

    /// Shared per-generation loop breaker. webSearch is the most important
    /// tool to govern: its replies are the largest, so a runaway loop here
    /// is what overflows the context window. Optional so existing callers /
    /// tests that construct the tool directly are unaffected.
    var governor: ToolCallGovernor?
    /// Records successful tool replies so a later context-window overflow
    /// can recover from the last known-good tool state.
    var transcriptRecorder: ToolTranscriptRecorder?

    /// Default result count when the model doesn't supply `maxResults`.
    /// Five gives SearchView a useful range of cards to display and lets
    /// the model triangulate across sources when summarising.
    private static let defaultMaxResults = 5

    /// Hard floor on the result count regardless of what the model asks
    /// for. Models routinely pick `maxResults=1` because their training
    /// labels low counts as "quick lookup"; for SearchView's card UX
    /// that produces a single-source list the user reads as broken.
    /// Three is the smallest count that conveys "we surveyed sources".
    private static let minResults = 3
    /// Hard ceiling so a model that asks for 10 doesn't blow the
    /// per-call token budget.
    private static let maxResultsCap = 5

    /// Overhead per result block (title + URL + headers). Roughly
    /// estimated so the derived per-page char budget leaves space for it.
    private static let overheadCharsPerResult = 120

    func call(arguments: Arguments) async throws -> String {
        #if DEBUG
        print("[Tool:webSearch] called with query=\"\(arguments.query)\" maxResults=\(arguments.maxResults.map(String.init) ?? "default")")
        #endif

        // Loop breaker: refuse duplicate / over-budget calls before doing
        // any network work, so a runaway model can't overflow the window.
        if let governor {
            let decision = await governor.evaluate(tool: name, arguments: arguments.query)
            if case .allow = decision {
                // continue
            } else if let refusal = decision.refusalMessage {
                return refusal
            }
        }

        let trimmed = arguments.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Error: empty query. Provide focused keywords (3–6 words usually works best)."
        }
        guard useDuckDuckGo || useWikipedia else {
            return """
            Web search is not available in this conversation: both \
            DuckDuckGo and Wikipedia are disabled in settings. Answer the \
            user from your own knowledge instead.
            """
        }

        let limit = max(Self.minResults, min(arguments.maxResults ?? Self.defaultMaxResults, Self.maxResultsCap))

        // Derive per-page char cap from the total token budget. We split
        // the budget evenly across the model-requested result count,
        // then subtract a small per-result overhead for the title/URL
        // headers we emit. Token → char conversion uses the shared
        // avgCharsPerToken so this scales coherently with the rest of
        // the context-token accounting.
        let totalChars = max(0, tokenBudget) * TokenBudgeting.avgCharsPerToken
        let perResultCharBudget = max(
            300,
            (totalChars / max(1, limit)) - Self.overheadCharsPerResult
        )

        // Suppress Wikipedia when the model asked for current/recent
        // information. Wikipedia's keyword search dutifully returns the
        // closest encyclopedic article ("Crise des subprimes" for
        // "actualité des marchés cette semaine"), which is exactly the
        // wrong content for a time-sensitive query — DDG already covers
        // current news in the same call. Only kicks in when the model's
        // query carries temporal cues; definitional queries unaffected.
        let temporal = RAGContextService.hasTemporalIntent(trimmed)
        let effectiveUseWikipedia = useWikipedia && !temporal
        #if DEBUG
        if useWikipedia && !effectiveUseWikipedia {
            print("[Tool:webSearch] suppressing Wikipedia for temporal query: \"\(trimmed)\"")
        }
        #endif

        let results: [SearchResult]
        do {
            results = try await webSearchService.search(
                query: trimmed,
                maxDuckDuckGoResults: maxDuckDuckGoResults,
                maxWikipediaResults: maxWikipediaResults,
                language: language,
                useDuckDuckGo: useDuckDuckGo,
                useWikipedia: effectiveUseWikipedia
            )
        } catch is CancellationError {
            // User pressed Stop while the tool was running — re-throw so the
            // surrounding model session bails out cleanly instead of seeing
            // a stale tool result.
            throw CancellationError()
        } catch {
            return "Web search failed: \(error.localizedDescription). Answer from your own knowledge instead of retrying."
        }

        let top = Array(results.prefix(limit))
        guard !top.isEmpty else {
            return "No web results found for query: '\(trimmed)'. Refine the query (e.g. add a year or proper noun) or answer from your own knowledge."
        }

        // Scrape pages that didn't ship full content already (Wikipedia
        // results typically have `retrievedContent`; DuckDuckGo results
        // are usually snippet-only and need a scrape).
        let urlsToScrape = top.compactMap { result -> String? in
            guard (result.retrievedContent ?? "").trimmingCharacters(in: .whitespaces).isEmpty else {
                return nil
            }
            return result.url
        }
        let scraped = await webScraper.scrapeMultiplePages(
            urls: urlsToScrape,
            limit: limit,
            maxCharacters: perResultCharBudget
        )

        // Each result block carries enough metadata for the model to cite
        // it accurately in its final answer.
        let rendered = top.enumerated().map { idx, result -> String in
            var lines = ["--- Result \(idx + 1): \(result.title)"]
            lines.append("URL: \(result.url)")
            let body: String
            if let retrieved = result.retrievedContent,
               !retrieved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                body = String(retrieved.prefix(perResultCharBudget))
            } else if let scrapedBody = scraped[result.url],
                      !scrapedBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                body = scrapedBody
            } else {
                body = result.snippet
            }
            lines.append("Content: \(body)")
            return lines.joined(separator: "\n")
        }

        #if DEBUG
        print("[Tool:webSearch] returning \(top.count) result(s) to model, \(results.count) to cards")
        #endif
        // Send EVERY fetched result to the UI sink, not just the slice the
        // model received. The model's reply (`rendered`) is still bounded
        // by its requested `maxResults`, so the model's context isn't
        // affected — but the user gets to see all the sources the tool
        // actually surfaced, the same way the prompt-stuffing path's
        // search-result cards do.
        onResults?(results)
        let output = rendered.joined(separator: "\n\n")
        if let transcriptRecorder {
            await transcriptRecorder.record(tool: name, arguments: trimmed, result: output)
        }
        return output
    }
}
