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
#if canImport(WebKit)
import WebKit
#endif

/// Main search experience that fetches web results and generates AI summaries.
struct SearchView: View {
    private static let aiSummaryOverfetchResults = 3
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
    @ObservedObject var aiService = AIService()

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
        guard !filtered.isEmpty else { return [:] }
        let total = filtered.values.reduce(0, +)
        guard total > 0 else {
            return filtered.mapValues { _ in 0.0 }
        }

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

    // Generation timer
    @State private var summaryStartTime: Date? = nil
    @State private var summaryElapsedSeconds: Double? = nil
    @State private var activeSearchRequestID = UUID()
    @State private var didCopySummary = false

    // Per-result web page reader view and summaries
    @State private var isShowingWebPageSummaryOverlay = false
    @State private var selectedWebPageSummaryResult: SearchResult?
    @State private var webPageSummaryText: String = ""
    @State private var webPageReaderHTML: String = ""
    @State private var webPageReaderBaseURL: URL? = nil
    @State private var webPageContentHeight: CGFloat = 800
    @State private var webPageMarkdownText: String = ""
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
    
    private var maxAllowedContextTokensForCurrentResponse: Int {
        AppSettings.maxAllowedContextTokens(forResponseTokens: settings.maxResponseTokens, totalBudget: settings.totalTokensBudget)
    }

