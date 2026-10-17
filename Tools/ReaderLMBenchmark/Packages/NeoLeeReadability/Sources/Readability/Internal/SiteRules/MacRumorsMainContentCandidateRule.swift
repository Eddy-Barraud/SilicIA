import Foundation
import SwiftSoup

/// Preserves MacRumors `main#maincontent` as the selected candidate so the
/// algorithm does not promote into the outer site chrome wrapper.
///
/// SiteRule Metadata:
/// - Scope: MacRumors article main container
/// - Phase: candidate protection during top-candidate promotion
/// - Trigger: `main#maincontent` containing `article > [data-io-article-url]`
/// - Evidence: `CLI/.staging/macrumors`
/// - Risk if misplaced: outer brand header leaks into extracted article content
enum MacRumorsMainContentCandidateRule: CandidateProtectionSiteRule {
    static let id = "macrumors-maincontent-candidate"

    static func shouldKeepCandidate(_ current: Element) -> Bool {
        guard let document = current.ownerDocument(),
              isMacRumorsDocument(document),
              current.tagName().uppercased() == "MAIN" else {
            return false
        }

        let currentID = current.id().trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard currentID == "maincontent" else {
            return false
        }

        let hasArticleBody = (try? current.select("> article [data-io-article-url]").isEmpty()) == false
        return hasArticleBody
    }

    private static func isMacRumorsDocument(_ document: Document) -> Bool {
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
