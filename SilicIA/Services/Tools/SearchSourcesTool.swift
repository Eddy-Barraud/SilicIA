//
//  SearchSourcesTool.swift
//  SilicIA
//
//  Foundation Models tools exposing external web search (DuckDuckGo)
//  and encyclopedic search (Wikipedia) unified through SourceFunnel.
//  Three variants are provided with name = "searchSources" matching
//  the active source configuration.
//

import Foundation
import FoundationModels
import NaturalLanguage

struct SearchSourcesTool: Tool {

    @Generable
    struct Arguments {
        @Guide(description: "Two distinct web search queries.", .count(2))
        var webQueries: [String] = []

        @Guide(description: "Two distinct Wikipedia encyclopedic article titles relevant to the topic.", .count(2))
        var wikiQueries: [String] = []
    }

    @Generable
    struct WikiFastArguments {
        @Guide(description: "Two distinct web search queries written strictly in the same language as the user's prompt.", .count(2))
        var webQueries: [String] = []

        @Guide(description: "Two distinct Wikipedia encyclopedic article titles translated into English (mandatory). Expand any acronyms into full English technical names. Never write questions.", .count(2))
        var wikiQueries: [String] = []
    }

    @Generable
    struct SingleQueryArguments {
        @Guide(description: "One targeted web search query.")
        var webQuery: String = ""

        @Guide(description: "One targeted Wikipedia encyclopedic article title relevant to the topic.")
        var wikiQuery: String = ""
    }

    @Generable
    struct WikiFastSingleQueryArguments {
        @Guide(description: "One targeted web search query written strictly in the same language as the user's prompt.")
        var webQuery: String = ""

        @Guide(description: "One targeted Wikipedia encyclopedic article title translated into English (mandatory). Expand any acronyms into full English technical names. Never write questions.")
        var wikiQuery: String = ""
    }

    @Generable
    struct WebOnlyArguments {
        @Guide(description: "Two distinct web search queries.", .count(2))
        var webQueries: [String] = []
    }

    @Generable
    struct WikiOnlyArguments {
        @Guide(description: "Two distinct Wikipedia encyclopedic article titles relevant to the topic.", .count(2))
        var wikiQueries: [String] = []
    }

    @Generable
    struct WikiFastOnlyArguments {
        @Guide(description: "Two distinct Wikipedia encyclopedic article titles translated into English (mandatory). Expand any acronyms into full English technical names. Never write questions.", .count(2))
        var wikiQueries: [String] = []
    }

    @Generable
    struct WebOnlySingleQueryArguments {
        @Guide(description: "One targeted web search query.")
        var webQuery: String = ""
    }

    @Generable
    struct WikiOnlySingleQueryArguments {
        @Guide(description: "One targeted Wikipedia encyclopedic article title relevant to the topic.")
        var wikiQuery: String = ""
    }

    @Generable
    struct WikiFastOnlySingleQueryArguments {
        @Guide(description: "One targeted Wikipedia encyclopedic article title translated into English (mandatory). Expand any acronyms into full English technical names. Never write questions.")
        var wikiQuery: String = ""
    }

    let name = "searchSources"
    let description = """
    Search the web and Wikipedia simultaneously for relevant sources. Favor a single focused query; reserve Wikipedia (wikiQueries) strictly for precise data, figures, definitions, or notable facts (pass [] if not needed). Only provide up to 2 queries per source if the topic is difficult or multi-faceted.
    """

    let funnel: SourceFunnel

    func call(arguments: Arguments) async throws -> String {
        try await funnel.run(webQueries: arguments.webQueries, wikiQueries: arguments.wikiQueries)
    }

