import Foundation
import NeoLeeReadability
import HTMLToMarkdown

public enum NeoLeeReadabilityExtractor {
    public struct ExtractionResult: Sendable {
        public let title: String
        public let textContent: String
        public let contentHTML: String
        public let markdown: String
        public let extractMs: Double
        public let markdownConvertMs: Double
        public let totalMs: Double
    }
    
    public static func extractAndConvert(
        html: String,
        baseURL: URL? = nil
    ) throws -> ExtractionResult {
        let totalStart = CFAbsoluteTimeGetCurrent()
        
        let extractStart = CFAbsoluteTimeGetCurrent()
        let readability = try Readability(html: html, baseURL: baseURL)
        let result = try readability.parse()
        let extractMs = (CFAbsoluteTimeGetCurrent() - extractStart) * 1000.0
        
        let convStart = CFAbsoluteTimeGetCurrent()
        let markdown: String
        if !result.content.isEmpty {
            markdown = (try? HTMLToMarkdown.convert(result.content, plugins: [
                BasePlugin(),
                CommonmarkPlugin(),
                GFMPlugin()
            ])) ?? result.textContent
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
