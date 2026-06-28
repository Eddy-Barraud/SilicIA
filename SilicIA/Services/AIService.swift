//
//  AIService.swift
//  SilicIA
//
//  Created by Claude on 23/03/2026.
//

import Foundation
import Combine
import FoundationModels

@MainActor
/// Generates search summaries using Foundation Models with deterministic fallbacks.
class AIService: ObservableObject {
    enum GenerationProfile: String {
        case fast
        case deep
    }

    @Published var isSummarizing = false
    @Published var summary: String = ""
    /// Results the `webSearch` tool has fetched during the current
    /// `summarize` call. Reset at the start of every `summarize` and
    /// appended to whenever the model invokes the tool. SearchView mirrors
    /// this into `searchResults` so the user sees cards even when tool
    /// calling skips the auto web search.
    @Published var toolFetchedResults: [SearchResult] = []
    @Published var citations: String = ""

    // Properties to support real-time RAG scoring during tool calling
    private var activeQuery: String = ""
    private var activeQueries: [String]? = nil
    private var activeEffectiveMaxTokens: Int = 1000
    private var activeContextUtilizationFactor: Double = 0.65
    private var activeOnMatchingScores: (([String: Double]) -> Void)? = nil

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
    // with retrieved context. Higher = the model sees more sources per
    // answer, using more of the 4096-token budget.
    //
    // These sit alongside a second, implicit safety margin: char↔token
    // conversion uses `avgCharsPerToken = 3`, but real-world English is
    // closer to 4 chars/token, so a budget computed in "3-char tokens"
    // already underfills the real tokenizer by ~25%. The factors below
    // are tuned on top of that headroom.
    //
    // Deep search matches the chat path's `RAGSelectionOptions.default`
    // (0.8) so a thorough search uses the window as fully as a chat turn
    // does; fast search stays a notch lower to keep its first-answer
    // latency down without leaving half the window empty (was 0.50).
    private static let fastSummaryContextUtilizationFactor = 0.65
    private static let deepSummaryContextUtilizationFactor = 0.80
    private static let fastSummaryScrapingResultCap = 6
    private static let fastSummaryScrapingCharacterCap = 4500

    // MARK: - Cached LaTeX-sanitizer regexes
    //
    // The summary post-processor strips full-document LaTeX wrappers that the
    // renderer doesn't expect. The two patterns below are run on every summary
    // and were previously recompiled per call; cache them here.

