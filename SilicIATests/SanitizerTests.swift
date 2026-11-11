//
//  SanitizerTests.swift
//  SilicIATests
//
//  Tests for ModelOutputLaTeXSanitizer currency escaping, LaTeX math preservation,
//  progressive stream segmentation, and HTML cookie consent stripping.
//

import XCTest
@testable import SilicIA

final class SanitizerTests: XCTestCase {

    func testLaTeXSanitizationEscapingAndStreamSegmentation() {
        // 1. Currency escaping vs math preservation
        XCTAssertEqual(
            ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: "The total is $1025.75."),
            #"The total is \$1025.75."#
        )
        XCTAssertEqual(
            ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: "Cost: **$100**"),
            #"Cost: **\$100**"#
        )
        XCTAssertEqual(
            ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: "Le total est 1025.75$."),
            #"Le total est 1025.75\$."#
        )
        let alreadyEscaped = #"The total is \$1025.75."#
        XCTAssertEqual(ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: alreadyEscaped), alreadyEscaped)

        XCTAssertEqual(ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: "$$E = mc^2$$"), "$$E = mc^2$$")
        XCTAssertEqual(ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: "$$1 + x = 2$$"), "$$1 + x = 2$$")
        XCTAssertEqual(ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: "Compute $x + y$."), "Compute $x + y$.")
        XCTAssertEqual(ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: #"Half is $\frac{1}{2}$."#), #"Half is $\frac{1}{2}$."#)

        let digitClose = #"coefficients $a_3$, $a_2$, $a_1$ et $a_0$"#
        XCTAssertEqual(ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: digitClose), digitClose)

        let finalized = ModelOutputLaTeXSanitizer.finalizeSanitizedText("Final price: $1025.75 USD. Math: $a_3$.")
        XCTAssertTrue(finalized.contains(#"\$1025.75"#))
        XCTAssertFalse(finalized.contains(#"\$a_3"#))

        // 2. Prose array unwrap & wiki fast math
        let arrayProse = """
        \\[\\begin{array}{l}
        \\text{SwiftData is an iOS framework introduced by Apple for seamless data management.} \\\\
        \\text{The setup involves integrating SwiftData into an Xcode project.} \\\\
        \\end{array}\\]
        """
        let sanitized = ModelOutputLaTeXSanitizer.sanitizeLaTeXDocumentWrappers(arrayProse)
        XCTAssertFalse(sanitized.contains("\\begin{array}"))
        XCTAssertFalse(sanitized.contains("\\end{array}"))
        XCTAssertFalse(sanitized.contains("\\text{"))
        XCTAssertTrue(sanitized.contains("SwiftData is an iOS framework introduced by Apple"))

        let mathInput = """
        Boyle's law: {\\displaystyle V\\propto {\\frac {1}{P}}};
        Fraction: {\\displaystyle {\\frac {1 + {\\frac {a}{b}}}{2}}}.
        Display:
        {\\displaystyle PV = nRT}
        """
        let mathOutput = ModelOutputLaTeXSanitizer.formatWikiFastMath(mathInput)
        XCTAssertFalse(mathOutput.contains("{\\displaystyle"))
        XCTAssertTrue(mathOutput.contains("$\\displaystyle V\\propto"))
        XCTAssertTrue(mathOutput.contains(#"$\displaystyle {\frac {1 + {\frac {a}{b}}}{2}}$"#))
        XCTAssertTrue(mathOutput.contains("$$\\displaystyle PV = nRT$$"))

        // 3. LaTeXStreamSegmenter paragraph blocks & safe boundaries
        let streamText = "Intro paragraph.\n\n$$\nE = mc^2\n$$\n\nClosing paragraph."
        let blocks = LaTeXStreamSegmenter.paragraphBlocks(in: streamText)
        XCTAssertEqual(blocks, ["Intro paragraph.", "$$\nE = mc^2\n$$", "Closing paragraph."])
        XCTAssertEqual(LaTeXStreamSegmenter.paragraphBlocks(in: "A\n\n\n\nB"), ["A", "B"])

        let partial = LaTeXStreamSegmenter.paragraphBlocks(in: "First.\n\n$$\nx\n$$\n\nSec")
        let grown = LaTeXStreamSegmenter.paragraphBlocks(in: "First.\n\n$$\nx\n$$\n\nSecond block.")
        XCTAssertEqual(Array(partial.dropLast()), Array(grown.dropLast()))

        XCTAssertTrue(LaTeXStreamSegmenter.safeBoundaries("The value is").isEmpty)
        let s2 = "First sentence. Second sentence."
        let b = LaTeXStreamSegmenter.safeBoundaries(s2)
        XCTAssertEqual(b.count, 2)
        XCTAssertEqual(String(s2.prefix(b[0])), "First sentence.")

        let balanced = "The solution is $x = 1$ today."
        XCTAssertEqual(LaTeXStreamSegmenter.safeBoundaries(balanced), [balanced.count])
        XCTAssertTrue(LaTeXStreamSegmenter.safeBoundaries("Let $x be the value.").isEmpty)

        let currency = "It costs $5.00 today."
        XCTAssertEqual(LaTeXStreamSegmenter.safeBoundaries(currency), [currency.count])
    }

    @MainActor
    func testCookieConsentStrippingAndScraperIntegration() async throws {
        // YouTube consent bump
        let youtubeHTML = """
        <div id="consent-bump" class="consent-bump">
            <h2>Avant d'accéder à YouTube</h2>
            <p>Nous utilisons des cookies et des données. Tout accepter.</p>
            <button>Tout accepter</button>
        </div>
        <article><h1>Actualités</h1><p>Contenu réel de l'article.</p></article>
        """
        let cleanedYT = HTMLSanitizer.removeCookieConsent(from: youtubeHTML)
        XCTAssertFalse(cleanedYT.contains("consent-bump"))
        XCTAssertFalse(cleanedYT.contains("Tout accepter"))
        XCTAssertTrue(cleanedYT.contains("Actualités"))
        XCTAssertTrue(cleanedYT.contains("Contenu réel de l'article."))

        // CMP platforms (OneTrust, Didomi, Cookiebot)
        let cmpHTML = """
        <div id="onetrust-consent-sdk"><p>Accept all cookies</p></div>
        <div id="didomi-host"><p>Didomi consent</p></div>
        <div id="CybotCookiebotDialog"><p>Cookiebot notice</p></div>
        <p>Main content after CMPs.</p>
        """
        let cleanedCMP = HTMLSanitizer.removeCookieConsent(from: cmpHTML)
        XCTAssertFalse(cleanedCMP.contains("onetrust-consent-sdk"))
        XCTAssertFalse(cleanedCMP.contains("didomi-host"))
        XCTAssertFalse(cleanedCMP.contains("CybotCookiebotDialog"))
        XCTAssertTrue(cleanedCMP.contains("Main content after CMPs."))

        // Preserves articles about HTTP cookies
        let techHTML = """
        <article class="tech-article">
            <h1>History of HTTP Cookies</h1>
            <p>An HTTP cookie is a small piece of data stored on the computer by the web browser.</p>
        </article>
        """
        let cleanedTech = HTMLSanitizer.removeCookieConsent(from: techHTML)
        XCTAssertTrue(cleanedTech.contains("History of HTTP Cookies"))
        XCTAssertTrue(cleanedTech.contains("An HTTP cookie"))

        XCTAssertTrue(HTMLSanitizer.isCookieConsentText("Tout accepter"))
        XCTAssertTrue(HTMLSanitizer.isCookieConsentText("Accept all"))
        XCTAssertFalse(HTMLSanitizer.isCookieConsentText("An HTTP cookie is a small piece of data."))

        // Plain text with structure & scraper integration
        let structuredHTML = """
        <div class="cookie-consent-modal"><p>Nous utilisons des cookies. Tout accepter.</p></div>
        <h1>Actualité</h1>
        <p>Premier paragraphe utile.</p>
        <p>Deuxième paragraphe avec des détails.</p>
        """
        let plain = HTMLSanitizer.htmlToPlainText(structuredHTML)
        XCTAssertFalse(plain.contains("cookies"))
        XCTAssertTrue(plain.contains("Premier paragraphe utile."))

        let structured = HTMLSanitizer.htmlToPlainTextWithStructure(structuredHTML)
        XCTAssertFalse(structured.contains("cookies"))
        XCTAssertTrue(structured.contains("Actualité\n\n"))
        XCTAssertTrue(structured.contains("Premier paragraphe utile.\n\nDeuxième paragraphe avec des détails."))

        let scraper = WebScrapingService()
        let (_, markdown) = try await scraper.extractMarkdown(from: structuredHTML)
        XCTAssertFalse(markdown.contains("cookies"))
        XCTAssertTrue(markdown.contains("Premier paragraphe utile."))
    }
}
