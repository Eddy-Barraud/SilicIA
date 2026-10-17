import Foundation
import SwiftSoup

/// Removes the sponsored banner from simonwillison.net pages before candidate
/// scoring, preventing it from being selected as article content on short
/// quote-type posts.
///
/// SiteRule Metadata:
/// - Scope: simonwillison.net sponsored banner
/// - Phase: `unwantedElements` cleanup
/// - Trigger: `div#sponsored-banner` with `sponsored-label` and
///   `rel="sponsored"` link
/// - Evidence: `CLI/.staging/simonwillison-6`
/// - Risk if misplaced: sponsored banner remains in candidate pool,
///   causing wrong selection on short quote pages
enum SimonWillisonSponsoredBannerRule: ArticleCleanerSiteRule {
    static let id = "simonwillison-sponsored-banner"

    static func apply(to articleContent: Element, context _: ArticleCleanerSiteRuleContext) throws {
        for banner in try articleContent.select("#sponsored-banner") {
            let hasSponsoredLabel = (try? banner.select(".sponsored-label").isEmpty()) == false
            let hasSponsoredLink = (try? banner.select("a[rel*=sponsored]").isEmpty()) == false
            guard hasSponsoredLabel || hasSponsoredLink else { continue }
            try banner.remove()
        }
    }
}
