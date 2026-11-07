//
//  DynamicSessionCoordinator.swift
//  SilicIA
//
//  Manages a persistent, prewarmed LanguageModelSession configured with
//  DynamicInstructions and LanguageModelSession.DynamicProfile so the
//  on-device Foundation Model stays loaded in memory from app startup and
//  seamlessly adapts its instructions, tools, and reasoningLevel when
//  changing settings or switching between Search and Chat views.
//

import Foundation
import FoundationModels
import os

/// Operational mode determining which instructions, tools, and profile
/// configuration the dynamic session evaluates.
nonisolated enum DynamicSessionMode: String, Sendable, Equatable {
    case searchSummary
    case chat
    case chatFallback
    case webPageSummary
    case searchQueryGeneration
}

/// Thread-safe state container read by `SilicIADynamicInstructions` and
/// `SilicIADynamicProfile` whenever `FoundationModels` re-evaluates their
/// `body` before a model request or prewarm call.
nonisolated final class DynamicSessionStateStore: @unchecked Sendable {

    struct Snapshot: Sendable {
        var mode: DynamicSessionMode
        var instructionsText: String
        var tools: [any Tool]
        var reasoningLevel: ContextOptions.ReasoningLevel
        var temperature: Double
        var maximumResponseTokens: Int
    }

    private let lock: OSAllocatedUnfairLock<Snapshot>

    init(initial: Snapshot) {
        self.lock = OSAllocatedUnfairLock(initialState: initial)
    }

    var current: Snapshot {
        lock.withLock { $0 }
    }

    func update(_ snapshot: Snapshot) {
        lock.withLock { $0 = snapshot }
    }
}

/// Declarative dynamic instructions that re-evaluate before every model
/// request, injecting the active system instructions and tool kit for the
/// current app state (Search vs. Chat, language, token profile, and sources).
nonisolated struct SilicIADynamicInstructions: DynamicInstructions {
    let stateStore: DynamicSessionStateStore

    var body: some DynamicInstructions {
        let snapshot = stateStore.current
        Instructions(snapshot.instructionsText)
        snapshot.tools
    }
}

/// Declarative dynamic profile that binds `SilicIADynamicInstructions` to
/// session-level modifiers including `.reasoningLevel(_:)` (`.light` for
/// `.concise`, `.moderate` for `.standard`, `.deep` for `.detailed`),
/// `.temperature(_:)`, and `.maximumResponseTokens(_:)`.
nonisolated struct SilicIADynamicProfile: LanguageModelSession.DynamicProfile {
    let stateStore: DynamicSessionStateStore

    var body: some LanguageModelSession.DynamicProfile {
        let snapshot = stateStore.current
        let effectiveReasoningLevel = Self.effectiveReasoningLevel(
            requested: snapshot.reasoningLevel
        )
        Profile {
            SilicIADynamicInstructions(stateStore: stateStore)
        }
        .reasoningLevel(effectiveReasoningLevel)
        .temperature(snapshot.temperature)
        .maximumResponseTokens(snapshot.maximumResponseTokens)
    }

    /// Resolves the requested reasoning level against the active model's
    /// declared capabilities. If the on-device model (`SystemLanguageModel.default`)
    /// does not advertise `.reasoning`, passing a non-nil reasoning level causes
    /// `FoundationModels` to throw `LanguageModelError.unsupportedCapability`
    /// on all requests.
    static func effectiveReasoningLevel(
        requested: ContextOptions.ReasoningLevel,
        capabilities: LanguageModelCapabilities = SystemLanguageModel.default.capabilities
    ) -> ContextOptions.ReasoningLevel? {
        capabilities.contains(.reasoning) ? requested : nil
    }
}

/// Coordinates a persistent, prewarmed `LanguageModelSession(profile:)` shared
/// across Search Assist and Chat. Keeps the model warm in memory from launch
/// and updates the active profile whenever the user switches views or changes
/// settings.
@MainActor
final class DynamicSessionCoordinator {
    static let shared = DynamicSessionCoordinator()

    private struct PrewarmKey: Equatable {
        var mode: DynamicSessionMode
        var instructionsText: String
        var toolNames: [String]
        var reasoningLevel: ContextOptions.ReasoningLevel
        var temperature: Double
        var maximumResponseTokens: Int

        init(snapshot: DynamicSessionStateStore.Snapshot) {
            self.mode = snapshot.mode
            self.instructionsText = snapshot.instructionsText
            self.toolNames = snapshot.tools.map { $0.name }
            self.reasoningLevel = snapshot.reasoningLevel
            self.temperature = snapshot.temperature
            self.maximumResponseTokens = snapshot.maximumResponseTokens
        }
    }

    private let stateStore: DynamicSessionStateStore
    private var sharedSession: LanguageModelSession?
    private(set) var activeViewMode: DynamicSessionMode = .searchSummary
    private(set) var prewarmCount: Int = 0
    private var lastPrewarmedKey: PrewarmKey?
    private var settingsDebounceTask: Task<Void, Never>?

