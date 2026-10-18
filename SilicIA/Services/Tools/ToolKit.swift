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
nonisolated enum ToolCallingTone: Sendable, Equatable {
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
        /// search where the model fetches everything via `searchSources`.
        let corpusChunks: [RAGChunk]
        /// Anchor query from the user (used for RAG semantic embedding and ranking).
        var userQuery: String = ""
        /// Master switch for external search tools. The caller decides
        /// whether the conversation allows web access at all — typically
        /// derived from settings + per-conversation chip + mode flags.
        let webSearchAvailable: Bool
        let webSearchService: WebSearchService
        let webScraper: WebScrapingService
        var ragContextService: RAGContextService = RAGContextService()
        let maxDuckDuckGoResults: Int
        let maxWikipediaResults: Int
        let useDuckDuckGo: Bool
        let useWikipedia: Bool
        var contextUtilizationFactor: Double? = nil
        /// Optional sink that receives every result the model's
        /// `searchSources` call fetched. SearchView wires it through
        /// AIService so the cards reflect the model's tool decisions.
        var onWebResults: (@Sendable ([SearchResult]) -> Void)? = nil
        var onScrapeDuration: (@Sendable (Double) -> Void)? = nil
        var onScores: (@Sendable ([String: Double]) -> Void)? = nil
        var onRAGDuration: (@Sendable (Double, Double) -> Void)? = nil
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
        // `searchSources` is strictly capped at 1 call per turn.
        let governor = ToolCallGovernor(
            maxExpensiveToolCalls: 1,
            expensiveToolName: "searchSources",
            additionalToolCaps: [
                "searchContext": 3
            ]
        )
        let transcriptRecorder = ToolTranscriptRecorder()

        var tools: [any Tool] = []
        if !config.corpusChunks.isEmpty {
            var ragTool = RAGSearchTool(chunks: config.corpusChunks, tokenBudget: tokenBudget, language: config.language)
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
            let funnel = SourceFunnel(
                webSearchService: config.webSearchService,
                webScraper: config.webScraper,
                ragContextService: config.ragContextService,
                userQuery: config.userQuery,
                language: config.language,
                maxDuckDuckGoResults: config.maxDuckDuckGoResults,
                maxWikipediaResults: config.maxWikipediaResults,
                useDuckDuckGo: config.useDuckDuckGo,
                useWikipedia: config.useWikipedia,
                responseTokens: responseTokens,
                contextUtilizationFactor: config.contextUtilizationFactor,
                onResults: config.onWebResults,
                onScrapeDuration: config.onScrapeDuration,
                onScores: config.onScores,
                onRAGDuration: config.onRAGDuration,
                governor: governor,
                transcriptRecorder: transcriptRecorder
            )

            if config.useDuckDuckGo && config.useWikipedia {
                tools.append(SearchSourcesTool(funnel: funnel))
            } else if config.useDuckDuckGo {
                tools.append(WebSourcesTool(funnel: funnel))
            } else if config.useWikipedia {
                tools.append(WikiSourcesTool(funnel: funnel))
            }
        }
        return (tools, tokenBudget, transcriptRecorder)
    }

    /// Per-language paragraph appended onto the system instructions when
    /// tool calling is enabled. The `tone` selects the `searchContext`
    /// description; the other tool descriptions are tone-agnostic.
    /// The `searchSources` entry is included only when external search
    /// is enabled and attached. `hasCorpus` controls whether
    /// `searchContext` is advertised.
    static func instructionsAppendix(
        for language: ModelLanguage,
        tone: ToolCallingTone,
        webSearchAvailable: Bool,
        hasCorpus: Bool = true,
        useDuckDuckGo: Bool = true,
        useWikipedia: Bool = true
    ) -> String {
        let header = loadHeader(for: language)
        let searchContextLine = loadSearchContextLine(for: language, tone: tone)
        let calculateLine = loadCalculateLine(for: language)
        let dateTimeLine = loadDateTimeLine(for: language)
        let hasActiveSearch = webSearchAvailable && (useDuckDuckGo || useWikipedia)
        let searchSourcesLine = hasActiveSearch ? loadSearchSourcesLine(
            for: language,
            useDuckDuckGo: useDuckDuckGo,
            useWikipedia: useWikipedia
        ) : nil
        let footer = loadFooter(
            for: language,
            tone: tone,
            hasSearchOrCorpus: (hasCorpus || hasActiveSearch)
        )

        var toolLines: [String] = []
        if hasCorpus {
            toolLines.append(searchContextLine)
        }
        toolLines.append(contentsOf: [calculateLine, dateTimeLine])
        if let searchSourcesLine {
            toolLines.append(searchSourcesLine)
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

    private static func loadSearchSourcesLine(
        for language: ModelLanguage,
        useDuckDuckGo: Bool,
        useWikipedia: Bool
    ) -> String {
        let variant: String
        if useDuckDuckGo && useWikipedia {
            variant = "tool.search_sources.both"
        } else if useDuckDuckGo {
            variant = "tool.search_sources.web"
        } else {
            variant = "tool.search_sources.wiki"
        }

        if let loaded = PromptLoader.loadPrompt(mode: "normal", feature: "toolkit", variant: variant, language: language) {
            return loaded
        }

        if useDuckDuckGo && useWikipedia {
            switch language {
            case .french:
                return "- `searchSources(webQueries, wikiQueries)` : recherche simultanément sur le web et Wikipédia et renvoie les passages pertinents. Privilégie 1 seule requête ciblée. Réserve Wikipédia (`wikiQueries`) strictement aux données précises, chiffres, définitions ou faits (laisse `[]` si non nécessaire). N'augmente jusqu'à 2 requêtes par source que si le sujet est complexe ou difficile."
            case .spanish:
                return "- `searchSources(webQueries, wikiQueries)`: busca simultáneamente en la web y Wikipedia y devuelve pasajes relevantes. Prioriza 1 sola consulta específica. Reserva Wikipedia (`wikiQueries`) estrictamente para datos precisos, cifras, definiciones o hechos (deja `[]` si no es necesario). Solo amplía hasta 2 consultas por fuente si el tema es complejo o difícil."
            case .english:
                return "- `searchSources(webQueries, wikiQueries)`: search both the web and Wikipedia simultaneously and return relevant passages. Favor 1 single focused query. Reserve Wikipedia (`wikiQueries`) strictly for precise data, figures, definitions, or facts (pass `[]` if not needed). Only provide up to 2 queries per source if the topic is difficult or multi-faceted."
            }
        } else if useDuckDuckGo {
            switch language {
            case .french:
                return "- `searchSources(webQueries)` : recherche sur le web via DuckDuckGo et renvoie les passages pertinents. Privilégie 1 seule requête ciblée. N'utilise une 2e requête que si le sujet est complexe ou difficile."
            case .spanish:
                return "- `searchSources(webQueries)`: busca en la web mediante DuckDuckGo y devuelve pasajes relevantes. Prioriza 1 sola consulta específica. Solo usa una 2.ª consulta si el tema es complejo o difícil."
            case .english:
                return "- `searchSources(webQueries)`: search the web via DuckDuckGo and return relevant passages. Favor 1 single focused query. Only provide a 2nd query if the topic is difficult or multi-faceted."
            }
        } else {
            switch language {
            case .french:
                return "- `searchSources(wikiQueries)` : recherche des articles encyclopédiques sur Wikipédia et renvoie les passages pertinents. À réserver strictement aux données précises, chiffres, définitions ou faits. Privilégie 1 seul sujet court (1 à 2 mots). N'utilise un 2e sujet que si le sujet est complexe ou difficile."
            case .spanish:
                return "- `searchSources(wikiQueries)`: busca artículos enciclopédicos en Wikipedia y devuelve pasajes relevantes. Reserva estrictamente para datos precisos, cifras, definiciones o hechos. Prioriza 1 solo tema breve (1 o 2 palabras). Solo usa un 2.º tema si el tema es complejo o difícil."
            case .english:
                return "- `searchSources(wikiQueries)`: search encyclopedic articles on Wikipedia and return relevant passages. Reserve strictly for precise data, figures, definitions, or facts. Favor 1 single concise topic (1–2 words). Only provide a 2nd topic if the topic is difficult."
            }
        }
    }

    private static func loadFooter(for language: ModelLanguage, tone: ToolCallingTone, hasSearchOrCorpus: Bool) -> String {
        if tone == .search {
            if let loaded = PromptLoader.loadPrompt(mode: "normal", feature: "toolkit", variant: "footer.search", language: language) {
                return loaded
            }
            switch language {
            case .french:
                return "Tu peux appeler ces outils pour obtenir des données complètes. Vérifie systématiquement les faits, dates, chiffres, distances et comparaisons en interrogeant les sources externes (`searchSources`) avant de formuler ta réponse."
            case .spanish:
                return "Puedes llamar a estas herramientas para obtener información completa. Verifica sistemáticamente los hechos, fechas, cifras, distancias y comparaciones consultando fuentes externas (`searchSources`) antes de redactar tu respuesta."
            case .english:
                return "You may call these tools to gather complete information. Always verify facts, dates, figures, distances, and comparisons by searching external sources (`searchSources`) before writing your answer."
            }
        }

        let variant = hasSearchOrCorpus ? "footer.with_search" : "footer.direct"
        if let loaded = PromptLoader.loadPrompt(mode: "normal", feature: "toolkit", variant: variant, language: language) {
            return loaded
        }
        if hasSearchOrCorpus {
            switch language {
            case .french:
                return "Tu peux appeler ces outils pour vérifier les faits, définitions, dates ou chiffres avant de formuler ta réponse. Tu peux les appeler si nécessaire. Cite la source des passages uniquement lorsqu'un document ou une recherche web a été utilisé. Ne mentionne jamais de contexte manquant."
            case .spanish:
                return "Puedes llamar a estas herramientas para verificar hechos, definiciones, fechas o cifras antes de formular tu respuesta. Puedes llamarlas si es necesario. Cita la fuente de los pasajes únicamente cuando se haya utilizado un documento o una búsqueda web. Nunca menciones la falta de contexto."
            case .english:
                return "You may call these tools to verify facts, definitions, dates, or figures before formulating your answer. You may call them if needed. Cite the source of passages only when an attached document or web search was used. Never mention missing context."
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
