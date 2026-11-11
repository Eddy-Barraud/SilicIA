//
//  AIService.swift
//  SilicIA
//
//

import Foundation
import Combine
import FoundationModels

@MainActor
/// Generates search summaries using Foundation Models with deterministic fallbacks.
class AIService: ObservableObject {
    @Published var isSummarizing = false
    @Published var summary: String = ""
    /// Results the `webSearch` tool has fetched during the current
    /// `summarize` call. Reset at the start of every `summarize` and
    /// appended to whenever the model invokes the tool. SearchView mirrors
    /// this into `searchResults` so the user sees cards even when tool
    /// calling skips the auto web search.
    @Published var toolFetchedResults: [SearchResult] = []
    @Published var citations: String = ""
    @Published var lastAnswerElapsedSeconds: Double? = nil

    // Properties to support real-time RAG scoring during tool calling
    private var activeQuery: String = ""
    private var activeEffectiveMaxTokens: Int = 1000
    private var activeContextUtilizationFactor: Double = 0.80
    private var activeOnMatchingScores: (([String: Double]) -> Void)? = nil
    private var toolScoresCalculated: Bool = false

    private var toolRAGScrapeDuration: Double = 0.0
    private var toolRAGChunkDuration: Double = 0.0
    private var toolRAGRankingDuration: Double = 0.0

    #if DEBUG
    struct TimingMetric: Identifiable {
        let id = UUID()
        let name: String
        let seconds: Double
    }

    @Published var debugTimings: [TimingMetric] = []
    @Published var debugNotes: [String] = []
    #endif

    private let webScraper = WebScrapingService()
    private let ragChunker = RAGChunker()
    private let ragContextService = RAGContextService()
    /// Web search dependency reused by the tool-calling path so the model
    /// can invoke `webSearch` against the same source mix the prompt-
    /// stuffing path would have used. Held by AIService (not injected
    /// from SearchView) so the tool kit stays self-contained.
    private let webSearchService = WebSearchService()

    private static let webChunkMaxTokens = 240
    private static let webChunkOverlapTokens = 40
    // Fraction of the *available* context window (after instructions +
    // overhead + output are reserved) that the search-summary path fills
    // with retrieved context. Scaled by output profile to prevent concise
    // answers from being flooded with excessive peripheral chunks.
    private static let summaryContextUtilizationFactor = 0.80

    static func summaryContextUtilizationFactor(forTokens maxTokens: Int) -> Double {
        let profile = TokenBudgeting.outputProfile(forResponseTokens: maxTokens)
        switch profile.kind {
        case .concise:
            return 0.8
        case .standard:
            return 0.9
        case .detailed:
            return 1.0
        }
    }

    // MARK: - Cached LaTeX-sanitizer regexes
    private func debugLog(_ message: String) {
        #if DEBUG
        print("[AIService] \(message)")
        #endif
    }

    /// Summarizes a single web page using Foundation Models and returns both the summary and clean markdown/text.
    func summarizeWebPage(
        title: String,
        url: String,
        language: ModelLanguage = .french,
        maxCharacters: Int = 4500,
        temperature: Double = 0.3,
        maxTokens: Int = 320,
        preExtractedContent: String? = nil,
        onPartialUpdate: ((String) -> Void)? = nil
    ) async -> (summary: String, markdown: String) {
        var pageMarkdown = preExtractedContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if pageMarkdown.isEmpty, let targetURL = URL(string: url) {
            if let extracted = try? await webScraper.extractMarkdown(from: targetURL) {
                pageMarkdown = extracted.markdown
            }
        }
        if pageMarkdown.isEmpty {
            pageMarkdown = await webScraper.scrapeContent(from: url, maxCharacters: maxCharacters) ?? ""
        }
        let trimmedContent = RAGChunker.stripWikipediaNavboxes(from: pageMarkdown)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return ("", "") }

        guard let instructions = PromptLoader.loadPrompt(
            mode: "normal",
            feature: "webpage",
            variant: "instructions",
            language: language
        ),
        let prompt = PromptLoader.loadPrompt(
            mode: "normal",
            feature: "webpage",
            language: language,
            replacements: [
                "title": title,
                "url": url,
                "content": String(trimmedContent.prefix(maxCharacters))
            ]
        ) else {
            #if DEBUG
            assertionFailure("Failed to load webpage prompt templates for language: \(language.code)")
            #endif
            return ("", "")
        }

