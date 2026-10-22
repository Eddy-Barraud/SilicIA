//
//  SourceFunnel.swift
//  SilicIA
//
//  Shared engine for the `searchSources` funnel tool.
//  Executes web (DuckDuckGo) and encyclopedic (Wikipedia) searches in parallel,
//  scrapes full webpage content without truncation, runs full RAG paragraph chunking,
//  and selects the most relevant passages via RAGContextService to return to the model.
//

import Foundation

struct SourceFunnel {

    let webSearchService: WebSearchService
    let webScraper: WebScrapingService
    let ragContextService: RAGContextService
    let userQuery: String
    let language: ModelLanguage
    let maxDuckDuckGoResults: Int
    let maxWikipediaResults: Int
    let useDuckDuckGo: Bool
    let useWikipedia: Bool
    let responseTokens: Int
    let contextUtilizationFactor: Double?

    var onResults: (@Sendable ([SearchResult]) -> Void)? = nil
    var onScrapeDuration: (@Sendable (Double) -> Void)? = nil
    var onScores: (@Sendable ([String: Double]) -> Void)? = nil
    var onRAGDuration: (@Sendable (Double, Double) -> Void)? = nil
    var governor: ToolCallGovernor? = nil
    var transcriptRecorder: ToolTranscriptRecorder? = nil
    let toolName: String = "searchSources"

