import Foundation
import SwiftSoup

/// Removes the dfarq trailing share CTA and following author/comment tail modules.
///
/// SiteRule Metadata:
/// - Scope: dfarq.homeip.net article tail after the main body
/// - Phase: `postProcess` cleanup
/// - Trigger: Shariff-style share block with the exact "If you found this post informative..."
///   lead-in, followed by schema.org author/comment tail nodes
/// - Evidence: `CLI/.staging/dfarq`
/// - Risk if misplaced: share CTA and author bio leak into extracted body output
enum DFarqShareAuthorTailRule: ArticleCleanerSiteRule {
    static let id = "dfarq-share-author-tail"

    static func apply(to articleContent: Element, context _: ArticleCleanerSiteRuleContext) throws {
        for shareBlock in try articleContent.select("div[data-services][data-backendurl*='share_counts']").reversed() {
            let text = normalizedText(try DOMHelpers.getInnerText(shareBlock))
            guard text.contains("if you found this post informative or helpful, please share it!") else {
                continue
            }

            var cursor = try shareBlock.nextElementSibling()
            while let node = cursor {
                let next = try node.nextElementSibling()
                guard isRecognizedTailNode(node) else { break }
                try node.remove()
                cursor = next
            }

            try shareBlock.remove()
        }

        try removeTrailingAuthorBioIfPresent(from: articleContent)
    }

    private static func isRecognizedTailNode(_ node: Element) -> Bool {
        let itemprop = (try? node.attr("itemprop"))?.lowercased() ?? ""
        let itemtype = (try? node.attr("itemtype"))?.lowercased() ?? ""
        if itemprop == "author", itemtype.contains("schema.org/person") {
            return true
        }

        let identity = ((((try? node.className()) ?? "") + " " + node.id())).lowercased()
        if identity.contains("disqus") || identity.contains("comment") || identity.contains("respond") {
            return true
        }

        return false
    }

    private static func removeTrailingAuthorBioIfPresent(from articleContent: Element) throws {
        for node in try articleContent
            .select("div[itemprop='author'][itemtype*='schema.org/Person']")
            .array()
            .reversed()
        {
            if try isRecognizedAuthorBio(node), isTrailingNode(node) {
                try node.remove()
                continue
            }
            break
        }
    }

    private static func isRecognizedAuthorBio(_ node: Element) throws -> Bool {
        let itemprop = try node.attr("itemprop").lowercased()
        let itemtype = try node.attr("itemtype").lowercased()
        guard itemprop == "author", itemtype.contains("schema.org/person") else {
            return false
        }

        let text = normalizedText(try DOMHelpers.getInnerText(node))
        if text.contains("david farquhar is a computer security professional"),
           text.contains("he has written professionally about computers since 1991") {
            return true
        }

        let imageSources = try node.select("img[itemprop='image']").array().compactMap { image in
            (try? image.attr("src"))?.lowercased()
        }
        return imageSources.contains { $0.contains("dave_farquhar_181px") }
    }

    private static func isTrailingNode(_ node: Element) -> Bool {
        ((try? node.nextElementSibling()) ?? nil) == nil
    }

    private static func normalizedText(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
