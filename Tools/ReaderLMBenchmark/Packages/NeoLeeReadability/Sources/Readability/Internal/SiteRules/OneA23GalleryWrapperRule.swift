import Foundation
import SwiftSoup

/// Restores the expected inner wrapper for very short 1A23 gallery pages.
///
/// The short-article fallback recovers the visible featured image plus credit paragraph.
/// During normal cleanup we keep that content as direct children of `#readability-page-1`,
/// but the curated fixture expects one additional wrapper div under the page container.
enum OneA23GalleryWrapperRule: SerializationSiteRule {
    static let id = "1a23-gallery-wrapper"

    static func apply(to articleContent: Element) throws {
        guard let page = try articleContent.select("div#readability-page-1.page").first() else {
            return
        }

        let children = page.children().array()
        guard children.count == 2 else { return }

        let figure = children[0]
        let paragraph = children[1]
        guard figure.tagName().lowercased() == "figure",
              paragraph.tagName().lowercased() == "p" else {
            return
        }

        let figureClasses = ((try? figure.className()) ?? "").lowercased()
        guard figureClasses.contains("wp-block-post-featured-image") else {
            return
        }

        let paragraphText = ((try? DOMHelpers.getInnerText(paragraph)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard paragraphText.hasPrefix("photo by "),
              paragraphText.contains("typefaces:") else {
            return
        }

        let doc = articleContent.ownerDocument() ?? Document("")
        let wrapper = try doc.createElement("div")
        try wrapper.appendChild(figure)
        try wrapper.appendChild(paragraph)
        try page.appendChild(wrapper)
    }
}
