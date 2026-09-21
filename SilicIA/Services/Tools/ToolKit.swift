//
//  ToolKit.swift
//  SilicIA
//
//  Centralised builder for the Foundation Models tool kit. Two callers
//  (`ChatService.sendMessage` and
//  `AIService.generateSummaryWithFoundationModels`) used to assemble the
//  same `[searchContext, calculate, currentDateTime, webSearch?]` array
//  with nearly-identical code and a per-language tool-usage appendix
//  pasted into both files. This module is the single source of truth so
//  the chat and search paths stay in lock-step on tool config, budget
//  scaling, and the prompt prose the model sees.
//
//  Two surfaces:
//    - `ToolKit.assemble(config:responseTokens:)` builds the tools array
//      + the per-call token budget.
//    - `ToolKit.instructionsAppendix(for:tone:webSearchAvailable:)`
//      builds the per-language paragraph appended onto the system
//      instructions. The `tone` parameter swaps the `searchContext`
//      description between chat-style ("the user's attached documents")
//      and search-style ("the already-fetched web corpus"); the other
//      three tool descriptions are shared verbatim.
//

import Foundation
import FoundationModels

/// Per-conversation framing for the tool-usage appendix. Chat treats the
/// model's input as a turn in a back-and-forth; search treats it as a
/// research query against a freshly-fetched corpus.
enum ToolCallingTone {
    case chat
    case search
}

