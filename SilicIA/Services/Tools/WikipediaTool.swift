//
//  WikipediaTool.swift
//  SilicIA
//
//  Foundation Models tool that queries Wikipedia REST APIs directly for
//  encyclopedic knowledge and articles. Returns clean Markdown article
//  content to the model and surfaces the pages as cards in SearchView.
//

import Foundation
import FoundationModels

struct WikipediaTool: Tool {

    @Generable
    struct Arguments {
        @Guide(description: "One or two words max. Simple concepts, person names, machine names, technique names, or places (e.g. 'Paris', 'Nantes', 'Albert Einstein', 'Photosynthèse', 'Machine de Turing'). Never use full sentences, questions, or conversational words.")
        let query: String
    }

    let name = "wikipediaSearch"
    let description = """
    Search Wikipedia for encyclopedic articles about concepts, persons, \
    places, events, machines, or techniques. Returns the full summary and \
    content of the matching Wikipedia pages.
    """

    let webSearchService: WebSearchService
    let maxWikipediaResults: Int
    let language: ModelLanguage

    var onResults: (@Sendable ([SearchResult]) -> Void)? = nil
    var tokenBudget: Int = 1500
    var governor: ToolCallGovernor?
    var transcriptRecorder: ToolTranscriptRecorder?

    private static let overheadCharsPerResult = 120

    func call(arguments: Arguments) async throws -> String {
        #if DEBUG
        print("[Tool:wikipediaSearch] called with query=\"\(arguments.query)\" limit=\(maxWikipediaResults)")
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
            return "Error: empty query. Provide a 1- or 2-word topic or concept name."
        }

        let limit = max(1, maxWikipediaResults)

        let totalChars = max(0, tokenBudget) * TokenBudgeting.avgCharsPerToken
        let perResultCharBudget = max(
            500,
            (totalChars / max(1, limit)) - Self.overheadCharsPerResult
        )

        let results: [SearchResult]
        do {
            results = try await webSearchService.searchWikipedia(
                query: trimmed,
                language: language,
                limit: limit
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            #if DEBUG
            print("[Tool:wikipediaSearch] fetch failed: \(error.localizedDescription)")
            #endif
            return "Wikipedia search failed for '\(trimmed)': \(error.localizedDescription)."
        }

        guard !results.isEmpty else {
            return "No Wikipedia article found for query: '\(trimmed)'. Refine the query to a 1–2 word concept, person name, or place, or use `webSearch`."
        }

        let top = Array(results.prefix(limit))
        let rendered = top.enumerated().map { idx, result -> String in
            var lines = ["--- Wikipedia Result \(idx + 1): \(result.title)"]
            lines.append("URL: \(result.url)")
            let content = result.retrievedContent ?? result.snippet
            let body = String(content.prefix(perResultCharBudget))
            lines.append("Content: \(body)")
            return lines.joined(separator: "\n")
        }

        #if DEBUG
        let firstContentCount = top.first?.retrievedContent?.count ?? 0
        print("[Tool:wikipediaSearch] returning \(top.count) result(s) to model and cards (full markdown chars: \(firstContentCount))")
        #endif
        onResults?(top)
        let output = rendered.joined(separator: "\n\n")
        if let transcriptRecorder {
            await transcriptRecorder.record(tool: name, arguments: trimmed, result: output)
        }
        return output
    }
}
