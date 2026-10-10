import Foundation
import SwiftSoup

public enum SwiftSoupExtractor {
    /// Extracts the HTML of the `<body>` element.
    /// Optionally strips non-content tags (<script>, <style>, <svg>, <nav>, <header>, <footer>).
    public static func extractBodyHTML(_ html: String, cleanNonContent: Bool = true) throws -> String {
        let doc: Document = try SwiftSoup.parse(html)
        guard let body = doc.body() else {
            return html
        }
        
        if cleanNonContent {
            // Remove scripts, styles, SVGs, navs, headers, footers cleanly via DOM selectors
            try body.select("script, style, svg, nav, header, footer, noscript").remove()
        }
        
        return try body.html()
    }
    
    /// Directly extracts the text/markdown-like clean text from the body
    public static func extractBodyText(_ html: String) throws -> String {
        let doc: Document = try SwiftSoup.parse(html)
        guard let body = doc.body() else {
            return ""
        }
        try body.select("script, style, svg, nav, header, footer, noscript").remove()
        return try body.text()
    }
}
