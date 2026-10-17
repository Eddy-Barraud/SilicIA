import SwiftSoup

/// Includes `figure.wp-block-post-featured-image` from WordPress block editor pages
/// when it appears as a **direct** sibling of the selected content candidate.
///
/// WordPress block editor separates the featured image block from the post-content div.
/// A bare figure with no text content scores 0 and does not meet the sibling score
/// threshold. This rule forces inclusion so the featured image appears at the top
/// of the extracted article, matching what a reader would see on the original page.
enum WordPressFeaturedImageRule: SiblingInclusionSiteRule {
    static let id = "wordpress-featured-image"

    static func shouldIncludeSibling(_ sibling: Element, topCandidate: Element) throws -> Bool? {
        guard sibling.tagName().lowercased() == "figure" else { return nil }
        let className = (try? sibling.className()) ?? ""
        guard className.contains("wp-block-post-featured-image") else { return nil }
        guard DOMHelpers.isProbablyVisible(sibling) else { return nil }
        return true
    }
}

/// Extracts `figure.wp-block-post-featured-image` buried inside a sibling wrapper div.
///
/// Some WordPress block theme layouts wrap the featured image together with article metadata
/// (title, date, taxonomy) inside a single `div` that precedes `div.entry-content`.
/// The wrapper div scores near 0 and would normally be excluded, but the figure inside it
/// should appear at the top of the extracted article.
///
/// This rule extracts only the figure from the wrapper and discards the rest of the wrapper,
/// preventing metadata noise (buttons, date, links) from leaking into extracted content.
enum WordPressFeaturedImageExtractRule: SiblingExtractSiteRule {
    static let id = "wordpress-featured-image-extract"
    private static let preservedClass = "copilot-preserve-figure"

    static func extractFromSibling(_ sibling: Element, topCandidate: Element) throws -> Element? {
        guard sibling.tagName().lowercased() == "div" else { return nil }
        guard let figure = try sibling.select("figure.wp-block-post-featured-image").first() else { return nil }
        guard DOMHelpers.isProbablyVisible(figure) else { return nil }
        let doc = try sibling.ownerDocument() ?? SwiftSoup.parse("")
        let clone = try DOMHelpers.cloneElement(figure, in: doc)
        let existingClass = ((try? clone.className()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let mergedClass = existingClass.isEmpty ? preservedClass : existingClass + " " + preservedClass
        try clone.attr("class", mergedClass)
        return clone
    }
}