    // Lightweight service instances used exclusively to assemble the default
    // tool schemas when prewarming the Chat profile on tab switch / settings change.
    private let prewarmWebSearchService = WebSearchService()
    private let prewarmWebScraper = WebScrapingService()
    private let prewarmRAGContextService = RAGContextService()

    var currentSnapshot: DynamicSessionStateStore.Snapshot {
        stateStore.current
    }

    init() {
        let initialSettings = AppSettings.load()
        let initialSnapshot = Self.makeDefaultSnapshot(
            for: .searchSummary,
            settings: initialSettings,
            webSearchService: prewarmWebSearchService,
            webScraper: prewarmWebScraper,
            ragContextService: prewarmRAGContextService
        )
        self.stateStore = DynamicSessionStateStore(initial: initialSnapshot)
    }

    /// Switches the coordinator's active view mode (`.searchSummary` or `.chat`),
    /// updates the dynamic instructions/profile snapshot for `settings`, and
    /// optionally prewarms the shared session so the model is ready before the
    /// user submits a query.
    func switchActiveViewMode(
        _ mode: DynamicSessionMode,
        settings: AppSettings,
        prewarm: Bool = true
    ) {
        activeViewMode = mode
        let snapshot = Self.makeDefaultSnapshot(
            for: mode,
            settings: settings,
            webSearchService: prewarmWebSearchService,
            webScraper: prewarmWebScraper,
            ragContextService: prewarmRAGContextService
        )

        if sharedSession?.isResponding != true {
            stateStore.update(snapshot)
        }

        guard prewarm, FoundationModelAvailability.check().isAvailable else { return }
        prewarmSharedSessionIfIdle(with: snapshot)
    }

