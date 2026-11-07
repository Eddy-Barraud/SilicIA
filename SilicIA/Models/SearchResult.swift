//
//  SearchResult.swift
//  SilicIA
//
//  Created by Claude on 23/03/2026.
//

import Foundation

/// Represents one web search result returned by the search provider.
struct SearchResult: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let url: String
    let snippet: String
    let retrievedContent: String?
    /// Optional `NLEmbedding` similarity score `[0, 1]` between the user query and `snippet`.
    let snippetSimilarity: Double?
    /// True when the `NLEmbedding` similarity of `snippet` is below the relevance threshold,
    /// instructing downstream pipelines to skip downloading/scraping full content and assign `0%` used content.
    let isBelowRelevanceThreshold: Bool
    /// Optional raw page title returned by the `wiki_fast` API (`https://wikifast.trevalim.fr/`),
    /// used in Reader Mode to request `GET /articles/{page_title}` directly.
    let wikiFastTitle: String?

    /// Creates a search result with title, URL and snippet metadata.
    init(
        id: UUID = UUID(),
        title: String,
        url: String,
        snippet: String,
        retrievedContent: String? = nil,
        snippetSimilarity: Double? = nil,
        isBelowRelevanceThreshold: Bool = false,
        wikiFastTitle: String? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.snippet = snippet
        self.retrievedContent = retrievedContent
        self.snippetSimilarity = snippetSimilarity
        self.isBelowRelevanceThreshold = isBelowRelevanceThreshold
        self.wikiFastTitle = wikiFastTitle
    }
}

/// Wraps a full search response payload with metadata.
struct SearchResponse: Codable {
    let results: [SearchResult]
    let query: String
    let timestamp: Date
}