    func run(webQueries: [String], wikiQueries: [String]) async throws -> String {
        let cleanWeb = useDuckDuckGo ? Array(webQueries
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(2)) : []
        let cleanWiki = useWikipedia ? Array(wikiQueries
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(2)) : []

        let combinedArgs = "web: [\(cleanWeb.joined(separator: ", "))]; wiki: [\(cleanWiki.joined(separator: ", "))]"

        #if DEBUG
        print("[Tool:searchSources] called with web=\(cleanWeb) wiki=\(cleanWiki)")
        #endif

        if let governor {
            let decision = await governor.evaluate(tool: toolName, arguments: combinedArgs)
            if case .allow = decision {
                // continue
            } else if transcriptRecorder != nil {
                switch decision {
                case .allow:
                    break
                case .duplicate(let count):
                    throw ToolError.duplicate(tool: toolName, count: count)
                case .toolBudgetReached(let tool, let cap):
                    throw ToolError.toolBudgetReached(tool: tool, cap: cap)
                case .totalBudgetReached(let cap):
                    throw ToolError.totalBudgetReached(cap: cap)
                }
            } else if let refusal = decision.refusalMessage {
                return refusal
            }
        }

        guard !cleanWeb.isEmpty || !cleanWiki.isEmpty else {
            return "Error: No valid search queries provided. Provide up to 2 web queries or up to 2 Wikipedia topics."
        }

        // User setting is split across queries: if 2 queries are asked, each gets half the setting
        // so that the total sum of retrieved sources equals the user setting.
        let webLimitPerQuery = max(1, maxDuckDuckGoResults / max(1, cleanWeb.count))
        let wikiLimitPerQuery = max(1, maxWikipediaResults / max(1, cleanWiki.count))

        var rawResults: [SearchResult] = []
        var rawErrors: [Error] = []

        await withTaskGroup(of: Result<[SearchResult], Error>.self) { group in
            for query in cleanWeb {
                group.addTask {
                    do {
                        let res = try await self.webSearchService.searchDuckDuckGo(query: query, limit: webLimitPerQuery)
                        return .success(res)
                    } catch {
                        return .failure(error)
                    }
                }
            }
            for query in cleanWiki {
                group.addTask {
                    do {
                        let res = try await self.webSearchService.searchWikipedia(query: query, language: self.language, limit: wikiLimitPerQuery)
                        return .success(res)
                    } catch {
                        return .failure(error)
                    }
                }
            }

            for await result in group {
                switch result {
                case .success(let items):
                    rawResults.append(contentsOf: items)
                case .failure(let err):
                    rawErrors.append(err)
                }
            }
        }

        if Task.isCancelled {
            throw CancellationError()
        }

        guard !rawResults.isEmpty else {
            if let firstErr = rawErrors.first {
                if firstErr is CancellationError {
                    throw CancellationError()
                }
                return "Search failed: \(firstErr.localizedDescription). Answer from your own knowledge instead."
            }
            return "No search results found for the queries. Refine the queries or answer from your own knowledge."
        }

        // Deduplicate results by URL
        var uniqueResults: [SearchResult] = []
        var seenURLs = Set<String>()
        for result in rawResults {
            let normalizedURL = result.url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !seenURLs.contains(normalizedURL) else { continue }
            seenURLs.insert(normalizedURL)
            uniqueResults.append(result)
        }

        // Scrape web pages that did not already have full retrieved content (Wikipedia already has it)
        let urlsToScrape = uniqueResults.compactMap { result -> String? in
            guard (result.retrievedContent ?? "").trimmingCharacters(in: .whitespaces).isEmpty else {
                return nil
            }
            return result.url
        }

        let scraped: [String: String]
        if !urlsToScrape.isEmpty {
            let scrapeStart = Date()
            scraped = await webScraper.scrapeMultiplePages(
                urls: urlsToScrape,
                limit: urlsToScrape.count,
                maxCharacters: 10_000
            )
            let toolScrapeElapsed = Date().timeIntervalSince(scrapeStart)
            onScrapeDuration?(toolScrapeElapsed)
        } else {
            scraped = [:]
        }

        // Enrich results and prune pages that failed Markdown extraction
        let enrichedResults = uniqueResults.compactMap { result -> SearchResult? in
            if let retrieved = result.retrievedContent?.trimmingCharacters(in: .whitespacesAndNewlines),
               !retrieved.isEmpty {
                return result
            }
            if let scrapedText = scraped[result.url]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !scrapedText.isEmpty {
                return SearchResult(
                    id: result.id,
                    title: result.title,
                    url: result.url,
                    snippet: result.snippet,
                    retrievedContent: scrapedText
                )
            }
            return nil
        }

        #if DEBUG
        print("[Tool:searchSources] enriched \(enrichedResults.count) total source(s) from \(uniqueResults.count) candidate(s)")
        #endif

        onResults?(enrichedResults)

        // Chunk all enriched sources for RAG ranking
        let chunkStart = Date()
        var allChunks: [RAGChunk] = []
        for result in enrichedResults {
            let text = (result.retrievedContent ?? result.snippet).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let chunks = RAGChunker.chunkParagraphs(
                text: text,
                source: result.title,
                url: result.url
            )
            allChunks.append(contentsOf: chunks)
        }
        let chunkElapsed = Date().timeIntervalSince(chunkStart)

        guard !allChunks.isEmpty else {
            return "No readable content found for the provided search queries. Answer from your own knowledge."
        }

        // Rank against the user's original query, combining all sub-queries for lexical scoring
        let trimmedUserQuery = userQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let rankingQuery = trimmedUserQuery.isEmpty ? (cleanWeb + cleanWiki).joined(separator: " ") : trimmedUserQuery
        var allSubQueries = [rankingQuery]
        for q in cleanWeb + cleanWiki {
            if !allSubQueries.contains(q) {
                allSubQueries.append(q)
            }
        }

        let rankStart = Date()
        let selectionResult = await ragContextService.selectContext(
            chunks: allChunks,
            query: rankingQuery,
            maxOutputTokens: responseTokens,
            contextUtilizationFactor: contextUtilizationFactor,
            queries: allSubQueries,
            language: language
        )
        let rankElapsed = Date().timeIntervalSince(rankStart)
        onRAGDuration?(chunkElapsed, rankElapsed)

        let scores = RAGContextService.normalizedSourceScores(from: selectionResult)
        onScores?(scores)

        let topChunks = selectionResult.selectedChunks
        guard !topChunks.isEmpty else {
            return "No relevant passages found for query: '\(rankingQuery)'."
        }

        var rendered: [String] = []
        for (idx, ranked) in topChunks.enumerated() {
            var lines = ["--- Result \(idx + 1): \(ranked.chunk.source)"]
            if let url = ranked.chunk.url {
                lines.append("URL: \(url)")
            }
            lines.append("Content: \(ranked.chunk.text)")
            rendered.append(lines.joined(separator: "\n"))
        }

        let output = rendered.joined(separator: "\n\n")

        #if DEBUG
        print("[Tool:searchSources] returning \(topChunks.count) RAG chunk(s) (\(output.count) chars) to model from \(allChunks.count) candidate chunks")
        #endif

        if let transcriptRecorder {
            await transcriptRecorder.record(tool: toolName, arguments: combinedArgs, result: output)
        }
        return output
    }
}
