import Foundation
import SwiftSoup

/// Removes the mobile date eyebrow from simonwillison.net pages.
///
/// simonwillison.net renders a per-post-type date line in
/// `p.mobile-date-eyebrow` (e.g. "20th July 2026",
/// "20th July 2026 - Link Blog"). This is site metadata — invisible on
/// desktop and redundant with the publication date already in `<meta>` and
/// the entry footer. Removing it gives all post types a consistent, clean
/// start at the article body.
///
/// SiteRule Metadata:
/// - Scope: simonwillison.net mobile date eyebrow
/// - Phase: `unwantedElements` cleanup
/// - Trigger: `p.mobile-date-eyebrow`
/// - Evidence: `CLI/.staging/simonwillison-7`, `CLI/.staging/simonwillison-8`
/// - Risk if misplaced: date lines remain in extracted article body
enum SimonWillisonMobileDateEyebrowRule: ArticleCleanerSiteRule {
    static let id = "simonwillison-mobile-date-eyebrow"

    static func apply(to articleContent: Element, context _: ArticleCleanerSiteRuleContext) throws {
        for dateLine in try articleContent.select("p.mobile-date-eyebrow") {
            try dateLine.remove()
        }
    }
}