    /// Called by `AppSettingsStore` when any setting changes. Immediately
    /// refreshes the snapshot if idle and schedules a debounced `prewarm()`
    /// so slider drags do not trigger redundant prewarm passes.
    func handleSettingsChanged(_ settings: AppSettings) {
        let mode = activeViewMode
        let snapshot = Self.makeDefaultSnapshot(
            for: mode,
            settings: settings,
            webSearchService: prewarmWebSearchService,
            webScraper: prewarmWebScraper,
            ragContextService: prewarmRAGContextService
        )

        if sharedSession?.isResponding != true {
            stateStore.update(snapshot)
        }

        settingsDebounceTask?.cancel()
        settingsDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self else { return }
            guard FoundationModelAvailability.check().isAvailable else { return }
            self.prewarmSharedSessionIfIdle(with: snapshot)
        }
    }

    /// Re-prewarms the active view mode's session if idle.
    /// Useful after an ephemeral subtask (such as query generation) completes,
    /// so the model session is hot while network I/O proceeds.
    func reprewarmActiveSession() {
        guard sharedSession?.isResponding != true else { return }
        guard FoundationModelAvailability.check().isAvailable else { return }
        let session = ensureSharedSession()
        if !session.transcript.history.isEmpty {
            session.transcript.history = []
        }
        session.prewarm()
        #if DEBUG
        print("[DynamicSessionCoordinator] Re-prewarmed active session during network I/O")
        #endif
    }

    /// Configures and returns a `LanguageModelSession` for an imminent request.
    ///
    /// - Maps `maxResponseTokens` to `ContextOptions.ReasoningLevel` via
    ///   `TokenBudgeting.reasoningLevel(forResponseTokens:)` unless
    ///   `reasoningLevelOverride` is explicitly provided.
    /// - Reuses the warm shared `LanguageModelSession` (after clearing prior
    ///   turn entries from `session.transcript.history`) when idle.
    /// - Falls back to an isolated `LanguageModelSession(profile:)` if the
    ///   shared session is currently busy (`isResponding == true`) to prevent
    ///   `LanguageModelSession.Error.concurrentRequests`.
    func acquireSession(
        mode: DynamicSessionMode,
        instructions: String,
        tools: [any Tool] = [],
        temperature: Double,
        maxResponseTokens: Int,
        effectiveMaxOutputTokens: Int? = nil,
        reasoningLevelOverride: ContextOptions.ReasoningLevel? = nil
    ) -> LanguageModelSession {
        let reasoningLevel = reasoningLevelOverride
            ?? TokenBudgeting.reasoningLevel(forResponseTokens: maxResponseTokens)
        let resolvedMaxTokens = max(1, effectiveMaxOutputTokens ?? maxResponseTokens)

        let snapshot = DynamicSessionStateStore.Snapshot(
            mode: mode,
            instructionsText: instructions,
            tools: tools,
            reasoningLevel: reasoningLevel,
            temperature: temperature,
            maximumResponseTokens: resolvedMaxTokens
        )

        let session = ensureSharedSession()
        // Ephemeral subtasks (like query generation or webpage summary) must not
        // clobber or invalidate the persistent session prewarmed for the active view.
        if mode == activeViewMode && !session.isResponding {
            let key = PrewarmKey(snapshot: snapshot)
            if lastPrewarmedKey != key {
                stateStore.update(snapshot)
                lastPrewarmedKey = key
            }
            if !session.transcript.history.isEmpty {
                session.transcript.history = []
            }
            return session
        }

        let isolatedStore = DynamicSessionStateStore(initial: snapshot)
        return LanguageModelSession(profile: SilicIADynamicProfile(stateStore: isolatedStore))
    }

    private func ensureSharedSession() -> LanguageModelSession {
        if let existing = sharedSession {
            return existing
        }
        let created = LanguageModelSession(profile: SilicIADynamicProfile(stateStore: stateStore))
        sharedSession = created
        return created
    }

    private func prewarmSharedSessionIfIdle(with snapshot: DynamicSessionStateStore.Snapshot) {
        let key = PrewarmKey(snapshot: snapshot)
        if lastPrewarmedKey == key {
            #if DEBUG
            print("[DynamicSessionCoordinator] Skipping redundant prewarm (key matches last prewarm)")
            #endif
            return
        }

        let session = ensureSharedSession()
        guard !session.isResponding else { return }
        stateStore.update(snapshot)
        session.transcript.history = []
        session.prewarm()
        lastPrewarmedKey = key
        prewarmCount += 1
        #if DEBUG
        print("[DynamicSessionCoordinator] Prewarmed session (mode=\(snapshot.mode.rawValue), reasoning=\(snapshot.reasoningLevel), maxTokens=\(snapshot.maximumResponseTokens))")
        #endif
    }

    private static func makeDefaultSnapshot(
        for mode: DynamicSessionMode,
        settings: AppSettings,
        webSearchService: WebSearchService,
        webScraper: WebScrapingService,
        ragContextService: RAGContextService
    ) -> DynamicSessionStateStore.Snapshot {
        let reasoningLevel = TokenBudgeting.reasoningLevel(forResponseTokens: settings.maxResponseTokens)
        let effectiveMaxTokens = TokenBudgeting.clampedToolResponseTokens(
            requestedMaxTokens: settings.maxResponseTokens
        )

        switch mode {
        case .searchSummary, .webPageSummary, .searchQueryGeneration:
            let isConcise = TokenBudgeting.outputProfile(forResponseTokens: settings.maxResponseTokens).kind == .concise
            let allowTools = !isConcise
            let instructions = AIService.buildSearchInstructions(
                for: settings.language,
                maxOutputTokens: settings.maxResponseTokens,
                webSearchAvailable: false,
                hasCorpus: false,
                useDuckDuckGo: false,
                useWikipedia: false,
                includeToolsAppendix: allowTools
            )
            let tools: [any Tool]
            if allowTools {
                let assembled = ToolKit.assemble(
                    config: ToolKit.Configuration(
                        language: settings.language,
                        corpusChunks: [],
                        userQuery: "",
                        webSearchAvailable: false,
                        webSearchService: webSearchService,
                        webScraper: webScraper,
                        ragContextService: ragContextService,
                        maxDuckDuckGoResults: settings.maxDuckDuckGoResults,
                        maxWikipediaResults: settings.maxWikipediaResults,
                        useDuckDuckGo: false,
                        useWikipedia: false,
                        contextUtilizationFactor: nil
                    ),
                    responseTokens: effectiveMaxTokens
                )
                tools = assembled.tools
            } else {
                tools = []
            }
            return DynamicSessionStateStore.Snapshot(
                mode: .searchSummary,
                instructionsText: instructions,
                tools: tools,
                reasoningLevel: reasoningLevel,
                temperature: settings.temperature,
                maximumResponseTokens: effectiveMaxTokens
            )

        case .chat, .chatFallback:
            let webSearchAvailable = settings.useDuckDuckGo || settings.useWikipedia
            let instructions = ChatService.buildChatInstructions(
                for: settings.language,
                maxOutputCharacters: TokenBudgeting.estimatedOutputCharacters(forTokens: effectiveMaxTokens),
                hasContext: false,
                appendToolsAppendix: true,
                webSearchAvailable: webSearchAvailable,
                hasCorpus: false,
                useDuckDuckGo: settings.useDuckDuckGo,
                useWikipedia: settings.useWikipedia
            )
            let assembled = ToolKit.assemble(
                config: ToolKit.Configuration(
                    language: settings.language,
                    corpusChunks: [],
                    userQuery: "",
                    webSearchAvailable: webSearchAvailable,
                    webSearchService: webSearchService,
                    webScraper: webScraper,
                    ragContextService: ragContextService,
                    maxDuckDuckGoResults: settings.maxDuckDuckGoResults,
                    maxWikipediaResults: settings.maxWikipediaResults,
                    useDuckDuckGo: settings.useDuckDuckGo,
                    useWikipedia: settings.useWikipedia,
                    wikipediaSource: settings.wikipediaSource,
                    contextUtilizationFactor: nil
                ),
                responseTokens: effectiveMaxTokens
            )
            return DynamicSessionStateStore.Snapshot(
                mode: .chat,
                instructionsText: instructions,
                tools: assembled.tools,
                reasoningLevel: reasoningLevel,
                temperature: settings.temperature,
                maximumResponseTokens: effectiveMaxTokens
            )
        }
    }
}
