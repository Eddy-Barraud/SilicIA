//
//  ChatService.swift
//  SilicIA
//
//  Created by Eddy Barraud on 27/03/2026.
//

import Foundation
import Combine
import SwiftData
import FoundationModels
import PDFKit
import NaturalLanguage
import Vision
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Service layer that orchestrates retrieval-augmented chat generation.
@MainActor
final class ChatService: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isResponding = false
    @Published var errorMessage: String?
    @Published var isAnalyzingContext = false
    @Published var contextAnalysisProgress = 0.0
    /// Filename of the PDF the current conversation is anchored to, if any.
    /// PDFtalkme observes this to keep its left pane in sync with whichever
    /// conversation is loaded (e.g. when the user picks one from history).
    @Published var currentConversationPDFFilename: String?
    /// Security-scoped bookmark for the same PDF, for hosts that want to
    /// resolve the file across launches.
    @Published var currentConversationPDFBookmark: Data?
    /// Normalized base filenames of every PDF currently in context, in
    /// order. The host watches this to mirror the full set of PDFs (not
    /// just the anchor) into its UI when a conversation is restored.
    @Published var currentConversationPDFFilenames: [String] = []
    /// Security-scoped bookmarks aligned to `currentConversationPDFFilenames`.
    @Published var currentConversationPDFBookmarks: [Data] = []

    private let webScraper = WebScrapingService()
    private let webSearchService = WebSearchService()
    private let ragChunker = RAGChunker()
    private let ragContextService = RAGContextService()

    // SwiftData persistence
    var modelContext: ModelContext?
    private var currentConversation: Conversation?
    private var pendingSaveTask: Task<Void, Never>?
    /// PDF URL captured from the most recent `sendMessage` call. Used by
    /// `persistMessage` to stamp a freshly created conversation with the
    /// document the user is asking about.
    private var activePDFURLForNewConversation: URL?
    /// The *full* PDF context list from the most recent `sendMessage` call.
    /// Stamped onto a freshly created conversation, and synced onto an
    /// existing conversation so it always reflects whatever PDFs the
    /// composer currently has attached.
    private var activePDFURLsForNewConversation: [URL] = []

    // Keep web retrieval bounded to control latency and context size.
    private static let maxWebContextURLCap = 30
    // Chunk sizes tuned to preserve locality while allowing many chunks in a 4096-token budget.
    private static let webChunkMaxTokens = 240
    private static let webChunkOverlapTokens = 40
    private static let pdfChunkMaxTokens = 220
    private static let pdfChunkOverlapTokens = 30
    private static let minWebScrapingCharacters = 1500
    private static let maxWebScrapingCharacters = 12000
    private static let maxRecentMessagesForWebSearch = 4
    private static let maxWebSearchQueryLength = 500
    // Keep recent turns only, to leave room for retrieved context.
    private static let historyMessageLimit = 6
    private static let saveDebounceIntervalNanoseconds: UInt64 = 250_000_000
    private var preAnalyzedContextKey: String?
    private var preAnalyzedChunks: [RAGChunk] = []
    private var preAnalyzedMaxContextTokens: Int?
    private var preAnalyzedMaxOutputTokens: Int?
    private var preAnalyzedMaxDuckDuckGoResults: Int?
    private var preAnalyzedMaxWikipediaResults: Int?
    private var preAnalyzedUseDuckDuckGo: Bool = true
    private var preAnalyzedUseWikipedia: Bool = true

    /// Sends a user message and appends the assistant response.
    func sendMessage(
        _ message: String,
        contextInput: String,
        pdfURLs: [URL],
        imageURLs: [URL] = [],
        includeWebSearch: Bool,
        maxDuckDuckGoResults: Int,
        maxWikipediaResults: Int,
        language: ModelLanguage,
        temperature: Double,
        maxResponseTokens: Int,
        maxContextTokens: Int,
        useDuckDuckGo: Bool = true,
        useWikipedia: Bool = true
    ) async {
        activePDFURLForNewConversation = pdfURLs.first
        activePDFURLsForNewConversation = pdfURLs
        syncCurrentConversationPDFs(with: pdfURLs)
        messages.append(ChatMessage(role: .user, content: message))
        persistMessage(role: "user", content: message, citations: nil)
        errorMessage = nil

        isResponding = true
        defer { isResponding = false }

        // Compute every effective/clamped value ONCE up front and reuse for the
        // cache key, the cache-hit comparison, and downstream calls. Clamping
        // is idempotent, but doing it twice (once for the key, once after) was
        // wasteful and made the cache key risk going out of sync with the
        // values actually used.
        let effectiveMaxDDGResults = clampedMaxDuckDuckGoResults(maxDuckDuckGoResults)
        let effectiveMaxWikiResults = clampedMaxWikipediaResults(maxWikipediaResults)
        let effectiveMaxOutputTokens = calculateEffectiveMaxOutputTokens(maxResponseTokens)
        let effectiveMaxContextTokens = calculateEffectiveContextTokens(
            requestedContextTokens: maxContextTokens,
            maxOutputTokens: effectiveMaxOutputTokens
        )

        let contextKey = makeContextKey(
            contextInput: contextInput,
            pdfURLs: pdfURLs,
            imageURLs: imageURLs,
            includeWebSearch: includeWebSearch,
            searchQuerySeed: includeWebSearch ? message : "",
            clampedDuckDuckGoResults: effectiveMaxDDGResults,
            clampedWikipediaResults: effectiveMaxWikiResults
        )
        let hasRequestedContext = !contextKey.isEmpty
        let canUsePreAnalyzed = contextKey == preAnalyzedContextKey
            && effectiveMaxContextTokens == preAnalyzedMaxContextTokens
            && effectiveMaxOutputTokens == preAnalyzedMaxOutputTokens
            && effectiveMaxDDGResults == preAnalyzedMaxDuckDuckGoResults
            && effectiveMaxWikiResults == preAnalyzedMaxWikipediaResults
            && useDuckDuckGo == preAnalyzedUseDuckDuckGo
            && useWikipedia == preAnalyzedUseWikipedia
            && (!hasRequestedContext || !preAnalyzedChunks.isEmpty)
        debugContext("sendMessage cache=\(canUsePreAnalyzed ? "hit" : "miss") keyEmpty=\(contextKey.isEmpty) pdfCount=\(pdfURLs.count) imageCount=\(imageURLs.count) preChunks=\(preAnalyzedChunks.count)")
        let chunks: [RAGChunk]
        if canUsePreAnalyzed {
            chunks = preAnalyzedChunks
        } else {
            chunks = await collectChunks(
                contextInput: contextInput,
                pdfURLs: pdfURLs,
                imageURLs: imageURLs,
                includeWebSearch: includeWebSearch,
                currentMessage: message,
                language: language,
                maxDuckDuckGoResults: effectiveMaxDDGResults,
                maxWikipediaResults: effectiveMaxWikiResults,
                maxContextTokens: effectiveMaxContextTokens,
                useDuckDuckGo: useDuckDuckGo,
                useWikipedia: useWikipedia
            )
            preAnalyzedContextKey = contextKey
            preAnalyzedChunks = chunks
            preAnalyzedMaxContextTokens = effectiveMaxContextTokens
            preAnalyzedMaxOutputTokens = effectiveMaxOutputTokens
            preAnalyzedMaxDuckDuckGoResults = effectiveMaxDDGResults
            preAnalyzedMaxWikipediaResults = effectiveMaxWikiResults
            preAnalyzedUseDuckDuckGo = useDuckDuckGo
            preAnalyzedUseWikipedia = useWikipedia
        }
        debugContext("sendMessage chunkCount=\(chunks.count)")
        let selected = await ragContextService.selectContext(
            chunks: chunks,
            query: message,
            maxOutputTokens: effectiveMaxOutputTokens,
            contextUtilizationFactor: RAGSelectionOptions.default.contextUtilizationFactor
        )
        // Cap the selected context with a single primary strategy:
        //   1. Word-aware truncation (semantic boundaries — preferred).
        //   2. Hard character safety-net only when (1) still exceeds the
        //      prompt-character budget that the model can ingest.
        // This replaces the prior double-cap which built two intermediate
        // Strings and picked the shorter — wasteful and harder to reason
        // about, since the two budgets are derived from the same token cap.
        let maxPromptContextCharacters = TokenBudgeting.maxContextCharacters(
            maxOutputTokens: effectiveMaxOutputTokens,
            contextUtilizationFactor: 1.0
        )
        let effectiveContextTokenCap = min(
            effectiveMaxContextTokens,
            TokenBudgeting.estimatedTokens(forApproxCharacters: maxPromptContextCharacters)
        )
        let contextWordEstimate = TokenBudgeting.estimatedContextWords(forTokens: effectiveContextTokenCap)
        var finalSelectedContext = TokenBudgeting.truncateToApproxWordCount(
            selected.selectedContext,
            maxWords: contextWordEstimate
        )
        if finalSelectedContext.count > maxPromptContextCharacters {
            finalSelectedContext = String(finalSelectedContext.prefix(maxPromptContextCharacters))
        }
        finalSelectedContext = finalSelectedContext.trimmingCharacters(in: .whitespacesAndNewlines)
        debugContext("sendMessage contextChars raw=\(selected.selectedContext.count) capped=\(finalSelectedContext.count) tokenCap=\(effectiveMaxContextTokens) topChunks=\(selected.topChunks.count)")
        #if DEBUG
        // Full per-chunk dump of what the model is about to see. Guarded by
        // DEBUG so release builds stay silent; only the chunks that actually
        // landed in `selectedContext` are printed (i.e. survived budgeting).
        print(selected.debugDescription(label: "ChatService → chat prompt"))
        #endif

        var streamingAssistantID: UUID?
        do {
            let instructions = buildInstructions(for: language)
            let session = LanguageModelSession(instructions: instructions)
            let maxOutputCharacters = TokenBudgeting.estimatedOutputCharacters(forTokens: effectiveMaxOutputTokens)
            let prompt = buildPrompt(
                for: message,
                selectedContext: finalSelectedContext,
                language: language,
                maxOutputCharacters: maxOutputCharacters,
                maxOutputTokens: effectiveMaxOutputTokens
            )
            let options = GenerationOptions(temperature: temperature, maximumResponseTokens: effectiveMaxOutputTokens)
            let citations = RAGCitationFormatter.citationBlock(from: selected.topChunks, language: language)

            let assistantID = UUID()
            streamingAssistantID = assistantID
            messages.append(ChatMessage(id: assistantID, role: .assistant, content: "", citations: citations))

            var latestPartial = ""
            let responseStream = session.streamResponse(to: prompt, options: options)
            for try await snapshot in responseStream {
                let partial = String(describing: snapshot.content)
                guard !partial.isEmpty, partial != latestPartial else { continue }
                latestPartial = partial
                updateAssistantMessage(id: assistantID, content: partial, citations: citations)
            }

            let finalContent: String
            if latestPartial.isEmpty {
                let response = try await session.respond(to: prompt, options: options)
                finalContent = String(describing: response.content)
                updateAssistantMessage(id: assistantID, content: finalContent, citations: citations)
            } else {
                finalContent = latestPartial
            }

            persistMessage(role: "assistant", content: finalContent, citations: citations)
        } catch {
            let fallback = "I couldn't generate a response with the foundation model right now. Please try again."
            if let streamingAssistantID,
               let index = messages.firstIndex(where: { $0.id == streamingAssistantID }) {
                messages[index].content = fallback
                messages[index].citations = nil
            } else {
                messages.append(ChatMessage(role: .assistant, content: fallback))
            }
            persistMessage(role: "assistant", content: fallback, citations: nil)
            errorMessage = error.localizedDescription
        }
    }

    /// Pre-analyzes context in the background so send-time latency remains low.
    func preAnalyzeContext(
        contextInput: String,
        pdfURLs: [URL],
        imageURLs: [URL] = [],
        includeWebSearch: Bool,
        maxDuckDuckGoResults: Int,
        maxWikipediaResults: Int,
        maxContextTokens: Int,
        maxResponseTokens: Int,
        useDuckDuckGo: Bool = true,
        useWikipedia: Bool = true
    ) async {
        // Compute clamped/effective values ONCE; reused below for both the
        // cache key and the cache-hit comparison.
        let effectiveMaxDDGResults = clampedMaxDuckDuckGoResults(maxDuckDuckGoResults)
        let effectiveMaxWikiResults = clampedMaxWikipediaResults(maxWikipediaResults)
        let effectiveMaxOutputTokens = calculateEffectiveMaxOutputTokens(maxResponseTokens)
        let effectiveMaxContextTokens = calculateEffectiveContextTokens(
            requestedContextTokens: maxContextTokens,
            maxOutputTokens: effectiveMaxOutputTokens
        )

        let contextKey = makeContextKey(
            contextInput: contextInput,
            pdfURLs: pdfURLs,
            imageURLs: imageURLs,
            includeWebSearch: includeWebSearch,
            searchQuerySeed: "",
            clampedDuckDuckGoResults: effectiveMaxDDGResults,
            clampedWikipediaResults: effectiveMaxWikiResults
        )
        if contextKey.isEmpty {
            preAnalyzedContextKey = nil
            preAnalyzedChunks = []
            preAnalyzedMaxContextTokens = nil
            preAnalyzedMaxOutputTokens = nil
            preAnalyzedMaxDuckDuckGoResults = nil
            preAnalyzedMaxWikipediaResults = nil
            isAnalyzingContext = false
            contextAnalysisProgress = 0
            return
        }
        if contextKey == preAnalyzedContextKey,
           effectiveMaxContextTokens == preAnalyzedMaxContextTokens,
           effectiveMaxOutputTokens == preAnalyzedMaxOutputTokens,
           effectiveMaxDDGResults == preAnalyzedMaxDuckDuckGoResults,
           effectiveMaxWikiResults == preAnalyzedMaxWikipediaResults,
           useDuckDuckGo == preAnalyzedUseDuckDuckGo,
           useWikipedia == preAnalyzedUseWikipedia {
            return
        }

        isAnalyzingContext = true
        contextAnalysisProgress = 0
        debugContext("preAnalyzeContext started for pdfCount=\(pdfURLs.count) imageCount=\(imageURLs.count)")
        let chunks = await collectChunks(
            contextInput: contextInput,
            pdfURLs: pdfURLs,
            imageURLs: imageURLs,
            includeWebSearch: includeWebSearch,
            currentMessage: "",
            maxDuckDuckGoResults: effectiveMaxDDGResults,
            maxWikipediaResults: effectiveMaxWikiResults,
            maxContextTokens: effectiveMaxContextTokens,
            reportProgress: true,
            useDuckDuckGo: useDuckDuckGo,
            useWikipedia: useWikipedia
        )
        preAnalyzedContextKey = contextKey
        preAnalyzedChunks = chunks
        preAnalyzedMaxContextTokens = effectiveMaxContextTokens
        preAnalyzedMaxOutputTokens = effectiveMaxOutputTokens
        preAnalyzedMaxDuckDuckGoResults = effectiveMaxDDGResults
        preAnalyzedMaxWikipediaResults = effectiveMaxWikiResults
        preAnalyzedUseDuckDuckGo = useDuckDuckGo
        preAnalyzedUseWikipedia = useWikipedia
        debugContext("preAnalyzeContext completed chunkCount=\(chunks.count)")
    }

    /// Discards an existing assistant answer (and the preceding user prompt
    /// that produced it, plus everything after) and re-runs `sendMessage`
    /// with the current settings. Use case: the user changed temperature /
    /// language / token budget and wants a fresh answer for the same prompt.
    ///
    /// - Note: anything after the target user prompt in the transcript is
    ///   discarded too — the standard "regenerate from here" semantic.
    func regenerateAssistantMessage(
        id: UUID,
        contextInput: String,
        pdfURLs: [URL],
        imageURLs: [URL] = [],
        includeWebSearch: Bool,
        maxDuckDuckGoResults: Int,
        maxWikipediaResults: Int,
        language: ModelLanguage,
        temperature: Double,
        maxResponseTokens: Int,
        maxContextTokens: Int,
        useDuckDuckGo: Bool = true,
        useWikipedia: Bool = true
    ) async {
        guard let assistantIndex = messages.firstIndex(where: { $0.id == id && $0.role == .assistant }) else {
            return
        }
        // Walk backwards to find the user prompt that triggered this response.
        guard let userIndex = messages[..<assistantIndex].lastIndex(where: { $0.role == .user }) else {
            return
        }
        let userText = messages[userIndex].content

        // Drop everything from the triggering user prompt onwards — both
        // in-memory and from the persisted conversation. `sendMessage` will
        // re-append the user prompt and stream a fresh assistant response.
        messages.removeSubrange(userIndex...)
        deletePersistedTail(fromIndex: userIndex)

        // Invalidate the pre-analyzed context cache so settings changes
        // (e.g. new max-context-tokens, new sources) get re-evaluated.
        preAnalyzedContextKey = nil

        await sendMessage(
            userText,
            contextInput: contextInput,
            pdfURLs: pdfURLs,
            imageURLs: imageURLs,
            includeWebSearch: includeWebSearch,
            maxDuckDuckGoResults: maxDuckDuckGoResults,
            maxWikipediaResults: maxWikipediaResults,
            language: language,
            temperature: temperature,
            maxResponseTokens: maxResponseTokens,
            maxContextTokens: maxContextTokens,
            useDuckDuckGo: useDuckDuckGo,
            useWikipedia: useWikipedia
        )
    }

    /// Deletes the trailing `Message` rows from the current `Conversation`
    /// starting at the given index, mirroring how `messages` and
    /// `currentConversation.messages` are kept in lockstep by `persistMessage`.
    private func deletePersistedTail(fromIndex index: Int) {
        guard let modelContext, let conversation = currentConversation else { return }
        let persisted = conversation.messages
        guard index < persisted.count else { return }
        for message in persisted[index...] {
            modelContext.delete(message)
        }
        // Remove from the relationship array too so subsequent appends land
        // at the right offset.
        conversation.messages.removeSubrange(index...)
        conversation.updatedAt = Date()
        scheduleContextSave()
    }

    /// Clears conversation and cached context analysis so a new chat starts cleanly.
    func resetConversation() {
        pendingSaveTask?.cancel()
        finalizeCurrentConversation()
        messages = []
        errorMessage = nil
        isResponding = false
        isAnalyzingContext = false
        contextAnalysisProgress = 0
        preAnalyzedContextKey = nil
        preAnalyzedChunks = []
        preAnalyzedMaxContextTokens = nil
        preAnalyzedMaxOutputTokens = nil
        preAnalyzedMaxDuckDuckGoResults = nil
        preAnalyzedMaxWikipediaResults = nil
        preAnalyzedUseDuckDuckGo = true
        preAnalyzedUseWikipedia = true
        currentConversation = nil
        currentConversationPDFFilename = nil
        currentConversationPDFBookmark = nil
        currentConversationPDFFilenames = []
        currentConversationPDFBookmarks = []
        activePDFURLForNewConversation = nil
        activePDFURLsForNewConversation = []
    }

    /// Collects web, PDF, and image chunks from provided context.
    private func collectChunks(
        contextInput: String,
        pdfURLs: [URL],
        imageURLs: [URL] = [],
        includeWebSearch: Bool,
        currentMessage: String = "",
        language: ModelLanguage = .english,
        maxDuckDuckGoResults: Int,
        maxWikipediaResults: Int,
        maxContextTokens: Int,
        reportProgress: Bool = false,
        useDuckDuckGo: Bool = true,
        useWikipedia: Bool = true
    ) async -> [RAGChunk] {
        var chunks: [RAGChunk] = []
        if reportProgress {
            isAnalyzingContext = true
            contextAnalysisProgress = 0
        }
        defer {
            if reportProgress {
                contextAnalysisProgress = 1
                isAnalyzingContext = false
            }
        }

        let contextURLs = extractURLs(from: contextInput)
        let effectiveMaxDDGResults = clampedMaxDuckDuckGoResults(maxDuckDuckGoResults)
        let effectiveMaxWikiResults = clampedMaxWikipediaResults(maxWikipediaResults)
        var discoveredResults: [SearchResult] = []
        // Web discovery is send-time only because it needs the current user query.
        if includeWebSearch && !currentMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let searchQuery = buildWebSearchQuery(
                currentMessage: currentMessage,
                contextInput: contextInput
            )
            discoveredResults = await discoverWebResults(
                for: searchQuery,
                language: language,
                maxDuckDuckGoResults: effectiveMaxDDGResults,
                maxWikipediaResults: effectiveMaxWikiResults,
                useDuckDuckGo: useDuckDuckGo,
                useWikipedia: useWikipedia
            )
        }

        var retrievedWebResults: [SearchResult] = []
        var retrievedResultURLKeys = Set<String>()
        for result in discoveredResults {
            guard let retrievedContent = result.retrievedContent?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !retrievedContent.isEmpty else {
                continue
            }
            let urlKey = normalizedURLString(result.url)
            if retrievedResultURLKeys.insert(urlKey).inserted {
                retrievedWebResults.append(result)
            }
        }

        let discoveredURLs = discoveredResults.map(\.url)
        let urls = deduplicatedURLs(contextURLs + discoveredURLs)
            .filter { !retrievedResultURLKeys.contains(normalizedURLString($0)) }
        let uniquePDFs = Array(Set(pdfURLs))
        let uniqueImages = Array(Set(imageURLs))
        let totalWorkItems = max(urls.count + uniquePDFs.count + uniqueImages.count + retrievedWebResults.count, 1)
        var completedWorkItems = 0
        let webScrapingCharacters = webScrapingCharacterBudget(forContextTokens: maxContextTokens)
        let totalMaxWebResults = effectiveMaxDDGResults + effectiveMaxWikiResults

        for result in retrievedWebResults {
            guard let retrievedContent = result.retrievedContent?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !retrievedContent.isEmpty else {
                continue
            }
            let chunked = ragChunker.chunk(
                text: retrievedContent,
                source: result.title,
                maxChunkTokens: Self.webChunkMaxTokens,
                overlapTokens: Self.webChunkOverlapTokens,
                url: result.url
            )
            chunks.append(contentsOf: chunked)
            completedWorkItems += 1
            if reportProgress {
                contextAnalysisProgress = Double(completedWorkItems) / Double(totalWorkItems)
            }
        }

        if !urls.isEmpty {
            let scraped = await webScraper.scrapeMultiplePages(
                urls: urls,
                limit: min(urls.count, totalMaxWebResults),
                maxCharacters: webScrapingCharacters
            )
            for url in urls {
                guard let text = scraped[url] else { continue }
                let chunked = ragChunker.chunk(
                    text: text,
                    source: "Web: \(url)",
                    maxChunkTokens: Self.webChunkMaxTokens,
                    overlapTokens: Self.webChunkOverlapTokens,
                    url: url
                )
                chunks.append(contentsOf: chunked)
                completedWorkItems += 1
                if reportProgress {
                    contextAnalysisProgress = Double(completedWorkItems) / Double(totalWorkItems)
                }
            }
        }

        for pdfURL in uniquePDFs {
            let pageTexts = extractPDFPageTexts(from: pdfURL)
            debugContext("collectChunks pdf=\(pdfURL.lastPathComponent) extractedPages=\(pageTexts.count)")
            for (pageIndex, pageText) in pageTexts.enumerated() {
                // Convert any whitespace-aligned tables (invoices, quotes,
                // spreadsheets exported as PDF) to Markdown pipe rows BEFORE
                // chunking. Otherwise the chunker's whitespace normalisation
                // collapses the columns and the model can't tell a price
                // from a TVA percentage on the same row.
                let tabularized = RAGChunker.convertWhitespaceAlignedTables(pageText)
                let source = "PDF: \(pdfURL.lastPathComponent) page \(pageIndex + 1)"
                let chunked = ragChunker.chunk(
                    text: tabularized,
                    source: source,
                    maxChunkTokens: Self.pdfChunkMaxTokens,
                    overlapTokens: Self.pdfChunkOverlapTokens,
                    pdfPage: pageIndex + 1
                )
                chunks.append(contentsOf: chunked)
            }
            completedWorkItems += 1
            if reportProgress {
                contextAnalysisProgress = Double(completedWorkItems) / Double(totalWorkItems)
            }
        }

        // Images: one chunk per file containing OCR text and/or Vision classification
        // labels. We don't run the chunker — OCR output is short and a single chunk
        // keeps citation block tidy ("Image: filename.jpg").
        for imageURL in uniqueImages {
            if let chunk = await makeImageChunk(for: imageURL) {
                chunks.append(chunk)
                debugContext("collectChunks image=\(imageURL.lastPathComponent) chars=\(chunk.text.count)")
            } else {
                debugContext("collectChunks image=\(imageURL.lastPathComponent) skipped (no extractable content)")
            }
            completedWorkItems += 1
            if reportProgress {
                contextAnalysisProgress = Double(completedWorkItems) / Double(totalWorkItems)
            }
        }

        return chunks
    }

    /// Runs Vision OCR + image classification on the file and packages the
    /// result as a single `RAGChunk`. Returns `nil` if neither OCR nor
    /// classification produced any usable output.
    private func makeImageChunk(for imageURL: URL) async -> RAGChunk? {
        guard let result = await ImageAnalysisService.analyze(imageAt: imageURL),
              !result.isEmpty else {
            return nil
        }

        var sections: [String] = []
        if !result.recognizedText.isEmpty {
            sections.append(result.recognizedText)
        }
        if !result.labels.isEmpty {
            let labelText = result.labels
                .map { String(format: "%@ (%.2f)", $0.label, $0.confidence) }
                .joined(separator: ", ")
            sections.append("Estimated content: \(labelText)")
        }

        return RAGChunk(
            source: "Image: \(imageURL.lastPathComponent)",
            text: sections.joined(separator: "\n\n"),
            url: nil,
            pdfPage: nil
        )
    }

    private func buildWebSearchQuery(currentMessage: String, contextInput: String) -> String {
        let recentMessages = messages.suffix(Self.maxRecentMessagesForWebSearch)
            .filter { $0.role == .user || $0.role == .assistant }
            .map(\.content)
            .joined(separator: ". ")

        let combined = [
            currentMessage.trimmingCharacters(in: .whitespacesAndNewlines),
            recentMessages.trimmingCharacters(in: .whitespacesAndNewlines),
            contextInput.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return String(combined.prefix(Self.maxWebSearchQueryLength))
    }

    private func discoverWebResults(
        for query: String,
        language: ModelLanguage,
        maxDuckDuckGoResults: Int,
        maxWikipediaResults: Int,
        useDuckDuckGo: Bool = true,
        useWikipedia: Bool = true
    ) async -> [SearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }
        guard useDuckDuckGo || useWikipedia else { return [] }

        do {
            let results = try await webSearchService.search(
                query: trimmedQuery,
                maxDuckDuckGoResults: clampedMaxDuckDuckGoResults(maxDuckDuckGoResults),
                maxWikipediaResults: clampedMaxWikipediaResults(maxWikipediaResults),
                language: language,
                useDuckDuckGo: useDuckDuckGo,
                useWikipedia: useWikipedia
            )

            var deduplicated: [SearchResult] = []
            var seenURLKeys = Set<String>()
            for result in results {
                guard let scheme = URL(string: result.url)?.scheme?.lowercased() else { continue }
                guard scheme == "http" || scheme == "https" else { continue }
                let urlKey = normalizedURLString(result.url)
                if seenURLKeys.insert(urlKey).inserted {
                    deduplicated.append(result)
                }
            }

            return deduplicated
        } catch {
            debugContext("discoverWebResults failed for query=\"\(trimmedQuery)\": \(error.localizedDescription)")
            return []
        }
    }

    /// Returns a stable key used to reuse pre-analyzed context.
    /// Callers pass values they have ALREADY clamped (via
    /// `clampedMaxDuckDuckGoResults` / `clampedMaxWikipediaResults`) so this
    /// helper never re-clamps. Clamping is idempotent, but doing it twice was
    /// wasteful and confusing — the cache key now reflects exactly the
    /// effective values used everywhere else in the request.
    private func makeContextKey(
        contextInput: String,
        pdfURLs: [URL],
        imageURLs: [URL] = [],
        includeWebSearch: Bool,
        searchQuerySeed: String,
        clampedDuckDuckGoResults: Int,
        clampedWikipediaResults: Int
    ) -> String {
        let normalizedContext = contextInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedPDFPaths = Array(Set(pdfURLs.map(\.path))).sorted().joined(separator: "|")
        let normalizedImagePaths = Array(Set(imageURLs.map(\.path))).sorted().joined(separator: "|")
        let normalizedQuerySeed = includeWebSearch
            ? searchQuerySeed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            : ""
        if normalizedContext.isEmpty && normalizedPDFPaths.isEmpty && normalizedImagePaths.isEmpty && normalizedQuerySeed.isEmpty {
            return ""
        }
        return "\(normalizedContext)||\(normalizedPDFPaths)||img:\(normalizedImagePaths)||web:\(includeWebSearch)||query:\(normalizedQuerySeed)||ddg:\(clampedDuckDuckGoResults)||wiki:\(clampedWikipediaResults)"
    }

    private func clampedMaxDuckDuckGoResults(_ value: Int) -> Int {
        min(max(value, AppSettings.maxDuckDuckGoResultsRange.lowerBound), Self.maxWebContextURLCap)
    }

    private func clampedMaxWikipediaResults(_ value: Int) -> Int {
        min(max(value, AppSettings.maxWikipediaResultsRange.lowerBound), Self.maxWebContextURLCap)
    }

    private func deduplicatedURLs(_ urls: [String]) -> [String] {
        var seen = Set<String>()
        return urls.filter { url in
            let normalized = normalizedURLString(url)
            return seen.insert(normalized).inserted
        }
    }

    private func normalizedURLString(_ rawURL: String) -> String {
        guard var components = URLComponents(string: rawURL) else {
            return rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        return components.string ?? rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extracts unique HTTP(S) URLs from free-form text.
    private func extractURLs(from raw: String) -> [String] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        let found = detector?.matches(in: raw, options: [], range: range) ?? []

        let urls = found.compactMap { match -> String? in
            guard let url = match.url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                return nil
            }
            return url.absoluteString
        }

        return Array(Set(urls))
    }

    /// Extracts non-empty text from every page of a PDF file URL.
    private func extractPDFPageTexts(from url: URL) -> [String] {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let document = PDFDocument(url: url) else {
            debugContext("extractPDFPageTexts failed to open PDF at path=\(url.path)")
            return []
        }

        if document.isLocked, document.unlock(withPassword: "") {
            debugContext("extractPDFPageTexts unlocked a PDF with empty password")
        }
        var pages: [String] = []

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            if let pageString = page.string?.trimmingCharacters(in: .whitespacesAndNewlines),
               !pageString.isEmpty {
                pages.append(pageString)
                continue
            }
            if let attributedPageString = page.attributedString?.string.trimmingCharacters(in: .whitespacesAndNewlines),
               !attributedPageString.isEmpty {
                pages.append(attributedPageString)
            }
        }

        if pages.isEmpty,
           let documentText = document.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !documentText.isEmpty {
            debugContext("extractPDFPageTexts using document-level fallback text for \(url.lastPathComponent)")
            pages.append(documentText)
        }

        if pages.isEmpty {
            debugContext("extractPDFPageTexts attempting OCR fallback for image-only PDF")
            pages = extractPDFPageTextsWithOCR(from: document)
            debugContext("extractPDFPageTexts OCR fallback extractedPages=\(pages.count)")
        }

        return pages
    }

    /// Fallback OCR extraction for image-only PDFs.
    private func extractPDFPageTextsWithOCR(from document: PDFDocument) -> [String] {
        var pages: [String] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex),
                  let pageText = recognizeText(in: page) else { continue }
            pages.append(pageText)
        }
        return pages
    }

    /// Runs Vision OCR on a rendered PDF page and returns recognized text.
    /// Renders the page to a `CGImage`, then delegates to `ImageAnalysisService`
    /// so both image attachments and PDF-OCR-fallback share the same OCR config.
    private func recognizeText(in page: PDFPage) -> String? {
        let pageBounds = page.bounds(for: .mediaBox)
        let pageSize = pageBounds.size
        let maxSide: CGFloat = 2000
        let scale = max(pageSize.width, pageSize.height) > maxSide
            ? (maxSide / max(pageSize.width, pageSize.height))
            : 1
        let targetSize = CGSize(
            width: max(1, pageSize.width * scale),
            height: max(1, pageSize.height * scale)
        )
        let image = page.thumbnail(of: targetSize, for: .mediaBox)
        #if os(macOS)
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        let cgImage = image.cgImage
        #endif
        guard let cgImage else {
            return nil
        }
        return ImageAnalysisService.recognizeText(in: cgImage)
    }

    private func debugContext(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[ChatService][Context] \(message())")
        #endif
    }

    /// Clamps requested output tokens to fit the shared 4096-token context window budget.
    private func calculateEffectiveMaxOutputTokens(_ requestedMaxTokens: Int) -> Int {
        TokenBudgeting.clampedOutputTokens(
            requestedMaxTokens: requestedMaxTokens,
            instructionTokens: TokenBudgeting.instructionTokens,
            promptOverheadTokens: TokenBudgeting.promptOverheadTokens,
            minContextTokens: TokenBudgeting.minContextTokens
        )
    }

    private func calculateEffectiveContextTokens(
        requestedContextTokens: Int,
        maxOutputTokens: Int
    ) -> Int {
        TokenBudgeting.clampedContextTokens(
            requestedContextTokens: requestedContextTokens,
            maxOutputTokens: maxOutputTokens,
            settingsRange: AppSettings.maxContextTokensRange,
            instructionTokens: TokenBudgeting.instructionTokens,
            promptOverheadTokens: TokenBudgeting.promptOverheadTokens,
            minContextTokens: TokenBudgeting.minContextTokens
        )
    }

    private func clampContextTokens(_ requestedTokens: Int) -> Int {
        min(max(requestedTokens, AppSettings.maxContextTokensRange.lowerBound), AppSettings.maxContextTokensRange.upperBound)
    }

    private func webScrapingCharacterBudget(forContextTokens contextTokens: Int) -> Int {
        let clampedTokens = clampContextTokens(contextTokens)
        let approxContextChars = TokenBudgeting.estimatedContextCharacters(forTokens: clampedTokens)
        let scrapeBudget = approxContextChars * 2
        return min(max(scrapeBudget, Self.minWebScrapingCharacters), Self.maxWebScrapingCharacters)
    }

    /// Builds the model prompt from recent history and retrieved context.
    private func buildPrompt(
        for userMessage: String,
        selectedContext: String,
        language: ModelLanguage,
        maxOutputCharacters: Int,
        maxOutputTokens: Int
    ) -> String {
        let historyMessages: [ChatMessage]
        if let last = messages.last, last.role == .user, last.content == userMessage {
            historyMessages = Array(messages.dropLast())
        } else {
            historyMessages = messages
        }

        let history = historyMessages
            .suffix(Self.historyMessageLimit)
            .map { item in
                if item.role == .assistant {
                    return "Assistant: \(item.content)"
                }
                return "User: \(item.content)"
            }
            .joined(separator: "\n")

        return PromptLoader.loadPrompt(
            mode: "normal",
            feature: "chat",
            language: language,
            replacements: [
                "history": history,
                "context": selectedContext,
                "question": userMessage,
                "maxOutputCharacters": "\(maxOutputCharacters)",
                "maxOutputTokens": "\(maxOutputTokens)"
            ]
        ) ?? fallbackChatPrompt(
            history: history,
            selectedContext: selectedContext,
            userMessage: userMessage,
            language: language,
            maxOutputCharacters: maxOutputCharacters,
            maxOutputTokens: maxOutputTokens
        )
    }


    private func updateAssistantMessage(id: UUID, content: String, citations: String?) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content = content
        messages[index].citations = citations
    }

    /// Builds dynamic chat instructions matching the user's query language.
    private func buildInstructions(for language: ModelLanguage) -> String {
        return PromptLoader.loadPrompt(mode: "normal", feature: "chat", variant: "instructions", language: language)
            ?? fallbackChatInstructions(for: language)
    }

    private func fallbackChatInstructions(for language: ModelLanguage) -> String {
        if language == .french {
            return """
            Vous êtes un assistant de chat utile. Répondez clairement et précisément.
            Utilisez le contexte récupéré lorsqu'il est pertinent et indiquez vos incertitudes si le contexte est insuffisant.
            Répondez dans la même langue que la question de l'utilisateur (ici: français).
            """
        }

        return """
        You are a helpful chat assistant. Answer the user clearly and accurately.
        Use retrieved context when relevant and mention uncertainty when context is insufficient.
        Respond in the same language as the user's latest question.
        """
    }

    private func fallbackChatPrompt(
        history: String,
        selectedContext: String,
        userMessage: String,
        language: ModelLanguage,
        maxOutputCharacters: Int,
        maxOutputTokens: Int
    ) -> String {
        if language == .french {
            return """
            Conversation :
            \(history)

            Contexte récupéré :
            \(selectedContext)

            Question de l'utilisateur :
            \(userMessage)

            Réponds de façon concise et pratique.
            Limite de sortie : \(maxOutputTokens) tokens maximum (environ \(maxOutputCharacters) caractères).
            Quand c'est pertinent, inclus des expressions ou formules mathématiques.
            Format de sortie attendu : LaTeX pour les expressions mathématiques.
            Règles de format math :
            - Utilise $...$ pour l'inline.
            - Utilise \\[...\\] pour les blocs.
            - Utilise un LaTeX simple compatible avec le rendu de l'application.
            - N'utilise jamais d'environnements \\begin{.
            """
        }

        return """
        Conversation:
        \(history)

        Retrieved Context:
        \(selectedContext)

        User question:
        \(userMessage)

        Answer in a concise and practical way.
        Output limit: \(maxOutputTokens) tokens maximum (about \(maxOutputCharacters) characters).
        When relevant, include mathematical expressions or formulas.
        Required output format: LaTeX for mathematical expressions.
        Math format requirements:
        - Use $...$ for inline math.
        - Use \\[...\\] for block math.
        - Use simple LaTeX compatible with the app renderer.
        - Never use environments with \\begin{.
        """
    }
    private func debugLog(_ message: String) {
        #if DEBUG
        print("[ChatView] \(message)")
        #endif
    }
    /// Persists a message to the current SwiftData conversation.
    private func persistMessage(role: String, content: String, citations: String?) {
        guard let modelContext else { return }

        // Create conversation if needed
        if currentConversation == nil {
            let (filename, bookmark) = pdfStampForNewConversation()
            let (filenames, bookmarks) = pdfStampListForNewConversation()
            let conv = Conversation(
                messages: [],
                title: role == "user" ? generateTitle(from: content) : nil,
                pdfFilename: filename,
                pdfBookmark: bookmark,
                pdfFilenames: filenames,
                pdfBookmarks: bookmarks
            )
            currentConversation = conv
            modelContext.insert(conv)
            currentConversationPDFFilename = filename
            currentConversationPDFBookmark = bookmark
            currentConversationPDFFilenames = filenames
            currentConversationPDFBookmarks = bookmarks
        }

        guard let conversation = currentConversation else { return }

        // Create and add message
        let message = Message(role: role, content: content, citations: citations)
        conversation.messages.append(message)
        conversation.updatedAt = Date()

        // Debug log the new message and conversation state
        #if DEBUG
        debugLog("Persisted new message with role=\(role) content=\\n \"\(content))\" \\ncitations=\"\(citations ?? "none")\"")
        debugLog("Current conversation now has \(conversation.messages.count) messages, last updated at \(conversation.updatedAt)")
        #endif

        scheduleContextSave()
    }

    /// Auto-generates a title from the first user message.
    private func generateTitle(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let maxLength = 50
        if trimmed.count <= maxLength {
            return trimmed
        }
        let index = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
        return String(trimmed[..<index]) + "..."
    }

    /// Finalizes the current conversation by auto-generating a title if needed.
    private func finalizeCurrentConversation() {
        guard let modelContext, let conversation = currentConversation, !conversation.messages.isEmpty else { return }

        // Auto-generate title from first user message if not set
        if conversation.title == nil {
            if let firstUserMessage = conversation.messages.first(where: { $0.role == "user" }) {
                conversation.title = generateTitle(from: firstUserMessage.content)
            }
        }

        pendingSaveTask?.cancel()
        _ = saveContext(modelContext)
    }

    /// Saves the current SwiftData context and reports failures in debug builds.
    @discardableResult
    private func saveContext(_ modelContext: ModelContext) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            #if DEBUG
            print("[ChatService][Persistence] Failed to save model context: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    /// Debounces persistence writes to avoid saving on every single appended message.
    @MainActor private func scheduleContextSave() {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.saveDebounceIntervalNanoseconds)
            } catch {
                return
            }
            guard let self else {
                #if DEBUG
                print("[ChatService][Persistence] Skipped save: ChatService deallocated before debounced save.")
                #endif
                return
            }
            guard let modelContext = self.modelContext else {
                #if DEBUG
                print("[ChatService][Persistence] Skipped save: modelContext unavailable.")
                #endif
                return
            }
            _ = self.saveContext(modelContext)
        }
    }

    /// Seeds a new conversation from a Search Assist exchange and persists it to history.
    func startConversationFromSearch(query: String, answer: String, citations: String?) {
        pendingSaveTask?.cancel()
        finalizeCurrentConversation()
        errorMessage = nil
        isResponding = false
        isAnalyzingContext = false
        contextAnalysisProgress = 0
        preAnalyzedContextKey = nil
        preAnalyzedChunks = []
        preAnalyzedMaxContextTokens = nil
        preAnalyzedMaxOutputTokens = nil
        preAnalyzedMaxDuckDuckGoResults = nil
        preAnalyzedMaxWikipediaResults = nil
        preAnalyzedUseDuckDuckGo = true
        preAnalyzedUseWikipedia = true

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCitations = citations?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCitations = (trimmedCitations?.isEmpty ?? true) ? nil : trimmedCitations

        messages = []
        if !trimmedQuery.isEmpty {
            messages.append(ChatMessage(role: .user, content: trimmedQuery))
        }
        if !trimmedAnswer.isEmpty {
            messages.append(ChatMessage(role: .assistant, content: trimmedAnswer, citations: normalizedCitations))
        }

        guard let modelContext else { return }

        let conversation = Conversation(
            messages: [],
            title: trimmedQuery.isEmpty ? nil : generateTitle(from: trimmedQuery)
        )
        modelContext.insert(conversation)
        currentConversation = conversation

        if !trimmedQuery.isEmpty {
            conversation.messages.append(Message(role: "user", content: trimmedQuery))
        }
        if !trimmedAnswer.isEmpty {
            conversation.messages.append(Message(role: "assistant", content: trimmedAnswer, citations: normalizedCitations))
        }
        conversation.updatedAt = Date()
        _ = saveContext(modelContext)
    }

    /// Loads a previous conversation by ID and syncs it to the UI.
    func loadConversation(id: UUID) {
        guard let modelContext else { return }

        // Find the conversation
        let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { $0.id == id })
        guard let conversation = try? modelContext.fetch(descriptor).first else { return }

        currentConversation = conversation
        currentConversationPDFFilename = conversation.pdfFilename
        currentConversationPDFBookmark = conversation.pdfBookmark
        currentConversationPDFFilenames = conversation.pdfFilenames
        currentConversationPDFBookmarks = conversation.pdfBookmarks

        // Convert SwiftData messages to ChatMessage for UI
        messages = conversation.messages
            .sorted { $0.timestamp < $1.timestamp }
            .map { ChatMessage(role: $0.role == "user" ? .user : .assistant, content: $0.content, citations: $0.citations) }
    }

    /// Builds the PDF stamp for a freshly created conversation from
    /// `activePDFURLForNewConversation`. Returns `(nil, nil)` when no PDF
    /// was attached or the bookmark can't be created (e.g. file isn't
    /// reachable). Filename is *normalized* (see `Self.pdfBaseFilename`)
    /// so two drops of the same source file collapse onto one conv key.
    private func pdfStampForNewConversation() -> (String?, Data?) {
        guard let url = activePDFURLForNewConversation else { return (nil, nil) }
        let filename = Self.pdfBaseFilename(url.lastPathComponent)
        let bookmark = try? makeSecurityScopedBookmark(for: url)
        return (filename, bookmark)
    }

    /// Same as `pdfStampForNewConversation` but for the *full* set of PDFs
    /// currently in context, not just the anchor. Bookmarks that fail to
    /// build are skipped so the two parallel arrays stay aligned.
    private func pdfStampListForNewConversation() -> ([String], [Data]) {
        var names: [String] = []
        var bookmarks: [Data] = []
        for url in activePDFURLsForNewConversation {
            guard let bookmark = try? makeSecurityScopedBookmark(for: url) else { continue }
            names.append(Self.pdfBaseFilename(url.lastPathComponent))
            bookmarks.append(bookmark)
        }
        return (names, bookmarks)
    }

    /// Keeps the active conversation's persisted PDF list in sync with
    /// whatever the composer currently has attached. Called from
    /// `sendMessage` so adds/removes that happen between turns reach the
    /// store on the next message.
    private func syncCurrentConversationPDFs(with pdfURLs: [URL]) {
        guard let conv = currentConversation else { return }
        var names: [String] = []
        var bookmarks: [Data] = []
        for url in pdfURLs {
            guard let bookmark = try? makeSecurityScopedBookmark(for: url) else { continue }
            names.append(Self.pdfBaseFilename(url.lastPathComponent))
            bookmarks.append(bookmark)
        }
        // Skip the SwiftData write (and the @Published republish) when the
        // arrays haven't actually changed, so we don't trigger redundant
        // host-side reactions mid-send.
        if conv.pdfFilenames != names {
            conv.pdfFilenames = names
            currentConversationPDFFilenames = names
        }
        if conv.pdfBookmarks != bookmarks {
            conv.pdfBookmarks = bookmarks
            currentConversationPDFBookmarks = bookmarks
        }
    }

    /// Strips the trailing " (N)" suffix that `DroppedPDFStore` adds when
    /// the same filename is dropped twice ("X.pdf" → "X.pdf",
    /// "X (3).pdf" → "X.pdf"). The normalized form is the conversation
    /// lookup key — it's filename-stable across sessions, sandbox copy
    /// numbering, and Spotlight/share-extension rewrites.
    static func pdfBaseFilename(_ raw: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #" \(\d+\)(?=\.[^.]+$)"#) else {
            return raw
        }
        let ns = raw as NSString
        let range = NSRange(location: 0, length: ns.length)
        return regex.stringByReplacingMatches(in: raw, range: range, withTemplate: "")
    }

    private func makeSecurityScopedBookmark(for url: URL) throws -> Data {
#if os(macOS)
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
#else
        return try url.bookmarkData()
#endif
    }

    /// Returns the most recently updated conversation that included a PDF
    /// with the given filename in context — whether it was the *anchor*
    /// (the legacy `pdfFilename` field, populated on the first turn) or
    /// any later addition (the `pdfFilenames` array, kept in sync by
    /// `syncCurrentConversationPDFs`). Both sides are normalized via
    /// `pdfBaseFilename` so a re-dropped "X (3).pdf" still lands on the
    /// original "X.pdf" conversation.
    ///
    /// Implementation note: we used to compose this in a single `#Predicate`
    /// with `pdfFilenames.contains(normalized)`, but SwiftData's predicate
    /// engine crashes (`EXC_BAD_ACCESS`) on `[String].contains` against a
    /// `@Model` property — that operator doesn't translate to the backing
    /// store. So this runs in two steps: cheap anchor predicate first,
    /// then an in-memory scan of the broader set as a fallback.
    func findLatestConversation(matchingPDFFilename filename: String) -> Conversation? {
        guard let modelContext else { return nil }
        let normalized = Self.pdfBaseFilename(filename)

        var anchorDescriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.pdfFilename == normalized },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        anchorDescriptor.fetchLimit = 1
        if let anchor = try? modelContext.fetch(anchorDescriptor).first {
            return anchor
        }

        let allDescriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        guard let all = try? modelContext.fetch(allDescriptor) else { return nil }
        return all.first { $0.pdfFilenames.contains(normalized) }
    }

    /// Returns a conversation anchored to a PDF with the given checksum,
    /// most recently updated first. Used as a fallback when filename
    /// lookup misses (e.g. the user renamed the file).
    func findLatestConversation(matchingPDFChecksum checksum: String) -> Conversation? {
        guard let modelContext else { return nil }
        var descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.pdfChecksum == checksum },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    /// Stamps the current conversation with a freshly computed checksum.
    /// Safe to call from a background hash — no-op if the conversation has
    /// already been re-opened/replaced or already carries a matching value.
    func updateCurrentConversationChecksum(_ checksum: String) {
        guard let conversation = currentConversation,
              conversation.pdfChecksum != checksum else { return }
        conversation.pdfChecksum = checksum
        scheduleContextSave()
    }
}

/// Represents a chat turn in the conversation.
struct ChatMessage: Identifiable {
    /// Distinguishes user and assistant messages.
    enum Role {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    var content: String
    var citations: String?

    init(id: UUID = UUID(), role: Role, content: String, citations: String? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.citations = citations
    }
}