    private var effectiveContextTokens: Int {
        min(settings.maxContextTokens, maxAllowedContextTokensForCurrentResponse)
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
            guard hasAttemptedSearch else { return }
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
                ZStack {
                    SourceToggleButtons(settingsStore: settingsStore)

                    HStack(spacing: 4) {
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

            // Action row: Chat left-aligned, send arrow right.
            HStack(spacing: 8) {
                Button(action: handleChatButtonTap) {
                    Label(chatButtonTitle, systemImage: "bubble.left.and.bubble.right")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isChatButtonDisabled)
                .accessibilityLabel(chatButtonTitle)

                Spacer()

                // Swap send → stop while any phase is running (web search,
                // RAG scoring, AI summary). Tapping rotates
                // `activeSearchRequestID`, which every in-flight task
                // checks before publishing — same mechanism as `goHome()`.
                let isBusy = searchService.isSearching || aiService.isSummarizing
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
                    Button(action: { performSearch() }) {
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
                            isReaderViewAndSummaryEnabled: settings.isReaderViewAndSummaryEnabled,
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

                if FoundationModelAvailability.check().isAvailable {
                    Button {
                        let textToCopy = aiService.summary
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
                    .disabled(aiService.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if aiService.isSummarizing {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            if case .unavailable(let reason) = FoundationModelAvailability.check() {
                ModelAvailabilityNotice(reason: reason, language: settings.language, drawBackground: false)
            } else {
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
                            if let elapsed = summaryElapsedSeconds {
                                Text(L.t("search.summary.generatedIn", language: settings.language, elapsed))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

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
            .disabled(!FoundationModelAvailability.check().isAvailable)
            .opacity(!FoundationModelAvailability.check().isAvailable ? 0.5 : 1.0)

            // Reader View and Summary Toggle
            VStack(alignment: .leading, spacing: 4) {
                let isModelAvailable = FoundationModelAvailability.check().isAvailable
                Toggle(isOn: $settingsStore.settings.isReaderViewAndSummaryEnabled) {
                    Text(L.t("search.settings.readerViewAndSummaryToggle", language: settings.language))
                        .font(.subheadline)
                }
                .disabled(!isModelAvailable)
                .opacity(!isModelAvailable ? 0.5 : 1.0)

                if !isModelAvailable {
                    Text(FoundationModelAvailability.appleIntelligenceRequiredNotice(language: settings.language))
                        .font(.caption2)
                        .foregroundColor(.red)
                }
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
                    HStack(spacing: 4) {
                        Image(systemName: "wifi.slash")
                        Text(L.t("search.settings.offlineMode", language: settings.language))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            // Token Budget (Unified Input/Output Slider)
            TokenBudgetSliderView(
                settings: $settingsStore.settings,
                language: settings.language
            )

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

        }
        .padding()
        .glassCard(cornerRadius: 16)
    }

    // MARK: - Web Page Reader View and Summary Overlay
    private var webPageSummaryOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissWebPageSummaryOverlay()
                }

            VStack(alignment: .leading, spacing: 14) {
                // Header bar
                HStack(spacing: 12) {
                    if let result = selectedWebPageSummaryResult {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.title)
                                .font(.headline)
                                .lineLimit(1)
                            Text(result.url)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

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

                    Button {
                        dismissWebPageSummaryOverlay()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                    .keyboardShortcut(.escape, modifiers: [])
                    .help(L.t("common.close", language: settings.language))
                }

                Divider()

                // Unified vertical scroll field containing both the native AI Summary and the HTML WebKit view
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Native AI Summary on top of HTML webkit with fixed height (~10 lines) and internal scroll field
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(L.t("search.webPage.readerSummary", language: settings.language), systemImage: "sparkles")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.accentColor)

                                if isGeneratingWebPageSummary {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                }
                                Spacer()
                            }

                            ScrollView {
                                Group {
                                    if isGeneratingWebPageSummary && webPageSummaryText.isEmpty {
                                        Text(L.t("search.webPage.generatingSummary", language: settings.language))
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .italic()
                                    } else if let webPageSummaryError, webPageSummaryText.isEmpty {
                                        Text(webPageSummaryError)
                                            .font(.subheadline)
                                            .foregroundColor(.red)
                                    } else if !webPageSummaryText.isEmpty {
                                        StreamingLaTeXText(text: webPageSummaryText, isStreaming: isGeneratingWebPageSummary)
                                            .font(.body)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(height: 185)
                        }
                        .padding(14)
                        .subtleAccentCard(cornerRadius: 12)

                        // Reader view: Rendered Reeeed HTML content (scrolls together with summary above it)
                        if !webPageReaderHTML.isEmpty {
                            ReaderHTMLWebView(
                                html: webPageReaderHTML,
                                baseURL: webPageReaderBaseURL,
                                contentHeight: $webPageContentHeight,
                                onLinkClicked: { clickedURL in
                                    openWebPage(clickedURL.absoluteString)
                                }
                            )
                            .frame(height: max(400, webPageContentHeight))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        } else if webPageMarkdownText.isEmpty && isGeneratingWebPageSummary {
                            ProgressView()
                                .padding(.vertical, 30)
                                .frame(maxWidth: .infinity)
                        } else if !webPageMarkdownText.isEmpty {
                            MarkdownContentView(markdown: webPageMarkdownText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else if let snippet = selectedWebPageSummaryResult?.snippet, !snippet.isEmpty {
                            Text(snippet)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassCard(cornerRadius: 16)
            .shadow(color: Color.black.opacity(0.3), radius: 24, x: 0, y: 8)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
    }

    private func presentWebPageSummary(for result: SearchResult) {
        guard settings.isReaderViewAndSummaryEnabled else { return }

        selectedWebPageSummaryResult = result
        webPageSummaryText = ""
        webPageReaderHTML = ""
        webPageReaderBaseURL = URL(string: result.url)
        webPageContentHeight = 800
        webPageMarkdownText = ""
        webPageSummaryError = nil
        isGeneratingWebPageSummary = true
        isShowingWebPageSummaryOverlay = true

        let requestID = UUID()
        activeWebPageSummaryRequestID = requestID

        Task {
            var preExtractedPlainText: String? = nil
            if let targetURL = URL(string: result.url) {
                if let readerContent = try? await WebScrapingService().extractReaderHTML(from: targetURL) {
                    guard activeWebPageSummaryRequestID == requestID else { return }
                    webPageReaderHTML = readerContent.styledHTML
                    webPageReaderBaseURL = readerContent.baseURL
                    preExtractedPlainText = readerContent.plainText
                }
            }

            let (summary, markdown) = await aiService.summarizeWebPage(
                title: result.title,
                url: result.url,
                language: settings.language,
                preExtractedContent: preExtractedPlainText,
                onPartialUpdate: { partial in
                    guard activeWebPageSummaryRequestID == requestID else { return }
                    webPageSummaryText = partial
                }
            )
            guard activeWebPageSummaryRequestID == requestID else { return }
            isGeneratingWebPageSummary = false

            if webPageReaderHTML.isEmpty && !markdown.isEmpty {
                webPageMarkdownText = markdown
            }
            let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty && webPageSummaryText.isEmpty {
                webPageSummaryError = L.t("search.webPage.unavailable", language: settings.language)
            } else if !trimmed.isEmpty {
                webPageSummaryText = trimmed
            }
        }
    }

    private func dismissWebPageSummaryOverlay() {
        isShowingWebPageSummaryOverlay = false
        isGeneratingWebPageSummary = false
        selectedWebPageSummaryResult = nil
        webPageSummaryText = ""
        webPageReaderHTML = ""
        webPageReaderBaseURL = nil
        webPageContentHeight = 800
        webPageMarkdownText = ""
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
    private func performSearch(maxScrapingChars: Int? = nil, noAIOnly: Bool = false) {
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
        showingSummary = !noAIOnly
        isNoAIMode = noAIOnly
        summaryStartTime = nil
        summaryElapsedSeconds = nil
        searchService.isSearching = true
        #if DEBUG
        aiService.debugTimings = []
        aiService.debugNotes = []
        #endif

        let isModelAvailable = FoundationModelAvailability.check().isAvailable

        Task {
            do {
                let fetchedResults: [SearchResult]
                if !noAIOnly && isModelAvailable {
                    let generated = await SearchSourcesTool.generateQueries(
                        for: trimmedQuery,
                        language: settings.language,
                        useDuckDuckGo: settings.useDuckDuckGo,
                        useWikipedia: settings.useWikipedia
                    )

                    fetchedResults = try await searchService.search(
                        webQueries: generated.webQueries,
                        wikiQueries: generated.wikiQueries,
                        maxDuckDuckGoResults: settings.maxDuckDuckGoResults + Self.aiSummaryOverfetchResults,
                        maxWikipediaResults: settings.maxWikipediaResults,
                        mergedLimit: resultsCount + Self.aiSummaryOverfetchResults,
                        language: settings.language,
                        useDuckDuckGo: settings.useDuckDuckGo,
                        useWikipedia: settings.useWikipedia,
                        userQuery: trimmedQuery
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

                guard activeSearchRequestID == requestID else {
                    searchService.isSearching = false
                    return
                }
                searchResults = Array(fetchedResults.prefix(resultsCount))
                errorMessage = nil

                // Auto-generate summary only when AI mode is enabled
                if !noAIOnly && isModelAvailable {
                    showingSummary = true
                    if searchResults.isEmpty {
                        aiService.isSummarizing = true
                    }
                    searchService.isSearching = false
                    await generateSummary(
                        maxScrapingResults: resultsCount,
                        maxScrapingChars: scrapingChars,
                        summaryResults: fetchedResults
                    )
                } else {
                    searchService.isSearching = false
                }
            } catch {
                guard activeSearchRequestID == requestID else {
                    searchService.isSearching = false
                    return
                }
                searchService.isSearching = false
                errorMessage = error.localizedDescription
                searchResults = []

                #if DEBUG
                debugLog("performSearch failed: \(error.localizedDescription)")
                #endif

                if !noAIOnly && isModelAvailable {
                    showingSummary = true
                    await generateSummary(
                        maxScrapingResults: resultsCount,
                        maxScrapingChars: scrapingChars,
                        summaryResults: []
                    )
                }
            }
        }
    }

    /// Toggles summary visibility and lazily generates it when first opened.
    private func toggleSummary() {
        guard !isNoAIMode else { return }
        showingSummary.toggle()
        if showingSummary && aiService.summary.isEmpty {
            Task {
                await generateSummary(summaryResults: searchResults)
            }
        }
    }

    /// Generates a synthesized answer from current search results.
    private func generateSummary(maxScrapingResults: Int? = nil, maxScrapingChars: Int? = nil, summaryResults: [SearchResult]? = nil) async {
        summaryStartTime = Date()
        summaryElapsedSeconds = nil
        let isModelAvailable = FoundationModelAvailability.check().isAvailable
        _ = await aiService.summarize(
            query: searchQuery,
            results: summaryResults ?? searchResults,
            maxScrapingResults: maxScrapingResults ?? settings.maxSearchResults,
            maxScrapingChars: maxScrapingChars ?? defaultScrapingCharactersFromContextTokens,
            temperature: settings.temperature,
            maxTokens: settings.maxResponseTokens,
            language: settings.language,
            maxDuckDuckGoResults: settings.maxDuckDuckGoResults,
            maxWikipediaResults: settings.maxWikipediaResults,
            useDuckDuckGo: settings.useDuckDuckGo,
            useWikipedia: settings.useWikipedia,
            generateAnswer: isModelAvailable,
            onSummaryPartialUpdate: { _ in
                if summaryElapsedSeconds == nil, let start = summaryStartTime {
                    summaryElapsedSeconds = Date().timeIntervalSince(start)
                }
            },
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
            },
            onValidSourcesUpdated: { validSources in
                Task { @MainActor in
                    searchResults = Array(validSources.prefix(settings.maxSearchResults))
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

        if let answerElapsed = aiService.lastAnswerElapsedSeconds {
            summaryElapsedSeconds = answerElapsed
        } else if let start = summaryStartTime, summaryElapsedSeconds == nil {
            summaryElapsedSeconds = Date().timeIntervalSince(start)
        }
    }

    /// Resets all search and summary state to the initial home screen.
    /// Cancels every in-flight search phase: rotates the request ID so
    /// pending RAG / summary tasks stop publishing, clears
    /// the busy flags, and tears down the AIService streaming state so a
    /// fresh search starts cleanly.
    private func cancelCurrentSearch() {
        activeSearchRequestID = UUID()
        // Flip the published flags so the UI swaps the stop button back to
        // send immediately. The discarded tasks will see the request-ID
        // mismatch and exit without touching state.
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
        aiService.summary = ""
        aiService.citations = ""
        errorMessage = nil
        summaryStartTime = nil
        summaryElapsedSeconds = nil
        searchService.isSearching = false
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
    var isReaderViewAndSummaryEnabled: Bool = false
    var isWebSummariesEnabled: Bool {
        get { isReaderViewAndSummaryEnabled }
        set { isReaderViewAndSummaryEnabled = newValue }
    }
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
        if isReaderViewAndSummaryEnabled, let onRequestSummary {
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

// MARK: - Reader HTML WebView
/// Renders Reeeed's styled Reader HTML inside a WKWebView, dynamically sizing to document height
/// and forwarding scroll events to the enclosing unified SwiftUI ScrollView.
struct ReaderHTMLWebView: View {
    let html: String
    let baseURL: URL?
    @Binding var contentHeight: CGFloat
    var onLinkClicked: ((URL) -> Void)? = nil

    var body: some View {
        ReaderHTMLWebViewRepresentable(
            html: html,
            baseURL: baseURL,
            contentHeight: $contentHeight,
            onLinkClicked: onLinkClicked
        )
    }
}

#if os(macOS)
private final class NonScrollingWKWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        // Forward trackpad and mouse scroll wheel events directly to the enclosing SwiftUI ScrollView
        nextResponder?.scrollWheel(with: event)
    }
}

private struct ReaderHTMLWebViewRepresentable: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    @Binding var contentHeight: CGFloat
    let onLinkClicked: ((URL) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(contentHeight: $contentHeight, onLinkClicked: onLinkClicked)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "heightChange")
        config.userContentController = userContentController

        let webView = NonScrollingWKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.loadIfNeeded(html: html, baseURL: baseURL, into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onLinkClicked = onLinkClicked
        context.coordinator.loadIfNeeded(html: html, baseURL: baseURL, into: webView)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "heightChange")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding var contentHeight: CGFloat
        var onLinkClicked: ((URL) -> Void)?
        private var lastLoadedHTML: String = ""
        private var lastLoadedBaseURL: URL? = nil

        init(contentHeight: Binding<CGFloat>, onLinkClicked: ((URL) -> Void)?) {
            self._contentHeight = contentHeight
            self.onLinkClicked = onLinkClicked
        }

        func loadIfNeeded(html: String, baseURL: URL?, into webView: WKWebView) {
            guard html != lastLoadedHTML || baseURL != lastLoadedBaseURL else { return }
            lastLoadedHTML = html
            lastLoadedBaseURL = baseURL
            let htmlWithMathJax = WebScrapingService.injectMathJax(into: html)
            webView.loadHTMLString(htmlWithMathJax, baseURL: baseURL)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "heightChange", let height = message.body as? CGFloat, height > 100 {
                DispatchQueue.main.async {
                    if abs(self.contentHeight - height) > 5 {
                        self.contentHeight = height
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let script = """
            (function() {
                function report() {
                    var h = Math.max(document.body.scrollHeight, document.documentElement.scrollHeight);
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.heightChange) {
                        window.webkit.messageHandlers.heightChange.postMessage(h);
                    }
                }
                report();
                if (window.ResizeObserver) {
                    new ResizeObserver(report).observe(document.body);
                }
                if (window.MathJax && window.MathJax.typesetPromise) {
                    window.MathJax.typesetPromise().then(report);
                }
                window.addEventListener('load', report);
                setTimeout(report, 300);
                setTimeout(report, 1000);
            })();
            """
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                onLinkClicked?(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
#elseif canImport(UIKit)
private struct ReaderHTMLWebViewRepresentable: UIViewRepresentable {
    let html: String
    let baseURL: URL?
    @Binding var contentHeight: CGFloat
    let onLinkClicked: ((URL) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(contentHeight: $contentHeight, onLinkClicked: onLinkClicked)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "heightChange")
        config.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        context.coordinator.loadIfNeeded(html: html, baseURL: baseURL, into: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onLinkClicked = onLinkClicked
        context.coordinator.loadIfNeeded(html: html, baseURL: baseURL, into: webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "heightChange")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding var contentHeight: CGFloat
        var onLinkClicked: ((URL) -> Void)?
        private var lastLoadedHTML: String = ""
        private var lastLoadedBaseURL: URL? = nil

        init(contentHeight: Binding<CGFloat>, onLinkClicked: ((URL) -> Void)?) {
            self._contentHeight = contentHeight
            self.onLinkClicked = onLinkClicked
        }

        func loadIfNeeded(html: String, baseURL: URL?, into webView: WKWebView) {
            guard html != lastLoadedHTML || baseURL != lastLoadedBaseURL else { return }
            lastLoadedHTML = html
            lastLoadedBaseURL = baseURL
            let htmlWithMathJax = WebScrapingService.injectMathJax(into: html)
            webView.loadHTMLString(htmlWithMathJax, baseURL: baseURL)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "heightChange", let height = message.body as? CGFloat, height > 100 {
                DispatchQueue.main.async {
                    if abs(self.contentHeight - height) > 5 {
                        self.contentHeight = height
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let script = """
            (function() {
                function report() {
                    var h = Math.max(document.body.scrollHeight, document.documentElement.scrollHeight);
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.heightChange) {
                        window.webkit.messageHandlers.heightChange.postMessage(h);
                    }
                }
                report();
                if (window.ResizeObserver) {
                    new ResizeObserver(report).observe(document.body);
                }
                if (window.MathJax && window.MathJax.typesetPromise) {
                    window.MathJax.typesetPromise().then(report);
                }
                window.addEventListener('load', report);
                setTimeout(report, 300);
                setTimeout(report, 1000);
            })();
            """
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                onLinkClicked?(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
#endif

#Preview {
    SearchView(chatService: ChatService())
        .frame(width: 800, height: 600)
}