    private static let documentClassRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?m)^\s*\\documentclass(?:\[[^\]]*\])?\{[^}]*\}\s*$"#,
        options: []
    )
    private static let usePackageRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?m)^\s*\\usepackage(?:\[[^\]]*\])?\{[^}]*\}\s*$"#,
        options: []
    )

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[AIService] \(message)")
        #endif
    }


    /// Generates a tiny no-context intuition to provide immediate feedback.
    func generateFirstGuess(
        query: String,
        language: ModelLanguage = .french,
        temperature: Double = 0.3,
        maxTokens: Int = 150,
        onPartialUpdate: ((String) -> Void)? = nil
    ) async -> String {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return "" }

        do {
            // Fresh, ephemeral session per call — first guess is a one-shot,
            // context-free intuition with no memory of prior searches, so a
            // long-lived session would only accumulate dead transcript and
            // eventually overflow the window. It's released when this scope
            // exits.
            let session = LanguageModelSession(
                instructions: Self.buildFirstGuessInstructions(for: language)
            )
            let prompt = PromptLoader.loadPrompt(
                mode: "quick",
                feature: "search",
                language: language,
                replacements: ["query": trimmedQuery]
            ) ?? fallbackFirstGuessPrompt(for: trimmedQuery, language: language)

            let options = GenerationOptions(
                temperature: temperature,
                maximumResponseTokens: maxTokens
            )

            if let onPartialUpdate {
                var latestPartial = ""
                let responseStream = session.streamResponse(to: prompt, options: options)
                for try await snapshot in responseStream {
                    let partial = sanitizeLaTeXDocumentWrappers(String(describing: snapshot.content))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !partial.isEmpty, partial != latestPartial else { continue }
                    latestPartial = partial
                    onPartialUpdate(partial)
                }

                if !latestPartial.isEmpty {
                    return latestPartial
                }
            }

            let response = try await session.respond(to: prompt, options: options)
            let content = String(describing: response.content)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if content.isEmpty { return "" }

            return sanitizeLaTeXDocumentWrappers(content)
        } catch {
            // FoundationModels failed (likely Apple Intelligence unavailable —
            // the app's launch check surfaces this to the user). Return empty
            // rather than a hand-rolled placeholder.
            return ""
        }
    }

    /// Expands one query into up to `maxDerivedQueries` related web-search
    /// queries via the on-device language model. Returns an empty array if
    /// Foundation Models is unavailable or fails — callers fall back to
    /// running the single original query.
    func expandSearchQueries(
        query: String,
        language: ModelLanguage = .french,
        maxDerivedQueries: Int = 3
    ) async -> [String] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty, maxDerivedQueries > 0 else { return [] }

        do {
            // Fresh, ephemeral session per call (see generateFirstGuess) —
            // query expansion is stateless, so it never needs to persist.
            let session = LanguageModelSession(
                instructions: Self.buildQueryExpanderInstructions(for: language)
            )
            let raw = String(describing: try await session.respond(
                to: queryExpanderPrompt(for: trimmedQuery, language: language, maxDerivedQueries: maxDerivedQueries),
                options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 140)
            ).content)

            let parsed = parseDerivedQueries(
                raw,
                originalQuery: trimmedQuery,
                maxDerivedQueries: maxDerivedQueries
            )
            debugLog("query expansion: expected=\(maxDerivedQueries), kept=\(parsed.count) — \(parsed.joined(separator: " | "))")
            return parsed
        } catch {
            debugLog("query expansion failed: \(error.localizedDescription)")
            return []
        }
    }

    /// Summarizes a single web page using Foundation Models. Returns an empty string when unavailable.
    func summarizeWebPage(
        title: String,
        url: String,
        language: ModelLanguage = .french,
        maxCharacters: Int = 4500,
        temperature: Double = 0.3,
        maxTokens: Int = 320,
        useWebVision: Bool = false
    ) async -> String {
        let scraped = await webScraper.scrapeContent(from: url, maxCharacters: maxCharacters, useVision: useWebVision) ?? ""
        let trimmedContent = scraped.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return "" }

        let instructions = PromptLoader.loadPrompt(
            mode: "normal",
            feature: "webpage",
            variant: "instructions",
            language: language
        ) ?? fallbackWebPageInstructions(for: language)

        let prompt = PromptLoader.loadPrompt(
            mode: "normal",
            feature: "webpage",
            language: language,
            replacements: [
                "title": title,
                "url": url,
                "content": trimmedContent
            ]
        ) ?? fallbackWebPagePrompt(
            title: title,
            url: url,
            content: trimmedContent,
            language: language
        )

        do {
            let session = LanguageModelSession(instructions: instructions)
            let options = GenerationOptions(
                temperature: temperature,
                maximumResponseTokens: maxTokens
            )
            let response = try await session.respond(to: prompt, options: options)
            let text = String(describing: response.content)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return sanitizeLaTeXDocumentWrappers(text)
        } catch {
            return ""
        }
    }

    /// Summarize search results using Foundation Models or fallback to NLP.
    ///
    /// The Search Assist flow uses the same chunking/relevance selection pipeline as chat.
    /// - Parameter queries: Full query set (user + derived). When more than one query is provided
    ///   (Deep search), the RAG selection ranks chunks via cosine similarity against the
    ///   combined query vector.
    /// - Parameter generateAnswer: When false, the method still scrapes,
    ///   chunks, ranks and emits per-source match scores (so the caller can
    ///   render retrieval-ranked source cards), but skips the Foundation
    ///   Models generation step entirely and returns an empty summary. Used
    ///   when Apple Intelligence is unavailable — the search experience stays
    ///   functional as web-search-with-ranked-sources without a written answer.
    func summarize(query: String, results: [SearchResult], maxScrapingResults: Int = 10, maxScrapingChars: Int = 5000, temperature: Double = 0.3, maxTokens: Int = 1000, language: ModelLanguage = .french, profile: GenerationProfile = .fast, queries: [String]? = nil, useToolCalling: Bool = false, useWebVision: Bool = false, maxDuckDuckGoResults: Int = 6, maxWikipediaResults: Int = 2, useDuckDuckGo: Bool = true, useWikipedia: Bool = true, generateAnswer: Bool = true, onSummaryPartialUpdate: ((String) -> Void)? = nil, onMatchingScores: (([String: Double]) -> Void)? = nil) async -> (summary: String, citations: String) {
        isSummarizing = true
        defer { isSummarizing = false }
        self.activeQuery = query
        self.activeQueries = queries
        self.activeOnMatchingScores = onMatchingScores
        // Reset the tool-results accumulator at the start of every
        // summarize call so previous turns don't bleed into the new one.
        // Tool-calling mode appends to this as the model invokes webSearch.
        toolFetchedResults = []

        #if DEBUG
        debugTimings = []
        debugNotes = []
        let summarizeStart = Date()
        #endif

        let effectiveScrapingResults = profile == .fast
            ? min(maxScrapingResults, Self.fastSummaryScrapingResultCap)
            : maxScrapingResults
        let effectiveScrapingChars = profile == .fast
            ? min(maxScrapingChars, Self.fastSummaryScrapingCharacterCap)
            : maxScrapingChars

        // Scrape only URLs without provider-supplied full content.
        let urlsToScrape = results.compactMap { result -> String? in
            guard result.retrievedContent?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else {
                return nil
            }
            return result.url
        }
        let scrapedContent: [String: String]
        #if DEBUG
        let scrapeStart = Date()
        scrapedContent = await webScraper.scrapeMultiplePages(
            urls: urlsToScrape,
            limit: effectiveScrapingResults,
            maxCharacters: effectiveScrapingChars,
            useVision: useWebVision
        )
        debugTimings.append(TimingMetric(
            name: "WebScrapingService.scrapeMultiplePages",
            seconds: Date().timeIntervalSince(scrapeStart)
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
        #else
        scrapedContent = await webScraper.scrapeMultiplePages(
            urls: urlsToScrape,
            limit: effectiveScrapingResults,
            maxCharacters: effectiveScrapingChars,
            useVision: useWebVision
        )
        #endif

        var chunks: [RAGChunk] = []
        #if DEBUG
        let contextPrepStart = Date()
        #endif
        for result in results {
            if let retrievedContent = result.retrievedContent?.trimmingCharacters(in: .whitespacesAndNewlines),
               !retrievedContent.isEmpty {
                let chunked = await ragChunker.chunk(
                    text: retrievedContent,
                    source: result.title,
                    maxChunkTokens: Self.webChunkMaxTokens,
                    overlapTokens: Self.webChunkOverlapTokens,
                    url: result.url
                )
                chunks.append(contentsOf: chunked)
            } else if let pageContent = scrapedContent[result.url] {
                let chunked = await ragChunker.chunk(
                    text: pageContent,
                    source: result.title,
                    maxChunkTokens: Self.webChunkMaxTokens,
                    overlapTokens: Self.webChunkOverlapTokens,
                    url: result.url
                )
                chunks.append(contentsOf: chunked)
            } else {
                let chunked = await ragChunker.chunk(
                    text: result.snippet,
                    source: result.title,
                    maxChunkTokens: Self.webChunkMaxTokens,
                    overlapTokens: Self.webChunkOverlapTokens,
                    url: result.url
                )
                chunks.append(contentsOf: chunked)
            }
        }

        let effectiveMaxTokens = TokenBudgeting.clampedOutputTokens(
            requestedMaxTokens: maxTokens,
            instructionTokens: TokenBudgeting.instructionTokens,
            promptOverheadTokens: TokenBudgeting.promptOverheadTokens,
            minContextTokens: TokenBudgeting.minContextTokens
        )
        let contextUtilizationFactor = profile == .deep
            ? Self.deepSummaryContextUtilizationFactor
            : Self.fastSummaryContextUtilizationFactor
        self.activeEffectiveMaxTokens = effectiveMaxTokens
        self.activeContextUtilizationFactor = contextUtilizationFactor
        let selected = await ragContextService.selectContext(
            chunks: chunks,
            query: query,
            maxOutputTokens: effectiveMaxTokens,
            contextUtilizationFactor: contextUtilizationFactor,
            queries: queries
        )

        // Expose per-source match scores derived from the selected chunks so
        // the UI can render a relevance badge on each result card. Sources
        // whose chunks didn't survive the budget filter are absent from the
        // map (callers treat absent keys as 0%).
        if let onMatchingScores {
            let scores = RAGContextService.normalizedSourceScores(from: selected)
            onMatchingScores(scores)
        }

        #if DEBUG
        debugTimings.append(TimingMetric(
            name: "RAG context prep (chunk + select)",
            seconds: Date().timeIntervalSince(contextPrepStart)
        ))
        // Full per-chunk dump of what the model is about to see for the
        // search-summary prompt. Only chunks that survived budgeting are
        // included — the rest of the scraped pages are discarded before
        // the prompt is built.
        print(selected.debugDescription(label: "AIService → search summary (profile=\(profile))"))
        #endif

        // Try Foundation Models first, fallback to NLP if it fails
        #if DEBUG
        let generationStart = Date()
        #endif
        let summary: String
        if generateAnswer {
            summary = await generateSummaryWithFoundationModels(
                query: query,
                context: selected.selectedContext,
                results: results,
                temperature: temperature,
                maxTokens: maxTokens,
                language: language,
                profile: profile,
                useToolCalling: useToolCalling,
                useWebVision: useWebVision,
                corpusChunks: selected.selectedChunks.map(\.chunk),
                maxDuckDuckGoResults: maxDuckDuckGoResults,
                maxWikipediaResults: maxWikipediaResults,
                useDuckDuckGo: useDuckDuckGo,
                useWikipedia: useWikipedia,
                onPartialUpdate: { [weak self] partial in
                    guard let self else { return }
                    self.summary = partial
                    onSummaryPartialUpdate?(partial)
                }
            )
        } else {
            summary = ""
        }

        // Tool-calling mode: now that the model has finished, the
        // `toolFetchedResults` accumulator holds every URL the model
        // actually consulted via webSearch. Chunk + score them through the
        // same RAG pipeline the prompt-stuffing path uses so the cards
        // render with match-score badges instead of bare 0% rings.
        if useToolCalling, !toolFetchedResults.isEmpty, let onMatchingScores {
            let toolChunks = await chunkResultsForRAG(toolFetchedResults)
            if !toolChunks.isEmpty {
                let toolSelected = await ragContextService.selectContext(
                    chunks: toolChunks,
                    query: query,
                    maxOutputTokens: effectiveMaxTokens,
                    contextUtilizationFactor: contextUtilizationFactor,
                    queries: queries
                )
                let scores = RAGContextService.normalizedSourceScores(from: toolSelected)
                onMatchingScores(scores)
            }
        }

        #if DEBUG
        debugTimings.append(TimingMetric(
            name: "generateSummaryWithFoundationModels",
            seconds: Date().timeIntervalSince(generationStart)
        ))
        #endif
        let citations = generateAnswer ? RAGCitationFormatter.citationBlock(from: selected.topChunks, language: language) : ""

        #if DEBUG
        debugTimings.append(TimingMetric(
            name: "AIService.summarize (total)",
            seconds: Date().timeIntervalSince(summarizeStart)
        ))
        #endif

        self.summary = summary
        self.citations = citations
        return (summary: summary, citations: citations)
    }

    /// Appends `incoming` to `toolFetchedResults`, skipping any URL we've
    /// already seen so multiple webSearch calls don't produce duplicate
    /// cards. Order-preserving — newer URLs append at the tail.
    @MainActor
    private func appendUniqueResults(_ incoming: [SearchResult]) async {
        let existing = Set(toolFetchedResults.map(\.url))
        let novel = incoming.filter { !existing.contains($0.url) }
        guard !novel.isEmpty else { return }
        toolFetchedResults.append(contentsOf: novel)

        // Calculate scores in real-time as results arrive so they display immediately
        if let onMatchingScores = activeOnMatchingScores, !toolFetchedResults.isEmpty {
            let toolChunks = await chunkResultsForRAG(toolFetchedResults)
            if !toolChunks.isEmpty {
                let query = activeQuery
                let queries = activeQueries
                let maxTokens = activeEffectiveMaxTokens
                let factor = activeContextUtilizationFactor
                Task {
                    let toolSelected = await ragContextService.selectContext(
                        chunks: toolChunks,
                        query: query,
                        maxOutputTokens: maxTokens,
                        contextUtilizationFactor: factor,
                        queries: queries
                    )
                    let scores = RAGContextService.normalizedSourceScores(from: toolSelected)
                    await MainActor.run {
                        onMatchingScores(scores)
                    }
                }
            }
        }
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
            let chunked = await ragChunker.chunk(
                text: text,
                source: result.title,
                maxChunkTokens: Self.webChunkMaxTokens,
                overlapTokens: Self.webChunkOverlapTokens,
                url: result.url
            )
            chunks.append(contentsOf: chunked)
        }
        return chunks
    }

    /// Builds compact instructions for the selected response language.
    /// When `useToolCalling` is true, appends a tool-usage paragraph via
    /// the shared `ToolKit` (search tone). The `webSearchAvailable` flag
    /// gates the `webSearch` description so the model isn't told to call
    /// a tool that isn't attached.
    private func buildInstructions(
        for language: ModelLanguage,
        useToolCalling: Bool = false,
        webSearchAvailable: Bool = true
    ) -> String {
        let base = PromptLoader.loadPrompt(mode: "normal", feature: "search", variant: "instructions", language: language)
            ?? fallbackSummaryInstructions(for: language)
        guard useToolCalling else { return base }
        return base + "\n\n" + ToolKit.instructionsAppendix(
            for: language,
            tone: .search,
            webSearchAvailable: webSearchAvailable
        )
    }

    /// Per-language user-turn prompt for the search-summary tool-calling
    /// path. Differs from the prompt-stuffing template in two key ways:
    ///   1. NO pre-baked context block — the model is expected to call
    ///      `searchContext` / `webSearch` / `currentDateTime` as needed.
    ///   2. Explicitly nudges the model to use the tools that match the
    ///      query shape (time-relative → currentDateTime first;
    ///      factual lookup → searchContext + webSearch; arithmetic →
    ///      calculate). Without this, the model often just answers from
    ///      memory and the tools sit unused.
    private static func toolCallingSearchPrompt(
        query: String,
        corpusChunkCount: Int,
        webSearchAvailable: Bool,
        language: ModelLanguage,
        isDeepProfile: Bool,
        maxOutputTokens: Int
    ) -> String {
        let keyPoints = isDeepProfile ? (language == .french ? "4 à 6" : "4 to 6") : (language == .french ? "1 à 3" : "1 to 3")
        let corpusHint: String
        if corpusChunkCount > 0 {
            switch language {
            case .french: corpusHint = "\(corpusChunkCount) extraits de pages web ont déjà été récupérés pour cette requête : interroge-les via `searchContext` AVANT de tomber sur le web ouvert."
            case .spanish: corpusHint = "\(corpusChunkCount) fragmentos de páginas web ya se han recuperado para esta consulta: consúltalos con `searchContext` ANTES de recurrir a la web abierta."
            case .english: corpusHint = "\(corpusChunkCount) web-page chunks have already been fetched for this query — query them via `searchContext` BEFORE falling back to the open web."
            }
        } else {
            switch language {
            case .french: corpusHint = webSearchAvailable
                ? "Aucun extrait n'a été pré-récupéré. Utilise `webSearch` pour obtenir l'information."
                : "Aucun extrait n'a été pré-récupéré et la recherche web est désactivée. Réponds depuis tes connaissances."
            case .spanish: corpusHint = webSearchAvailable
                ? "No hay fragmentos pre-recuperados. Usa `webSearch` para obtener la información."
                : "No hay fragmentos pre-recuperados y la búsqueda web está desactivada. Responde con tus conocimientos."
            case .english: corpusHint = webSearchAvailable
                ? "No chunks were pre-fetched. Use `webSearch` to get the information."
                : "No chunks were pre-fetched and web search is disabled. Answer from your own knowledge."
            }
        }

        switch language {
        case .french:
            return """
            Question : \(query)

            \(corpusHint)
            Si la question est temporellement relative (« aujourd'hui », « bientôt », « prochain »), appelle `currentDateTime` AVANT toute autre tâche.
            Si la question nécessite un calcul, utilise `calculate`.

            Réponds avec :
            1. Une réponse directe.
            2. \(keyPoints) points clés.
            Limite : \(maxOutputTokens) tokens.
            Format de sortie requis : LaTeX.
            """
        case .spanish:
            return """
            Pregunta: \(query)

            \(corpusHint)
            Si la pregunta es temporalmente relativa ('hoy', 'pronto', 'próximo'), llama a `currentDateTime` ANTES de cualquier otra tarea.
            Si la pregunta requiere un cálculo, usa `calculate`.

            Responde con:
            1. Una respuesta directa.
            2. \(keyPoints) puntos clave.
            Límite: \(maxOutputTokens) tokens.
            Formato de salida requerido: LaTeX.
            """
        case .english:
            return """
            Question: \(query)

            \(corpusHint)
            If the question is time-relative ("today", "soon", "next"), call `currentDateTime` BEFORE anything else.
            If the question requires a calculation, use `calculate`.

            Respond with:
            1. A direct answer.
            2. \(keyPoints) key points.
            Limit: \(maxOutputTokens) tokens.
            Required output format: LaTeX.
            """
        }
    }

    /// Builds instructions for an ultra-short first-guess response.
    private static func buildFirstGuessInstructions(for language: ModelLanguage) -> String {
        PromptLoader.loadPrompt(mode: "quick", feature: "search", variant: "instructions", language: language)
            ?? fallbackFirstGuessInstructions(for: language)
    }

    /// Builds instructions for query expansion during deep web search.
    private static func buildQueryExpanderInstructions(for language: ModelLanguage) -> String {
        if language == .french {
            return """
            Retourne des requêtes de recherche web pour la question.
            """
        }

        return """
        Return web search queries for the question.
        """
    }

    /// Prompt used to produce search-query expansions in the active UI language.
    private func queryExpanderPrompt(for query: String, language: ModelLanguage, maxDerivedQueries: Int) -> String {
        if language == .french {
            return """
            Question: \(query)

            Retourne exactement \(maxDerivedQueries) requêtes de recherche web pour la question, en texte brut, une par ligne, sans numérotation, sans commentaires.
            """
        }

        return """
        Question: \(query)

        Output exactly \(maxDerivedQueries) search queries for the question, plain text, one per line, no numbering, no comments.
        """
    }

    /// Parses one-query-per-line model output and removes duplicates/noise.
    private func parseDerivedQueries(_ raw: String, originalQuery: String, maxDerivedQueries: Int) -> [String] {
        var seen = Set<String>()
        let normalizedOriginal = normalizeQueryKey(originalQuery)
        seen.insert(normalizedOriginal)

        let queries = raw
            .components(separatedBy: .newlines)
            .map { sanitizeDerivedQueryLine($0) }
            .filter { !$0.isEmpty }
            .filter { !isRawURLSearchQuery($0) }
            .filter { isMeaningfullyDifferentFromOriginal($0, originalQuery: originalQuery) }
            .filter { candidate in
                seen.insert(normalizeQueryKey(candidate)).inserted
            }
            .filter { !isNearDuplicate(ofAny: $0, in: [originalQuery]) }

        return Array(queries.prefix(maxDerivedQueries))
    }

    /// Removes bullets/numbering artifacts and trims wrapping quotes.
    private func sanitizeDerivedQueryLine(_ line: String) -> String {
        let withoutPrefix = line.replacingOccurrences(
            of: #"^\s*(?:[-*•]|\d+[.)])\s*"#,
            with: "",
            options: .regularExpression
        )

        return withoutPrefix
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Normalizes a query for case-insensitive deduplication.
    private func normalizeQueryKey(_ query: String) -> String {
        query
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Detects lines that are raw links instead of plain search query text.
    private func isRawURLSearchQuery(_ candidate: String) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.range(
            of: #"^(?i)(?:https?://|www\.)\S+$"#,
            options: .regularExpression
        ) != nil {
            return true
        }

        if trimmed.contains(" ") {
            return false
        }

        guard let components = URLComponents(string: trimmed) else {
            return false
        }

        let hasSchemeAndHost =
            (components.scheme?.isEmpty == false) &&
            (components.host?.isEmpty == false)

        return hasSchemeAndHost
    }

    /// Tokenizes text for lightweight lexical-similarity checks.
    private func queryTokenSet(_ query: String) -> Set<String> {
        let normalized = normalizeQueryKey(query)
        let separators = CharacterSet.alphanumerics.inverted
        let tokens = normalized
            .components(separatedBy: separators)
            .filter { $0.count >= 3 }

        return Set(tokens)
    }

    /// Returns true when candidate adds enough novel tokens vs original query.
    private func isMeaningfullyDifferentFromOriginal(_ candidate: String, originalQuery: String) -> Bool {
        let candidateTokens = queryTokenSet(candidate)
        let originalTokens = queryTokenSet(originalQuery)
        guard !candidateTokens.isEmpty else { return false }

        let novelTokens = candidateTokens.subtracting(originalTokens)
        return novelTokens.count >= 2
    }

    /// Rejects near-duplicate variants using Jaccard overlap on token sets.
    private func isNearDuplicate(ofAny candidate: String, in existingQueries: [String]) -> Bool {
        let candidateTokens = queryTokenSet(candidate)
        guard !candidateTokens.isEmpty else { return true }

        for existing in existingQueries {
            let existingTokens = queryTokenSet(existing)
            guard !existingTokens.isEmpty else { continue }

            let intersectionCount = candidateTokens.intersection(existingTokens).count
            let unionCount = candidateTokens.union(existingTokens).count
            guard unionCount > 0 else { continue }

            let similarity = Double(intersectionCount) / Double(unionCount)
            if similarity >= 0.75 {
                return true
            }
        }

        return false
    }

    /// Removes full LaTeX document wrappers that the renderer does not expect.
    private func sanitizeLaTeXDocumentWrappers(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let beginRange = cleaned.range(of: "\\begin{document}"),
           let endRange = cleaned.range(of: "\\end{document}"),
           beginRange.upperBound <= endRange.lowerBound {
            cleaned = String(cleaned[beginRange.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Use the cached regexes instead of recompiling on every call.
        cleaned = Self.applyRegex(Self.documentClassRegex, to: cleaned)
        cleaned = Self.applyRegex(Self.usePackageRegex, to: cleaned)
        // The remaining two are plain string replaces — no regex needed.
        cleaned = cleaned.replacingOccurrences(of: "\\begin{document}", with: "")
        cleaned = cleaned.replacingOccurrences(of: "\\end{document}", with: "")

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Applies a cached regex over the full string, replacing each match with the empty string.
    /// No-op when the regex failed to compile.
    private static func applyRegex(_ regex: NSRegularExpression?, to text: String) -> String {
        guard let regex else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    /// Generates the final summary through Foundation Models with context budgeting.
    /// Generates a search summary with resilience around the on-device
    /// model's transient failures — notably the intermittent
    /// `GenerationError -1`, which is usually tool-calling transcript
    /// overflow tipping past the 4096-token window on an unlucky run:
    ///   1. Run as requested (tool-calling or classical).
    ///   2. On a transient error, retry ONCE with a fresh session — the
    ///      exact same input frequently succeeds on a second attempt.
    ///   3. If tool calling was on and still failing, fall back to the
    ///      classical (no-tools) path, which builds no tool transcript and
    ///      so sidesteps the window pressure behind most -1 failures.
    /// Deterministic rejections (guardrail / unsupported locale) skip the
    /// retry — a retry only reproduces them. User cancellation
    /// short-circuits everything. Returns "" only when every avenue fails.
    private func generateSummaryWithFoundationModels(
        query: String,
        context: String,
        results: [SearchResult],
        temperature: Double = 0.3,
        maxTokens: Int = 1000,
        language: ModelLanguage = .french,
        profile: GenerationProfile = .fast,
        useToolCalling: Bool = false,
        useWebVision: Bool = false,
        corpusChunks: [RAGChunk] = [],
        maxDuckDuckGoResults: Int = 6,
        maxWikipediaResults: Int = 2,
        useDuckDuckGo: Bool = true,
        useWikipedia: Bool = true,
        onPartialUpdate: ((String) -> Void)? = nil
    ) async -> String {
        // Attempt 1 — as requested.
        do {
            return try await runSummaryGeneration(
                query: query, context: context, results: results,
                temperature: temperature, maxTokens: maxTokens, language: language,
                profile: profile, useToolCalling: useToolCalling, useWebVision: useWebVision, corpusChunks: corpusChunks,
                maxDuckDuckGoResults: maxDuckDuckGoResults, maxWikipediaResults: maxWikipediaResults,
                useDuckDuckGo: useDuckDuckGo, useWikipedia: useWikipedia,
                onPartialUpdate: onPartialUpdate
            )
        } catch is CancellationError {
            return ""   // user pressed Stop — no retry, no fallback
        } catch {
            let diagnosis = Self.classifyGenerationError(error)
            noteGenerationFailure(stage: "attempt 1 (toolCalling=\(useToolCalling))", label: diagnosis.label)

            // Attempt 2 — retry once for transient failures, same mode. The
            // session is rebuilt fresh inside runSummaryGeneration, so a
            // nondeterministic tool-loop overflow often clears on retry.
            if diagnosis.isTransient {
                do {
                    return try await runSummaryGeneration(
                        query: query, context: context, results: results,
                        temperature: temperature, maxTokens: maxTokens, language: language,
                        profile: profile, useToolCalling: useToolCalling, useWebVision: useWebVision, corpusChunks: corpusChunks,
                        maxDuckDuckGoResults: maxDuckDuckGoResults, maxWikipediaResults: maxWikipediaResults,
                        useDuckDuckGo: useDuckDuckGo, useWikipedia: useWikipedia,
                        onPartialUpdate: onPartialUpdate
                    )
                } catch is CancellationError {
                    return ""
                } catch {
                    noteGenerationFailure(stage: "attempt 2 retry", label: Self.classifyGenerationError(error).label)
                }
            }

            // Attempt 3 — drop the tools. The classical prompt-stuffing path
            // builds no tool transcript, so it avoids the context-window
            // pressure behind most -1 failures. Only meaningful if we were
            // using tools in the first place.
            if useToolCalling {
                do {
                    print("ℹ️ Falling back to non-tool generation after tool-calling failure")
                    return try await runSummaryGeneration(
                        query: query, context: context, results: results,
                        temperature: temperature, maxTokens: maxTokens, language: language,
                        profile: profile, useToolCalling: false, useWebVision: useWebVision, corpusChunks: corpusChunks,
                        maxDuckDuckGoResults: maxDuckDuckGoResults, maxWikipediaResults: maxWikipediaResults,
                        useDuckDuckGo: useDuckDuckGo, useWikipedia: useWikipedia,
                        onPartialUpdate: onPartialUpdate
                    )
                } catch is CancellationError {
                    return ""
                } catch {
                    noteGenerationFailure(stage: "non-tool fallback", label: Self.classifyGenerationError(error).label)
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
    /// worthwhile. We deliberately don't switch on specific
    /// `LanguageModelSession.GenerationError` enum cases — their set shifts
    /// across OS versions — but surface the case name via
    /// `String(describing:)` so logs show the real cause (e.g.
    /// `GenerationError.exceededContextWindowSize`) instead of a bare "-1",
    /// and treat deterministic rejections as non-retryable.
    nonisolated private static func classifyGenerationError(_ error: Error) -> (label: String, isTransient: Bool) {
        if let genError = error as? LanguageModelSession.GenerationError {
            let full = String(describing: genError)
            let caseName = String(full.prefix(while: { $0 != "(" }))
            let lower = caseName.lowercased()
            let permanent = lower.contains("guardrail")
                || lower.contains("unsupportedlanguage")
                || lower.contains("unsupportedlocale")
                || lower.contains("unsupportedguide")
            return ("GenerationError.\(caseName)", !permanent)
        }
        if error is CancellationError {
            return ("cancelled", false)
        }
        let ns = error as NSError
        return ("\(ns.domain) code=\(ns.code): \(error.localizedDescription)", true)
    }

    /// Single generation attempt. Throws on failure so the orchestrator
    /// (`generateSummaryWithFoundationModels`) can retry / fall back. Builds
    /// a fresh `LanguageModelSession` every call so prior-search context
    /// never accumulates across attempts.
    private func runSummaryGeneration(
        query: String,
        context: String,
        results: [SearchResult],
        temperature: Double = 0.3,
        maxTokens: Int = 1000,
        language: ModelLanguage = .french,
        profile: GenerationProfile = .fast,
        useToolCalling: Bool = false,
        useWebVision: Bool = false,
        corpusChunks: [RAGChunk] = [],
        maxDuckDuckGoResults: Int = 6,
        maxWikipediaResults: Int = 2,
        useDuckDuckGo: Bool = true,
        useWikipedia: Bool = true,
        onPartialUpdate: ((String) -> Void)? = nil
    ) async throws -> String {
            // Always create a fresh session so that context from previous searches
            // does not accumulate and overflow the context window.
            let instructions = buildInstructions(
                for: language,
                useToolCalling: useToolCalling,
                webSearchAvailable: useToolCalling && (useDuckDuckGo || useWikipedia)
            )
            let session: LanguageModelSession
            if useToolCalling {
                let webSearchAvailable = useDuckDuckGo || useWikipedia
                // Tool budget is sized from the clamped response cap. We
                // recompute it here (rather than reuse the `effectiveMaxTokens`
                // computed below) because session construction precedes the
                // prompt step — same clamp, same inputs, so the value matches.
                let clampedOutputTokens = TokenBudgeting.clampedOutputTokens(
                    requestedMaxTokens: maxTokens,
                    instructionTokens: TokenBudgeting.instructionTokens,
                    promptOverheadTokens: TokenBudgeting.promptOverheadTokens,
                    minContextTokens: TokenBudgeting.minContextTokens
                )
                let (tools, toolBudget, _) = ToolKit.assemble(
                    config: ToolKit.Configuration(
                        language: language,
                        corpusChunks: corpusChunks,
                        webSearchAvailable: webSearchAvailable,
                        webSearchService: webSearchService,
                        webScraper: webScraper,
                        useWebVision: useWebVision,
                        maxDuckDuckGoResults: maxDuckDuckGoResults,
                        maxWikipediaResults: maxWikipediaResults,
                        useDuckDuckGo: useDuckDuckGo,
                        useWikipedia: useWikipedia,
                        // Mirror every webSearch reply into `toolFetchedResults`
                        // so SearchView can surface the sources as cards with
                        // RAG match scores once the model finishes. Deduped on
                        // the published side via `appendUniqueResults`.
                        onWebResults: { results in
                            // The Task gets its OWN `[weak self]` capture so it
                            // doesn't reach into an enclosing mutable `self`
                            // binding (which Swift 6 flags as capturing a var in
                            // concurrently-executing code).
                            Task { @MainActor [weak self] in
                                await self?.appendUniqueResults(results)
                            }
                        }
                    ),
                    responseTokens: clampedOutputTokens
                )
                #if DEBUG
                debugNotes.append("generateSummaryWithFoundationModels path=tool-calling tools=[\(tools.map(\.name).joined(separator: ", "))] corpusChunks=\(corpusChunks.count) webSearchAvailable=\(webSearchAvailable) toolBudget=\(toolBudget)t")
                #endif
                session = LanguageModelSession(tools: tools, instructions: instructions)
            } else {
                session = LanguageModelSession(instructions: instructions)
            }

            let isDeepProfile = profile == .deep

            // Token budget for the final summary. In tool-calling mode the
            // response cap must reserve the tool appendix + schema overhead
            // (~600t) so the answer can't grow large enough to leave no room
            // for the tool transcript — otherwise a high response setting
            // (slider reaches 3500) overflows the 4096 window and the model
            // fails to respond. The prompt-stuffing path keeps the base clamp.
            let effectiveMaxTokens = useToolCalling
                ? TokenBudgeting.clampedToolResponseTokens(requestedMaxTokens: maxTokens)
                : TokenBudgeting.clampedOutputTokens(
                    requestedMaxTokens: maxTokens,
                    instructionTokens: TokenBudgeting.instructionTokens,
                    promptOverheadTokens: TokenBudgeting.promptOverheadTokens,
                    minContextTokens: TokenBudgeting.minContextTokens
                )
            let maxContextChars = TokenBudgeting.maxContextCharacters(
                maxOutputTokens: effectiveMaxTokens,
                contextUtilizationFactor: isDeepProfile ? Self.deepSummaryContextUtilizationFactor : Self.fastSummaryContextUtilizationFactor
            )
            
            // If context fits, use it all; otherwise intelligently select summaries
            var selectedContext: String
            if context.count <= maxContextChars {
                selectedContext = context
            } else {
                // Split summaries and include as many as fit within the context window
                let summaryChunks = context.components(separatedBy: "\n\n---\n\n")
                selectedContext = ""
                for chunk in summaryChunks {
                    if (selectedContext + chunk).count <= maxContextChars {
                        if selectedContext.isEmpty {
                            selectedContext = chunk
                        } else {
                            selectedContext += "\n\n---\n\n" + chunk
                        }
                    } else {
                        break
                    }
                }
                
                // If no summaries fit, use at least the first one
                if selectedContext.isEmpty && !summaryChunks.isEmpty {
                    selectedContext = String(summaryChunks[0].prefix(maxContextChars))
                }
            }

            // Build the prompt. In tool-calling mode we use a tool-aware
            // prompt that does NOT include the pre-baked scraped context;
            // if we hand the model both a context block AND the tools, it
            // satisfies the request from the block alone and never calls
            // `webSearch` / `currentDateTime`. The scraped chunks are
            // still reachable through `searchContext` as a tool. In the
            // prompt-stuffing baseline we keep the existing template so
            // the output remains identical when tool calling is off.
            let prompt: String
            if useToolCalling {
                prompt = Self.toolCallingSearchPrompt(
                    query: query,
                    corpusChunkCount: corpusChunks.count,
                    webSearchAvailable: useDuckDuckGo || useWikipedia,
                    language: language,
                    isDeepProfile: isDeepProfile,
                    maxOutputTokens: effectiveMaxTokens
                )
            } else {
                prompt = PromptLoader.loadPrompt(
                    mode: "normal",
                    feature: "search",
                    language: language,
                    replacements: [
                        "query": query,
                        "context": selectedContext,
                        "maxOutputTokens": "\(effectiveMaxTokens)",
                        "keyPointsRange": isDeepProfile ? "4 to 6" : "1 to 3",
                        "keyPointsRangeFr": isDeepProfile ? "4 à 6" : "1 à 3"
                    ]
                ) ?? fallbackSummaryPrompt(
                    query: query,
                    context: selectedContext,
                    language: language,
                    isDeepProfile: isDeepProfile,
                    maxOutputTokens: effectiveMaxTokens
                )
            }

            #if DEBUG
            debugNotes.append(
                "generation profile=\(profile.rawValue), budget: reqTokens=\(maxTokens), effTokens=\(effectiveMaxTokens), contextCharsIn=\(context.count), contextCharsUsed=\(selectedContext.count), promptChars=\(prompt.count)"
            )
            #endif

            // Configure generation options using the effective (clamped) token limit
            let options = GenerationOptions(
                temperature: temperature,
                maximumResponseTokens: effectiveMaxTokens
            )

            if let onPartialUpdate {
                var latestPartial = ""
                let responseStream = session.streamResponse(to: prompt, options: options)
                for try await snapshot in responseStream {
                    let partial = sanitizeLaTeXDocumentWrappers(String(describing: snapshot.content))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !partial.isEmpty, partial != latestPartial else { continue }
                    latestPartial = partial
                    onPartialUpdate(partial)
                }

                if !latestPartial.isEmpty {
                    return latestPartial
                }
            }

            // Generate the summary
            let response = try await session.respond(to: prompt, options: options)
            let txt_response = String(describing: response.content)

            return txt_response
    }

    private static func fallbackFirstGuessInstructions(for language: ModelLanguage) -> String {
        if language == .french {
            return """
            Vous êtes un assistant de chat utile. Répondez clairement et précisément.
            Répondez en français.
            """
        }

        return """
        You are a helpful chat assistant. Answer the user clearly and accurately.
        Respond in English.
        """
    }

    private func fallbackSummaryInstructions(for language: ModelLanguage) -> String {
        if language == .french {
            return """
            Tu produis un résumé web précis et concis.
            Réponds en français.
            Donne une réponse directe, puis 1 à 3 points clés.
            Si une information est incertaine, indique-le clairement.
            """
        }

        return """
        You produce concise, accurate web summaries.
        Respond in English.
        Give a direct answer, then 1 to 3 key points.
        If information is uncertain, state it explicitly.
        """
    }

    private func fallbackFirstGuessPrompt(for query: String, language: ModelLanguage) -> String {
        if language == .french {
            return """
            Question: \(query)

            Réponds de manière courte, précise et factuelle.
            Réponds en français.
            Réponds en une phrase maximum.
            Si pertinent, inclus une expression mathématique courte.
            Format de sortie attendu : LaTeX pour les expressions mathématiques, avec $...$ en inline.
            """
        }

        return """
        Question: \(query)

        Answer in a short, precise and factual manner.
        Answer in English.
        Answer in one sentence maximum.
        If relevant, include a short mathematical expression.
        Required output format: LaTeX for mathematical expressions, using $...$ inline.
        """
    }

    private func fallbackSummaryPrompt(
        query: String,
        context: String,
        language: ModelLanguage,
        isDeepProfile: Bool,
        maxOutputTokens: Int
    ) -> String {
        if language == .french {
            return """
            Question : \(query)

            Contexte web :
            \(context)

            Réponds avec :
            1. Une réponse directe.
            2. \(isDeepProfile ? "4 à 6" : "1 à 3") points clés.
            Limite : \(maxOutputTokens) tokens maximum.
            Format de sortie attendu : LaTeX pour les expressions mathématiques.
            Quand c'est pertinent, inclus des formules mathématiques avec du LaTeX simple.
            Format math attendu: inline avec $...$ et blocs avec \\[...\\].
            N'utilise jamais d'environnements \\begin{.
            """
        }

        return """
        Question: \(query)

        Web context:
        \(context)

        Respond with:
        1. A direct answer.
        2. \(isDeepProfile ? "4 to 6" : "1 to 3") key points.
        Limit: \(maxOutputTokens) tokens maximum.
        Required output format: LaTeX for mathematical expressions.
        When relevant, include mathematical formulas in simple LaTeX.
        Required math format: use $...$ inline and \\[...\\].
        Never use environments with \\begin{.
        """
    }

    private func fallbackWebPageInstructions(for language: ModelLanguage) -> String {
        if language == .french {
            return """
            Tu produis des résumés de pages web précis et concis.
            Réponds en français.
            Résume la page en 5 phrases maximum.
            Sois factuel et évite la spéculation.
            """
        }

        return """
        You produce concise, accurate web page summaries.
        Respond in English.
        Summarize the page in 5 sentences maximum.
        Be factual and avoid speculation.
        """
    }

    private func fallbackWebPagePrompt(
        title: String,
        url: String,
        content: String,
        language: ModelLanguage
    ) -> String {
        if language == .french {
            return """
            Titre : \(title)
            URL : \(url)

            Contenu de la page :
            \(content)

            Rédige un résumé concis de la page ci-dessus.
            Limite : 5 phrases maximum.
            Reste factuel ; n'invente pas d'informations absentes de la page.
            Réponds en français.
            """
        }

        return """
        Title: \(title)
        URL: \(url)

        Page content:
        \(content)

        Write a concise summary of the page above.
        Limit: 5 sentences maximum.
        Stay factual; do not invent information that is not in the page.
        Respond in English.
        """
    }

}
