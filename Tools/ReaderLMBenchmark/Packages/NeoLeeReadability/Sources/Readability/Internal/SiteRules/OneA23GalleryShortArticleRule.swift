import Foundation
import SwiftSoup

/// Recovers very short 1A23 gallery pages that Mozilla rejects as unreadable.
///
/// These pages intentionally contain only a featured image and a brief credit/caption
/// paragraph. They fall below Mozilla's global `charThreshold`, but for curated ex-pages
/// we still want the visible reading content.
enum OneA23GalleryShortArticleRule: ShortContentFallbackSiteRule {
    static let id = "1a23-gallery-short-article"

    static func fallbackArticleContent(in document: Document, sourceURL: URL?) throws -> Element? {
        guard isOneA23GalleryPage(sourceURL) else {
            return nil
        }

        guard let entryContent = try document.select("div.entry-content").first(),
              let featuredImage = try document.select("figure.wp-block-post-featured-image").first(),
              let leadingParagraph = firstMeaningfulParagraph(in: entryContent) else {
            return nil
        }

        let container = try document.createElement("div")
        try container.appendChild(try DOMHelpers.cloneElement(featuredImage, in: document))
        try container.appendChild(try DOMHelpers.cloneElement(leadingParagraph, in: document))
        return container
    }

    private static func isOneA23GalleryPage(_ sourceURL: URL?) -> Bool {
        let host = sourceURL?.host?.lowercased() ?? ""
        guard host == "1a23.com" || host == "www.1a23.com" else {
            return false
        }

        let path = sourceURL?.path.lowercased() ?? ""
        return path.contains("/works/gallery/")
    }

    private static func firstMeaningfulParagraph(in entryContent: Element) -> Element? {
        for child in entryContent.children() where child.tagName().lowercased() == "p" {
            let text = ((try? DOMHelpers.getInnerText(child)) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return child
            }
        }
        return nil
    }
}
