import Foundation
import WebKit
import HTMLToMarkdown

public enum WKWebViewInnerTextExtractor {
    public struct ExtractionResult: Sendable {
        public let rawText: String
        public let markdown: String
        public let extractMs: Double
        public let markdownConvertMs: Double
        public let totalMs: Double
    }
    
    private final class NavigationDelegate: NSObject, WKNavigationDelegate {
        var continuation: CheckedContinuation<Void, Error>?
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            continuation?.resume()
            continuation = nil
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
    
    @MainActor
    public static func extractAndConvert(
        html: String,
        baseURL: URL? = nil
    ) async throws -> ExtractionResult {
        let totalStart = CFAbsoluteTimeGetCurrent()
        
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webpagePreferences = WKWebpagePreferences()
        webpagePreferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = webpagePreferences
        
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1200, height: 2000), configuration: configuration)
        let navDelegate = NavigationDelegate()
        webView.navigationDelegate = navDelegate
        
        let extractStart = CFAbsoluteTimeGetCurrent()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            navDelegate.continuation = continuation
            webView.loadHTMLString(html, baseURL: baseURL)
        }
        
        // Settle briefly for layout rendering
        try? await Task.sleep(nanoseconds: 50_000_000)
        
        let evaluated = try? await webView.evaluateJavaScript("document.body.innerText") as? String
        let pageText = evaluated?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let extractMs = (CFAbsoluteTimeGetCurrent() - extractStart) * 1000.0
        
        let convStart = CFAbsoluteTimeGetCurrent()
        let markdown: String
        if !pageText.isEmpty {
            do {
                markdown = try HTMLToMarkdown.convert(pageText, plugins: [
                    BasePlugin(),
                    CommonmarkPlugin(),
                    GFMPlugin()
                ])
            } catch {
                markdown = pageText
            }
        } else {
            markdown = ""
        }
        let markdownConvertMs = (CFAbsoluteTimeGetCurrent() - convStart) * 1000.0
        let totalMs = (CFAbsoluteTimeGetCurrent() - totalStart) * 1000.0
        
        return ExtractionResult(
            rawText: pageText,
            markdown: markdown,
            extractMs: extractMs,
            markdownConvertMs: markdownConvertMs,
            totalMs: totalMs
        )
    }
}
