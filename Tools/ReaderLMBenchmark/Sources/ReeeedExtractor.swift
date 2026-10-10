import Foundation
import Reeeed
import HTMLToMarkdown

public enum ReeeedExtractor {
    public struct ExtractionResult {
        public let title: String?
        public let contentHTML: String
        public let markdown: String
        public let plainText: String
        public let extractMs: Double
        public let markdownConvertMs: Double
        public let totalMs: Double
    }
    
    public static func extractAndConvert(
        html: String,
        url: URL,
        extractor: Extractor = .mercury
    ) async throws -> ExtractionResult {
        let totalStart = CFAbsoluteTimeGetCurrent()
        
        let extractStart = CFAbsoluteTimeGetCurrent()
        let extracted = try await Reeeed.extractArticleContent(url: url, html: html, extractor: extractor)
        let extractMs = (CFAbsoluteTimeGetCurrent() - extractStart) * 1000.0
        
        let rawContent = extracted.content ?? ""
        let plainText = extracted.extractPlainText
        
        let convStart = CFAbsoluteTimeGetCurrent()
        var markdown = ""
        if !rawContent.isEmpty {
            markdown = (try? HTMLToMarkdown.convert(rawContent, plugins: [
                BasePlugin(),
                CommonmarkPlugin(),
                GFMPlugin()
            ])) ?? plainText
        } else {
            markdown = plainText
        }
        let markdownConvertMs = (CFAbsoluteTimeGetCurrent() - convStart) * 1000.0
        
        let totalMs = (CFAbsoluteTimeGetCurrent() - totalStart) * 1000.0
        
        return ExtractionResult(
            title: extracted.title,
            contentHTML: rawContent,
            markdown: markdown,
            plainText: plainText,
            extractMs: extractMs,
            markdownConvertMs: markdownConvertMs,
            totalMs: totalMs
        )
    }
}
