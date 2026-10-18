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
        @Guide(description: "Up to 2 focused web keyword search queries (recent events, news, websites, technical docs).", .maximumCount(2))
        let webQueries: [String]

        @Guide(description: "Up to 2 concise Wikipedia topics (1–2 words each: person, concept, place, entity).", .maximumCount(2))
        let wikiQueries: [String]
    }

    let name = "searchSources"
    let description = """
    Search the web and Wikipedia simultaneously for relevant sources, returning the most relevant extracted passages. Provide up to 2 web queries and up to 2 Wikipedia topics.
    """

    let funnel: SourceFunnel

    func call(arguments: Arguments) async throws -> String {
        try await funnel.run(webQueries: arguments.webQueries, wikiQueries: arguments.wikiQueries)
    }
}

struct WebSourcesTool: Tool {

    @Generable
    struct Arguments {
        @Guide(description: "Up to 2 focused web keyword search queries (recent events, news, websites, technical docs).", .maximumCount(2))
        let webQueries: [String]
    }

    let name = "searchSources"
    let description = """
    Search the web for relevant sources, returning the most relevant extracted passages. Provide up to 2 web queries.
    """

    let funnel: SourceFunnel

    func call(arguments: Arguments) async throws -> String {
        try await funnel.run(webQueries: arguments.webQueries, wikiQueries: [])
    }
}

struct WikiSourcesTool: Tool {

    @Generable
    struct Arguments {
        @Guide(description: "Up to 2 concise Wikipedia topics (1–2 words each: person, concept, place, entity).", .maximumCount(2))
        let wikiQueries: [String]
    }

    let name = "searchSources"
    let description = """
    Search Wikipedia for encyclopedic articles, returning the most relevant extracted passages. Provide up to 2 Wikipedia topics.
    """

    let funnel: SourceFunnel

    func call(arguments: Arguments) async throws -> String {
        try await funnel.run(webQueries: [], wikiQueries: arguments.wikiQueries)
    }
}
