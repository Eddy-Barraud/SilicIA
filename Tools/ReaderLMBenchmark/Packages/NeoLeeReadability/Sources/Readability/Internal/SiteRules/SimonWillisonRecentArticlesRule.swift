import Foundation
import SwiftSoup

/// Removes Simon Willison quote-page "Recent articles" and secondary metabox chrome.
///
/// SiteRule Metadata:
/// - Scope: simonwillison.net quote-page tail modules
/// - Phase: `postProcess` cleanup
/// - Trigger: `simonwillison.net` quote page with `div.recent-articles` and `#secondary .metabox`
/// - Evidence: `CLI/.staging/simonwillison-5`
/// - Risk if misplaced: site navigation and tag rails remain in extracted body
enum SimonWillisonRecentArticlesRule: ArticleCleanerSiteRule {
    static let id = "simonwillison-recent-articles"

    static func apply(to articleContent: Element, context _: ArticleCleanerSiteRuleContext) throws {
        let quoteMetaText = ((try? articleContent.select("div#secondary").first()?.text()) ?? "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let hasQuoteMeta = quoteMetaText.contains("this is a quotation collected by simon willison")
        guard hasQuoteMeta else { return }

        for recent in try articleContent.select("div#primary > div").reversed() {
            let heading = ((try? recent.select("> h2").first()?.text()) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard heading == "recent articles" else { continue }
            try recent.remove()
        }

        for secondary in try articleContent.select("div#secondary").reversed() {
            let summary = ((try? DOMHelpers.getInnerText(secondary)) ?? "")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let hasQuoteMeta = summary.contains("this is a quotation collected by simon willison")
            let hasTagLinks = (try? secondary.select("a[rel=tag]").isEmpty()) == false
            guard hasQuoteMeta || hasTagLinks else { continue }
            try secondary.remove()
        }
    }
}