        do {
            let session = DynamicSessionCoordinator.shared.acquireSession(
                mode: .webPageSummary,
                instructions: instructions,
                temperature: temperature,
                maxResponseTokens: maxTokens
            )
            let options = GenerationOptions(
                temperature: temperature,
                maximumResponseTokens: maxTokens
            )
            #if DEBUG
            DebugRAGStorage.shared.logFinalPrompt(prompt, label: "WebPageSummary")
            #endif

            if let onPartialUpdate {
                var latestPartial = ""
                var lastUpdateTime: ContinuousClock.Instant = .now - .milliseconds(100)
                let minInterval = Duration.milliseconds(35)
                let responseStream = session.streamResponse(to: prompt, options: options)
                for try await snapshot in responseStream {
                    let text = snapshot.content
                    guard !text.isEmpty, text != latestPartial else { continue }
                    latestPartial = text
                    let now = ContinuousClock.now
                    if now - lastUpdateTime >= minInterval || text.hasSuffix("\n") {
                        lastUpdateTime = now
                        let cleanText: String
                        if text.contains("\\begin{document}") || text.contains("\\documentclass") {
                            cleanText = ModelOutputLaTeXSanitizer.sanitizeLaTeXDocumentWrappers(text)
                        } else {
                            cleanText = text
                        }
                        let trimmed = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
                        onPartialUpdate(trimmed)
                    }
                }
                if !latestPartial.isEmpty {
                    let finalSanitized = ModelOutputLaTeXSanitizer.sanitizeLaTeXDocumentWrappers(latestPartial)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    onPartialUpdate(finalSanitized)
                    return (finalSanitized, pageMarkdown)
                }
            }

            let response = try await session.respond(to: prompt, options: options)
            let text = String(describing: response.content)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (ModelOutputLaTeXSanitizer.sanitizeLaTeXDocumentWrappers(text), pageMarkdown)
        } catch {
            return ("", pageMarkdown)
        }
    }

    /// Summarize search results using Foundation Models or fallback to NLP.
    ///
    /// The Search Assist flow uses the same chunking/relevance selection pipeline as chat.
    /// - Parameter generateAnswer: When false, the method still scrapes,
    ///   chunks, ranks and emits per-source match scores (so the caller can
    ///   render retrieval-ranked source cards), but skips the Foundation
    ///   Models generation step entirely and returns an empty summary. Used
    ///   when Apple Intelligence is unavailable — the search experience stays
    ///   functional as web-search-with-ranked-sources without a written answer.
    func summarize(query: String, results: [SearchResult], maxScrapingResults: Int = 10, maxScrapingChars: Int = 5000, temperature: Double = 0.3, maxTokens: Int = 1000, language: ModelLanguage = .french, maxDuckDuckGoResults: Int = 6, maxWikipediaResults: Int = 2, useDuckDuckGo: Bool = true, useWikipedia: Bool = true, subQueries: [String]? = nil, webQueries: [String]? = nil, wikiQueries: [String]? = nil, generateAnswer: Bool = true, onSummaryPartialUpdate: ((String) -> Void)? = nil, onMatchingScores: (([String: Double]) -> Void)? = nil, onValidSourcesUpdated: (([SearchResult]) -> Void)? = nil) async -> (summary: String, citations: String) {
        isSummarizing = true
        defer { isSummarizing = false }
        self.activeQuery = query
        self.activeOnMatchingScores = onMatchingScores
        // Reset the tool-results accumulator at the start of every
        // summarize call so previous turns don't bleed into the new one.
        // Tool-calling mode appends to this as the model invokes webSearch.
        toolFetchedResults = []
        toolScoresCalculated = false

        // Keep active Foundation Models session warm in memory during network I/O
        DynamicSessionCoordinator.shared.reprewarmActiveSession()

        lastAnswerElapsedSeconds = nil
        toolRAGScrapeDuration = 0.0
        toolRAGChunkDuration = 0.0
        toolRAGRankingDuration = 0.0

        #if DEBUG
        debugTimings = []
        debugNotes = []
        #endif

        let outputProfile = TokenBudgeting.outputProfile(forResponseTokens: maxTokens)
        let isConcise = outputProfile.kind == .concise
        let effectiveScrapingResults: Int
        if isConcise {
            effectiveScrapingResults = min(maxScrapingResults, useWikipedia ? 2 : 3)
        } else {
            effectiveScrapingResults = max(0, maxScrapingResults)
        }
        let effectiveScrapingChars = isConcise ? min(maxScrapingChars, 2_500) : max(0, maxScrapingChars)
        let scrapeTimeout: Double = isConcise ? 1.5 : 3.0

        // Scrape only URLs without provider-supplied full content that passed the NLEmbedding snippet threshold.
        let urlsToScrape = results.compactMap { result -> String? in
            guard !result.isBelowRelevanceThreshold else {
                return nil
            }
            guard result.retrievedContent?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else {
                return nil
            }
            return result.url
        }
        let scrapeStart = Date()
        let scrapedContent = await webScraper.scrapeMultiplePages(
            urls: urlsToScrape,
            limit: effectiveScrapingResults,
            maxCharacters: effectiveScrapingChars,
            timeoutSeconds: scrapeTimeout
        )
        let ragScrapeDuration = Date().timeIntervalSince(scrapeStart)

        #if DEBUG
        debugTimings.append(TimingMetric(
            name: "WebScrapingService.scrapeMultiplePages",
            seconds: ragScrapeDuration
        ))
        if let stats = webScraper.lastDebugStats {
            if stats.candidateURLCount <= stats.requestedLimit {
                debugNotes.append(
                    "overfetch unavailable: candidates (\(stats.candidateURLCount)) <= requested (\(stats.requestedLimit))"
                )
            }
            debugNotes.append(
                "scrape stats: requested=\(stats.requestedLimit), candidates=\(stats.candidateURLCount), launched=\(stats.launchedTasks), completed=\(stats.completedTasks), succeeded=\(stats.succeededPages), canceled=\(stats.canceledTasks), pool=\(stats.poolSize), overfetch=+\(stats.overfetchCount), earlyCancel=\(stats.didEarlyCancel)"
            )
            debugNotes.append(String(format: "scrape elapsed (service): %.3f s", stats.elapsedSeconds))
        }
        #endif

        var validResults: [SearchResult] = []
        var chunks: [RAGChunk] = []
        let chunkingStart = Date()
        for result in results {
            if result.isBelowRelevanceThreshold {
                // Below NLEmbedding snippet similarity threshold: do not download or chunk for context,
                // keep in active sources with 0% used content.
                validResults.append(result)
            } else if let retrievedContent = result.retrievedContent?.trimmingCharacters(in: .whitespacesAndNewlines),
               !retrievedContent.isEmpty {
                validResults.append(result)
                let maxRetrievedContentChars = 100_000
                let boundedText = String(retrievedContent.prefix(maxRetrievedContentChars))
                let chunked = RAGChunker.chunkParagraphs(
                    text: boundedText,
                    source: result.title,
                    url: result.url
                )
                chunks.append(contentsOf: chunked)
            } else if let pageContent = scrapedContent[result.url]?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !pageContent.isEmpty {
                validResults.append(result)
                let chunked = RAGChunker.chunkParagraphs(
                    text: pageContent,
                    source: result.title,
                    url: result.url
                )
                chunks.append(contentsOf: chunked)
            } else {
                // Ignore sources that cannot be reduced to Markdown and delete them from active sources.
                #if DEBUG
                debugLog("Pruning source unable to be reduced to Markdown: \(result.url)")
                #endif
            }
        }
        onValidSourcesUpdated?(validResults)
        let chunkingDuration = Date().timeIntervalSince(chunkingStart)
        #if DEBUG
        debugTimings.append(TimingMetric(
            name: "Paragraph Chunking (NLTokenizer)",
            seconds: chunkingDuration
        ))
        print(String(format: "[Timing][Chunking] Chunked into %d paragraphs in %.3f s (%.2f ms)", chunks.count, chunkingDuration, chunkingDuration * 1000.0))
        #endif

        let effectiveMaxTokens = TokenBudgeting.clampedOutputTokens(
            requestedMaxTokens: maxTokens,
            instructionTokens: TokenBudgeting.instructionTokens,
            promptOverheadTokens: TokenBudgeting.promptOverheadTokens,
            minContextTokens: TokenBudgeting.minContextTokens
        )
        let contextUtilizationFactor = Self.summaryContextUtilizationFactor(forTokens: maxTokens)
        self.activeEffectiveMaxTokens = effectiveMaxTokens
        self.activeContextUtilizationFactor = contextUtilizationFactor

        let rankingPrepStart = Date()
        let selected = await ragContextService.selectContext(
            chunks: chunks,
            query: query,
            maxOutputTokens: effectiveMaxTokens,
            contextUtilizationFactor: contextUtilizationFactor,
            queries: subQueries,
            webQueries: webQueries,
            wikiQueries: wikiQueries,
            language: language
        )
        let rankingDuration = Date().timeIntervalSince(rankingPrepStart)
        #if DEBUG
        debugTimings.append(TimingMetric(
            name: "NLEmbedding Ranking & Selection",
            seconds: rankingDuration
        ))
        #endif

        // Expose per-source match scores derived from the selected chunks so
        // the UI can render a relevance badge on each result card. Sources
        // whose chunks didn't survive the budget filter or were below the
        // NLEmbedding snippet similarity threshold receive 0%.
        if let onMatchingScores {
            var scores = RAGContextService.normalizedSourceScores(from: selected)
            for result in validResults where result.isBelowRelevanceThreshold {
                scores[result.url] = 0.0
            }
            onMatchingScores(scores)
        }

        #if DEBUG
        // Full per-chunk dump of what the model is about to see for the
        // search-summary prompt. Only chunks that survived budgeting are
        // included — the rest of the scraped pages are discarded before
        // the prompt is built.
        print(selected.debugDescription(label: "AIService → search summary"))
        #endif

        // Try Foundation Models first, fallback to NLP if it fails
        // Note: selected.selectedChunks are ordered from least relevant to most relevant (#1 at the end).
        let contextToSend: String
        let corpusChunksToSend: [RAGChunk]
        let maxKeptChunks: Int
        switch outputProfile.kind {
        case .concise: maxKeptChunks = 3
        case .standard: maxKeptChunks = 4
        case .detailed: maxKeptChunks = 6
        }
        if selected.selectedChunks.count > maxKeptChunks {
            let cappedChunks = Array(selected.selectedChunks.suffix(maxKeptChunks))
            corpusChunksToSend = cappedChunks.map(\.chunk)
            contextToSend = cappedChunks.map { "Source: \($0.chunk.source)\n\($0.chunk.text)" }.joined(separator: "\n\n---\n\n")
        } else {
            contextToSend = selected.selectedContext
            corpusChunksToSend = selected.selectedChunks.map(\.chunk)
        }

        let generationStart = Date()
        var firstTokenDate: Date? = nil
        let summary: String
        if generateAnswer {
            summary = await generateSummaryWithFoundationModels(
                query: query,
                context: contextToSend,
                results: validResults,
                temperature: temperature,
                maxTokens: maxTokens,
                language: language,
                corpusChunks: corpusChunksToSend,
                maxDuckDuckGoResults: maxDuckDuckGoResults,
                maxWikipediaResults: maxWikipediaResults,
                useDuckDuckGo: useDuckDuckGo,
                useWikipedia: useWikipedia,
                contextUtilizationFactor: contextUtilizationFactor,
                onPartialUpdate: { [weak self] partial in
                    guard let self else { return }
                    if firstTokenDate == nil {
                        firstTokenDate = Date()
                    }
                    self.summary = partial
                    onSummaryPartialUpdate?(partial)
                }
            )
        } else {
            summary = ""
        }

        // If the model fetched results through tools and scores have not yet been
        // calculated by SourceFunnel, chunk + score them through the RAG pipeline.
        if !toolScoresCalculated && !toolFetchedResults.isEmpty, let onMatchingScores {
            let toolChunkStart = Date()
            let toolChunks = await chunkResultsForRAG(toolFetchedResults)
            let toolChunkElapsed = Date().timeIntervalSince(toolChunkStart)
            toolRAGChunkDuration += toolChunkElapsed
            if !toolChunks.isEmpty {
                let toolRankStart = Date()
                let toolSelected = await ragContextService.selectContext(
                    chunks: toolChunks,
                    query: query,
                    maxOutputTokens: effectiveMaxTokens,
                    contextUtilizationFactor: contextUtilizationFactor,
                    language: language
                )
                let toolRankElapsed = Date().timeIntervalSince(toolRankStart)
                toolRAGRankingDuration += toolRankElapsed
                let scores = RAGContextService.normalizedSourceScores(from: toolSelected)
                toolScoresCalculated = true
                onMatchingScores(scores)
            }
        }

        let totalGenerationDuration = Date().timeIntervalSince(generationStart)
        let resolvedFirstTokenDate = firstTokenDate ?? Date()
        let rawLLMAnsweringDuration = generateAnswer
            ? min(totalGenerationDuration, resolvedFirstTokenDate.timeIntervalSince(generationStart))
            : 0.0
        let streamingDuration = max(0.0, totalGenerationDuration - rawLLMAnsweringDuration)

        let effectiveScrapeDuration = max(ragScrapeDuration, toolRAGScrapeDuration)
        let effectiveChunkDuration = max(chunkingDuration, toolRAGChunkDuration)
        let effectiveRankingDuration = max(rankingDuration, toolRAGRankingDuration)
        let totalRAGDuration = effectiveScrapeDuration + effectiveChunkDuration + effectiveRankingDuration

        // In tool-calling mode, web searching & scraping occur synchronously
        // inside rawLLMAnsweringDuration. Subtract that embedded RAG time to isolate
        // genuine LLM answering time.
        let toolRAGDuration = toolRAGScrapeDuration + toolRAGChunkDuration + toolRAGRankingDuration
        let pureLLMAnsweringDuration = max(0.0, rawLLMAnsweringDuration - toolRAGDuration)
        let totalLLMAnsweringDuration = generateAnswer ? pureLLMAnsweringDuration : 0.0

        // Timing of RAG Pipeline + LLM Answering (streaming part explicitly excluded)
        let totalAnswerTime = totalRAGDuration + totalLLMAnsweringDuration
        self.lastAnswerElapsedSeconds = totalAnswerTime

        let citations = generateAnswer ? RAGCitationFormatter.citationBlock(from: selected.topChunks, language: language) : ""

        #if DEBUG
        let sumPhases = totalRAGDuration + totalLLMAnsweringDuration
        let ragPercent = sumPhases > 0 ? (totalRAGDuration / sumPhases) * 100.0 : 0.0
        let llmPercent = sumPhases > 0 ? (totalLLMAnsweringDuration / sumPhases) * 100.0 : 0.0

        debugTimings.append(TimingMetric(
            name: "RAG Pipeline (Scrape + Chunk + Rank)",
            seconds: totalRAGDuration
        ))
        debugTimings.append(TimingMetric(
            name: "LLM Answering (Time to First Token)",
            seconds: totalLLMAnsweringDuration
        ))
        debugTimings.append(TimingMetric(
            name: "Summary Streaming (excluded from timer)",
            seconds: streamingDuration
        ))
        debugTimings.append(TimingMetric(
            name: "AIService.summarize (RAG + LLM Answering)",
            seconds: totalAnswerTime
        ))

        var breakdownLines: [String] = [
            "┏━━━━━━━━━━━━━━━━ [DEBUG TIMING BREAKDOWN] ━━━━━━━━━━━━━━━━",
            "┃ Total Time to Answer: \(String(format: "%.3f s", totalAnswerTime)) (streaming excluded)",
            "┃ ├─ RAG Pipeline: \(String(format: "%.3f s (%.1f%%)", totalRAGDuration, ragPercent))",
            "┃ │  ├─ Web Download/Markdown: \(String(format: "%.3f s", effectiveScrapeDuration))",
            "┃ │  ├─ Paragraph Chunking:    \(String(format: "%.3f s (%.2f ms)", effectiveChunkDuration, effectiveChunkDuration * 1000.0))",
            "┃ │  └─ NLEmbedding Ranking:   \(String(format: "%.3f s (%.2f ms)", effectiveRankingDuration, effectiveRankingDuration * 1000.0))",
            "┃ └─ LLM Answering: \(String(format: "%.3f s (%.1f%%)", totalLLMAnsweringDuration, llmPercent))"
        ]
        breakdownLines.append("┃    ├─ Time to First Token:    \(String(format: "%.3f s", totalLLMAnsweringDuration))")
        breakdownLines.append("┃    └─ Streaming (excluded):   \(String(format: "%.3f s", streamingDuration))")
        breakdownLines.append("┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        let breakdownLog = breakdownLines.joined(separator: "\n")
        print(breakdownLog)
        #endif

        self.summary = summary
        self.citations = citations
        return (summary: summary, citations: citations)
    }

    /// Appends `incoming` to `toolFetchedResults`, skipping any URL we've
    /// already seen so multiple search calls don't produce duplicate
    /// cards. Order-preserving — newer URLs append at the tail.
    @MainActor
    private func appendUniqueResults(_ incoming: [SearchResult]) async {
        let existing = Set(toolFetchedResults.map(\.url))
        let novel = incoming.filter { !existing.contains($0.url) }
        guard !novel.isEmpty else { return }
        toolFetchedResults.append(contentsOf: novel)
    }

    /// Chunks a list of `SearchResult`s for RAG scoring in tool-calling
    /// mode. Mirrors the chunking the prompt-stuffing path applies to
    /// `summarize`'s `results` parameter — same source field, same chunk
    /// size, same fallback ladder (retrieved content → snippet) so the
    /// resulting per-URL scores are comparable across the two modes.
    private func chunkResultsForRAG(_ results: [SearchResult]) async -> [RAGChunk] {
        var chunks: [RAGChunk] = []
        for result in results {
            let text: String
            if let retrieved = result.retrievedContent?.trimmingCharacters(in: .whitespacesAndNewlines),
               !retrieved.isEmpty {
                text = retrieved
            } else {
                text = result.snippet
            }
            guard !text.isEmpty else { continue }
            let chunked = RAGChunker.chunkParagraphs(
                text: text,
                source: result.title,
                url: result.url
            )
            chunks.append(contentsOf: chunked)
        }
        return chunks
    }

    /// Builds compact instructions for the selected response language,
    /// appending a tool-usage paragraph via the shared `ToolKit` (search tone).
    /// The `webSearchAvailable` flag gates the `webSearch` description so the model
    /// isn't told to call a tool that isn't attached.
    static func buildSearchInstructions(
        for language: ModelLanguage,
        maxOutputTokens: Int,
        webSearchAvailable: Bool = true,
        hasCorpus: Bool = false,
        useDuckDuckGo: Bool = true,
        useWikipedia: Bool = true,
        includeToolsAppendix: Bool = true
    ) -> String {
        let maxSentences = TokenBudgeting.estimatedOutputSentences(forTokens: maxOutputTokens)
        let profile = TokenBudgeting.outputProfile(forResponseTokens: maxOutputTokens)
        let base = PromptLoader.loadPrompt(
            mode: "normal",
            feature: "search",
            variant: "instructions",
            language: language,
            replacements: [
                "maxOutputTokens": "\(maxOutputTokens)",
                "maxOutputSentences": "\(maxSentences)",
                "keyPointsRange": profile.keyPointsRangeString,
                "keyPointsRangeFr": profile.keyPointsRangeFrString,
                "keyPointsRangeEs": profile.keyPointsRangeEsString,
                "personaDirective": profile.personaDirective(for: language),
                "structureDirective": profile.structureDirective(for: language),
                "lengthDirective": profile.lengthDirective(for: language)
            ]
        ) ?? ""
        guard includeToolsAppendix else { return base }
        return base + "\n\n" + ToolKit.instructionsAppendix(
            for: language,
            tone: .search,
            webSearchAvailable: webSearchAvailable,
            hasCorpus: hasCorpus,
            useDuckDuckGo: useDuckDuckGo,
            useWikipedia: useWikipedia
        )
    }

    private func buildInstructions(
        for language: ModelLanguage,
        maxOutputTokens: Int,
        webSearchAvailable: Bool = true,
        hasCorpus: Bool = false,
        useDuckDuckGo: Bool = true,
        useWikipedia: Bool = true,
        includeToolsAppendix: Bool = true
    ) -> String {
        Self.buildSearchInstructions(
            for: language,
            maxOutputTokens: maxOutputTokens,
            webSearchAvailable: webSearchAvailable,
            hasCorpus: hasCorpus,
            useDuckDuckGo: useDuckDuckGo,
            useWikipedia: useWikipedia,
            includeToolsAppendix: includeToolsAppendix
        )
    }

    /// Per-language user-turn prompt for the search-summary tool-calling
    /// path. Differs from the prompt-stuffing template in two key ways:
    ///   1. NO pre-baked context block — the model is expected to call
    ///      `searchContext` / `webSearch` / `wikipediaSearch` / `currentDateTime` as needed.
    ///   2. Explicitly nudges the model to use the tools that match the
    ///      query shape (time-relative → currentDateTime first;
    ///      factual lookup → searchContext + webSearch / wikipediaSearch; arithmetic →
    ///      calculate). Without this, the model often just answers from
    ///      memory and the tools sit unused.
    private static func toolCallingSearchPrompt(
        query: String,
        corpusChunkCount: Int,
        webSearchAvailable: Bool,
        language: ModelLanguage,
        maxOutputTokens: Int,
        groundingContext: String = ""
    ) -> String {
        let profile = TokenBudgeting.outputProfile(forResponseTokens: maxOutputTokens)
        let keyPoints: String
        switch language {
        case .french: keyPoints = profile.keyPointsRangeFrString
        case .spanish: keyPoints = profile.keyPointsRangeEsString
        case .english: keyPoints = profile.keyPointsRangeString
        }
        let trimmedGrounding = groundingContext.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasGrounding = !trimmedGrounding.isEmpty
        let corpusHint = loadSearchCorpusHint(
            chunkCount: corpusChunkCount,
            webSearchAvailable: webSearchAvailable,
            language: language,
            hasGrounding: hasGrounding
        )

        let contextBlock = localizedSearchContextBlock(from: trimmedGrounding, language: language)
        let maxOutputSentences = TokenBudgeting.estimatedOutputSentences(forTokens: maxOutputTokens)

        if let loaded = PromptLoader.loadPrompt(
            mode: "normal",
            feature: "search",
            variant: "tool_calling",
            language: language,
            replacements: [
                "query": query,
                "corpusHint": corpusHint,
                "keyPoints": keyPoints,
                "maxOutputTokens": "\(maxOutputTokens)",
                "maxOutputSentences": "\(maxOutputSentences)",
                "structureDirective": profile.structureDirective(for: language),
                "lengthDirective": profile.lengthDirective(for: language),
                "groundingContext": contextBlock
            ]
        ) {
            return loaded
        }

        #if DEBUG
        assertionFailure("Missing tool_calling prompt template for language: \(language.code)")
        #endif
        return ""
    }

    private static func localizedSearchContextBlock(from selectedContext: String, language: ModelLanguage) -> String {
        let trimmedContext = selectedContext.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContext.isEmpty else { return "" }
        switch language {
        case .french:
            return "Contexte web de référence (support factuel) :\n\(trimmedContext)\n\n"
        case .spanish:
            return "Contexto web de referencia (apoyo factual):\n\(trimmedContext)\n\n"
        case .english:
            return "Web reference context (factual support):\n\(trimmedContext)\n\n"
        }
    }

    private static func loadSearchCorpusHint(
        chunkCount: Int,
        webSearchAvailable: Bool,
        language: ModelLanguage,
        hasGrounding: Bool = false
    ) -> String {
        if hasGrounding {
            if let loaded = PromptLoader.loadPrompt(
                mode: "normal",
                feature: "search",
                variant: "corpus_hint.grounding",
                language: language
            ) {
                return loaded
            }
            switch language {
            case .french:
                return "Réponds d'abord clairement et directement à la question posée à partir de tes connaissances fondamentales. Utilise le contexte web ci-dessus comme support factuel. Si le contexte est incomplet ou omet des notions essentielles, complète impérativement avec tes connaissances sans inclure de détails hors sujet."
            case .spanish:
                return "Responde primero de forma clara y directa a la pregunta planteada a partir de tus conocimientos fundamentales. Utiliza el contexto web anterior como apoyo factual. Si el contexto es incompleto u omite nociones esenciales, completa imperativamente con tus conocimientos sin incluir detalles fuera de tema."
            case .english:
                return "Answer the question clearly and directly first using your foundational knowledge. Use the web context above as factual support. If the context is incomplete or omits essential fundamentals, supplement it with your knowledge without including off-topic details."
            }
        } else {
            if let loaded = PromptLoader.loadPrompt(
                mode: "normal",
                feature: "search",
                variant: "corpus_hint.direct",
                language: language
            ) {
                return loaded
            }
            switch language {
            case .french: return "Aucun extrait n'a été pré-récupéré et la recherche web est désactivée. Réponds depuis tes connaissances."
            case .spanish: return "No hay fragmentos pre-recuperados y la búsqueda web está desactivada. Responde con tus conocimientos."
            case .english: return "No chunks were pre-fetched and web search is disabled. Answer from your own knowledge."
            }
        }
    }

    /// Generates the final summary through Foundation Models with context budgeting.
    private func generateSummaryWithFoundationModels(
        query: String,
        context: String,
        results: [SearchResult],
        temperature: Double = 0.3,
        maxTokens: Int = 1000,
        language: ModelLanguage = .french,
        corpusChunks: [RAGChunk] = [],
        maxDuckDuckGoResults: Int = 6,
        maxWikipediaResults: Int = 2,
        useDuckDuckGo: Bool = true,
        useWikipedia: Bool = true,
        contextUtilizationFactor: Double? = nil,
        onPartialUpdate: ((String) -> Void)? = nil
    ) async -> String {
        // Attempt 1 — as requested.
        do {
            return try await runSummaryGeneration(
                query: query, context: context, results: results,
                temperature: temperature, maxTokens: maxTokens, language: language,
                corpusChunks: corpusChunks,
                maxDuckDuckGoResults: maxDuckDuckGoResults, maxWikipediaResults: maxWikipediaResults,
                useDuckDuckGo: useDuckDuckGo, useWikipedia: useWikipedia,
                contextUtilizationFactor: contextUtilizationFactor,
                onPartialUpdate: onPartialUpdate
            )
        } catch is CancellationError {
            return ""   // user pressed Stop — no retry, no fallback
        } catch {
            let diagnosis = Self.classifyGenerationError(error)
            noteGenerationFailure(stage: "attempt 1", label: diagnosis.label)

            // Attempt 2 — retry once for transient failures, same mode.
            if diagnosis.isTransient {
                do {
                    return try await runSummaryGeneration(
                        query: query, context: context, results: results,
                        temperature: temperature, maxTokens: maxTokens, language: language,
                        corpusChunks: corpusChunks,
                        maxDuckDuckGoResults: maxDuckDuckGoResults, maxWikipediaResults: maxWikipediaResults,
                        useDuckDuckGo: useDuckDuckGo, useWikipedia: useWikipedia,
                        contextUtilizationFactor: contextUtilizationFactor,
                        onPartialUpdate: onPartialUpdate
                    )
                } catch is CancellationError {
                    return ""
                } catch {
                    noteGenerationFailure(stage: "attempt 2 retry", label: Self.classifyGenerationError(error).label)
                }
            }

            return ""
        }
    }

    /// Logs a generation failure (console always; `debugNotes` in DEBUG).
    private func noteGenerationFailure(stage: String, label: String) {
        print("⚠️ Foundation Models summary failed [\(stage)]: \(label)")
        #if DEBUG
        debugNotes.append("generation failure [\(stage)]: \(label)")
        #endif
    }

    /// Classifies a generation error into a log label + whether retrying is
    /// worthwhile.
    nonisolated static func classifyGenerationError(_ error: Error) -> (label: String, isTransient: Bool) {
        if let modelError = error as? LanguageModelError {
            let label = "LanguageModelError.\(modelError)"
            switch modelError {
            case .guardrailViolation,
                 .refusal,
                 .unsupportedCapability,
                 .unsupportedTranscriptContent,
                 .unsupportedGenerationGuide,
                 .unsupportedLanguageOrLocale:
                return (label, false)
            case .contextSizeExceeded,
                 .rateLimited,
                 .timeout:
                return (label, true)
            @unknown default:
                return (label, true)
            }
        }
        if error is CancellationError {
            return ("cancelled", false)
        }
        let ns = error as NSError
        return ("\(ns.domain) code=\(ns.code): \(error.localizedDescription)", true)
    }

    private nonisolated static let arithmeticRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"\d\s*[\+\-\*\/\^]\s*\d|\d\s*%"#,
        options: []
    )
    private nonisolated static let mathVerbsRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"\b(?:calcul|calcule|calculer|calculez|combien font|somme de|multiplier|diviser|multiply|divide|square root|racine carrée)\b"#,
        options: [.caseInsensitive]
    )
    private nonisolated static let dateRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"\b(?:date|dates|aujourd'hui|heure|heures|quel jour|today|current time|what day|what time)\b"#,
        options: [.caseInsensitive]
    )

    /// Fast heuristic check to see if a factual query needs calculation or current date/time tools.
    /// Used in concise mode to bypass tool schemas and appendix, saving ~500 tokens of prefill
    /// and eliminating tool-routing passes to accelerate Time-To-First-Token.
    static func queryRequiresTools(_ query: String) -> Bool {
        let lower = query.lowercased()
        let nsRange = NSRange(lower.startIndex..., in: lower)
        if let arithmetic = arithmeticRegex, arithmetic.firstMatch(in: lower, options: [], range: nsRange) != nil {
            return true
        }
        if let math = mathVerbsRegex, math.firstMatch(in: lower, options: [], range: nsRange) != nil {
            return true
        }
        if let date = dateRegex, date.firstMatch(in: lower, options: [], range: nsRange) != nil {
            return true
        }
        return false
    }

    /// Single generation attempt. Throws on failure so the orchestrator
    /// (`generateSummaryWithFoundationModels`) can retry. Builds
    /// a fresh `LanguageModelSession` every call so prior-search context
    /// never accumulates across attempts.
    private func runSummaryGeneration(
        query: String,
        context: String,
        results: [SearchResult],
        temperature: Double = 0.3,
        maxTokens: Int = 1000,
        language: ModelLanguage = .french,
        corpusChunks: [RAGChunk] = [],
        maxDuckDuckGoResults: Int = 6,
        maxWikipediaResults: Int = 2,
        useDuckDuckGo: Bool = true,
        useWikipedia: Bool = true,
        contextUtilizationFactor: Double? = nil,
        onPartialUpdate: ((String) -> Void)? = nil
    ) async throws -> String {
        let profile = TokenBudgeting.outputProfile(forResponseTokens: maxTokens)
        let allowTools = Self.queryRequiresTools(query)

        // In SearchView summary generation, searchSources is NOT allowed as a tool.
        // Web results are pre-fetched and grounded directly; the model only uses
        // calculate and currentDateTime when tools are allowed.
        let instructions = buildInstructions(
            for: language,
            maxOutputTokens: maxTokens,
            webSearchAvailable: false,
            hasCorpus: false,
            useDuckDuckGo: false,
            useWikipedia: false,
            includeToolsAppendix: allowTools
        )
        let clampedOutputTokens = TokenBudgeting.clampedOutputTokens(
            requestedMaxTokens: maxTokens,
            instructionTokens: TokenBudgeting.instructionTokens,
            promptOverheadTokens: TokenBudgeting.promptOverheadTokens,
            minContextTokens: TokenBudgeting.minContextTokens
        )

        let tools: [any Tool]
        let toolBudget: Int
        if allowTools {
            let assembled = ToolKit.assemble(
                config: ToolKit.Configuration(
                    language: language,
                    corpusChunks: [],
                    userQuery: query,
                    webSearchAvailable: false,
                    webSearchService: webSearchService,
                    webScraper: webScraper,
                    ragContextService: ragContextService,
                    maxDuckDuckGoResults: maxDuckDuckGoResults,
                    maxWikipediaResults: maxWikipediaResults,
                    useDuckDuckGo: false,
                    useWikipedia: false,
                    contextUtilizationFactor: contextUtilizationFactor
                ),
                responseTokens: clampedOutputTokens
            )
            tools = assembled.tools
            toolBudget = assembled.tokenBudget
        } else {
            tools = []
            toolBudget = 0
        }

        let effectiveMaxTokens = TokenBudgeting.clampedToolResponseTokens(requestedMaxTokens: maxTokens)
        let reasoningLevel = TokenBudgeting.reasoningLevel(forResponseTokens: maxTokens)
        #if DEBUG
        debugNotes.append("generateSummaryWithFoundationModels path=search-summary tools=[\(tools.map { $0.name }.joined(separator: ", "))] webSearchAvailable=false toolBudget=\(toolBudget)t reasoning=\(reasoningLevel)")
        #endif
        let session = DynamicSessionCoordinator.shared.acquireSession(
            mode: .searchSummary,
            instructions: instructions,
            tools: tools,
            temperature: temperature,
            maxResponseTokens: maxTokens,
            effectiveMaxOutputTokens: effectiveMaxTokens,
            reasoningLevelOverride: reasoningLevel
        )
        let maxContextChars = min(
            TokenBudgeting.maxContextCharacters(
                maxOutputTokens: effectiveMaxTokens,
                contextUtilizationFactor: Self.summaryContextUtilizationFactor(forTokens: maxTokens)
            ),
            profile.kind.implicitContextCharacters
        )

        // If context fits, use it all; otherwise preserve the tail (most relevant chunks are at the end)
        var selectedContext: String
        if context.count <= maxContextChars {
            selectedContext = context
        } else {
            let summaryChunks = context.components(separatedBy: "\n\n---\n\n")
            var keptReversed: [String] = []
            var runningChars = 0
            let separator = "\n\n---\n\n"
            for chunk in summaryChunks.reversed() {
                let sepChars = keptReversed.isEmpty ? 0 : separator.count
                if runningChars + sepChars + chunk.count <= maxContextChars {
                    keptReversed.append(chunk)
                    runningChars += sepChars + chunk.count
                } else {
                    continue
                }
            }

            if keptReversed.isEmpty, let mostRelevant = summaryChunks.last {
                selectedContext = String(mostRelevant.prefix(maxContextChars))
            } else {
                selectedContext = keptReversed.reversed().joined(separator: separator)
            }
        }

        // Build the prompt. When tools are not needed, pass selectedContext intact
        // without mid-sentence word chopping. When tools are attached, drop least-relevant
        // leading chunks first so the most-relevant chunk at the end remains intact.
        let toolGroundingContext: String
        if selectedContext.isEmpty {
            toolGroundingContext = ""
        } else if !allowTools {
            toolGroundingContext = selectedContext.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let toolGroundingCharCap = min(
                maxContextChars,
                TokenBudgeting.maxHybridToolGroundingCharacters(
                    maxOutputTokens: effectiveMaxTokens,
                    reservedToolReplyTokens: toolBudget + 120
                )
            )
            if selectedContext.count <= toolGroundingCharCap {
                toolGroundingContext = selectedContext.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                let summaryChunks = selectedContext.components(separatedBy: "\n\n---\n\n")
                var keptReversed: [String] = []
                var runningChars = 0
                let separator = "\n\n---\n\n"
                for chunk in summaryChunks.reversed() {
                    let sepChars = keptReversed.isEmpty ? 0 : separator.count
                    if runningChars + sepChars + chunk.count <= toolGroundingCharCap {
                        keptReversed.append(chunk)
                        runningChars += sepChars + chunk.count
                    } else {
                        continue
                    }
                }
                if keptReversed.isEmpty, let mostRelevant = summaryChunks.last {
                    toolGroundingContext = String(mostRelevant.prefix(toolGroundingCharCap)).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    toolGroundingContext = keptReversed.reversed().joined(separator: separator).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        let prompt = Self.toolCallingSearchPrompt(
            query: query,
            corpusChunkCount: 0,
            webSearchAvailable: false,
            language: language,
            maxOutputTokens: effectiveMaxTokens,
            groundingContext: toolGroundingContext
        )

        #if DEBUG
        debugNotes.append(
            "budget: reqTokens=\(maxTokens), effTokens=\(effectiveMaxTokens), contextCharsIn=\(context.count), contextCharsUsed=\(selectedContext.count), promptChars=\(prompt.count)"
        )
        DebugRAGStorage.shared.logFinalPrompt(prompt, label: "SearchSummary")
        #endif

        // Configure generation options using the effective (clamped) token limit
        let options = GenerationOptions(
            temperature: temperature,
            maximumResponseTokens: effectiveMaxTokens
        )

        if let onPartialUpdate {
            var latestPartial = ""
            var lastUpdateTime: ContinuousClock.Instant = .now - .milliseconds(100)
            let minInterval = Duration.milliseconds(35)
            let responseStream = session.streamResponse(to: prompt, options: options)
            for try await snapshot in responseStream {
                let text = snapshot.content
                guard !text.isEmpty, text != latestPartial else { continue }
                latestPartial = text
                let now = ContinuousClock.now
                if now - lastUpdateTime >= minInterval || text.hasSuffix("\n") {
                    lastUpdateTime = now
                    let cleanText: String
                    if text.contains("\\begin{document}") || text.contains("\\documentclass") {
                        cleanText = ModelOutputLaTeXSanitizer.sanitizeLaTeXDocumentWrappers(text)
                    } else {
                        cleanText = text
                    }
                    let trimmed = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
                    onPartialUpdate(trimmed)
                }
            }

            if !latestPartial.isEmpty {
                let finalSanitized = ModelOutputLaTeXSanitizer.sanitizeLaTeXDocumentWrappers(latestPartial)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                onPartialUpdate(finalSanitized)
                return finalSanitized
            }
        }

        // Generate the summary (fallback if streaming was skipped or empty)
        let response = try await session.respond(to: prompt, options: options)
        let txt_response = String(describing: response.content)
        let finalSanitized = ModelOutputLaTeXSanitizer.sanitizeLaTeXDocumentWrappers(txt_response)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        onPartialUpdate?(finalSanitized)
        return finalSanitized
    }
}
