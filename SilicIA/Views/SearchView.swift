//
//  SearchView.swift
//  SilicIA
//
//  Created by Claude on 23/03/2026.
//

import SwiftUI
import UniformTypeIdentifiers
#if canImport(SwiftData)
import SwiftData
#endif
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
import SafariServices
#endif

/// Main search experience that fetches web results and generates AI summaries.
struct SearchView: View {
    private static let aiSummaryOverfetchResults = 3
    private static let firstGuessTokenCap = 220
    private static let deepSearchDerivedQueryCount = 3
    let initialQuery: String?
    let onInitialQueryHandled: (() -> Void)?
    let chatService: ChatService
    let onOfflineQuery: ((String) -> Void)?
    let onChatMore: ((_ query: String, _ answer: String, _ citations: String?) -> Void)?
    /// Dropping a PDF/image on the search surface writes here so that the
    /// containing view can flip to the Chat tab and ChatView picks the file
    /// up as context via its existing shared-input merge.
    let onAttachmentsDropped: (([URL], [URL]) -> Void)?

    private static let imageFileExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "bmp"
    ]

    @StateObject private var searchService = WebSearchService()
    @StateObject private var aiService = AIService()

    @State private var searchQuery = ""
    @State private var searchResults: [SearchResult] = []
    @State private var hasAttemptedSearch: Bool = false
    /// Per-source RAG match-score percentages keyed by `SearchResult.url`.
    /// Populated by `aiService.summarize` via its `onMatchingScores` callback.
    /// Missing keys are treated as 0% by the card view.
    @State private var matchingScoresByURL: [String: Double] = [:]

    /// Whether the result cards should be rendered. We hide them until
    /// RAG scoring finishes so users see the cards in their final, sorted
    /// order — except in no-AI mode, where scoring never runs and the raw
    /// web-search order is the best we have.
    private var shouldDisplaySearchCards: Bool {
        isNoAIMode || !matchingScoresByURL.isEmpty
    }

    /// True when tool calling is on AND the user has run a search and the
    /// model is either still generating a tool-driven summary or has just
    /// finished one. Used by the body-level branch to keep the resultsView
    /// visible (and therefore the summary card) even though
    /// `searchResults` is intentionally empty in this mode.
    private var hasToolDrivenSummary: Bool {
        guard settings.useToolCalling else { return false }
        guard hasAttemptedSearch else { return false }
        return aiService.isSummarizing
            || !aiService.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Filters raw per-URL relevance scores to only those URLs actually
    /// displayed as cards, renormalizes so the values sum to 100, then
    /// applies largest-remainder (Hamilton) rounding so the integer values
    /// shown in the `MatchScoreBadge`s also sum to exactly 100 — naive
    /// `round()` would let three 33.33s collapse to 99% or six 16.67s
    /// expand to 102%.
    private static func rebalanceScores(
        _ raw: [String: Double],
        displayedURLs: Set<String>
    ) -> [String: Double] {
        let filtered = raw.filter { displayedURLs.contains($0.key) }
        let total = filtered.values.reduce(0, +)
        guard total > 0 else { return [:] }

        let scaled = filtered.mapValues { ($0 / total) * 100 }

        // Largest-remainder allocation: floor each value, then distribute
        // the leftover units to the entries with the largest fractional
        // remainders. Ties broken by URL for determinism.
        var floors: [String: Int] = [:]
        var remainders: [(url: String, frac: Double)] = []
        for (url, value) in scaled {
            let f = floor(value)
            floors[url] = Int(f)
            remainders.append((url, value - f))
        }
        var leftover = 100 - floors.values.reduce(0, +)
        remainders.sort { lhs, rhs in
            lhs.frac != rhs.frac ? lhs.frac > rhs.frac : lhs.url < rhs.url
        }
        var i = 0
        while leftover > 0 && i < remainders.count {
            floors[remainders[i].url, default: 0] += 1
            leftover -= 1
            i += 1
        }
        // Negative leftover (sum exceeds 100 from FP drift) — trim smallest.
        if leftover < 0 {
            for entry in remainders.reversed() where leftover < 0 {
                if let v = floors[entry.url], v > 0 {
                    floors[entry.url] = v - 1
                    leftover += 1
                }
            }
        }
        return floors.mapValues { Double($0) }
    }

    /// `searchResults` sorted by descending RAG match score, with stable
    /// ordering on ties (preserves the original web-search rank).
    /// Returns the original list unchanged while `matchingScoresByURL` is
    /// empty (i.e. before the AI summary lands).
    private var sortedSearchResults: [SearchResult] {
        guard !matchingScoresByURL.isEmpty else { return searchResults }
        return searchResults
            .enumerated()
            .sorted { lhs, rhs in
                let lScore = matchingScoresByURL[lhs.element.url] ?? 0
                let rScore = matchingScoresByURL[rhs.element.url] ?? 0
                if lScore != rScore { return lScore > rScore }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
    @State private var showingSummary = false
    @State private var isNoAIMode = false
    @State private var errorMessage: String?
    @FocusState private var isSearchFieldFocused: Bool

    // Settings
    /// Shared settings store (@Observable). `@Bindable` so the settings
    /// panel can derive `$settingsStore.settings.x` bindings.
    @Bindable private var settingsStore = AppSettingsStore.shared
    /// Convenience accessor over the shared store so existing `settings.x`
    /// reads and `settings.x = y` writes keep working unchanged; binding
    /// sites use `$settingsStore.settings.x`.
    private var settings: AppSettings {
        get { settingsStore.settings }
        nonmutating set { settingsStore.settings = newValue }
    }
    @State private var showSettings = false
    @State private var activeGenerationProfile: AIService.GenerationProfile = .fast

    // Generation timer
    @State private var summaryStartTime: Date? = nil
    @State private var summaryElapsedSeconds: Double? = nil
    @State private var firstGuessElapsedSeconds: Double? = nil
    @State private var firstGuessText = ""
    @State private var isGeneratingFirstGuess = false
    @State private var activeSearchRequestID = UUID()
    @State private var didCopySummary = false

    // Per-result web page summaries
    @State private var isShowingWebPageSummaryOverlay = false
    @State private var selectedWebPageSummaryResult: SearchResult?
    @State private var webPageSummaryText: String = ""
    @State private var webPageSummaryError: String?
    @State private var isGeneratingWebPageSummary = false
    @State private var activeWebPageSummaryRequestID = UUID()

    init(
        initialQuery: String? = nil,
        onInitialQueryHandled: (() -> Void)? = nil,
        chatService: ChatService,
        onOfflineQuery: ((String) -> Void)? = nil,
        onChatMore: ((_ query: String, _ answer: String, _ citations: String?) -> Void)? = nil,
        onAttachmentsDropped: (([URL], [URL]) -> Void)? = nil
    ) {
        self.initialQuery = initialQuery
        self.onInitialQueryHandled = onInitialQueryHandled
        self.chatService = chatService
        self.onOfflineQuery = onOfflineQuery
        self.onChatMore = onChatMore
        self.onAttachmentsDropped = onAttachmentsDropped
    }
    
    private var estimatedMaxOutputCharacters: Int {
        TokenBudgeting.estimatedOutputCharacters(forTokens: settings.maxResponseTokens)
    }

    private var estimatedMaxOutputSentences: Int {
        TokenBudgeting.estimatedOutputSentences(forTokens: settings.maxResponseTokens)
    }

    private var maxAllowedContextTokensForCurrentResponse: Int {
        AppSettings.maxAllowedContextTokens(forResponseTokens: settings.maxResponseTokens)
    }

    private var effectiveContextTokens: Int {
        min(settings.maxContextTokens, maxAllowedContextTokensForCurrentResponse)
    }

    private var estimatedMaxContextWords: Int {
        TokenBudgeting.estimatedContextWords(forTokens: effectiveContextTokens)
    }

    private var defaultScrapingCharactersFromContextTokens: Int {
        max(TokenBudgeting.estimatedContextCharacters(forTokens: effectiveContextTokens) * 2, 1500)
    }

    private var hasChatMoreContext: Bool {
        !searchResults.isEmpty &&
        !aiService.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !aiService.isSummarizing
    }

    private var chatButtonTitle: String {
        return hasChatMoreContext
            ? L.t("search.button.chatMore", language: settings.language)
            : L.t("search.button.chat", language: settings.language)
    }

    private var isChatButtonDisabled: Bool {
        if hasChatMoreContext {
            return false
        }
        return searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || searchService.isSearching
    }

    private func handleChatButtonTap() {
        if hasChatMoreContext {
            let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            let answer = aiService.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            let citationsTrimmed = aiService.citations.trimmingCharacters(in: .whitespacesAndNewlines)
            let citations = citationsTrimmed.isEmpty ? nil : citationsTrimmed
            onChatMore?(query, answer, citations)
            return
        }
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }
        onOfflineQuery?(trimmedQuery)
    }

    /// Lays out header, search controls, and context-sensitive body content.
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                headerView

                if showSettings {
                    settingsPage
                } else {
                    // Content
                    if searchService.isSearching {
                        loadingView
                    } else if !searchResults.isEmpty {
                        resultsView
                    } else if hasToolDrivenSummary {
                        // Tool-calling mode skips the auto web search, so
                        // searchResults stays empty even after a successful
                        // run. The model still produces a summary via the
                        // tool kit — surface it through the same resultsView
                        // (which only renders the summary card when no
                        // search-result cards exist).
                        resultsView
                    } else if !hasAttemptedSearch {
                        welcomeView
                    } else {
                        emptyStateView
                    }

                    // Search Bar
                    searchBarView
                }
            }

            if isShowingWebPageSummaryOverlay {
                webPageSummaryOverlay
            }
        }
        .background(Color.platformWindowBackground)
        .contentShape(Rectangle())
        .onDrop(of: [.pdf, .image, .fileURL], isTargeted: nil) { providers in
            handleAttachmentDrop(providers)
        }
        // Mirror the AIService's tool-call accumulator into the local
        // searchResults state whenever it changes — this is how the cards
        // get populated in tool-calling mode (the auto web search is
        // skipped, so the model's webSearch invocations are the only
        // source of URLs). Filtered to current request only by also
        // checking hasAttemptedSearch so a stale post-cancel notification
        // doesn't repopulate the cards on the welcome screen.
        .onChange(of: aiService.toolFetchedResults) { _, newResults in
            guard settings.useToolCalling, hasAttemptedSearch else { return }
            searchResults = newResults
        }
        .onAppear {
            consumeInitialQueryIfNeeded()
            // Drop the caret into the search field whenever this screen
            // appears in an idle state. Triggers the iOS soft keyboard
            // immediately so the user can start typing without an extra
            // tap. We skip it when results are visible to avoid stealing
            // focus while the user is scanning them.
            if searchResults.isEmpty && !searchService.isSearching {
                // Defer a runloop so the TextField is mounted before we
                // request focus — SwiftUI ignores focus changes made
                // before the target view is in the responder chain.
                DispatchQueue.main.async {
                    isSearchFieldFocused = true
                }
            }
        }
        .onChange(of: settings) {
            // Persistence is automatic via AppSettingsStore; this handler
            // only reacts to the first-guess toggle being switched off.
            if !settings.isFirstGuessEnabled {
                firstGuessText = ""
                firstGuessElapsedSeconds = nil
                isGeneratingFirstGuess = false
            }
        }
        .onChange(of: initialQuery) {
            consumeInitialQueryIfNeeded()
        }
        #if canImport(UIKit)
        .overlay {
            KeyboardDismissTapOverlay(onTapOutsideTextInput: {
                dismissKeyboard()
            })
        }
        #endif
    }

    // MARK: - Header View
    private var headerView: some View {
        HStack(spacing: 4) {
            if showSettings {
                // Settings is a sub-screen; keep its back button as the
                // dominant affordance so users know how to leave.
                Button(action: { showSettings = false }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text(L.t("common.back", language: settings.language))
                            .fontWeight(.medium)
                    }
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(L.t("common.back", language: settings.language))

                Text(L.t("search.settings.title", language: settings.language))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)

                Spacer(minLength: 0)
            } else {
                // Reset action sits on the leading edge so it mirrors the
                // chat tab's "new conversation" button position.
                headerIconButton(
                    systemImage: "arrow.counterclockwise",
                    label: L.t("common.startOver", language: settings.language),
                    action: { goHome() }
                )

                Spacer()

                headerIconButton(
                    systemImage: "gearshape",
                    label: L.t("common.settings", language: settings.language),
                    action: { showSettings = true }
                )
            }
        }
        .padding()
        // Transparent header — floats over the content in the Liquid
        // Glass style rather than sitting on an opaque bar.
    }

    /// 44pt-tap-target icon button used in the top bar. Matches the
    /// equivalent helper in `ChatView` so the two tabs feel symmetric.
    @ViewBuilder
    private func headerIconButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private var settingsPage: some View {
        ScrollView {
            settingsPanel
                .padding()
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Search Bar View
    private var searchBarView: some View {
        let isInputEmpty = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isPrimaryDisabled = isInputEmpty || searchService.isSearching
        return VStack(spacing: 10) {
            // Growing text field — expands vertically as the query grows.
            // The send button lives in the action row below, so there's no
            // need for Return/Enter to submit; on iOS the keyboard Search
            // button still fires `.onSubmit` via `.submitLabel(.search)`.
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                    .padding(.top, 3)

                TextField(L.t("search.placeholder", language: settings.language), text: $searchQuery, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .lineLimit(1...6)
                    .focused($isSearchFieldFocused)
                    .submitLabel(.search)
                    #if canImport(UIKit)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
                    #endif
                    .onSubmit {
                        performSearch()
                    }

                if !searchQuery.isEmpty {
                    Button(action: { searchQuery = ""; hasAttemptedSearch = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 3)
                    .help(L.t("common.clear", language: settings.language))
                    .accessibilityLabel(L.t("common.clear", language: settings.language))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            // No inner fill — the field sits directly on the glass island
            // (avoids glass-on-glass) and matches the ChatView composer.

            if let errorMessage,
               !errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Action row: Chat + Extensive left-aligned, send arrow right.
            HStack(spacing: 8) {
                Button(action: handleChatButtonTap) {
                    Label(chatButtonTitle, systemImage: "bubble.left.and.bubble.right")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isChatButtonDisabled)
                .accessibilityLabel(chatButtonTitle)

                Button(action: { performSearch(maxScrapingChars: 7000, generationProfile: .deep) }) {
                    Label(
                        L.t("search.button.deep", language: settings.language),
                        systemImage: "sparkle.magnifyingglass"
                    )
                    .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isPrimaryDisabled)
                .accessibilityLabel(L.t("search.button.deep", language: settings.language))

                Spacer()

                // Swap send → stop while any phase is running (web search,
                // RAG scoring, first-guess, AI summary). Tapping rotates
                // `activeSearchRequestID`, which every in-flight task
                // checks before publishing — same mechanism as `goHome()`.
                let isBusy = searchService.isSearching || aiService.isSummarizing || isGeneratingFirstGuess
                if isBusy {
                    Button(action: cancelCurrentSearch) {
                        Image(systemName: "stop.circle.fill")
                            .resizable()
                            .frame(width: 28, height: 28)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.red)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L.t("search.button.stop", language: settings.language))
                    .accessibilityLabel(L.t("search.button.stop", language: settings.language))
                } else {
                    Button(action: { performSearch(generationProfile: .fast) }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .resizable()
                            .frame(width: 28, height: 28)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(isPrimaryDisabled ? Color.secondary : Color.accentColor)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isPrimaryDisabled)
                    .help(L.t("search.button.go", language: settings.language))
                    .accessibilityLabel(L.t("search.button.go", language: settings.language))
                }
            }
        }
        .padding(10)
        // Liquid Glass search island — mirrors the ChatView composer so
        // the two screens share one input-surface look. The system
        // material refracts the results / welcome content behind it.
        .glassCard(cornerRadius: 16)
        // Whole rounded surface is the tap target for focusing the field —
        // previously only the placeholder text caught taps which made the
        // hit area a thin sliver in a tall container. Buttons inside (Chat,
        // Extensive, send/stop) still consume their own taps first because
        // SwiftUI prioritises Button.action gestures above ancestor
        // `.onTapGesture`. Match the ChatView composer convention.
        .contentShape(Rectangle())
        .onTapGesture {
            isSearchFieldFocused = true
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Results View
    private var resultsView: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !isNoAIMode {
                    // AI Summary
                    if showingSummary {
                        summaryCard
                    }

                    // Toggle summary button
                    Button(action: { toggleSummary() }) {
                        HStack {
                            Image(systemName: showingSummary ? "eye.slash" : "sparkles")
                            Text(showingSummary ? L.t("search.summary.hide", language: settings.language) : L.t("search.summary.show", language: settings.language))
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                    }
                    .buttonStyle(.bordered)

                    Divider()
                }

                // Search results — held back until RAG match-scoring is
                // finished, then shown sorted by descending score (stable
                // on ties). In no-AI mode, scoring is skipped entirely, so
                // we surface the raw web-search ordering immediately.
                if shouldDisplaySearchCards {
                    ForEach(sortedSearchResults) { result in
                        SearchResultCard(
                            result: result,
                            matchingScore: matchingScoresByURL[result.url] ?? 0,
                            accessibilityLanguage: settings.language,
                            isWebSummariesEnabled: settings.isWebSummariesEnabled,
                            onRequestSummary: { tapped in
                                presentWebPageSummary(for: tapped)
                            }
                        )
                    }
                    .animation(.easeInOut(duration: 0.35), value: matchingScoresByURL)
                } else if !searchResults.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(L.t("search.results.scoring", language: settings.language))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
        .textSelection(.enabled)
    }

    // MARK: - Summary Card
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.accentColor)
                Text(L.t("search.summary.aiSummary", language: settings.language))
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    let textToCopy = aiService.summary.isEmpty ? firstGuessText : aiService.summary
                    guard !textToCopy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    PlatformClipboard.copyPlainText(textToCopy)
                    didCopySummary = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        didCopySummary = false
                    }
                } label: {
                    Image(systemName: didCopySummary ? "checkmark.circle.fill" : "doc.on.doc")
                        .foregroundColor(didCopySummary ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help(L.t("common.copy", language: settings.language))
                .disabled(aiService.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && firstGuessText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if aiService.isSummarizing || (settings.isFirstGuessEnabled && isGeneratingFirstGuess) {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            if settings.isFirstGuessEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L.t("search.summary.firstGuess", language: settings.language))
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    if isGeneratingFirstGuess && firstGuessText.isEmpty {
                        Text(L.t("search.loading.firstGuessGenerating", language: settings.language))
                            .foregroundColor(.secondary)
                            .italic()
                    } else if !firstGuessText.isEmpty {
                        ProgressiveLaTeXText(text: firstGuessText, isStreaming: isGeneratingFirstGuess)
                    } else {
                        Text(L.t("search.loading.firstGuessPlaceholder", language: settings.language))
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }

                Divider()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L.t("search.summary.webContextAnswer", language: settings.language))
                    .font(.subheadline)
                    .fontWeight(.semibold)

                if aiService.isSummarizing {
                    Text(L.t("search.summary.analyzingPages", language: settings.language))
                        .foregroundColor(.secondary)
                        .italic()
                }

                if !aiService.summary.isEmpty {
                    StreamingLaTeXText(text: aiService.summary, isStreaming: aiService.isSummarizing)

                    if !aiService.citations.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Divider()
                        Text(L.t("search.summary.topSources", language: settings.language))
                            .font(.subheadline)
                            .fontWeight(.semibold)

                         if let attributedCitations = try? AttributedString(
                            markdown: aiService.citations,
                            options: AttributedString.MarkdownParsingOptions(
                                interpretedSyntax: .inlineOnlyPreservingWhitespace
                            )
                        ) {
                            #if canImport(UIKit)
                            citationLinksView(from: aiService.citations)
                            #else
                            Text(attributedCitations)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .tint(.accentColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            #endif
                        } else {
                            Text(aiService.citations)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else if !aiService.isSummarizing {
                    Text(L.t("search.summary.waitingAnswer", language: settings.language))
                        .foregroundColor(.secondary)
                        .italic()
                }
            }

            // Generation time shown at the bottom-right once complete
            if !aiService.isSummarizing && !aiService.summary.isEmpty {
                HStack {
                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        if settings.isFirstGuessEnabled, let elapsed = firstGuessElapsedSeconds {
                            Text(L.t("search.summary.timeToFirst", language: settings.language, elapsed))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        if let elapsed = summaryElapsedSeconds {
                            Text(L.t("search.summary.generatedIn", language: settings.language, elapsed))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                    }
                }
            }
        }
        .padding()
        .subtleAccentCard(cornerRadius: 16)
    }

    // MARK: - Loading View
    private var loadingView: some View {
        ScrollView {
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text(L.t("search.loading.searching", language: settings.language))
                    .foregroundColor(.secondary)

                if settings.isFirstGuessEnabled && !isNoAIMode && (isGeneratingFirstGuess || !firstGuessText.isEmpty) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.t("search.summary.firstGuess", language: settings.language))
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        if isGeneratingFirstGuess && firstGuessText.isEmpty {
                            Text(L.t("search.loading.firstGuessGenerating", language: settings.language))
                                .foregroundColor(.secondary)
                                .italic()
                        } else if !firstGuessText.isEmpty {
                            ProgressiveLaTeXText(text: firstGuessText, isStreaming: isGeneratingFirstGuess)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .subtleAccentCard(cornerRadius: 12)
                }
            }
            .padding()
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Welcome View
    private var welcomeView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Smaller hero icon — modern LLM apps lead with prompts,
                // not visual filler. Keeps room for the example chips.
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 48, weight: .regular))
                    .foregroundStyle(.tint)
                    .padding(.top, 16)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text(L.t("search.welcome.title", language: settings.language))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)

                    Text(L.t("search.welcome.subtitle", language: settings.language))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Example-query chips. Tap to drop the prompt into the
                // search field; user can tweak it or hit Search.
                exampleQueryChips
                    .padding(.top, 8)
            }
            .padding()
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Three localized example queries that pre-fill the search field
    /// on tap. Picked to span the categories the first-guess prompt
    /// already understands (definition / time-sensitive / how-to).
    @ViewBuilder
    private var exampleQueryChips: some View {
        let examples: [String] = {
            switch settings.language {
            case .french:
                return [
                    "Qu'est-ce que la photosynthèse ?",
                    "Actualité des marchés financiers cette semaine",
                    "Comment configurer SwiftData étape par étape"
                ]
            case .spanish:
                return [
                    "¿Qué es la fotosíntesis?",
                    "Noticias del mercado financiero esta semana",
                    "Cómo configurar SwiftData paso a paso"
                ]
            default:
                return [
                    "What is photosynthesis?",
                    "Financial market news this week",
                    "How to set up SwiftData step by step"
                ]
            }
        }()

        VStack(spacing: 8) {
            ForEach(examples, id: \.self) { example in
                Button {
                    searchQuery = example
                    isSearchFieldFocused = true
                } label: {
                    HStack {
                        Image(systemName: "text.cursor")
                            .foregroundStyle(.tertiary)
                        Text(example)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .subtleTile(cornerRadius: 10)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(example)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Settings Panel
    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(L.t("search.settings.title", language: settings.language))
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }

            Divider()

            // Temperature
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L.t("search.settings.temperature", language: settings.language))
                        .font(.subheadline)
                    Spacer()
                    Text(String(format: "%.2f", settings.temperature))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Slider(value: $settingsStore.settings.temperature, in: AppSettings.temperatureRange, step: 0.05)
            }

            // First Guess Toggle
            Toggle(isOn: $settingsStore.settings.isFirstGuessEnabled) {
                Text(L.t("search.settings.firstGuessToggle", language: settings.language))
                    .font(.subheadline)
            }

            // Web Summaries Toggle
            Toggle(isOn: $settingsStore.settings.isWebSummariesEnabled) {
                Text(L.t("search.settings.webSummariesToggle", language: settings.language))
                    .font(.subheadline)
            }

            // Search Sources
            VStack(alignment: .leading, spacing: 8) {
                Text(L.t("search.settings.searchSources", language: settings.language))
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Toggle(isOn: $settingsStore.settings.useDuckDuckGo) {
                    Text("DuckDuckGo")
                        .font(.subheadline)
                }
                if settings.useDuckDuckGo {
                    HStack {
                        Text(L.t("search.settings.maxDDG", language: settings.language))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(settings.maxDuckDuckGoResults)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(settings.maxDuckDuckGoResults) },
                        set: { settings.maxDuckDuckGoResults = Int($0) }
                    ), in: Double(AppSettings.maxDuckDuckGoResultsRange.lowerBound)...Double(AppSettings.maxDuckDuckGoResultsRange.upperBound), step: 1)
                }

                Toggle(isOn: $settingsStore.settings.useWikipedia) {
                    Text("Wikipedia")
                        .font(.subheadline)
                }
                if settings.useWikipedia {
                    HStack {
                        Text(L.t("search.settings.maxWiki", language: settings.language))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(settings.maxWikipediaResults)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(settings.maxWikipediaResults) },
                        set: { settings.maxWikipediaResults = Int($0) }
                    ), in: Double(AppSettings.maxWikipediaResultsRange.lowerBound)...Double(AppSettings.maxWikipediaResultsRange.upperBound), step: 1)
                }

                if !settings.useDuckDuckGo && !settings.useWikipedia {
                    Text(L.t("search.settings.selectAtLeastOne", language: settings.language))
                    .font(.caption)
                    .foregroundColor(.red)
                }
            }

            // Max Response Tokens
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L.t("search.settings.maxResponseTokens", language: settings.language))
                        .font(.subheadline)
                    Spacer()
                    Text("\(settings.maxResponseTokens)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Slider(value: Binding(
                    get: { Double(settings.maxResponseTokens) },
                    set: {
                        settings.maxResponseTokens = Int($0)
                        settings.maxContextTokens = min(
                            settings.maxContextTokens,
                            AppSettings.maxAllowedContextTokens(forResponseTokens: settings.maxResponseTokens)
                        )
                    }
                ), in: Double(AppSettings.maxResponseTokensRange.lowerBound)...Double(AppSettings.maxResponseTokensRange.upperBound), step: 100)

                Text(L.t("search.settings.estimatedOutput", language: settings.language, Int64(estimatedMaxOutputCharacters), Int64(estimatedMaxOutputSentences)))
                .font(.caption)
                .foregroundColor(.secondary)
            }

            // Max Context Tokens
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L.t("search.settings.maxContextTokens", language: settings.language))
                        .font(.subheadline)
                    Spacer()
                    Text("\(effectiveContextTokens)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Slider(value: Binding(
                    get: { Double(effectiveContextTokens) },
                    set: { settings.maxContextTokens = Int($0) }
                ), in: Double(AppSettings.maxContextTokensRange.lowerBound)...Double(maxAllowedContextTokensForCurrentResponse), step: 50)

                Text(L.t("search.settings.estimatedContext", language: settings.language, Int64(estimatedMaxContextWords)))
                .font(.caption)
                .foregroundColor(.secondary)

                if effectiveContextTokens < settings.maxContextTokens {
                    Text(L.t("search.settings.contextCapped", language: settings.language))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
            }

            // Model Language
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L.t("search.settings.modelLanguage", language: settings.language))
                        .font(.subheadline)
                    Spacer()
                    Text(settings.language.rawValue)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Picker("Language", selection: $settingsStore.settings.language) {
                    ForEach(ModelLanguage.allCases, id: \.self) { lang in
                        Text(lang.rawValue).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Tool-calling toggle — mirrors the ChatView setting on the
            // same `settings.useToolCalling` field, so the two views stay
            // in sync. Enables the model to call searchContext / calculate
            // / currentDateTime / webSearch on demand instead of receiving
            // a pre-baked context block in the summary prompt.
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $settingsStore.settings.useToolCalling) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tool calling (experimental)")
                            .font(.subheadline)
                        Text("Lets the model query the web, search the corpus, calculate, and get the current date on demand instead of relying on the pre-baked search summary.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .glassCard(cornerRadius: 16)
    }

    // MARK: - Web Page Summary Overlay
    private var webPageSummaryOverlay: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissWebPageSummaryOverlay()
                }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button {
                        guard let urlString = selectedWebPageSummaryResult?.url else { return }
                        openWebPage(urlString)
                    } label: {
                        Label(
                            L.t("search.webPage.openPage", language: settings.language),
                            systemImage: "safari"
                        )
                        .font(.subheadline)
                        .fontWeight(.medium)
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()

                    Button {
                        dismissWebPageSummaryOverlay()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                if let result = selectedWebPageSummaryResult {
                    Text(result.title)
                        .font(.headline)
                        .lineLimit(2)
                }

                Divider()

                if isGeneratingWebPageSummary {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(L.t("search.webPage.generatingSummary", language: settings.language))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else if let webPageSummaryError,
                          !webPageSummaryError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(webPageSummaryError)
                        .font(.body)
                        .foregroundColor(.red)
                } else {
                    ScrollView {
                        Text(webPageSummaryText)
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding()
            .frame(maxWidth: 650, maxHeight: 460)
            .glassCard(cornerRadius: 16)
            .shadow(radius: 12)
            .padding()
        }
    }

    private func presentWebPageSummary(for result: SearchResult) {
        guard settings.isWebSummariesEnabled else { return }

        selectedWebPageSummaryResult = result
        webPageSummaryText = ""
        webPageSummaryError = nil
        isGeneratingWebPageSummary = true
        isShowingWebPageSummaryOverlay = true

        let requestID = UUID()
        activeWebPageSummaryRequestID = requestID

        Task {
            let summary = await aiService.summarizeWebPage(
                title: result.title,
                url: result.url,
                language: settings.language
            )
            guard activeWebPageSummaryRequestID == requestID else { return }
            isGeneratingWebPageSummary = false

            let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                webPageSummaryError = L.t("search.webPage.unavailable", language: settings.language)
            } else {
                webPageSummaryText = trimmed
            }
        }
    }

    private func dismissWebPageSummaryOverlay() {
        isShowingWebPageSummaryOverlay = false
        isGeneratingWebPageSummary = false
        selectedWebPageSummaryResult = nil
        webPageSummaryText = ""
        webPageSummaryError = nil
        activeWebPageSummaryRequestID = UUID()
    }

    private func openWebPage(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #elseif canImport(UIKit)
        openURLInSafari(url)
        #endif
    }

    #if canImport(UIKit)
    private func dismissKeyboard() {
        isSearchFieldFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func openURLInSafari(_ url: URL) {
        DispatchQueue.main.async {
            let safariViewController = SFSafariViewController(url: url)
            safariViewController.modalPresentationStyle = .fullScreen
            
            if let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                rootViewController.present(safariViewController, animated: true, completion: nil)
            } else {
                // Fallback to UIApplication.open if SFSafariViewController presentation fails
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            }
        }
    }
    #endif

    #if canImport(UIKit)
    @ViewBuilder
    private func citationLinksView(from text: String) -> some View {
        let links = extractCitationLinks(from: text)

        if links.isEmpty {
            Text(text)
                .font(.footnote)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(links.enumerated()), id: \.element.id) { index, link in
                    Button(action: {
                        openURLInSafari(link.url)
                    }) {
                        Text("\(index + 1). \(displayURL(link.url))")
                            .font(.footnote)
                            .foregroundColor(.accentColor)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func extractCitationLinks(from text: String) -> [CitationLink] {
        var extracted: [CitationLink] = []

        // First pass: prefer markdown links generated by citation formatter.
        if let markdownRegex = try? NSRegularExpression(pattern: #"\[[^\]]+\]\((https?://[^\s)]+)\)"#) {
            let nsRange = NSRange(text.startIndex..., in: text)
            let matches = markdownRegex.matches(in: text, range: nsRange)
            for match in matches {
                guard match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: text) else {
                    continue
                }
                let candidate = String(text[range])
                if let url = normalizedURL(from: candidate) {
                    extracted.append(CitationLink(url: url))
                }
            }
        }

        // Fallback: detect plain URLs when markdown parsing does not yield links.
        if extracted.isEmpty,
           let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let nsRange = NSRange(text.startIndex..., in: text)
            let matches = detector.matches(in: text, range: nsRange)
            for match in matches {
                guard let range = Range(match.range, in: text) else { continue }
                let candidate = String(text[range])
                if let url = normalizedURL(from: candidate) {
                    extracted.append(CitationLink(url: url))
                }
            }
        }

        // Keep first occurrence only to avoid duplicates when sources repeat.
        var seen = Set<String>()
        return extracted.filter { link in
            let key = link.url.absoluteString
            if seen.contains(key) {
                return false
            }
            seen.insert(key)
            return true
        }
    }

    private func normalizedURL(from candidate: String) -> URL? {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:)]}"))
        return URL(string: cleaned)
    }

    private func displayURL(_ url: URL) -> String {
        let host = url.host ?? url.absoluteString
        let path = url.path == "/" ? "" : url.path
        return host + path
    }

    private struct CitationLink: Identifiable {
        let id = UUID()
        let url: URL
    }
    #endif

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[SearchView] \(message)")
        #endif
    }

    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(L.t("search.results.empty.title", language: settings.language))
                .font(.headline)
            Text(L.t("search.results.empty.subtitle", language: settings.language))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions
    /// Executes a web search then optionally triggers summary generation.
    private func performSearch(maxScrapingChars: Int? = nil, noAIOnly: Bool = false, generationProfile: AIService.GenerationProfile = .fast) {
        #if canImport(UIKit)
        dismissKeyboard()
        #endif

        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }
        searchQuery = trimmedQuery
        hasAttemptedSearch = true

        let requestID = UUID()
        activeSearchRequestID = requestID

        let resultsCount = settings.maxSearchResults
        let scrapingChars = maxScrapingChars ?? defaultScrapingCharactersFromContextTokens

        // Clear previous results and state before starting new search
        searchResults = []
        matchingScoresByURL = [:]
        errorMessage = nil
        aiService.summary = ""
        aiService.citations = ""
        firstGuessText = ""
        firstGuessElapsedSeconds = nil
        isGeneratingFirstGuess = false
        showingSummary = !noAIOnly
        isNoAIMode = noAIOnly
        activeGenerationProfile = generationProfile
        summaryStartTime = nil
        summaryElapsedSeconds = nil
        #if DEBUG
        aiService.debugTimings = []
        aiService.debugNotes = []
        #endif

        if !noAIOnly && settings.isFirstGuessEnabled {
            isGeneratingFirstGuess = true
            Task {
                let firstGuessStart = Date()
                let firstGuess = await aiService.generateFirstGuess(
                    query: trimmedQuery,
                    language: settings.language,
                    maxTokens: min(settings.maxResponseTokens, Self.firstGuessTokenCap),
                    onPartialUpdate: { partial in
                        guard activeSearchRequestID == requestID else { return }
                        firstGuessText = partial
                    }
                )
                guard activeSearchRequestID == requestID else { return }
                guard settings.isFirstGuessEnabled else {
                    firstGuessText = ""
                    firstGuessElapsedSeconds = nil
                    isGeneratingFirstGuess = false
                    return
                }
                firstGuessText = firstGuess
                #if DEBUG
                debugLog(firstGuessText)
                #endif
                firstGuessElapsedSeconds = Date().timeIntervalSince(firstGuessStart)
                isGeneratingFirstGuess = false
            }
        }
        
        Task {
            do {
                // Tool-calling mode: skip the auto web search entirely.
                // The model owns the decision to query the web via its
                // `webSearch` tool. Otherwise we end up handing it both a
                // pre-fetched corpus AND the tools, and it just calls
                // `searchContext` over the corpus — `webSearch` never
                // fires. Result cards stay empty in this mode; the
                // summary card carries the model's tool-driven answer.
                if settings.useToolCalling && !noAIOnly {
                    guard activeSearchRequestID == requestID else { return }
                    searchResults = []
                    errorMessage = nil
                    showingSummary = true
                    await generateSummary(
                        maxScrapingResults: resultsCount,
                        maxScrapingChars: scrapingChars,
                        summaryResults: [],
                        generationProfile: generationProfile,
                        queries: nil
                    )
                    if activeSearchRequestID == requestID {
                        isGeneratingFirstGuess = false
                    }
                    return
                }

                let fetchedResults: [SearchResult]
                var allQueries: [String] = [trimmedQuery]

                if generationProfile == .deep && !noAIOnly {
                    let derivedQueries = await aiService.expandSearchQueries(
                        query: trimmedQuery,
                        language: settings.language,
                        maxDerivedQueries: Self.deepSearchDerivedQueryCount
                    )
                    allQueries = [trimmedQuery] + derivedQueries

                    #if DEBUG
                    debugLog(
                        "deep query expansion count: expectedDerived=\(Self.deepSearchDerivedQueryCount), obtainedDerived=\(derivedQueries.count), inputTotal=\(1 + derivedQueries.count)"
                    )
                    debugLog("deep query expansion: \(allQueries.joined(separator: " | "))")
                    #endif

                    fetchedResults = try await searchService.search(
                        queries: allQueries,
                        maxDuckDuckGoResultsPerQuery: settings.maxDuckDuckGoResults + Self.aiSummaryOverfetchResults,
                        maxWikipediaResultsPerQuery: settings.maxWikipediaResults,
                        mergedLimit: (settings.maxDuckDuckGoResults + settings.maxWikipediaResults + Self.aiSummaryOverfetchResults) * Self.deepSearchDerivedQueryCount,
                        language: settings.language,
                        useDuckDuckGo: settings.useDuckDuckGo,
                        useWikipedia: settings.useWikipedia
                    )
                } else {
                    fetchedResults = try await searchService.search(
                        query: trimmedQuery,
                        maxDuckDuckGoResults: settings.maxDuckDuckGoResults + Self.aiSummaryOverfetchResults,
                        maxWikipediaResults: settings.maxWikipediaResults,
                        language: settings.language,
                        useDuckDuckGo: settings.useDuckDuckGo,
                        useWikipedia: settings.useWikipedia
                    )
                }

                guard activeSearchRequestID == requestID else { return }
                searchResults = Array(fetchedResults.prefix(resultsCount))
                errorMessage = nil

                // Auto-generate summary only when AI mode is enabled
                if !noAIOnly && !searchResults.isEmpty {
                    showingSummary = true
                    await generateSummary(
                        maxScrapingResults: resultsCount,
                        maxScrapingChars: scrapingChars,
                        summaryResults: fetchedResults,
                        generationProfile: generationProfile,
                        queries: generationProfile == .deep ? allQueries : nil
                    )
                }
            } catch {
                guard activeSearchRequestID == requestID else { return }
                errorMessage = error.localizedDescription
                searchResults = []

                #if DEBUG
                debugLog("performSearch failed: \(error.localizedDescription)")
                #endif
            }

            if activeSearchRequestID == requestID {
                isGeneratingFirstGuess = false
            }
        }
    }

    /// Toggles summary visibility and lazily generates it when first opened.
    private func toggleSummary() {
        guard !isNoAIMode else { return }
        showingSummary.toggle()
        if showingSummary && aiService.summary.isEmpty {
            Task {
                await generateSummary(generationProfile: activeGenerationProfile)
            }
        }
    }

    /// Generates a synthesized answer from current search results.
    private func generateSummary(maxScrapingResults: Int? = nil, maxScrapingChars: Int? = nil, summaryResults: [SearchResult]? = nil, generationProfile: AIService.GenerationProfile? = nil, queries: [String]? = nil) async {
        summaryStartTime = Date()
        summaryElapsedSeconds = nil
        _ = await aiService.summarize(
            query: searchQuery,
            results: summaryResults ?? searchResults,
            maxScrapingResults: maxScrapingResults ?? settings.maxSearchResults,
            maxScrapingChars: maxScrapingChars ?? defaultScrapingCharactersFromContextTokens,
            temperature: settings.temperature,
            maxTokens: settings.maxResponseTokens,
            language: settings.language,
            profile: generationProfile ?? activeGenerationProfile,
            queries: queries,
            useToolCalling: settings.useToolCalling,
            maxDuckDuckGoResults: settings.maxDuckDuckGoResults,
            maxWikipediaResults: settings.maxWikipediaResults,
            useDuckDuckGo: settings.useDuckDuckGo,
            useWikipedia: settings.useWikipedia,
            onMatchingScores: { scores in
                Task { @MainActor in
                    // AIService chunks the full overfetched `fetchedResults`
                    // array — wider than the displayed `searchResults` (capped
                    // at `resultsCount`). Without filtering, the overfetched
                    // URLs eat percentage points that never reach a visible
                    // card, so badges add up to less than 100%. Restrict to
                    // displayed URLs and renormalize so the visible total is
                    // always 100%, with largest-remainder rounding so the
                    // integer badges sum to exactly 100% too.
                    matchingScoresByURL = Self.rebalanceScores(
                        scores,
                        displayedURLs: Set(searchResults.map(\.url))
                    )
                }
            }
        )

        #if DEBUG
        if !aiService.summary.isEmpty {
            debugLog("Generated summary: \(aiService.summary)")
        }
        for metric in aiService.debugTimings {
            debugLog("\(metric.name): \(String(format: "%.3f s", metric.seconds))")
        }
        for note in aiService.debugNotes {
            debugLog(note)
        }
        #endif

        if let start = summaryStartTime {
            summaryElapsedSeconds = Date().timeIntervalSince(start)
        }
    }

    /// Resets all search and summary state to the initial home screen.
    /// Cancels every in-flight search phase: rotates the request ID so
    /// pending RAG / first-guess / summary tasks stop publishing, clears
    /// the busy flags, and tears down the AIService streaming state so a
    /// fresh search starts cleanly.
    private func cancelCurrentSearch() {
        activeSearchRequestID = UUID()
        // Flip the published flags so the UI swaps the stop button back to
        // send immediately. The discarded tasks will see the request-ID
        // mismatch and exit without touching state.
        isGeneratingFirstGuess = false
        aiService.isSummarizing = false
        searchService.isSearching = false
        summaryStartTime = nil
    }

    private func goHome() {
        activeSearchRequestID = UUID()
        searchQuery = ""
        searchResults = []
        hasAttemptedSearch = false
        matchingScoresByURL = [:]
        showingSummary = false
        isNoAIMode = false
        firstGuessText = ""
        firstGuessElapsedSeconds = nil
        isGeneratingFirstGuess = false
        aiService.summary = ""
        aiService.citations = ""
        errorMessage = nil
        summaryStartTime = nil
        summaryElapsedSeconds = nil
        #if DEBUG
        aiService.debugTimings = []
        aiService.debugNotes = []
        #endif
    }

    private func consumeInitialQueryIfNeeded() {
        guard let initialQuery else { return }
        let trimmed = initialQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            onInitialQueryHandled?()
            return
        }
        if searchQuery == trimmed && (searchService.isSearching || !searchResults.isEmpty) {
            onInitialQueryHandled?()
            return
        }
        searchQuery = trimmed
        onInitialQueryHandled?()
        performSearch()
    }

    // MARK: - Drag-and-drop

    /// Persists dropped PDFs and images, then hands them to the host view
    /// (typically `ContentView`) via `onAttachmentsDropped`. That callback is
    /// responsible for switching to the Chat tab and seeding shared inputs.
    private func handleAttachmentDrop(_ providers: [NSItemProvider]) -> Bool {
        let accepted = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
            || $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
            || $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !accepted.isEmpty else { return false }

        for provider in accepted {
            if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                loadDroppedPDF(from: provider)
                continue
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                loadDroppedImage(from: provider)
                continue
            }
            loadDroppedFileURL(from: provider)
        }

        return true
    }

    private func loadDroppedPDF(from provider: NSItemProvider) {
        provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { url, _ in
            guard let url,
                  let persisted = DroppedPDFStore.persist(url, preferredFileName: provider.suggestedName) else {
                return
            }
            Task { @MainActor in
                onAttachmentsDropped?([persisted], [])
            }
        }
    }

    private func loadDroppedImage(from provider: NSItemProvider) {
        provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
            guard let url,
                  let persisted = DroppedImageStore.persist(
                    url,
                    preferredFileName: provider.suggestedName ?? url.lastPathComponent
                  ) else {
                return
            }
            Task { @MainActor in
                onAttachmentsDropped?([], [persisted])
            }
        }
    }

    private func loadDroppedFileURL(from provider: NSItemProvider) {
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let fileURL: URL?
            if let data = item as? Data {
                fileURL = NSURL(absoluteURLWithDataRepresentation: data, relativeTo: nil) as URL?
            } else if let url = item as? URL {
                fileURL = url
            } else if let nsURL = item as? NSURL {
                fileURL = nsURL as URL
            } else {
                fileURL = nil
            }
            guard let fileURL else { return }
            let ext = fileURL.pathExtension.lowercased()
            if ext == "pdf" {
                guard let persisted = DroppedPDFStore.persist(fileURL) else { return }
                Task { @MainActor in
                    onAttachmentsDropped?([persisted], [])
                }
            } else if Self.imageFileExtensions.contains(ext) {
                guard let persisted = DroppedImageStore.persist(fileURL) else { return }
                Task { @MainActor in
                    onAttachmentsDropped?([], [persisted])
                }
            }
        }
    }
}

