//
//  test.swift
//  TestRAG
//
//  Direct CLI test runner for SilicIA SearchSourcesTool, RAGChunker,
//  and RAGContextService ranking.
//

import Foundation
@testable import SilicIA

final class CapturedResultsBox: @unchecked Sendable {
    var results: [SearchResult] = []
}

@main
struct TestRAGMain {
    @MainActor
    static func main() async throws {
        print("🚀 Starting TestRAG CLI runner...")

        let query = "distance euclidienne"
        let folderURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

        let webSearchService = WebSearchService()
        let webScraper = WebScrapingService()
        let ragContextService = RAGContextService()

        let box = CapturedResultsBox()

        // Configure SourceFunnel for Wikipedia search (max results = 1)
        var funnel = SourceFunnel(
            webSearchService: webSearchService,
            webScraper: webScraper,
            ragContextService: ragContextService,
            userQuery: query,
            language: .french,
            maxDuckDuckGoResults: 0,
            maxWikipediaResults: 1,
            useDuckDuckGo: false,
            useWikipedia: true,
            responseTokens: 1000,
            contextUtilizationFactor: 0.65
        )
        funnel.onResults = { results in
            box.results = results
        }

        print("📡 Calling SearchSourcesTool for wiki query: '\(query)' (max results = 1)...")
        let tool = SearchSourcesTool(funnel: funnel)
        let args = SearchSourcesTool.Arguments(webQueries: [], wikiQueries: [query])

        let toolOutput = try await tool.call(arguments: args)

        guard let firstResult = box.results.first else {
            print("❌ No search results captured from SearchSourcesTool.")
            return
        }

        let articleMarkdown = firstResult.retrievedContent ?? firstResult.snippet
        guard !articleMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("❌ Retrieved article markdown is empty.")
            return
        }

        // 1. Save Wikipedia Markdown to file
        let markdownFileName = "wiki_\(query.replacingOccurrences(of: " ", with: "_")).md"
        let markdownFileURL = folderURL.appendingPathComponent(markdownFileName)
        try articleMarkdown.write(to: markdownFileURL, atomically: true, encoding: .utf8)
        print("✅ Saved article Markdown (\(articleMarkdown.count) chars) to: \(markdownFileURL.path)")

        // 2. Use RAGChunker to chunk the article
        print("\n🧩 Chunking article into paragraphs and tables via RAGChunker...")
        let chunkStart = Date()
        let chunks = RAGChunker.chunkParagraphs(
            text: articleMarkdown,
            source: firstResult.title,
            url: firstResult.url
        )
        let chunkDuration = Date().timeIntervalSince(chunkStart)
        print(String(format: "✅ Chunked into %d chunks in %.3f s (%.2f ms)", chunks.count, chunkDuration, chunkDuration * 1000.0))

        // 3. Rank chunks via RAGContextService
        print("\n📊 Ranking chunks with RAGContextService (DCT/Cosine + NLEmbedding)...")
        let rankStart = Date()
        let selectionResult = await ragContextService.selectContext(
            chunks: chunks,
            query: query,
            historyTokens: 0,
            maxOutputTokens: 1000,
            contextUtilizationFactor: 0.65,
            queries: [query],
            language: .french
        )
        let rankDuration = Date().timeIntervalSince(rankStart)
        print(String(format: "✅ Ranking finished in %.3f s (%.2f ms)", rankDuration, rankDuration * 1000.0))
        print("   Total chunks: \(chunks.count)")
        print("   Ranked candidates: \(selectionResult.rankedChunks.count)")
        print("   Selected chunks fitting window: \(selectionResult.selectedChunks.count)")

        // 4. Save chunks and ranking results to file
        let rankedFileName = "ranked_chunks_\(query.replacingOccurrences(of: " ", with: "_")).txt"
        let rankedFileURL = folderURL.appendingPathComponent(rankedFileName)

        var reportLines: [String] = []
        reportLines.append("================================================================================")
        reportLines.append("TestRAG Ranking Report")
        reportLines.append("Query: \(query)")
        reportLines.append("Source: \(firstResult.title) (\(firstResult.url))")
        reportLines.append("Total Chunks: \(chunks.count)")
        reportLines.append("Ranked Candidates (Stage 2): \(selectionResult.rankedChunks.count)")
        reportLines.append("Selected Chunks (Final Window): \(selectionResult.selectedChunks.count)")
        reportLines.append("================================================================================\n")

        reportLines.append("--- SELECTED CHUNKS IN CONTEXT WINDOW (TOP RANKED) ---")
        for (i, ranked) in selectionResult.selectedChunks.enumerated() {
            reportLines.append(String(format: "\n[Rank #%d] Score: %.4f | Length: %d chars", i + 1, ranked.relevanceScore, ranked.chunk.text.count))
            reportLines.append("Source: \(ranked.chunk.source)")
            if let url = ranked.chunk.url {
                reportLines.append("URL: \(url)")
            }
            reportLines.append("Content:\n\(ranked.chunk.text)")
            reportLines.append("--------------------------------------------------------------------------------")
        }

        reportLines.append("\n\n--- ALL RANKED CANDIDATES (STAGE 2) ---")
        for (i, ranked) in selectionResult.rankedChunks.enumerated() {
            let isSelected = selectionResult.selectedChunks.contains(where: { $0.chunk.id == ranked.chunk.id })
            reportLines.append(String(format: "[#%02d] Score: %.4f | Selected: %@ | %d chars | Preview: %@",
                i + 1,
                ranked.relevanceScore,
                isSelected ? "YES" : "NO ",
                ranked.chunk.text.count,
                String(ranked.chunk.text.replacingOccurrences(of: "\n", with: " ").prefix(80))
            ))
        }

        reportLines.append("\n\n--- ALL INITIAL CHUNKS FROM RAGCHUNKER ---")
        for (i, chunk) in chunks.enumerated() {
            reportLines.append(String(format: "[Chunk #%03d] %d chars | Preview: %@",
                i + 1,
                chunk.text.count,
                String(chunk.text.replacingOccurrences(of: "\n", with: " ").prefix(80))
            ))
        }

        reportLines.append("\n\n--- TOOL OUTPUT RETURNED TO MODEL ---")
        reportLines.append(toolOutput)

        let reportContent = reportLines.joined(separator: "\n")
        try reportContent.write(to: rankedFileURL, atomically: true, encoding: .utf8)
        print("✅ Saved full ranking report to: \(rankedFileURL.path)")
        print("\n🎉 Test completed successfully!")
    }
}
