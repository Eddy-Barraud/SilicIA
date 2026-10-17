import Foundation
import SwiftSoup

/// Removes berthub.eu navigation chrome that leaks into the promoted outer site wrapper.
///
/// SiteRule Metadata:
/// - Scope: berthub.eu main menu and entry navigation shells
/// - Phase: `unwanted` cleanup
/// - Trigger: `berthub.eu` document with `nav#main-menu` skip link or `nav.entry-nav`
/// - Evidence: `CLI/.staging/berthub`
/// - Risk if misplaced: menu/previous-post navigation remains in extracted article output
enum BerthubNavigationChromeRule: ArticleCleanerSiteRule {
    static let id = "berthub-navigation-chrome"

    static func apply(to articleContent: Element, context _: ArticleCleanerSiteRuleContext) throws {
        for nav in try articleContent.select("nav#main-menu[aria-label=\"Main Menu\"]") {
            let hasSkipLink = (try? nav.select("a.screen-reader-text[href=\"#content\"]").isEmpty()) == false
            guard hasSkipLink else { continue }
            try removeAllChildren(from: nav)
        }

        for nav in try articleContent.select("nav.entry-nav") {
            let text = ((try? DOMHelpers.getInnerText(nav)) ?? "")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let hasPrevNextLabel = text.contains("previous post:") || text.contains("next post:")
            let hasEntryMarkers = (try? nav.select(".prev-entry, .next-entry").isEmpty()) == false
            guard hasPrevNextLabel || hasEntryMarkers else { continue }
            try removeAllChildren(from: nav)
        }
    }

    private static func removeAllChildren(from element: Element) throws {
        for child in element.getChildNodes() {
            try child.remove()
        }
    }
}
