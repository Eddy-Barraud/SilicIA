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

struct SearchSourcesTool: Tool {

    @Generable
    struct Arguments {
        @Guide(description: "Web keyword search queries. Favor 1 single focused query. Only provide a 2nd query if the topic is difficult or multi-faceted.", .maximumCount(2))
        let webQueries: [String]

        @Guide(description: "Wikipedia topics (1–2 words: person, concept, place). Reserve strictly for precise data, figures, definitions, or facts; pass [] if not needed. Only provide up to 2 topics if the topic is difficult.", .maximumCount(2))
        let wikiQueries: [String]
    }

    let name = "searchSources"
    let description = """
    Search the web and Wikipedia simultaneously for relevant sources. Favor a single focused query; reserve Wikipedia (wikiQueries) strictly for precise data, figures, definitions, or notable facts (pass [] if not needed). Only provide up to 2 queries per source if the topic is difficult or multi-faceted.
    """

    let funnel: SourceFunnel

    func call(arguments: Arguments) async throws -> String {
        try await funnel.run(webQueries: arguments.webQueries, wikiQueries: arguments.wikiQueries)
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