// MARK: - Search Result Card
/// Displays one search result row with link, source host, and snippet preview.
struct SearchResultCard: View {
    let result: SearchResult
    /// RAG match-score percentage in `[0, 100]`. Defaults to 0 for cards
    /// whose source did not contribute to the selected context.
    var matchingScore: Double = 0
    /// UI language for accessibility-label localisation. Defaults to English.
    var accessibilityLanguage: ModelLanguage = .english
    var isWebSummariesEnabled: Bool = false
    var onRequestSummary: ((SearchResult) -> Void)? = nil

    #if canImport(UIKit)
    private func openURLInSafari(_ url: URL) {
        DispatchQueue.main.async {
            let safariViewController = SFSafariViewController(url: url)
            safariViewController.modalPresentationStyle = .fullScreen

            if let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                rootViewController.present(safariViewController, animated: true, completion: nil)
            } else {
                // Fallback to UIApplication.open if SFSafariViewController presentation fails
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            }
        }
    }
    #endif

    private func handleTitleTap() {
        if isWebSummariesEnabled, let onRequestSummary {
            onRequestSummary(result)
            return
        }
        guard let url = URL(string: result.url) else { return }
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #elseif canImport(UIKit)
        openURLInSafari(url)
        #endif
    }

    /// Renders one result card with title link, host, and snippet.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title and URL sit in the same horizontal band as the
            // top-right MatchScoreBadge overlay (34pt + 8pt padding ≈ 44pt),
            // so they reserve trailing space to keep text from running
            // under the ring.
            Button(action: handleTitleTap) {
                Text(result.title)
                    .font(.headline)
                    .foregroundColor(.accentColor)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 44)

            // URL
            Text(formatURL(result.url))
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.trailing, 44)

            // Snippet (starts below the badge band; full width OK)
            Text(result.snippet)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .subtleTile(cornerRadius: 12)
        .contentShape(Rectangle())
        .overlay(alignment: .topTrailing) {
            MatchScoreBadge(percent: matchingScore, language: accessibilityLanguage)
                .padding(8)
        }
        .onTapGesture {
            handleTitleTap()
        }
    }

    /// Extracts a readable host from a URL string.
    private func formatURL(_ urlString: String) -> String {
        guard let url = URL(string: urlString),
              let host = url.host else {
            return urlString
        }
        return host
    }
}

// MARK: - Feature Row
/// Displays one feature line in the search welcome screen.
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    /// Renders one welcome-screen feature row with icon and text.
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    SearchView(chatService: ChatService())
        .frame(width: 800, height: 600)
}