    /// Generates targeted search queries for Web and Wikipedia using a dedicated, fast @Generable session.
    /// In concise output mode (maxResponseTokens < 400), generates 1 targeted web query and 1 Wikipedia topic
    /// directly, bypassing NLEmbedding deduplication for maximum speed. In standard/detailed modes, generates
    /// 2 web + 2 Wikipedia queries followed by NLEmbedding cosine deduplication.
    static func generateQueries(
        for userQuery: String,
        language: ModelLanguage = .english,
        maxResponseTokens: Int = 500,
        useDuckDuckGo: Bool = true,
        useWikipedia: Bool = true,
        wikipediaSource: WikipediaSource = .online
    ) async -> (webQueries: [String], wikiQueries: [String]) {
        guard useDuckDuckGo || useWikipedia else {
            return ([], [])
        }

        guard await FoundationModelAvailability.check().isAvailable else {
            return (
                webQueries: useDuckDuckGo ? [userQuery] : [],
                wikiQueries: useWikipedia ? [userQuery] : []
            )
        }

        let isWikiFast = (wikipediaSource == .wikiFast)
        let start = Date()
        do {
            let isConcise = TokenBudgeting.outputProfile(forResponseTokens: maxResponseTokens).kind == .concise
            if isConcise {
                let conciseInstructions: String
                let topicLabel: String
                switch language {
                case .french:
                    if isWikiFast && useWikipedia {
                        topicLabel = "Sujet (webQuery en français, wikiQuery en anglais)"
                        if useDuckDuckGo {
                            conciseInstructions = "Génère 1 requête web en français (webQuery) et 1 titre d'article Wikipédia traduit OBLIGATOIREMENT en anglais (wikiQuery). Développe impérativement les sigles/acronymes en leur nom technique complet en anglais. Ne formule jamais de question."
                        } else {
                            conciseInstructions = "Génère 1 titre d'article Wikipédia traduit OBLIGATOIREMENT en anglais (wikiQuery) pour le sujet. Développe impérativement les sigles/acronymes en leur nom technique complet en anglais. Ne formule jamais de question."
                        }
                    } else {
                        topicLabel = "Sujet (rédige les requêtes en français)"
                        if useDuckDuckGo && useWikipedia {
                            conciseInstructions = "Génère 1 requête de recherche web ciblée et 1 titre d'article Wikipédia pour le sujet, en français. Reste concis et précis."
                        } else if useDuckDuckGo {
                            conciseInstructions = "Génère 1 requête de recherche web ciblée pour le sujet, en français. Reste concis et précis."
                        } else {
                            conciseInstructions = "Génère 1 titre d'article Wikipédia pour le sujet, en français. Reste concis et précis."
                        }
                    }
                case .spanish:
                    if isWikiFast && useWikipedia {
                        topicLabel = "Tema (webQuery en español, wikiQuery en inglés)"
                        if useDuckDuckGo {
                            conciseInstructions = "Genera 1 consulta web en español (webQuery) y 1 título de artículo de Wikipedia traducido OBLIGATORIAMENTE al inglés (wikiQuery). Desarrolla siglas y acrónimos a su nombre técnico en inglés. Nunca formules preguntas."
                        } else {
                            conciseInstructions = "Genera 1 título de artículo de Wikipedia traducido OBLIGATORIAMENTE al inglés (wikiQuery). Desarrolla siglas y acrónimos a su nombre técnico en inglés. Nunca formules preguntas."
                        }
                    } else {
                        topicLabel = "Tema (redacta las consultas en español)"
                        if useDuckDuckGo && useWikipedia {
                            conciseInstructions = "Genera 1 consulta de búsqueda web y 1 título de artículo de Wikipedia para el tema, en español. Sé conciso y preciso."
                        } else if useDuckDuckGo {
                            conciseInstructions = "Genera 1 consulta de búsqueda web para el tema, en español. Sé conciso y preciso."
                        } else {
                            conciseInstructions = "Genera 1 título de artículo de Wikipedia para el tema, en español. Sé conciso y preciso."
                        }
                    }
                case .english:
                    topicLabel = "Topic (write queries in English)"
                    if useDuckDuckGo && useWikipedia {
                        conciseInstructions = "Generate 1 targeted web search query and 1 Wikipedia article title for the topic, in English. Expand any acronyms to their full technical name. Never write questions."
                    } else if useDuckDuckGo {
                        conciseInstructions = "Generate 1 targeted web search query for the topic, in English. Be concise and precise."
                    } else {
                        conciseInstructions = "Generate 1 Wikipedia article title for the topic, in English. Expand any acronyms to their full technical name. Never write questions."
                    }
                }

                let session = await DynamicSessionCoordinator.shared.acquireSession(
                    mode: .searchQueryGeneration,
                    instructions: conciseInstructions,
                    temperature: 0.2,
                    maxResponseTokens: 80,
                    reasoningLevelOverride: .light
                )
                let prompt = "\(topicLabel) : \(userQuery)"
                let rawWeb: String
                let rawWiki: String
                if useDuckDuckGo && useWikipedia {
                    if isWikiFast {
                        let response = try await session.respond(to: prompt, generating: WikiFastSingleQueryArguments.self)
                        rawWeb = response.content.webQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                        rawWiki = response.content.wikiQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        let response = try await session.respond(to: prompt, generating: SingleQueryArguments.self)
                        rawWeb = response.content.webQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                        rawWiki = response.content.wikiQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } else if useDuckDuckGo {
                    let response = try await session.respond(to: prompt, generating: WebOnlySingleQueryArguments.self)
                    rawWeb = response.content.webQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                    rawWiki = ""
                } else {
                    if isWikiFast {
                        let response = try await session.respond(to: prompt, generating: WikiFastOnlySingleQueryArguments.self)
                        rawWeb = ""
                        rawWiki = response.content.wikiQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        let response = try await session.respond(to: prompt, generating: WikiOnlySingleQueryArguments.self)
                        rawWeb = ""
                        rawWiki = response.content.wikiQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                let elapsed = Date().timeIntervalSince(start)

                let filteredWeb: [String]
                if useDuckDuckGo {
                    filteredWeb = rawWeb.isEmpty ? [userQuery] : [rawWeb]
                } else {
                    filteredWeb = []
                }

                let filteredWiki: [String]
                if useWikipedia {
                    let cleanedWiki = (rawWiki.isEmpty || rawWiki.lowercased() == "n/a" || rawWiki.lowercased() == "none") ? "" : rawWiki
                    filteredWiki = cleanedWiki.isEmpty ? [userQuery] : [cleanedWiki]
                } else {
                    filteredWiki = []
                }

                #if DEBUG
                print("┏━ [SearchSourcesTool] @Generable Query Generation (Concise 1+1, wikiSource=\(wikipediaSource.rawValue)) ━━")
                print("┃ User Query: \"\(userQuery)\" (elapsed: \(String(format: "%.3f s", elapsed)))")
                print("┃ Dispatched Web Query: \(filteredWeb)")
                print("┃ Dispatched Wiki Query: \(filteredWiki)")
                print("┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                #endif

                return (webQueries: filteredWeb, wikiQueries: filteredWiki)
            }

            let instructions: String
            let topicLabel: String
            switch language {
            case .french:
                if isWikiFast && useWikipedia {
                    if useDuckDuckGo {
                        topicLabel = "Sujet (webQueries en français, wikiQueries en anglais)"
                        instructions = "Génère 2 requêtes web en français (webQueries) et 2 titres d'articles Wikipédia traduits OBLIGATOIREMENT en anglais (wikiQueries). Développe impérativement les sigles/acronymes en leur nom technique complet en anglais. Ne formule jamais de questions."
                    } else {
                        topicLabel = "Sujet (wikiQueries en anglais)"
                        instructions = "Génère 2 titres d'articles Wikipédia traduits OBLIGATOIREMENT en anglais (wikiQueries) pour le sujet. Développe impérativement les sigles/acronymes en leur nom technique complet en anglais. Ne formule jamais de questions."
                    }
                } else {
                    topicLabel = "Sujet (rédige les requêtes en français)"
                    if useDuckDuckGo && useWikipedia {
                        instructions = "Génère 2 requêtes de recherche web et 2 titres d'articles Wikipédia pour le sujet, en français. Reste concis et précis."
                    } else if useDuckDuckGo {
                        instructions = "Génère 2 requêtes de recherche web pour le sujet, en français. Reste concis et précis."
                    } else {
                        instructions = "Génère 2 titres d'articles Wikipédia pour le sujet, en français. Reste concis et précis."
                    }
                }
            case .spanish:
                if isWikiFast && useWikipedia {
                    if useDuckDuckGo {
                        topicLabel = "Tema (webQueries en español, wikiQueries en inglés)"
                        instructions = "Genera 2 consultas web en español (webQueries) y 2 títulos de artículos de Wikipedia traducidos OBLIGATORIAMENTE al inglés (wikiQueries). Desarrolla siglas y acrónimos a su nombre técnico en inglés. Nunca formules preguntas."
                    } else {
                        topicLabel = "Tema (wikiQueries en inglés)"
                        instructions = "Genera 2 títulos de artículos de Wikipedia traducidos OBLIGATORIAMENTE al inglés (wikiQueries) para el tema. Desarrolla siglas y acrónimos a su nombre técnico en inglés. Nunca formules preguntas."
                    }
                } else {
                    topicLabel = "Tema (redacta las consultas en español)"
                    if useDuckDuckGo && useWikipedia {
                        instructions = "Genera 2 consultas de búsqueda web y 2 títulos de artículos de Wikipedia para el tema, en español. Sé conciso y preciso."
                    } else if useDuckDuckGo {
                        instructions = "Genera 2 consultas de búsqueda web para el tema, en español. Sé conciso y preciso."
                    } else {
                        instructions = "Genera 2 títulos de artículos de Wikipedia para el tema, en español. Sé conciso y preciso."
                    }
                }
            case .english:
                topicLabel = "Topic (write queries in English)"
                if useDuckDuckGo && useWikipedia {
                    instructions = "Generate 2 web search queries and 2 Wikipedia article titles for the topic, in English. Expand any acronyms to their full technical name. Never write questions."
                } else if useDuckDuckGo {
                    instructions = "Generate 2 web search queries for the topic, in English. Be concise and precise."
                } else {
                    instructions = "Generate 2 Wikipedia article titles for the topic, in English. Expand any acronyms to their full technical name. Never write questions."
                }
            }

            let session = await DynamicSessionCoordinator.shared.acquireSession(
                mode: .searchQueryGeneration,
                instructions: instructions,
                temperature: 0.2,
                maxResponseTokens: 200,
                reasoningLevelOverride: .light
            )
            let prompt = "\(topicLabel) : \(userQuery)"
            let rawWebList: [String]
            let rawWikiList: [String]
            if useDuckDuckGo && useWikipedia {
                if isWikiFast {
                    let response = try await session.respond(to: prompt, generating: WikiFastArguments.self)
                    rawWebList = response.content.webQueries
                    rawWikiList = response.content.wikiQueries
                } else {
                    let response = try await session.respond(to: prompt, generating: Arguments.self)
                    rawWebList = response.content.webQueries
                    rawWikiList = response.content.wikiQueries
                }
            } else if useDuckDuckGo {
                let response = try await session.respond(to: prompt, generating: WebOnlyArguments.self)
                rawWebList = response.content.webQueries
                rawWikiList = []
            } else {
                if isWikiFast {
                    let response = try await session.respond(to: prompt, generating: WikiFastOnlyArguments.self)
                    rawWebList = []
                    rawWikiList = response.content.wikiQueries
                } else {
                    let response = try await session.respond(to: prompt, generating: WikiOnlyArguments.self)
                    rawWebList = []
                    rawWikiList = response.content.wikiQueries
                }
            }
            let elapsed = Date().timeIntervalSince(start)

            let rawWeb = rawWebList
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let rawWiki = rawWikiList
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.lowercased() != "n/a" && $0.lowercased() != "none" }

            let nlLang: NLLanguage
            switch language {
            case .french: nlLang = .french
            case .spanish: nlLang = .spanish
            case .english: nlLang = .english
            }
            let embedding = NLEmbedding.sentenceEmbedding(for: nlLang) ?? NLEmbedding.wordEmbedding(for: nlLang)
            let wikiLang: NLLanguage = isWikiFast ? .english : nlLang
            let wikiEmbedding = NLEmbedding.sentenceEmbedding(for: wikiLang) ?? NLEmbedding.wordEmbedding(for: wikiLang)

            // Deduplicate web queries
            var finalWeb: [String] = []
            var webDist: Double? = nil
            if rawWeb.count >= 2 {
                let q1 = rawWeb[0]
                let q2 = rawWeb[1]
                let dist = embedding?.distance(between: q1, and: q2) ?? 1.0
                webDist = dist
                if isSimilarQuery(q1, q2, distance: dist) {
                    finalWeb = [q1]
                } else {
                    finalWeb = [q1, q2]
                }
            } else {
                finalWeb = rawWeb
            }

            // Deduplicate wiki queries
            var finalWiki: [String] = []
            var wikiDist: Double? = nil
            if rawWiki.count >= 2 {
                let w1 = rawWiki[0]
                let w2 = rawWiki[1]
                let dist = wikiEmbedding?.distance(between: w1, and: w2) ?? 1.0
                wikiDist = dist
                if isSimilarQuery(w1, w2, distance: dist) {
                    finalWiki = [w1]
                } else {
                    finalWiki = [w1, w2]
                }
            } else {
                finalWiki = rawWiki
            }

            let filteredWeb = useDuckDuckGo ? (finalWeb.isEmpty ? [userQuery] : finalWeb) : []
            let filteredWiki = useWikipedia ? (finalWiki.isEmpty ? [userQuery] : finalWiki) : []

            #if DEBUG
            print("┏━ [SearchSourcesTool] @Generable Query Generation (wikiSource=\(wikipediaSource.rawValue)) ━━")
            print("┃ User Query: \"\(userQuery)\" (elapsed: \(String(format: "%.3f s", elapsed)))")
            print("┃ Raw Web Queries: \(rawWeb)")
            print("┃ Raw Wiki Queries: \(rawWiki)")
            if let d = webDist {
                print("┃ Web NLEmbedding Distance: \(String(format: "%.3f", d)) -> \(finalWeb.count == 1 ? "Deduplicated to 1 query" : "Kept both 2 queries")")
            }
            if let d = wikiDist {
                print("┃ Wiki NLEmbedding Distance: \(String(format: "%.3f", d)) -> \(finalWiki.count == 1 ? "Deduplicated to 1 query" : "Kept both 2 queries")")
            }
            print("┃ Dispatched Web Queries: \(filteredWeb)")
            print("┃ Dispatched Wiki Queries: \(filteredWiki)")
            print("┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            #endif

            return (webQueries: filteredWeb, wikiQueries: filteredWiki)
        } catch {
            #if DEBUG
            print("⚠️ [SearchSourcesTool] @Generable query generation failed: \(error.localizedDescription), falling back to raw user query")
            #endif
            return (
                webQueries: useDuckDuckGo ? [userQuery] : [],
                wikiQueries: useWikipedia ? [userQuery] : []
            )
        }
    }

    internal static func isSimilarQuery(_ a: String, _ b: String, distance: Double) -> Bool {
        let lowerA = a.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerB = b.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lowerA == lowerB { return true }
        if lowerA.contains(lowerB) || lowerB.contains(lowerA) { return true }
        let wordsA = Set(
            lowerA.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 }
                .map { RAGContextService.morphologicalRootStatic($0) }
        )
        let wordsB = Set(
            lowerB.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 }
                .map { RAGContextService.morphologicalRootStatic($0) }
        )
        let intersection = wordsA.intersection(wordsB)
        let union = wordsA.union(wordsB)
        let jaccard = union.isEmpty ? 0.0 : Double(intersection.count) / Double(union.count)
        if jaccard >= 0.50 { return true }
        if distance < 0.40 { return true }
        if distance < 0.60 && !intersection.isEmpty { return true }
        return false
    }
}

struct WebSourcesTool: Tool {

    @Generable
    struct Arguments {
        @Guide(description: "Web keyword search queries. Favor 1 single focused query. Only provide a 2nd query if the topic is difficult or multi-faceted.", .maximumCount(2))
        let webQueries: [String]
    }

    let name = "searchSources"
    let description = """
    Search the web for relevant sources. Favor a single focused query; provide a 2nd query only if the topic is difficult or multi-faceted.
    """

    let funnel: SourceFunnel

    func call(arguments: Arguments) async throws -> String {
        try await funnel.run(webQueries: arguments.webQueries, wikiQueries: [])
    }
}

struct WikiSourcesTool: Tool {

    @Generable
    struct Arguments {
        @Guide(description: "Concise Wikipedia topics (1–2 words: entity, concept, place). Reserve strictly for precise data, figures, definitions, or facts. Favor 1 topic; provide a 2nd only if the topic is difficult.", .maximumCount(2))
        let wikiQueries: [String]
    }

    let name = "searchSources"
    let description = """
    Search Wikipedia for precise data, figures, definitions, or encyclopedic facts. Favor a single topic; provide a 2nd only if the topic is difficult or multi-faceted.
    """

    let funnel: SourceFunnel

    func call(arguments: Arguments) async throws -> String {
        try await funnel.run(webQueries: [], wikiQueries: arguments.wikiQueries)
    }
}