/// `nonisolated` because tool assembly is pure infrastructure that produces
/// Sendable `Tool` values consumed by the nonisolated FoundationModels
/// runtime. Under the project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
/// leaving it main-actor-isolated made `assemble` flag the `@Sendable`
/// `onWebResults` closure as crossing the actor boundary when stored into the
/// (nonisolated) `WebSearchTool`. Assembling off the actor removes that
/// false-positive crossing; callers on the main actor invoke it freely.
nonisolated enum ToolKit {

    /// Configuration the caller must supply to assemble a tool kit. The
    /// `webSearch*` fields are only read when `webSearchAvailable` is
    /// true, so callers that exclude web search can pass any placeholder
    /// values for them.
    struct Configuration {
        /// Output language. Drives DateTimeTool's locale and the web
        /// search service's regional source mix.
        let language: ModelLanguage
        /// Chunks reachable through `searchContext`. Empty in tool-only
        /// search where the model fetches everything via `webSearch`.
        let corpusChunks: [RAGChunk]
        /// Master switch for the `webSearch` tool. The caller decides
        /// whether the conversation allows web access at all — typically
        /// derived from settings + per-conversation chip + mode flags.
        let webSearchAvailable: Bool
        let webSearchService: WebSearchService
        let webScraper: WebScrapingService
        let useWebVision: Bool
        let maxDuckDuckGoResults: Int
        let maxWikipediaResults: Int
        let useDuckDuckGo: Bool
        let useWikipedia: Bool
        /// Optional sink that receives every result the model's
        /// `webSearch` call fetched. SearchView wires it through
        /// AIService so the cards reflect the model's tool decisions.
        var onWebResults: (@Sendable ([SearchResult]) -> Void)? = nil
    }

    /// Returns the model's tool array, the per-call token budget it was
    /// sized with, and a recorder containing any successful tool replies
    /// produced during the turn. The budget is also embedded inside each
    /// tool so the inner search / scrape steps respect the same cap.
    static func assemble(
        config: Configuration,
        responseTokens: Int
    ) -> (tools: [any Tool], tokenBudget: Int, transcriptRecorder: ToolTranscriptRecorder) {
        // Per-tool reply budget scales with the response cap so verbose
        // profiles ("deep") give tools room to return richer payloads and
        // terse profiles ("fast") keep tool output tight. See
        // `TokenBudgeting.toolOutputTokenBudget(forResponseTokens:)` for
        // the exact clamp.
        let tokenBudget = TokenBudgeting.toolOutputTokenBudget(forResponseTokens: responseTokens)

        // One loop breaker shared across every tool in this turn, so it sees
        // the whole call stream and can refuse duplicate / runaway calls
        // before they overflow the 4096-token window.
        let governor = ToolCallGovernor(
            additionalToolCaps: [
                "searchContext": 3
            ]
        )
        let transcriptRecorder = ToolTranscriptRecorder()

        var tools: [any Tool] = []
        if !config.corpusChunks.isEmpty {
            var ragTool = RAGSearchTool(chunks: config.corpusChunks, tokenBudget: tokenBudget)
            ragTool.governor = governor
            ragTool.transcriptRecorder = transcriptRecorder
            tools.append(ragTool)
        }
        var calcTool = CalculatorTool()
        calcTool.governor = governor
        calcTool.transcriptRecorder = transcriptRecorder
        var dateTool = DateTimeTool(language: config.language)
        dateTool.governor = governor
        tools.append(calcTool)
        tools.append(dateTool)

        if config.webSearchAvailable {
            // webSearch gets a TIGHTER budget than the other tools: its
            // reply (several scraped pages) is the dominant transcript
            // consumer and the main cause of context-window overflow
            // (`GenerationError -1`). Cap it below the shared budget so a
            // turn with one or more webSearch calls still fits the window.
            let webSearchBudget = min(tokenBudget, TokenBudgeting.webSearchReplyTokenCap)
            var webTool = WebSearchTool(
                webSearchService: config.webSearchService,
                webScraper: config.webScraper,
                useWebVision: config.useWebVision,
                maxDuckDuckGoResults: config.maxDuckDuckGoResults,
                maxWikipediaResults: config.maxWikipediaResults,
                useDuckDuckGo: config.useDuckDuckGo,
                useWikipedia: config.useWikipedia,
                language: config.language,
                tokenBudget: webSearchBudget
            )
            webTool.onResults = config.onWebResults
            webTool.governor = governor
            webTool.transcriptRecorder = transcriptRecorder
            tools.append(webTool)
        }
        return (tools, tokenBudget, transcriptRecorder)
    }

    /// Per-language paragraph appended onto the system instructions when
    /// tool calling is enabled. The `tone` selects the `searchContext`
    /// description; the other three tool descriptions are tone-agnostic.
    /// The `webSearch` entry is included only when the tool is actually
    /// in the kit so the model isn't told to call something that isn't
    /// attached. `hasCorpus` controls whether `searchContext` is advertised.
    static func instructionsAppendix(
        for language: ModelLanguage,
        tone: ToolCallingTone,
        webSearchAvailable: Bool,
        hasCorpus: Bool = true
    ) -> String {
        let header = loadHeader(for: language)
        let searchContextLine = loadSearchContextLine(for: language, tone: tone)
        let calculateLine = loadCalculateLine(for: language)
        let dateTimeLine = loadDateTimeLine(for: language)
        let webSearchLine = loadWebSearchLine(for: language)
        let footer = loadFooter(
            for: language,
            hasSearchOrCorpus: (hasCorpus || webSearchAvailable)
        )

        var toolLines: [String] = []
        if hasCorpus {
            toolLines.append(searchContextLine)
        }
        toolLines.append(contentsOf: [calculateLine, dateTimeLine])
        if webSearchAvailable {
            toolLines.append(webSearchLine)
        }

        let toolsBlock = toolLines.joined(separator: "\n")
        if let appendixTemplate = PromptLoader.loadPrompt(
            mode: "normal",
            feature: "toolkit",
            variant: "appendix",
            language: language,
            replacements: [
                "header": header,
                "tools": toolsBlock,
                "footer": footer
            ]
        ) {
            return appendixTemplate
        }

        var lines: [String] = [header]
        lines.append(contentsOf: toolLines)
        lines.append(footer)
        return lines.joined(separator: "\n")
    }

    private static func loadHeader(for language: ModelLanguage) -> String {
        if let loaded = PromptLoader.loadPrompt(mode: "normal", feature: "toolkit", variant: "header", language: language) {
            return loaded
        }
        switch language {
        case .french: return "Outils disponibles :"
        case .spanish: return "Herramientas disponibles:"
        case .english: return "Available tools:"
        }
    }

    private static func loadSearchContextLine(for language: ModelLanguage, tone: ToolCallingTone) -> String {
        let variant = tone == .chat ? "tool.search_context.chat" : "tool.search_context.search"
        if let loaded = PromptLoader.loadPrompt(mode: "normal", feature: "toolkit", variant: variant, language: language) {
            return loaded
        }
        switch (language, tone) {
        case (.french, .chat):
            return "- `searchContext(query)` : recherche dans les documents joints (PDF, images, pages web) et renvoie les passages pertinents avec leur source. Utilise-le AVANT de répondre dès que la question dépend des documents — n'invente jamais un chiffre, une date ou un nom propre qui pourrait y figurer."
        case (.french, .search):
            return "- `searchContext(query)` : recherche dans le corpus de pages web déjà récupérées et renvoie les passages pertinents avec leur source."
        case (.spanish, .chat):
            return "- `searchContext(query)`: busca en los documentos adjuntos (PDF, imágenes, páginas web) y devuelve los pasajes relevantes con su fuente. Úsala ANTES de responder cuando la pregunta dependa de los documentos — nunca inventes una cifra, fecha o nombre propio que podría estar allí."
        case (.spanish, .search):
            return "- `searchContext(query)`: busca en el corpus de páginas web ya recuperadas y devuelve los pasajes relevantes con su fuente."
        case (.english, .chat):
            return "- `searchContext(query)`: search the user's attached documents (PDFs, images, web pages) and return relevant passages with their source. Call this BEFORE answering whenever the question depends on the documents — never guess a number, date, or proper noun that might be in there."
        case (.english, .search):
            return "- `searchContext(query)`: search the already-fetched web corpus and return relevant passages with their source."
        }
    }

    private static func loadCalculateLine(for language: ModelLanguage) -> String {
        if let loaded = PromptLoader.loadPrompt(mode: "normal", feature: "toolkit", variant: "tool.calculate", language: language) {
            return loaded
        }
        switch language {
        case .french:
            return "- `calculate(expression)` : évalue une expression arithmétique exactement. Utilise-le pour tout calcul non trivial — ne calcule jamais de tête."
        case .spanish:
            return "- `calculate(expression)`: evalúa una expresión aritmética exactamente. Úsala para cualquier cálculo no trivial — nunca calcules de memoria."
        case .english:
            return "- `calculate(expression)`: evaluate an arithmetic expression exactly. Use this for any non-trivial math — do not compute in your head."
        }
    }

    private static func loadDateTimeLine(for language: ModelLanguage) -> String {
        if let loaded = PromptLoader.loadPrompt(mode: "normal", feature: "toolkit", variant: "tool.current_date_time", language: language) {
            return loaded
        }
        switch language {
        case .french:
            return "- `currentDateTime(format?)` : renvoie la date et l'heure actuelles. Utilise-le AVANT de répondre dès que la question contient une référence temporelle relative (« aujourd'hui », « bientôt », « la semaine prochaine », « dans X jours », etc.) — tu n'as pas d'horloge interne."
        case .spanish:
            return "- `currentDateTime(format?)`: devuelve la fecha y la hora actuales. Úsala ANTES de responder cuando la pregunta tenga una referencia temporal relativa ('hoy', 'pronto', 'la próxima semana', 'en X días', etc.) — no tienes reloj interno."
        case .english:
            return "- `currentDateTime(format?)`: get the current date and time. Call this BEFORE answering whenever the question contains relative time ('today', 'soon', 'next week', 'in X days', etc.) — you have no internal clock."
        }
    }

    private static func loadWebSearchLine(for language: ModelLanguage) -> String {
        if let loaded = PromptLoader.loadPrompt(mode: "normal", feature: "toolkit", variant: "tool.web_search", language: language) {
            return loaded
        }
        switch language {
        case .french:
            return "- `webSearch(query, maxResults?)` : interroge le web (DuckDuckGo + Wikipedia) avec une requête que TU formules toi-même à partir de la question de l'utilisateur. Utilise-le pour les informations récentes, les procédures techniques, les API, la documentation ou tout ce qui dépasse tes données d'entraînement — pas pour les calculs arithmétiques."
        case .spanish:
            return "- `webSearch(query, maxResults?)`: consulta la web (DuckDuckGo + Wikipedia) con una consulta que TÚ formulas a partir de la pregunta del usuario. Úsala para información reciente, procedimientos técnicos, APIs, documentación o cualquier dato más allá de tus datos de entrenamiento — no para cálculos aritméticos."
        case .english:
            return "- `webSearch(query, maxResults?)`: query the web (DuckDuckGo + Wikipedia) with a focused query YOU compose from the user's question. Use this for current or recent information, technical procedures, APIs, documentation, or facts beyond your training data — not for basic arithmetic."
        }
    }

    private static func loadFooter(for language: ModelLanguage, hasSearchOrCorpus: Bool) -> String {
        let variant = hasSearchOrCorpus ? "footer.with_search" : "footer.direct"
        if let loaded = PromptLoader.loadPrompt(mode: "normal", feature: "toolkit", variant: variant, language: language) {
            return loaded
        }
        if hasSearchOrCorpus {
            switch language {
            case .french:
                return "Tu peux appeler ces outils plusieurs fois par tour si la première réponse est incomplète. Cite la source des passages uniquement lorsqu'un document ou une recherche web a été utilisé. Pour les définitions basiques ou la culture générale courante, réponds directement à partir de tes connaissances sans mentionner de contexte manquant."
            case .spanish:
                return "Puedes llamar a estas herramientas varias veces en un turno si la primera respuesta es incompleta. Cita la fuente de los pasajes únicamente cuando se haya utilizado un documento o una búsqueda web. Para definiciones básicas o conceptos generales cotidianos, responde directamente a partir de tus conocimientos sin mencionar la falta de contexto."
            case .english:
                return "You may call these tools multiple times per turn if the first result was incomplete. Cite the source of passages only when an attached document or web search was used. For basic definitions or everyday general knowledge, answer directly from your knowledge without mentioning missing context."
            }
        } else {
            switch language {
            case .french:
                return "Réponds directement aux questions de définition, de concept et de culture générale à partir de tes connaissances sans mentionner de contexte manquant. N'utilise les outils que si un calcul ou la date/heure actuelle est nécessaire."
            case .spanish:
                return "Responde directamente a las preguntas de definición, conceptos y conocimiento general a partir de tus conocimientos sin mencionar la falta de contexto. Utiliza las herramientas solo cuando se necesite un cálculo o la fecha/hora actual."
            case .english:
                return "Answer conceptual, definition, and general knowledge questions directly from your knowledge without mentioning missing context. Use tools only when a calculation or real-time date/time is required."
            }
        }
    }
}
