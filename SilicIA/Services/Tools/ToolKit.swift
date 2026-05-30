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

enum ToolKit {

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
        let maxDuckDuckGoResults: Int
        let maxWikipediaResults: Int
        let useDuckDuckGo: Bool
        let useWikipedia: Bool
        /// Optional sink that receives every result the model's
        /// `webSearch` call fetched. SearchView wires it through
        /// AIService so the cards reflect the model's tool decisions.
        var onWebResults: (@Sendable ([SearchResult]) -> Void)? = nil
    }

    /// Returns the model's tool array and the per-call token budget it
    /// was sized with. The budget is also embedded inside each tool so
    /// the inner search / scrape steps respect the same cap.
    static func assemble(
        config: Configuration,
        responseTokens: Int
    ) -> (tools: [any Tool], tokenBudget: Int) {
        // Per-tool reply budget scales with the response cap so verbose
        // profiles ("deep") give tools room to return richer payloads and
        // terse profiles ("fast") keep tool output tight. See
        // `TokenBudgeting.toolOutputTokenBudget(forResponseTokens:)` for
        // the exact clamp.
        let tokenBudget = TokenBudgeting.toolOutputTokenBudget(forResponseTokens: responseTokens)

        var tools: [any Tool] = [
            RAGSearchTool(chunks: config.corpusChunks, tokenBudget: tokenBudget),
            CalculatorTool(),
            DateTimeTool(language: config.language)
        ]
        if config.webSearchAvailable {
            var webTool = WebSearchTool(
                webSearchService: config.webSearchService,
                webScraper: config.webScraper,
                maxDuckDuckGoResults: config.maxDuckDuckGoResults,
                maxWikipediaResults: config.maxWikipediaResults,
                useDuckDuckGo: config.useDuckDuckGo,
                useWikipedia: config.useWikipedia,
                language: config.language,
                tokenBudget: tokenBudget
            )
            webTool.onResults = config.onWebResults
            tools.append(webTool)
        }
        return (tools, tokenBudget)
    }

    /// Per-language paragraph appended onto the system instructions when
    /// tool calling is enabled. The `tone` selects the `searchContext`
    /// description; the other three tool descriptions are tone-agnostic.
    /// The `webSearch` entry is included only when the tool is actually
    /// in the kit so the model isn't told to call something that isn't
    /// attached.
    static func instructionsAppendix(
        for language: ModelLanguage,
        tone: ToolCallingTone,
        webSearchAvailable: Bool
    ) -> String {
        let header: String
        let searchContextLine: String
        let calculateLine: String
        let dateTimeLine: String
        let webSearchLine: String
        let footer: String

        switch language {
        case .french:
            header = "Outils disponibles :"
            searchContextLine = {
                switch tone {
                case .chat:
                    return "- `searchContext(query)` : recherche dans les documents joints (PDF, images, pages web) et renvoie les passages pertinents avec leur source. Utilise-le AVANT de répondre dès que la question dépend des documents — n'invente jamais un chiffre, une date ou un nom propre qui pourrait y figurer."
                case .search:
                    return "- `searchContext(query)` : recherche dans le corpus de pages web déjà récupérées et renvoie les passages pertinents avec leur source."
                }
            }()
            calculateLine = "- `calculate(expression)` : évalue une expression arithmétique exactement. Utilise-le pour tout calcul non trivial — ne calcule jamais de tête."
            dateTimeLine = "- `currentDateTime(format?)` : renvoie la date et l'heure actuelles. Utilise-le AVANT de répondre dès que la question contient une référence temporelle relative (« aujourd'hui », « bientôt », « la semaine prochaine », « dans X jours », etc.) — tu n'as pas d'horloge interne."
            webSearchLine = "- `webSearch(query, maxResults?)` : interroge le web (DuckDuckGo + Wikipedia) avec une requête que TU formules toi-même à partir de la question de l'utilisateur. Utilise-le pour les informations récentes, les événements actuels, ou tout ce qui dépasse tes données d'entraînement — pas pour les définitions ou les calculs."
            footer = "Tu peux appeler ces outils plusieurs fois par tour si la première réponse est incomplète. Cite la source des passages utilisés dans ta réponse finale."

        case .spanish:
            header = "Herramientas disponibles:"
            searchContextLine = {
                switch tone {
                case .chat:
                    return "- `searchContext(query)`: busca en los documentos adjuntos (PDF, imágenes, páginas web) y devuelve los pasajes relevantes con su fuente. Úsala ANTES de responder cuando la pregunta dependa de los documentos — nunca inventes una cifra, fecha o nombre propio que podría estar allí."
                case .search:
                    return "- `searchContext(query)`: busca en el corpus de páginas web ya recuperadas y devuelve los pasajes relevantes con su fuente."
                }
            }()
            calculateLine = "- `calculate(expression)`: evalúa una expresión aritmética exactamente. Úsala para cualquier cálculo no trivial — nunca calcules de memoria."
            dateTimeLine = "- `currentDateTime(format?)`: devuelve la fecha y la hora actuales. Úsala ANTES de responder cuando la pregunta tenga una referencia temporal relativa ('hoy', 'pronto', 'la próxima semana', 'en X días', etc.) — no tienes reloj interno."
            webSearchLine = "- `webSearch(query, maxResults?)`: consulta la web (DuckDuckGo + Wikipedia) con una consulta que TÚ formulas a partir de la pregunta del usuario. Úsala para información reciente, eventos actuales o cualquier dato más allá de tus datos de entrenamiento — no para definiciones ni cálculos."
            footer = "Puedes llamar a estas herramientas varias veces en un turno si la primera respuesta es incompleta. Cita la fuente de los pasajes utilizados en tu respuesta final."

        case .english:
            header = "Available tools:"
            searchContextLine = {
                switch tone {
                case .chat:
                    return "- `searchContext(query)`: search the user's attached documents (PDFs, images, web pages) and return relevant passages with their source. Call this BEFORE answering whenever the question depends on the documents — never guess a number, date, or proper noun that might be in there."
                case .search:
                    return "- `searchContext(query)`: search the already-fetched web corpus and return relevant passages with their source."
                }
            }()
            calculateLine = "- `calculate(expression)`: evaluate an arithmetic expression exactly. Use this for any non-trivial math — do not compute in your head."
            dateTimeLine = "- `currentDateTime(format?)`: get the current date and time. Call this BEFORE answering whenever the question contains relative time ('today', 'soon', 'next week', 'in X days', etc.) — you have no internal clock."
            webSearchLine = "- `webSearch(query, maxResults?)`: query the web (DuckDuckGo + Wikipedia) with a focused query YOU compose from the user's question. Use this for current/recent information or anything beyond your training data — not for definitions or arithmetic."
            footer = "You may call these tools multiple times per turn if the first result was incomplete. Cite the source of any passages you used in your final answer."
        }

        var lines: [String] = [header, searchContextLine, calculateLine, dateTimeLine]
        if webSearchAvailable {
            lines.append(webSearchLine)
        }
        lines.append(footer)
        return lines.joined(separator: "\n")
    }
}
