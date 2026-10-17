import Foundation
import SwiftSoup

/// Removes CNET playlist overlay widgets that are not part of article prose.
///
/// SiteRule Metadata:
/// - Scope: CNET `.playlist.overlay` chrome blocks
/// - Phase: `unwanted` cleanup
/// - Trigger: `div.playlist.overlay` and short `li.playlist` label entries
/// - Evidence: `realworld/cnet`
/// - Risk if misplaced: playlist UI remains and inflates DOM node count
enum CNETPlaylistOverlayRule: ArticleCleanerSiteRule {
    static let id = "cnet-playlist-overlay"

    static func apply(to articleContent: Element, context _: ArticleCleanerSiteRuleContext) throws {
        guard isCNETArticleContent(articleContent) else { return }

        try articleContent.select("div.playlist.overlay").remove()
        try articleContent.select("div[data-load-playlist] .playlist, div[data-load-playlist] .playlist-more, div[data-load-playlist] ul").remove()
        try articleContent.select("div[data-item-id][data-item-syndicated], [id*=taboola], [class*=taboola]").remove()

        for item in try articleContent.select("li.playlist").reversed() {
            let text = ((try? DOMHelpers.getInnerText(item)) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if text == "playlist" {
                try item.remove()
            }
        }

        for block in try articleContent.select("div").reversed() {
            guard block.parent() != nil else { continue }
            let paragraphs = try block.select("> p")
            guard paragraphs.count >= 2 else { continue }
            let allShortLinkParagraphs = paragraphs.array().allSatisfy { paragraph in
                let text = ((try? DOMHelpers.getInnerText(paragraph)) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let linkCount = (try? paragraph.select("a").count) ?? 0
                return !text.isEmpty && text.count <= 160 && linkCount >= 1
            }
            if allShortLinkParagraphs {
                try block.remove()
            }
        }
    }

    private static func isCNETArticleContent(_ articleContent: Element) -> Bool {
        let subtreeSignals = (try? articleContent.select(
            "div.playlist.overlay, div[data-load-playlist], [id*=taboola], [class*=taboola], div[data-container-asset-id][data-page-options]"
        ).isEmpty()) == false
        if subtreeSignals {
            return true
        }

        guard let document = articleContent.ownerDocument() else { return false }

        let siteName = ((try? document.select("meta[property=og:site_name]").first()?.attr("content")) ?? "")
            .lowercased()
        if siteName == "cnet" {
            return true
        }

        let canonical = ((try? document.select("link[rel=canonical]").first()?.attr("href")) ?? "")
            .lowercased()
        if canonical.contains("cnet.com") {
            return true
        }

        return document.location().lowercased().contains("cnet.com")
    }
}
