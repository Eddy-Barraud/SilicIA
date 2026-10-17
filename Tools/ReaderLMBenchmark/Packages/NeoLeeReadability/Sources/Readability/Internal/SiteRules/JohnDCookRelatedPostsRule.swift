import Foundation
import SwiftSoup

/// Removes John D. Cook blog "Related posts" navigation appended to article bodies.
///
/// SiteRule Metadata:
/// - Scope: johndcook.com related-posts tail list
/// - Phase: `postProcess` cleanup
/// - Trigger: `johndcook.com` article content with trailing `h2` "Related posts" followed by a link list
/// - Evidence: `CLI/.staging/johndcook`
/// - Risk if misplaced: article recommendation rail remains in extracted body
enum JohnDCookRelatedPostsRule: ArticleCleanerSiteRule {
    static let id = "johndcook-related-posts"

    static func apply(to articleContent: Element, context _: ArticleCleanerSiteRuleContext) throws {
        for heading in try articleContent.select("h2").reversed() {
            let text = ((try? DOMHelpers.getInnerText(heading)) ?? "")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard text == "related posts" else { continue }
            guard heading.parent()?.tagName().lowercased() == "div" else { continue }

            guard let list = try heading.nextElementSibling(), list.tagName().lowercased() == "ul" else {
                continue
            }
            let items = (try? list.select("> li")) ?? Elements()
            guard !items.isEmpty else { continue }
            let allLinked = items.array().allSatisfy { (try? $0.select("a").isEmpty()) == false }
            guard allLinked else { continue }

            try list.remove()
            try heading.remove()
        }
    }
}
