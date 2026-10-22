//
//  WebSearchService.swift
//  SilicIA
//
//  Created by Claude on 23/03/2026.
//

import Foundation
import Combine
#if os(iOS)
import UIKit
#endif

@MainActor
/// Performs multi-provider web search and merges DuckDuckGo with Wikipedia REST results.
class WebSearchService: ObservableObject {
    @Published var isSearching = false
    @Published var error: Error?

    /// Default DuckDuckGo per-query cap when callers do not override.
    nonisolated static let defaultDuckDuckGoLimit = 6
    /// Default Wikipedia per-query cap when callers do not override.
    nonisolated static let defaultWikipediaLimit = 2

    /// Strip HTML tags and decode common HTML entities from a raw HTML string.
    nonisolated private static func htmlToPlainText(_ html: String) -> String {
        HTMLSanitizer.htmlToPlainText(html).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extract the inner HTML for the first element matching a class name and tag.
    /// The pattern is built from arguments, so it is not cached.
    nonisolated private static func extractInnerHTML(in html: String, className: String, tagName: String) -> String? {
        let escapedClassName = NSRegularExpression.escapedPattern(for: className)
        let escapedTagName = NSRegularExpression.escapedPattern(for: tagName)
        let pattern = "<\(escapedTagName)[^>]*class=\"[^\"]*\\b\(escapedClassName)\\b[^\"]*\"[^>]*>([\\s\\S]*?)</\(escapedTagName)>"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              let contentRange = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[contentRange])
    }

    nonisolated private static var userAgent: String {
        NetworkConstants.defaultUserAgent
    }

