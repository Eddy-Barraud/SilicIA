import Foundation
import SwiftSoup

/// Normalizes `mksite` lead image + centered link caption into a full-width figure.
///
/// SiteRule Metadata:
/// - Scope: `mksite` pages whose extracted article starts with `img + center > a`
/// - Phase: `serialization` cleanup
/// - Trigger: `meta[name=generator*='mksite']` when available, otherwise a narrow
///   lead shape of top-level `img` followed by `center` containing a single link
/// - Evidence: `CLI/.staging/maurycyz`
/// - Risk if misplaced: low; only rewrites the very first image/caption pair
enum MksiteLeadImageFigureRule: SerializationSiteRule {
    static let id = "mksite-lead-image-figure"

    static func apply(to articleContent: Element) throws {
        guard let page = try articleContent.select("div#readability-page-1.page").first() else {
            return
        }

        let children = page.children().array()
        guard children.count >= 2 else { return }

        let first = children[0]
        let second = children[1]
        guard first.tagName().lowercased() == "img",
              second.tagName().lowercased() == "center" else {
            return
        }

        let captionChildren = second.children().array()
        guard captionChildren.count == 1,
              let link = captionChildren.first,
              link.tagName().lowercased() == "a" else {
            return
        }

        guard try matchesMksiteContextIfAvailable(articleContent) else { return }

        let doc = articleContent.ownerDocument() ?? Document("")
        let figure = try doc.createElement("figure")
        let figcaption = try doc.createElement("figcaption")

        try first.remove()
        try second.remove()

        let imageStyle = mergedStyle(
            existing: (try? first.attr("style")) ?? "",
            additions: [
                ("display", "block"),
                ("width", "100%"),
                ("height", "auto")
            ]
        )
        if !imageStyle.isEmpty {
            try first.attr("style", imageStyle)
        }

        let captionStyle = mergedStyle(
            existing: (try? figcaption.attr("style")) ?? "",
            additions: [
                ("text-align", "center")
            ]
        )
        if !captionStyle.isEmpty {
            try figcaption.attr("style", captionStyle)
        }

        try link.remove()
        try figcaption.appendChild(link)
        try figure.appendChild(first)
        try figure.appendChild(figcaption)
        try page.prependChild(figure)
    }

    private static func matchesMksiteContextIfAvailable(_ articleContent: Element) throws -> Bool {
        guard let document = articleContent.ownerDocument() else { return true }
        let generatorMetas = try document.select("meta[name=generator]")
        if generatorMetas.isEmpty() {
            return true
        }

        for meta in generatorMetas {
            let content = ((try? meta.attr("content")) ?? "").lowercased()
            if content.contains("mksite") {
                return true
            }
        }

        return false
    }

    private static func mergedStyle(existing: String, additions: [(String, String)]) -> String {
        var orderedKeys: [String] = []
        var styles: [String: String] = [:]

        for part in existing.split(separator: ";") {
            let pieces = part.split(separator: ":", maxSplits: 1).map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard pieces.count == 2 else { continue }
            let key = pieces[0].lowercased()
            if orderedKeys.contains(key) == false {
                orderedKeys.append(key)
            }
            styles[key] = pieces[1]
        }

        for (key, value) in additions {
            let normalizedKey = key.lowercased()
            if orderedKeys.contains(normalizedKey) == false {
                orderedKeys.append(normalizedKey)
            }
            styles[normalizedKey] = value
        }

        return orderedKeys.compactMap { key in
            guard let value = styles[key], !value.isEmpty else { return nil }
            return "\(key): \(value)"
        }.joined(separator: "; ")
    }
}
