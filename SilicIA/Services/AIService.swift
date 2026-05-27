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
    @Published var citations: String = ""

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
    private var firstGuessSession: LanguageModelSession
    private var firstGuessSessionLanguage: ModelLanguage
    private var queryExpanderSession: LanguageModelSession
    private var queryExpanderSessionLanguage: ModelLanguage

    private static let webChunkMaxTokens = 240
    private static let webChunkOverlapTokens = 40
    private static let fastSummaryContextUtilizationFactor = 0.50
    private static let deepSummaryContextUtilizationFactor = 0.65
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

    init(initialFirstGuessLanguage: ModelLanguage = .french) {
        self.firstGuessSessionLanguage = initialFirstGuessLanguage
        self.firstGuessSession = LanguageModelSession(
            instructions: Self.buildFirstGuessInstructions(for: initialFirstGuessLanguage)
        )
        self.queryExpanderSessionLanguage = initialFirstGuessLanguage
        self.queryExpanderSession = LanguageModelSession(
            instructions: Self.buildQueryExpanderInstructions(for: initialFirstGuessLanguage)
        )
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
            let session = firstGuessSession(for: language)
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
            let session = queryExpanderSession(for: language)
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
        maxTokens: Int = 320
    ) async -> String {
        let scraped = await webScraper.scrapeContent(from: url, maxCharacters: maxCharacters) ?? ""
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
    func summarize(query: String, results: [SearchResult], maxScrapingResults: Int = 10, maxScrapingChars: Int = 5000, temperature: Double = 0.3, maxTokens: Int = 1000, language: ModelLanguage = .french, profile: GenerationProfile = .fast, queries: [String]? = nil, onSummaryPartialUpdate: ((String) -> Void)? = nil, onMatchingScores: (([String: Double]) -> Void)? = nil) async -> (summary: String, citations: String) {
        isSummarizing = true
        defer { isSummarizing = false }

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
            maxCharacters: effectiveScrapingChars
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
            maxCharacters: effectiveScrapingChars
        )
        #endif

        var chunks: [RAGChunk] = []
        #if DEBUG
        let contextPrepStart = Date()
        #endif
        for result in results {
            if let retrievedContent = result.retrievedContent?.trimmingCharacters(in: .whitespacesAndNewlines),
               !retrievedContent.isEmpty {
                let chunked = ragChunker.chunk(
                    text: retrievedContent,
                    source: result.title,
                    maxChunkTokens: Self.webChunkMaxTokens,
                    overlapTokens: Self.webChunkOverlapTokens,
                    url: result.url
                )
                chunks.append(contentsOf: chunked)
            } else if let pageContent = scrapedContent[result.url] {
                let chunked = ragChunker.chunk(
                    text: pageContent,
                    source: result.title,
                    maxChunkTokens: Self.webChunkMaxTokens,
                    overlapTokens: Self.webChunkOverlapTokens,
                    url: result.url
                )
                chunks.append(contentsOf: chunked)
            } else {
                let chunked = ragChunker.chunk(
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
        let summary = await generateSummaryWithFoundationModels(
            query: query,
            context: selected.selectedContext,
            results: results,
            temperature: temperature,
            maxTokens: maxTokens,
            language: language,
            profile: profile,
            onPartialUpdate: { [weak self] partial in
                guard let self else { return }
                self.summary = partial
                onSummaryPartialUpdate?(partial)
            }
        )

        #if DEBUG
        debugTimings.append(TimingMetric(
            name: "generateSummaryWithFoundationModels",
            seconds: Date().timeIntervalSince(generationStart)
        ))
        #endif
        let citations = RAGCitationFormatter.citationBlock(from: selected.topChunks, language: language)

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

    /// Builds compact instructions for the selected response language.
    private func buildInstructions(for language: ModelLanguage) -> String {
        PromptLoader.loadPrompt(mode: "normal", feature: "search", variant: "instructions", language: language)
            ?? fallbackSummaryInstructions(for: language)
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

    /// Returns a long-lived first-guess session and rebuilds it when language changes.
    private func firstGuessSession(for language: ModelLanguage) -> LanguageModelSession {
        if language != firstGuessSessionLanguage {
            firstGuessSessionLanguage = language
            firstGuessSession = LanguageModelSession(
                instructions: Self.buildFirstGuessInstructions(for: language)
            )
        }

        return firstGuessSession
    }

    /// Returns a long-lived query-expander session and rebuilds it when language changes.
    private func queryExpanderSession(for language: ModelLanguage) -> LanguageModelSession {
        if language != queryExpanderSessionLanguage {
            queryExpanderSessionLanguage = language
            queryExpanderSession = LanguageModelSession(
                instructions: Self.buildQueryExpanderInstructions(for: language)
            )
        }

        return queryExpanderSession
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
    private func generateSummaryWithFoundationModels(query: String, context: String, results: [SearchResult], temperature: Double = 0.3, maxTokens: Int = 1000, language: ModelLanguage = .french, profile: GenerationProfile = .fast, onPartialUpdate: ((String) -> Void)? = nil) async -> String {
        do {
            // Always create a fresh session so that context from previous searches
            // does not accumulate and overflow the context window.
            let instructions = buildInstructions(for: language)
            let session = LanguageModelSession(instructions: instructions)

            let isDeepProfile = profile == .deep

            // Token budget for the final summary.
            let effectiveMaxTokens = TokenBudgeting.clampedOutputTokens(
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

            let prompt = PromptLoader.loadPrompt(
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
        } catch {
            // The app's launch-time check (see `FoundationModelAvailability`)
            // already warns when Apple Intelligence is unavailable, so we no
            // longer carry a deterministic NLP fallback. Return empty here —
            // the UI surfaces this as "no summary" rather than a misleading
            // hand-written one.
            print("⚠️ Error generating summary with Foundation Models: \(error.localizedDescription)")
            return ""
        }
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
