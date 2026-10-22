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

        @Guide(description: "Two distinct Wikipedia encyclopedic article titles (empty strings if not applicable).", .count(2))
        var wikiQueries: [String] = []
    }

    let name = "searchSources"
    let description = """
    Search the web and Wikipedia simultaneously for relevant sources. Favor a single focused query; reserve Wikipedia (wikiQueries) strictly for precise data, figures, definitions, or notable facts (pass [] if not needed). Only provide up to 2 queries per source if the topic is difficult or multi-faceted.
    """

    let funnel: SourceFunnel

    func call(arguments: Arguments) async throws -> String {
        try await funnel.run(webQueries: arguments.webQueries, wikiQueries: arguments.wikiQueries)
    }

    /// Generates targeted search queries for Web and Wikipedia using a dedicated, fast @Generable session,
    /// followed by NLEmbedding cosine deduplication to keep 1 or 2 queries based on semantic diversity.
    static func generateQueries(
        for userQuery: String,
        language: ModelLanguage = .english,
        useDuckDuckGo: Bool = true,
        useWikipedia: Bool = true
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

        let start = Date()
        do {
            let instructions: String
            switch language {
            case .french:
                instructions = "Génère 2 requêtes de recherche web et 2 titres d'articles Wikipédia pour le sujet (laisser vide pour Wikipédia si non applicable). Reste concis et précis."
            case .spanish:
                instructions = "Genera 2 consultas de búsqueda web y 2 títulos de artículos de Wikipedia para el tema (dejar vacío para Wikipedia si no aplica). Sé conciso y preciso."
            case .english:
                instructions = "Generate 2 web search queries and 2 Wikipedia article titles for the topic (leave empty for Wikipedia if not applicable). Be concise and precise."
            }

            let session = LanguageModelSession(instructions: instructions)
            let prompt = "Topic: \(userQuery)"
            let response = try await session.respond(to: prompt, generating: Arguments.self)
            let elapsed = Date().timeIntervalSince(start)
            let raw = response.content

            let rawWeb = raw.webQueries
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let rawWiki = raw.wikiQueries
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.lowercased() != "n/a" && $0.lowercased() != "none" }

            let nlLang: NLLanguage
            switch language {
            case .french: nlLang = .french
            case .spanish: nlLang = .spanish
            case .english: nlLang = .english
            }
            let embedding = NLEmbedding.sentenceEmbedding(for: nlLang) ?? NLEmbedding.wordEmbedding(for: nlLang)

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
                let dist = embedding?.distance(between: w1, and: w2) ?? 1.0
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
            let filteredWiki = useWikipedia ? (finalWiki.isEmpty ? (useDuckDuckGo ? [] : [userQuery]) : finalWiki) : []

            #if DEBUG
            print("┏━ [SearchSourcesTool] @Generable Query Generation ━━━━━━━━━━")
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

    private static func isSimilarQuery(_ a: String, _ b: String, distance: Double) -> Bool {
        let lowerA = a.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerB = b.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lowerA == lowerB { return true }
        if lowerA.contains(lowerB) || lowerB.contains(lowerA) { return true }
        let wordsA = Set(lowerA.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 })
        let wordsB = Set(lowerB.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 })
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
