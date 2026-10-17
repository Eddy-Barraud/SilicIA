import Foundation
import SwiftSoup

/// Removes MacRumors site chrome that can survive candidate selection and leak
/// into extracted article content.
///
/// SiteRule Metadata:
/// - Scope: MacRumors brand header utility block and newsletter signup form
/// - Phase: `unwanted` cleanup
/// - Trigger: MacRumors documents with site logo header or `form#mc-embedded-subscribe-form`
/// - Evidence: `CLI/.staging/macrumors`
/// - Risk if misplaced: header promo and newsletter form remain in article output
enum MacRumorsArticleChromeRule: ArticleCleanerSiteRule {
    static let id = "macrumors-article-chrome"

    static func apply(to articleContent: Element, context _: ArticleCleanerSiteRuleContext) throws {
        guard isMacRumorsContent(articleContent) else {
            return
        }

        for header in try articleContent.select("header").reversed() {
            let hasMacRumorsLogo = (try? header.select("a#logo[aria-label=\"MacRumors Home Page\"]").isEmpty()) == false
            let hasTipLink = (try? header.select("a[aria-label=\"Let us know - submit a tip\"]").isEmpty()) == false
            guard hasMacRumorsLogo || hasTipLink else { continue }
            try header.remove()
        }

        for container in try articleContent.select("div").reversed() {
            let hasTipLink = (try? container.select("a[aria-label=\"Let us know - submit a tip\"]").isEmpty()) == false
            guard hasTipLink else { continue }

            let text = normalizedText(container)
            if text.contains("got a tip for us?") || text.contains("let us know") {
                try container.remove()
            }
        }

        for form in try articleContent.select("form#mc-embedded-subscribe-form").reversed() {
            if let parent = form.parent() {
                let parentText = normalizedText(parent)
                if parentText.contains("get weekly top macrumors stories in your inbox") ||
                    parentText.contains("leave this field empty") {
                    try parent.remove()
                    continue
                }
            }
            try form.remove()
        }
    }

    private static func normalizedText(_ element: Element) -> String {
        (((try? DOMHelpers.getInnerText(element)) ?? "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased())
    }

    private static func isMacRumorsContent(_ articleContent: Element) -> Bool {
        if (try? articleContent.select("form#mc-embedded-subscribe-form").isEmpty()) == false {
            return true
        }
        if (try? articleContent.select("a#logo[aria-label=\"MacRumors Home Page\"]").isEmpty()) == false {
            return true
        }
        if (try? articleContent.select("a[aria-label=\"Let us know - submit a tip\"]").isEmpty()) == false {
            return true
        }

        guard let document = articleContent.ownerDocument() else {
            return false
        }

        let siteName = ((try? document.select("meta[property=og:site_name]").first()?.attr("content")) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if siteName == "macrumors" {
            return true
        }

        let canonical = ((try? document.select("link[rel=canonical]").first()?.attr("href")) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if canonical.contains("macrumors.com") {
            return true
        }

        return document.location().lowercased().contains("macrumors.com")
    }
}
