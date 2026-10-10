import Foundation
import Readability
import HTMLToMarkdown

public enum SwiftReadabilityExtractor {
    public struct ExtractionResult: Sendable {
        public let title: String
        public let textContent: String
        public let contentHTML: String
        public let markdown: String
        public let extractMs: Double
        public let markdownConvertMs: Double
        public let totalMs: Double
    }
    
    @MainActor
    private static let readability = Readability()
    
    @MainActor
    public static func extractAndConvert(
        html: String,
        baseURL: URL? = nil
    ) async throws -> ExtractionResult {
        let totalStart = CFAbsoluteTimeGetCurrent()
        
        let extractStart = CFAbsoluteTimeGetCurrent()
        let result = try await readability.parse(html: html, options: nil, baseURL: baseURL)
        let extractMs = (CFAbsoluteTimeGetCurrent() - extractStart) * 1000.0
        
        let convStart = CFAbsoluteTimeGetCurrent()
        let markdown: String
        if !result.content.isEmpty {
            markdown = try HTMLToMarkdown.convert(result.content, plugins: [
                BasePlugin(),
                CommonmarkPlugin(),
                GFMPlugin()
            ])
        } else if !result.textContent.isEmpty {
            markdown = result.textContent
        } else {
            markdown = ""
        }
        let markdownConvertMs = (CFAbsoluteTimeGetCurrent() - convStart) * 1000.0
        let totalMs = (CFAbsoluteTimeGetCurrent() - totalStart) * 1000.0
        
        return ExtractionResult(
            title: result.title,
            textContent: result.textContent,
            contentHTML: result.content,
            markdown: markdown,
            extractMs: extractMs,
            markdownConvertMs: markdownConvertMs,
            totalMs: totalMs
        )
    }
    
    @MainActor
    public static func extractAndConvert(
        url: URL
    ) async throws -> ExtractionResult {
        let totalStart = CFAbsoluteTimeGetCurrent()
        
        let extractStart = CFAbsoluteTimeGetCurrent()
        let result = try await readability.parse(url: url, options: nil)
        let extractMs = (CFAbsoluteTimeGetCurrent() - extractStart) * 1000.0
        
        let convStart = CFAbsoluteTimeGetCurrent()
        let markdown: String
        if !result.content.isEmpty {
            markdown = try HTMLToMarkdown.convert(result.content, plugins: [
                BasePlugin(),
                CommonmarkPlugin(),
                GFMPlugin()
            ])
        } else if !result.textContent.isEmpty {
            markdown = result.textContent
        } else {
            markdown = ""
        }
        let markdownConvertMs = (CFAbsoluteTimeGetCurrent() - convStart) * 1000.0
        let totalMs = (CFAbsoluteTimeGetCurrent() - totalStart) * 1000.0
        
        return ExtractionResult(
            title: result.title,
            textContent: result.textContent,
            contentHTML: result.content,
            markdown: markdown,
            extractMs: extractMs,
            markdownConvertMs: markdownConvertMs,
            totalMs: totalMs
        )
    }
}