    private static let wikipediaPagePathAllowed: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return allowed
    }()

    private static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private let session: URLSession
    private let webScraper: WebScrapingService

    private nonisolated func debugLog(_ message: String) {
        #if DEBUG
        print("[WebSearchService] \(message)")
        #endif
    }

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 15
            config.waitsForConnectivity = true
            config.requestCachePolicy = .returnCacheDataElseLoad
            self.session = URLSession(configuration: config)
        }
        self.webScraper = WebScrapingService()
    }

    init(session: URLSession? = nil, webScraper: WebScrapingService) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 15
            config.waitsForConnectivity = true
            config.requestCachePolicy = .returnCacheDataElseLoad
            self.session = URLSession(configuration: config)
        }
        self.webScraper = webScraper
    }

    /// Search DuckDuckGo and Wikipedia, then merge deduplicated results.
    func search(
        query: String,
        maxDuckDuckGoResults: Int = defaultDuckDuckGoLimit,
        maxWikipediaResults: Int = defaultWikipediaLimit,
        language: ModelLanguage = .english,
        useDuckDuckGo: Bool = true,
        useWikipedia: Bool = true
    ) async throws -> [SearchResult] {
        guard !query.isEmpty else { return [] }

        debugLog("single-query search start: query=\(query), ddgLimit=\(maxDuckDuckGoResults), wikiLimit=\(maxWikipediaResults), language=\(language.rawValue), ddg=\(useDuckDuckGo), wiki=\(useWikipedia)")

        isSearching = true
        defer { isSearching = false }

        let results = try await executeSearch(
            query: query,
            maxDuckDuckGoResults: maxDuckDuckGoResults,
            maxWikipediaResults: maxWikipediaResults,
            language: language,
            useDuckDuckGo: useDuckDuckGo,
            useWikipedia: useWikipedia
        )

        debugLog("single-query search done with query: \"\(query)\" and result count=\(results.count)")

        return results
    }

    /// Executes multiple searches and interleaves deduplicated results across queries.
    func search(
        queries: [String],
        maxDuckDuckGoResultsPerQuery: Int = defaultDuckDuckGoLimit,
        maxWikipediaResultsPerQuery: Int = defaultWikipediaLimit,
        mergedLimit: Int = 10,
        language: ModelLanguage = .english,
        useDuckDuckGo: Bool = true,
        useWikipedia: Bool = true
    ) async throws -> [SearchResult] {
        let normalizedQueries = queries
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !normalizedQueries.isEmpty,
              (maxDuckDuckGoResultsPerQuery > 0 || maxWikipediaResultsPerQuery > 0),
              mergedLimit > 0 else {
            debugLog("multi-query search skipped: invalid input")
            return []
        }

        isSearching = true
        defer { isSearching = false }

        var uniqueQueries: [String] = []
        var seenQueryKeys = Set<String>()
        for query in normalizedQueries {
            let key = normalizeQueryKey(query)
            if seenQueryKeys.insert(key).inserted {
                uniqueQueries.append(query)
            }
        }

        debugLog(
            "multi-query search start: input=\(normalizedQueries.count), unique=\(uniqueQueries.count), ddgPerQuery=\(maxDuckDuckGoResultsPerQuery), wikiPerQuery=\(maxWikipediaResultsPerQuery), mergedLimit=\(mergedLimit), language=\(language.rawValue)"
        )

        var perQueryResults: [[SearchResult]] = []
        perQueryResults.reserveCapacity(uniqueQueries.count)
        var failedQueries = 0

        for query in uniqueQueries {
            do {
                let results = try await executeSearch(
                    query: query,
                    maxDuckDuckGoResults: maxDuckDuckGoResultsPerQuery,
                    maxWikipediaResults: maxWikipediaResultsPerQuery,
                    language: language,
                    useDuckDuckGo: useDuckDuckGo,
                    useWikipedia: useWikipedia
                )
                perQueryResults.append(results)
                debugLog("query ok: \(query) => \(results.count) results")
            } catch {
                failedQueries += 1
                debugLog("query failed: \(query) => \(error.localizedDescription)")
            }
        }

        if perQueryResults.isEmpty {
            debugLog("multi-query search failed: all queries failed")
            throw SearchError.networkError
        }

        let merged = mergeInterleavedDeduplicatedResults(perQueryResults, mergedLimit: mergedLimit)

        debugLog(
            "multi-query search done: merged=\(merged.count), failures=\(failedQueries)/\(uniqueQueries.count)"
        )

        return merged
    }

    /// Executes web (DuckDuckGo) and Wikipedia searches for specific separate query sets in parallel,
    /// merging and deduplicating results up to `mergedLimit`.
    func search(
        webQueries: [String],
        wikiQueries: [String],
        maxDuckDuckGoResults: Int = defaultDuckDuckGoLimit,
        maxWikipediaResults: Int = defaultWikipediaLimit,
        mergedLimit: Int = 10,
        language: ModelLanguage = .english,
        useDuckDuckGo: Bool = true,
        useWikipedia: Bool = true
    ) async throws -> [SearchResult] {
        let cleanWeb = useDuckDuckGo ? webQueries
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } : []
        let cleanWiki = useWikipedia ? wikiQueries
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } : []

        guard !cleanWeb.isEmpty || !cleanWiki.isEmpty else {
            debugLog("multi-source search skipped: no queries")
            return []
        }

        isSearching = true
        defer { isSearching = false }

        // Distribute limits per query so total results respect requested caps
        let webLimitPerQuery = max(1, maxDuckDuckGoResults / max(1, cleanWeb.count))
        let wikiLimitPerQuery = max(1, maxWikipediaResults / max(1, cleanWiki.count))

        debugLog(
            "multi-source search start: webQueries=\(cleanWeb), wikiQueries=\(cleanWiki), webLimitPerQuery=\(webLimitPerQuery), wikiLimitPerQuery=\(wikiLimitPerQuery), mergedLimit=\(mergedLimit), language=\(language.rawValue)"
        )

        var perQueryResults: [[SearchResult]] = []
        var failures: [String] = []

        await withTaskGroup(of: (query: String, isWiki: Bool, result: Result<[SearchResult], Error>).self) { group in
            for query in cleanWeb {
                group.addTask {
                    do {
                        let res = try await self.executeDuckDuckGoSearch(query: query, maxResults: webLimitPerQuery)
                        return (query, false, .success(res))
                    } catch {
                        return (query, false, .failure(error))
                    }
                }
            }
            for query in cleanWiki {
                group.addTask {
                    do {
                        let res = try await self.executeWikipediaSearch(query: query, language: language, limit: wikiLimitPerQuery)
                        return (query, true, .success(res))
                    } catch {
                        return (query, true, .failure(error))
                    }
                }
            }

            for await (q, isWiki, res) in group {
                switch res {
                case .success(let items):
                    perQueryResults.append(items)
                    self.debugLog("\(isWiki ? "wiki" : "web") query ok: \"\(q)\" => \(items.count) results")
                case .failure(let err):
                    failures.append("\(q) (\(err.localizedDescription))")
                    self.debugLog("\(isWiki ? "wiki" : "web") query failed: \"\(q)\" => \(err.localizedDescription)")
                }
            }
        }

        if perQueryResults.isEmpty && !failures.isEmpty && failures.count == (cleanWeb.count + cleanWiki.count) {
            debugLog("multi-source search failed: all queries failed")
            throw SearchError.networkError
        }

        let merged = mergeInterleavedDeduplicatedResults(perQueryResults, mergedLimit: mergedLimit)
        debugLog("multi-source search done: merged=\(merged.count), failures=\(failures.count)/\(cleanWeb.count + cleanWiki.count)")
        return merged
    }

    /// Runs the enabled providers for one query and merges deduplicated results.
    private func executeSearch(
        query: String,
        maxDuckDuckGoResults: Int,
        maxWikipediaResults: Int,
        language: ModelLanguage,
        useDuckDuckGo: Bool = true,
        useWikipedia: Bool = true
    ) async throws -> [SearchResult] {
        guard !query.isEmpty else { return [] }
        guard useDuckDuckGo || useWikipedia else { return [] }

        async let duckDuckGoOutcome: ([SearchResult], Error?) = {
            guard useDuckDuckGo else { return ([], nil) }
            do {
                let results = try await executeDuckDuckGoSearch(query: query, maxResults: maxDuckDuckGoResults)
                return (results, nil)
            } catch {
                return ([], error)
            }
        }()

        async let wikipediaOutcome: ([SearchResult], Error?) = {
            guard useWikipedia else { return ([], nil) }
            do {
                let results = try await executeWikipediaSearch(
                    query: query,
                    language: language,
                    limit: maxWikipediaResults
                )
                return (results, nil)
            } catch {
                return ([], error)
            }
        }()

        let (duckDuckGoResults, duckDuckGoError) = await duckDuckGoOutcome
        let (wikipediaResults, wikipediaError) = await wikipediaOutcome

        if let duckDuckGoError {
            debugLog("DuckDuckGo search failed for query=\(query): \(duckDuckGoError.localizedDescription)")
        }
        if let wikipediaError {
            debugLog("Wikipedia search failed for query=\(query): \(wikipediaError.localizedDescription)")
        }

        let mergedProviders = mergeInterleavedDeduplicatedResults(
            [duckDuckGoResults, wikipediaResults],
            mergedLimit: maxDuckDuckGoResults + maxWikipediaResults
        )

        if mergedProviders.isEmpty {
            // Only surface an error when an enabled provider actually failed.
            // If providers succeeded but returned zero results, return [] so the
            // caller can show "No results found" rather than "Network error".
            let providerError = (useDuckDuckGo ? duckDuckGoError : nil)
                ?? (useWikipedia ? wikipediaError : nil)
            if let providerError {
                throw providerError
            }
            return []
        }

        return mergedProviders
    }

    /// Executes DuckDuckGo HTML search.
    private func executeDuckDuckGoSearch(query: String, maxResults: Int) async throws -> [SearchResult] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://html.duckduckgo.com/html/?q=\(encodedQuery)"

        guard let url = URL(string: urlString) else {
            throw SearchError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SearchError.invalidResponse
        }

        let results = try parseDuckDuckGoHTMLResults(from: data)
        return Array(results.prefix(maxResults))
    }

    /// Executes a search on DuckDuckGo and returns results.
    func searchDuckDuckGo(query: String, limit: Int = defaultDuckDuckGoLimit) async throws -> [SearchResult] {
        try await executeDuckDuckGoSearch(query: query, maxResults: limit)
    }

    /// Executes a search on Wikipedia using the REST API and converts article HTML to Markdown.
    func searchWikipedia(query: String, language: ModelLanguage = .english, limit: Int = defaultWikipediaLimit) async throws -> [SearchResult] {
        try await executeWikipediaSearch(query: query, language: language, limit: limit)
    }

    /// Extracts the language and article key from a Wikipedia URL, filtering out non-article namespaces and URL fragments.
    nonisolated static func extractWikipediaArticleKey(
        from rawURL: String,
        fallbackLanguage: ModelLanguage = .english
    ) -> (language: ModelLanguage, key: String)? {
        let withoutFragment = rawURL.components(separatedBy: "#").first ?? rawURL
        let trimmed = withoutFragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }

        guard let host = url.host?.lowercased(), host.contains("wikipedia.org") else {
            return nil
        }

        // Extract language from subdomain (e.g. fr.wikipedia.org -> .french, es.m.wikipedia.org -> .spanish)
        let hostParts = host.components(separatedBy: ".")
        var extractedLang: ModelLanguage?
        for part in hostParts {
            switch part.lowercased() {
            case "fr": extractedLang = .french
            case "es": extractedLang = .spanish
            case "en": extractedLang = .english
            default: break
            }
            if extractedLang != nil { break }
        }
        let language = extractedLang ?? fallbackLanguage

        // Path must start with /wiki/
        let path = url.path
        guard path.hasPrefix("/wiki/") else {
            return nil
        }

        let rawKey = String(path.dropFirst("/wiki/".count))
        guard !rawKey.isEmpty else { return nil }

        let decodedKey = (rawKey.removingPercentEncoding ?? rawKey)
            .replacingOccurrences(of: " ", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !decodedKey.isEmpty else { return nil }

        // Ignore non-article namespaces across supported languages
        let lowerKey = decodedKey.lowercased()
        let ignoredPrefixes = [
            "special:", "spécial:", "especial:",
            "file:", "fichier:", "archivo:", "image:", "imagen:",
            "help:", "aide:", "ayuda:",
            "talk:", "discussion:", "discusión:",
            "category:", "catégorie:", "categoría:",
            "portal:", "portail:",
            "template:", "modèle:", "plantilla:",
            "wikipedia:", "wikipédia:",
            "user:", "utilisateur:", "usuario:",
            "draft:", "projet:", "proyecto:"
        ]
        for prefix in ignoredPrefixes {
            if lowerKey.hasPrefix(prefix) {
                return nil
            }
        }

        return (language: language, key: decodedKey)
    }

    /// Executes Wikipedia search:
    /// Uses DuckDuckGo to discover candidate Wikipedia article URLs ("site:wikipedia.org " + query),
    /// extracts article keys from the URLs, and fetches the clean article content via the
    /// MediaWiki REST API (/w/rest.php/v1/page/{key}/with_html) converted to Markdown.
    /// Does not scrape raw Wikipedia HTML webpages.
    private func executeWikipediaSearch(query: String, language: ModelLanguage, limit: Int) async throws -> [SearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        let targetLimit = max(1, limit)
        let ddgWikiQuery = "site:wikipedia.org \(trimmedQuery)"
        var articleCandidates: [(language: ModelLanguage, key: String, ddgTitle: String, ddgSnippet: String)] = []
        var seenKeys = Set<String>()

        debugLog("Wikipedia DDG search start: query=\(ddgWikiQuery), limit=\(targetLimit), language=\(language.rawValue)")

        do {
            let ddgResults = try await executeDuckDuckGoSearch(query: ddgWikiQuery, maxResults: max(targetLimit * 3, 10))
            for result in ddgResults {
                if let extracted = Self.extractWikipediaArticleKey(from: result.url, fallbackLanguage: language) {
                    let dedupeKey = "\(extracted.language.code):\(extracted.key.lowercased())"
                    if seenKeys.insert(dedupeKey).inserted {
                        articleCandidates.append((
                            language: extracted.language,
                            key: extracted.key,
                            ddgTitle: result.title,
                            ddgSnippet: result.snippet
                        ))
                        if articleCandidates.count >= targetLimit {
                            break
                        }
                    }
                }
            }
        } catch {
            debugLog("DuckDuckGo wikipedia site search failed or hit challenge: \(error.localizedDescription)")
        }

        // Fallback: if DuckDuckGo yielded 0 Wikipedia candidates (due to bot challenge, rate limit, or no matches),
        // fallback to direct title lookup via MediaWiki API.
        if articleCandidates.isEmpty {
            let directKey = trimmedQuery.replacingOccurrences(of: " ", with: "_")
            articleCandidates.append((
                language: language,
                key: directKey,
                ddgTitle: trimmedQuery,
                ddgSnippet: "Wikipedia page"
            ))
        }

        // Fetch each candidate article via MediaWiki REST API (/w/rest.php/v1/page/{key}/with_html) concurrently
        var detailsByKey: [String: (title: String, markdown: String, url: String)] = [:]
        await withTaskGroup(of: (String, (title: String, markdown: String, url: String)?).self) { group in
            for candidate in articleCandidates {
                let candidateKey = "\(candidate.language.code):\(candidate.key)"
                group.addTask {
                    let page = await self.fetchWikipediaPageDetails(for: candidate.key, language: candidate.language)
                    return (candidateKey, page)
                }
            }
            for await (key, page) in group {
                if let page {
                    detailsByKey[key] = page
                }
            }
        }

        var searchResults: [SearchResult] = []
        for candidate in articleCandidates {
            let candidateKey = "\(candidate.language.code):\(candidate.key)"
            if let details = detailsByKey[candidateKey],
               !details.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let leadSnippet = details.markdown
                    .components(separatedBy: "\n\n")
                    .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                    ?? candidate.ddgSnippet

                searchResults.append(
                    SearchResult(
                        title: details.title.isEmpty ? candidate.ddgTitle : details.title,
                        url: details.url,
                        snippet: leadSnippet,
                        retrievedContent: details.markdown
                    )
                )

                if searchResults.count >= targetLimit {
                    break
                }
            }
        }

        // Secondary fallback: if candidate lookups returned no valid article content (e.g. DDG was challenged and direct key 404'd),
        // query MediaWiki search API as resilient fallback to resolve keys, then fetch full HTML via REST API.
        if searchResults.isEmpty {
            let directKey = trimmedQuery.replacingOccurrences(of: " ", with: "_")
            if let directPage = await fetchWikipediaPageDetails(for: directKey, language: language),
               !directPage.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let leadSnippet = directPage.markdown
                    .components(separatedBy: "\n\n")
                    .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                    ?? directPage.title
                searchResults.append(
                    SearchResult(
                        title: directPage.title,
                        url: directPage.url,
                        snippet: leadSnippet,
                        retrievedContent: directPage.markdown
                    )
                )
            } else if let fallbackKeys = await fetchWikipediaFallbackKeys(query: trimmedQuery, language: language, limit: targetLimit) {
                for key in fallbackKeys {
                    if let page = await fetchWikipediaPageDetails(for: key, language: language),
                       !page.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let leadSnippet = page.markdown
                            .components(separatedBy: "\n\n")
                            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                            ?? page.title
                        searchResults.append(
                            SearchResult(
                                title: page.title,
                                url: page.url,
                                snippet: leadSnippet,
                                retrievedContent: page.markdown
                            )
                        )
                        if searchResults.count >= targetLimit {
                            break
                        }
                    }
                }
            }
        }

        debugLog("Wikipedia DDG search completed: found \(searchResults.count) article(s)")
        return searchResults
    }

    /// Resilient fallback to resolve article keys when DuckDuckGo is blocked or returns 0 results.
    private func fetchWikipediaFallbackKeys(query: String, language: ModelLanguage, limit: Int) async -> [String]? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = wikipediaHost(for: language)
        components.path = "/w/rest.php/v1/search/page"
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "\(max(1, limit))")
        ]
        guard let url = components.url else { return nil }

        do {
            var request = URLRequest(url: url)
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            let decoded = try Self.jsonDecoder.decode(WikipediaSearchFallbackResponse.self, from: data)
            return decoded.pages.map(\.key)
        } catch {
            debugLog("Wikipedia fallback search API failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Calls MediaWiki /w/rest.php/v1/page/{key}/with_html and converts article HTML to Markdown.
    private func fetchWikipediaPageDetails(for key: String, language: ModelLanguage) async -> (title: String, markdown: String, url: String)? {
        guard let pageURL = wikipediaWithHTMLURL(key: key, language: language) else {
            return nil
        }

        do {
            var request = URLRequest(url: pageURL)
            request.setValue("MediaWiki REST API docs examples/0.1 (https://www.mediawiki.org/wiki/API_talk:REST_API)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            let parsed = try Self.jsonDecoder.decode(WikipediaWithHTMLResponse.self, from: data)
            let pageKey = parsed.key ?? key
            let title = (parsed.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? parsed.title!
                : pageKey.replacingOccurrences(of: "_", with: " ")
            let readableURL = wikipediaReadablePageURL(for: pageKey, language: language)

            let markdown: String
            if let html = parsed.html, !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                markdown = await convertWikipediaHTMLToMarkdown(html, pageURL: URL(string: readableURL))
            } else {
                markdown = ""
            }

            return (title: title, markdown: markdown, url: readableURL)
        } catch {
            debugLog("Wikipedia page fetch failed for key=\(key): \(error.localizedDescription)")
            return nil
        }
    }

    /// Converts raw Wikipedia article HTML into clean Markdown via WebScrapingService,
    /// with plain-text fallback. Guarantees no raw HTML tags reach RAG chunks or prompts.
    private func convertWikipediaHTMLToMarkdown(_ html: String, pageURL: URL?) async -> String {
        do {
            let (_, extractedMD) = try await webScraper.extractMarkdown(from: html, baseURL: pageURL)
            let trimmed = extractedMD.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        } catch {
            debugLog("Markdown extraction via WebScrapingService failed for Wikipedia page: \(error.localizedDescription)")
        }
        return HTMLSanitizer.htmlToPlainTextWithStructure(html)
    }

    /// Interleaves result lists, removing duplicate URLs, up to the provided limit.
    private func mergeInterleavedDeduplicatedResults(
        _ perQueryResults: [[SearchResult]],
        mergedLimit: Int
    ) -> [SearchResult] {
        guard mergedLimit > 0 else { return [] }

        var merged: [SearchResult] = []
        merged.reserveCapacity(mergedLimit)

        var seenURLKeys = Set<String>()
        var index = 0

        while merged.count < mergedLimit {
            var addedInRound = false

            for queryResults in perQueryResults where index < queryResults.count {
                let candidate = queryResults[index]
                let urlKey = normalizeURLKey(candidate.url)
                if seenURLKeys.insert(urlKey).inserted {
                    merged.append(candidate)
                    addedInRound = true
                    if merged.count == mergedLimit {
                        break
                    }
                }
            }

            // All providers exhausted: index now points at or past the last
            // element of every list, so further rounds cannot add anything.
            if perQueryResults.allSatisfy({ index >= $0.count }) {
                break
            }
            // Defensive fallback: nothing added this round and there is
            // nothing left to consider — also exhausted.
            if !addedInRound && perQueryResults.allSatisfy({ index >= $0.count }) {
                break
            }

            index += 1
        }

        return merged
    }

    /// Normalizes a query to support case-insensitive deduplication.
    private func normalizeQueryKey(_ query: String) -> String {
        query
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Normalizes URLs for deduplication while preserving path/query specificity.
    private func normalizeURLKey(_ rawURL: String) -> String {
        guard var components = URLComponents(string: rawURL) else {
            return rawURL
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }

        components.fragment = nil
        let scheme = (components.scheme ?? "https").lowercased()
        let host = (components.host ?? "").lowercased()
        let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        return "\(scheme)://\(host)\(path)\(query)"
    }

    /// Parse DuckDuckGo HTML response.
    private func parseDuckDuckGoHTMLResults(from data: Data) throws -> [SearchResult] {
        guard let html = String(data: data, encoding: .utf8) else {
            throw SearchError.parsingFailed
        }

        if html.contains("anomaly-modal") || html.contains("anomaly.js") || html.contains("bots use DuckDuckGo too") {
            throw SearchError.botChallengeDetected
        }

        var results: [SearchResult] = []
        let components = html.components(separatedBy: "class=\"result__a\"")

        for i in 1..<min(components.count, 21) {
            let component = components[i]

            guard let hrefRange = component.range(of: "href=\""),
                  let hrefEndRange = component.range(of: "\"", range: hrefRange.upperBound..<component.endIndex) else {
                continue
            }
            let url = String(component[hrefRange.upperBound..<hrefEndRange.lowerBound])

            guard let titleStart = component.range(of: ">"),
                  let titleEnd = component.range(of: "</a>", range: titleStart.upperBound..<component.endIndex) else {
                continue
            }
            let title = Self.htmlToPlainText(String(component[titleStart.upperBound..<titleEnd.lowerBound]))

            let snippetHTML = Self.extractInnerHTML(in: component, className: "result__snippet", tagName: "a")
                ?? Self.extractInnerHTML(in: component, className: "result__snippet", tagName: "div")
                ?? ""
            let snippet = Self.htmlToPlainText(snippetHTML)

            let cleanURL = url.hasPrefix("//duckduckgo.com/l/?") ? extractActualURL(from: url) : url

            results.append(SearchResult(
                title: title.isEmpty ? "Result \(i)" : title,
                url: cleanURL,
                snippet: snippet.isEmpty ? "No description available" : snippet
            ))
        }

        return results
    }

    /// Extract actual URL from DuckDuckGo redirect.
    private func extractActualURL(from ddgURL: String) -> String {
        guard let uddParam = ddgURL.components(separatedBy: "uddg=").last,
              let actualURL = uddParam.components(separatedBy: "&").first,
              let decoded = actualURL.removingPercentEncoding else {
            return ddgURL
        }
        return decoded
    }

    private func wikipediaWithHTMLURL(key: String, language: ModelLanguage) -> URL? {
        let decodedKey = key.removingPercentEncoding ?? key
        guard let encodedKey = decodedKey.addingPercentEncoding(withAllowedCharacters: Self.wikipediaPagePathAllowed) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = wikipediaHost(for: language)
        components.percentEncodedPath = "/w/rest.php/v1/page/\(encodedKey)/with_html"
        return components.url
    }

    private func wikipediaReadablePageURL(for key: String, language: ModelLanguage) -> String {
        let decodedKey = key.removingPercentEncoding ?? key
        let encodedKey = decodedKey.addingPercentEncoding(withAllowedCharacters: Self.wikipediaPagePathAllowed) ?? key
        return "https://\(wikipediaHost(for: language))/wiki/\(encodedKey)"
    }

    private func wikipediaHost(for language: ModelLanguage) -> String {
        switch language {
        case .french: return "fr.wikipedia.org"
        case .spanish: return "es.wikipedia.org"
        case .english: return "en.wikipedia.org"
        }
    }
}

private struct WikipediaWithHTMLResponse: Decodable {
    let id: Int?
    let key: String?
    let title: String?
    let html: String?
}

private struct WikipediaSearchFallbackResponse: Decodable {
    let pages: [WikipediaSearchFallbackPage]
}

private struct WikipediaSearchFallbackPage: Decodable {
    let key: String
}

/// Enumerates high-level search failure categories.
enum SearchError: LocalizedError {
    case invalidURL
    case invalidResponse
    case parsingFailed
    case networkError
    case botChallengeDetected

    /// Provides user-facing descriptions for search errors.
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid search URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .parsingFailed:
            return "Failed to parse search results"
        case .networkError:
            return "Network error occurred"
        case .botChallengeDetected:
            return "Search provider bot challenge detected"
        }
    }
}
