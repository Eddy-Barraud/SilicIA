//
//  SanitizerTests.swift
//  SilicIATests
//
//  Tests for ModelOutputLaTeXSanitizer currency escaping and LaTeX math delimiter preservation.
//

import XCTest
@testable import SilicIA

final class SanitizerTests: XCTestCase {

    func testCurrencyEscaping() {
        // Prefix currency before digit
        XCTAssertEqual(
            ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: "The total is $1025.75."),
            #"The total is \$1025.75."#
        )
        // Inside bold
        XCTAssertEqual(
            ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: "Cost: **$100**"),
            #"Cost: **\$100**"#
        )
        // Multiple prefix currencies
        XCTAssertEqual(
            ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: "Was $500, now $399.99"),
            #"Was \$500, now \$399.99"#
        )
        // Suffix currency (French/Quebec style)
        XCTAssertEqual(
            ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: "Le total est 1025.75$."),
            #"Le total est 1025.75\$."#
        )
    }

    func testAlreadyEscapedNotDoubleEscaped() {
        let input = #"The total is \$1025.75."#
        XCTAssertEqual(ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: input), input)
    }

    func testMathDelimitersPreserved() {
        // Display math with letters or digits
        XCTAssertEqual(ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: "$$E = mc^2$$"), "$$E = mc^2$$")
        XCTAssertEqual(ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: "$$1 + x = 2$$"), "$$1 + x = 2$$")

        // Inline math with letters or LaTeX commands
        XCTAssertEqual(ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: "Compute $x + y$."), "Compute $x + y$.")
        XCTAssertEqual(ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: #"Half is $\frac{1}{2}$."#), #"Half is $\frac{1}{2}$."#)
    }

    func testDigitAdjacentClosingDollars() {
        // Balanced math closing delimiter following a digit must not escape
        let input = #"coefficients $a_3$, $a_2$, $a_1$ et $a_0$"#
        let output = ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: input)
        XCTAssertFalse(output.contains(#"\$"#))
        XCTAssertEqual(output, input)
    }

    func testCurrencyAndMathCoexistenceAndFullPipeline() {
        // Interleaved currency and math
        let mixed = #"price $5 for $x$ items"#
        let escapedMixed = ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: mixed)
        XCTAssertTrue(escapedMixed.contains(#"\$5"#))
        XCTAssertTrue(escapedMixed.contains("$x$"))

        // Real-world invoice text
        let invoice = "The total invoice amount is **932.50 €**. Converting to USD: $932.50 × 1.10 = **$1025.75**."
        let escapedInvoice = ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: invoice)
        XCTAssertTrue(escapedInvoice.contains(#"\$932.50"#))
        XCTAssertTrue(escapedInvoice.contains(#"\$1025.75"#))

        // Full pipeline pass
        let finalized = ModelOutputLaTeXSanitizer.finalizeSanitizedText("Final price: $1025.75 USD. Math: $a_3$.")
        XCTAssertTrue(finalized.contains(#"\$1025.75"#))
        XCTAssertFalse(finalized.contains(#"\$a_3"#))
    }

    func testUnwrapProseArrayEnvironments() {
        let input = """
        \\[\\begin{array}{l}
        \\text{SwiftData is an iOS framework introduced by Apple for seamless data management.} \\\\
        \\text{The setup involves integrating SwiftData into an Xcode project.} \\\\
        \\end{array}\\]

        \\[\\begin{array}{l}
        \\bullet \\text{Add SwiftData via Xcode: File > Add Packages > SwiftData repository.}} \\\\
        \\bullet \\text{Create Core Data-like structures using @NSManaged and custom properties.}} \\\\
        \\bullet \\text{Configure persistence with NSPersistentContainer and context management.}}
        \\]
        """
        let sanitized = ModelOutputLaTeXSanitizer.sanitizeLaTeXDocumentWrappers(input)
        XCTAssertFalse(sanitized.contains("\\begin{array}"))
        XCTAssertFalse(sanitized.contains("\\end{array}"))
        XCTAssertFalse(sanitized.contains("\\text{"))
        XCTAssertTrue(sanitized.contains("SwiftData is an iOS framework introduced by Apple"))
        XCTAssertTrue(sanitized.contains("- Add SwiftData via Xcode: File > Add Packages > SwiftData repository."))
        XCTAssertTrue(sanitized.contains("- Create Core Data-like structures using @NSManaged and custom properties."))
        XCTAssertTrue(sanitized.contains("- Configure persistence with NSPersistentContainer and context management."))
    }

    func testFormatWikiFastMathUserExample() {
        let input = """
        This equation is derived from

        * Boyle's law: {\\displaystyle V\\propto {\\frac {1}{P}}};

        * Charles's law: {\\displaystyle V\\propto T};

        * Avogadro's law: {\\displaystyle V\\propto n}.
        """

        let output = ModelOutputLaTeXSanitizer.formatWikiFastMath(input)

        XCTAssertFalse(output.contains("{\\displaystyle"))
        XCTAssertTrue(output.contains("* Boyle's law: $\\displaystyle V\\propto {\\frac {1}{P}}$;"))
        XCTAssertTrue(output.contains("* Charles's law: $\\displaystyle V\\propto T$;"))
        XCTAssertTrue(output.contains("* Avogadro's law: $\\displaystyle V\\propto n$."))
    }

    func testFormatWikiFastMathNestedBracesAndEscapes() {
        // Nested braces
        let nested = "Set theory {\\displaystyle {\\mathsf {IZF}}} and fraction {\\displaystyle {\\frac {1 + {\\frac {a}{b}}}{2}}}."
        let nestedOutput = ModelOutputLaTeXSanitizer.formatWikiFastMath(nested)
        XCTAssertFalse(nestedOutput.contains("{\\displaystyle"))
        XCTAssertTrue(nestedOutput.contains("$\\displaystyle {\\mathsf {IZF}}$"))
        XCTAssertTrue(nestedOutput.contains(#"$\displaystyle {\frac {1 + {\frac {a}{b}}}{2}}$"#))

        // Escaped braces in sets \{ ... \}
        let set = #"{\displaystyle \{x \in \mathbb{R} \mid x > 0\}}"#
        let setOutput = ModelOutputLaTeXSanitizer.formatWikiFastMath(set)
        XCTAssertFalse(setOutput.contains("{\\displaystyle"))
        XCTAssertTrue(setOutput.contains(#"$$\displaystyle \{x \in \mathbb{R} \mid x > 0\}$$"#))

        // Markdown-escaped underscores \_ -> _
        let subscriptEscaped = #"{\displaystyle V\_{\mathrm {T} }={kT \over q}}"#
        let subscriptOutput = ModelOutputLaTeXSanitizer.formatWikiFastMath(subscriptEscaped)
        XCTAssertFalse(subscriptOutput.contains("{\\displaystyle"))
        XCTAssertFalse(subscriptOutput.contains(#"V\_"#))
        XCTAssertTrue(subscriptOutput.contains(#"V_{\mathrm {T} }"#))
    }

    func testFormatWikiFastMathStandaloneDisplayAndInline() {
        // Standalone equation on its own line
        let standalone = """
        Here is the equation:

        {\\displaystyle PV = nRT}

        where P is pressure.
        """
        let standaloneOutput = ModelOutputLaTeXSanitizer.formatWikiFastMath(standalone)
        XCTAssertFalse(standaloneOutput.contains("{\\displaystyle"))
        XCTAssertTrue(standaloneOutput.contains("$$\\displaystyle PV = nRT$$"))

        // Multiple inline equations on a single line
        let multipleInline = "Constants {\\displaystyle \\pi } and {\\displaystyle e} are transcendental."
        let multipleOutput = ModelOutputLaTeXSanitizer.formatWikiFastMath(multipleInline)
        XCTAssertFalse(multipleOutput.contains("{\\displaystyle"))
        XCTAssertTrue(multipleOutput.contains("$\\displaystyle \\pi$"))
        XCTAssertTrue(multipleOutput.contains("$\\displaystyle e$"))

        // MediaWiki colon-indented display equation
        let colonIndented = ":{\\displaystyle E = mc^2}"
        let colonOutput = ModelOutputLaTeXSanitizer.formatWikiFastMath(colonIndented)
        XCTAssertFalse(colonOutput.contains("{\\displaystyle"))
        XCTAssertTrue(colonOutput.contains("$$\\displaystyle E = mc^2$$"))
    }

    func testMarkdownBlockParserLooseLists() {
        let looseListMarkdown = """
        * Item 1

        * Item 2

        * Item 3
        """

        let blocks = MarkdownBlockParser.parse(markdown: looseListMarkdown)
        XCTAssertEqual(blocks.count, 1)
        if case .unorderedList(let items) = blocks.first {
            XCTAssertEqual(items.count, 3)
            XCTAssertEqual(items[0], "Item 1")
            XCTAssertEqual(items[1], "Item 2")
            XCTAssertEqual(items[2], "Item 3")
        } else {
            XCTFail("Expected a single unorderedList block")
        }
    }

    // MARK: - Cookie Consent Removal Tests

    func testRemoveCookieConsentYouTubeFrenchExample() {
        let html = """
        <!DOCTYPE html>
        <html>
        <head><title>Le Figaro Actualités - YouTube</title></head>
        <body>
        <div id="consent-bump" class="consent-bump">
            <h2>Avant d'accéder à YouTube</h2>
            <p>Nous utilisons des cookies et des données, y compris des adresses IP, pour :</p>
            <ul>
                <li>Proposer les services Google et s'assurer qu'ils fonctionnent correctement</li>
                <li>Suivre les interruptions de service et protéger contre le spam, les fraudes et les abus</li>
                <li>Mesurer l'engagement de l'audience et les statistiques des sites pour comprendre la façon dont nos services sont utilisés et pour améliorer leur qualité</li>
            </ul>
            <p>Si vous sélectionnez "Tout accepter", nous utiliserons aussi des cookies et des données, y compris des adresses IP, pour :</p>
            <ul>
                <li>Développer de nouveaux services et les améliorer</li>
                <li>Diffuser des annonces et évaluer leur efficacité</li>
                <li>Proposer des contenus personnalisés en fonction de vos paramètres</li>
                <li>Afficher des annonces personnalisées en fonction de vos paramètres</li>
            </ul>
            <div class="buttons">
                <button>Tout accepter</button>
                <button>Tout refuser</button>
            </div>
        </div>
        <main>
            <article>
                <h1>Le Figaro Actualités</h1>
                <p>Retrouvez toute l'actualité en direct, les reportages, les décryptages et les analyses de la rédaction.</p>
            </article>
        </main>
        </body>
        </html>
        """

        let cleaned = HTMLSanitizer.removeCookieConsent(from: html)
        XCTAssertFalse(cleaned.contains("consent-bump"), "Consent container ID must be removed")
        XCTAssertFalse(cleaned.contains("cookies et des données"), "Cookie consent text must be removed")
        XCTAssertFalse(cleaned.contains("Tout accepter"), "Cookie consent buttons must be removed")
        XCTAssertFalse(cleaned.contains("Proposer les services Google"), "Cookie consent bullet points must be removed")
        XCTAssertTrue(cleaned.contains("Le Figaro Actualités"), "Real article title must be preserved")
        XCTAssertTrue(cleaned.contains("Retrouvez toute l'actualité en direct"), "Real article content must be preserved")
    }

    func testRemoveCookieConsentCMPPlatforms() {
        // OneTrust
        let onetrustHTML = """
        <div id="onetrust-consent-sdk">
            <div class="ot-sdk-container">
                <p>This website uses cookies for analytics and ads.</p>
                <button id="onetrust-accept-btn-handler">Accept All Cookies</button>
            </div>
        </div>
        <p>Main content after OneTrust.</p>
        """
        let cleanedOneTrust = HTMLSanitizer.removeCookieConsent(from: onetrustHTML)
        XCTAssertFalse(cleanedOneTrust.contains("onetrust-consent-sdk"))
        XCTAssertFalse(cleanedOneTrust.contains("Accept All Cookies"))
        XCTAssertTrue(cleanedOneTrust.contains("Main content after OneTrust."))

        // Didomi
        let didomiHTML = """
        <div id="didomi-host">
            <div class="didomi-popup">
                <p>Nous et nos partenaires utilisons des cookies. Accepter tout.</p>
            </div>
        </div>
        <p>Main content after Didomi.</p>
        """
        let cleanedDidomi = HTMLSanitizer.removeCookieConsent(from: didomiHTML)
        XCTAssertFalse(cleanedDidomi.contains("didomi-host"))
        XCTAssertTrue(cleanedDidomi.contains("Main content after Didomi."))

        // Cookiebot
        let cookiebotHTML = """
        <div id="CybotCookiebotDialog">
            <p>Cookiebot notice: we use cookies.</p>
        </div>
        <p>Main content after Cookiebot.</p>
        """
        let cleanedCookiebot = HTMLSanitizer.removeCookieConsent(from: cookiebotHTML)
        XCTAssertFalse(cleanedCookiebot.contains("CybotCookiebotDialog"))
        XCTAssertTrue(cleanedCookiebot.contains("Main content after Cookiebot."))
    }

    func testRemoveCookieConsentDialogAndAsideAndForm() {
        let html = """
        <dialog id="cookie-dialog" aria-label="Cookie consent">
            <p>We use cookies. Click Accept to continue.</p>
            <button>Accept All</button>
        </dialog>
        <aside class="cookie-banner">
            <p>Manage your cookie preferences.</p>
        </aside>
        <form action="https://consent.youtube.com/s" method="POST">
            <input type="hidden" name="gl" value="FR">
            <button type="submit">Tout accepter</button>
        </form>
        <article>
            <h1>Article Header</h1>
            <p>Important article text that must remain intact.</p>
        </article>
        """
        let cleaned = HTMLSanitizer.removeCookieConsent(from: html)
        XCTAssertFalse(cleaned.contains("cookie-dialog"))
        XCTAssertFalse(cleaned.contains("cookie-banner"))
        XCTAssertFalse(cleaned.contains("consent.youtube.com"))
        XCTAssertTrue(cleaned.contains("Article Header"))
        XCTAssertTrue(cleaned.contains("Important article text that must remain intact."))
    }

    func testPreserveArticleAboutHTTPCookies() {
        let techHTML = """
        <article class="tech-article">
            <h1>History of HTTP Cookies</h1>
            <p>An HTTP cookie (web cookie, Internet cookie) is a small piece of data sent from a website and stored on the user's computer by the user's web browser while the user is browsing.</p>
            <p>Cookies were designed to be a reliable mechanism for websites to remember stateful information or to record the user's browsing activity.</p>
        </article>
        """
        let cleaned = HTMLSanitizer.removeCookieConsent(from: techHTML)
        XCTAssertTrue(cleaned.contains("History of HTTP Cookies"))
        XCTAssertTrue(cleaned.contains("An HTTP cookie"))
        XCTAssertTrue(cleaned.contains("Cookies were designed to be a reliable mechanism"))
    }

    func testRemoveCookieConsentNestedInRootWrapper() {
        let html = """
        <div id="root" class="app-container">
            <div id="consent-bump" class="consent-bump">
                <p>Nous utilisons des cookies et des données. Tout accepter.</p>
            </div>
            <article>
                <h1>SpaceX Starship Orbital Launch</h1>
                <p>SpaceX successfully launched Starship into orbit today from Starbase.</p>
            </article>
        </div>
        """
        let cleaned = HTMLSanitizer.removeCookieConsent(from: html)
        XCTAssertFalse(cleaned.contains("consent-bump"))
        XCTAssertFalse(cleaned.contains("Tout accepter"))
        XCTAssertTrue(cleaned.contains("SpaceX Starship Orbital Launch"), "Real article header in outer container must be preserved")
        XCTAssertTrue(cleaned.contains("SpaceX successfully launched Starship"), "Real article text in outer container must be preserved")
    }

    func testRemoveCookieConsentUppercaseTags() {
        let html = """
        <DIV class="cookie-banner">
            <P>Nous utilisons des cookies. Tout accepter.</P>
        </DIV>
        <ARTICLE>
            <H1>Science Journal Report</H1>
            <P>Groundbreaking discoveries in biology.</P>
        </ARTICLE>
        """
        let cleaned = HTMLSanitizer.removeCookieConsent(from: html)
        XCTAssertFalse(cleaned.contains("cookie-banner"))
        XCTAssertFalse(cleaned.contains("Tout accepter"))
        XCTAssertTrue(cleaned.contains("Science Journal Report"))
        XCTAssertTrue(cleaned.contains("Groundbreaking discoveries in biology."))
    }

    func testRemoveCookieConsentLooseElements() {
        let html = """
        <h2>Avant d'accéder à YouTube</h2>
        <p>Nous utilisons des cookies et des données, y compris des adresses IP, pour :</p>
        <ul>
            <li>Proposer les services Google et s'assurer qu'ils fonctionnent correctement</li>
            <li>Suivre les interruptions de service et protéger contre le spam, les fraudes et les abus</li>
        </ul>
        <button>Tout accepter</button>
        <button>Tout refuser</button>
        <main>
            <h1>Actualités Tech</h1>
            <p>Le nouveau processeur M-series offre des performances record.</p>
        </main>
        """
        let cleaned = HTMLSanitizer.removeCookieConsent(from: html)
        XCTAssertFalse(cleaned.contains("Avant d'accéder à YouTube"))
        XCTAssertFalse(cleaned.contains("Proposer les services Google"))
        XCTAssertFalse(cleaned.contains("Suivre les interruptions de service"))
        XCTAssertFalse(cleaned.contains("Tout accepter"))
        XCTAssertFalse(cleaned.contains("Tout refuser"))
        XCTAssertTrue(cleaned.contains("Actualités Tech"))
        XCTAssertTrue(cleaned.contains("Le nouveau processeur M-series offre des performances record."))
    }

    func testIsCookieConsentTextActionsAndClauses() {
        XCTAssertTrue(HTMLSanitizer.isCookieConsentText("Tout accepter"))
        XCTAssertTrue(HTMLSanitizer.isCookieConsentText("« Tout accepter »"))
        XCTAssertTrue(HTMLSanitizer.isCookieConsentText("Accept all"))
        XCTAssertTrue(HTMLSanitizer.isCookieConsentText("Avant d'accéder à YouTube"))
        XCTAssertTrue(HTMLSanitizer.isCookieConsentText("Before you continue to YouTube"))
        XCTAssertTrue(HTMLSanitizer.isCookieConsentText("Continuer sans accepter"))
        XCTAssertTrue(HTMLSanitizer.isCookieConsentText("Proposer les services Google et s'assurer qu'ils fonctionnent correctement"))
        XCTAssertTrue(HTMLSanitizer.isCookieConsentText("Suivre les interruptions de service et protéger contre le spam, les fraudes et les abus"))
        XCTAssertTrue(HTMLSanitizer.isCookieConsentText("Mesurer l'engagement de l'audience et les statistiques des sites"))
        XCTAssertTrue(HTMLSanitizer.isCookieConsentText("Diffuser des annonces et évaluer leur efficacité"))
        XCTAssertTrue(HTMLSanitizer.isCookieConsentText("Proposer des contenus personnalisés en fonction de vos paramètres"))
        XCTAssertTrue(HTMLSanitizer.isCookieConsentText("Afficher des annonces personnalisées en fonction de vos paramètres"))

        // Technical non-consent checks
        XCTAssertFalse(HTMLSanitizer.isCookieConsentText("An HTTP cookie is a small piece of data sent from a website."))
        XCTAssertFalse(HTMLSanitizer.isCookieConsentText("Cookies were designed to remember stateful information."))
        XCTAssertFalse(HTMLSanitizer.isCookieConsentText("The spacecraft entered Martian orbit after a ten-month journey."))
    }

    func testHTMLSanitizerPlainTextStripsCookieConsent() {
        let html = """
        <div class="cookie-consent-modal">
            <p>Nous utilisons des cookies et des données. Tout accepter.</p>
        </div>
        <p>Premier paragraphe utile.</p>
        <p>Deuxième paragraphe avec des détails.</p>
        """
        let plain = HTMLSanitizer.htmlToPlainText(html)
        XCTAssertFalse(plain.contains("cookies et des données"))
        XCTAssertFalse(plain.contains("Tout accepter"))
        XCTAssertTrue(plain.contains("Premier paragraphe utile."))
        XCTAssertTrue(plain.contains("Deuxième paragraphe avec des détails."))

        let structured = HTMLSanitizer.htmlToPlainTextWithStructure(html)
        XCTAssertFalse(structured.contains("cookies et des données"))
        XCTAssertFalse(structured.contains("Tout accepter"))
        XCTAssertTrue(structured.contains("Premier paragraphe utile.\n\nDeuxième paragraphe avec des détails."))
    }

    func testRAGContextServiceDropsCookieConsentChunks() {
        let cookieText = """
        Nous utilisons des cookies et des données, y compris des adresses IP, pour :

        - Proposer les services Google et s'assurer qu'ils fonctionnent correctement

        - Suivre les interruptions de service et protéger contre le spam, les fraudes et les abus

        - Mesurer l'engagement de l'audience et les statistiques des sites pour comprendre la façon dont nos services sont utilisés et pour améliorer leur qualité

        Si vous sélectionnez "Tout accepter", nous utiliserons aussi des cookies et des données, y compris des adresses IP, pour :

        - Développer de nouveaux services et les améliorer

        - Diffuser des annonces et évaluer leur efficacité

        - Proposer des contenus personnalisés en fonction de vos paramètres

        - Afficher des annonces personnalisées en fonction de vos paramètres
        """
        let combined = """
        \(cookieText)

        # Actualité Principale
        La mission spatiale a atteint son orbite avec succès aujourd'hui après un décollage parfait.
        """
        let chunks = RAGChunker.chunkParagraphs(text: combined, source: "Web", url: "https://www.youtube.com/@LeFigaro_Actualites")
        for chunk in chunks {
            XCTAssertFalse(chunk.text.contains("cookies et des données"), "Chunk must not contain cookie consent boilerplate")
            XCTAssertFalse(chunk.text.contains("Proposer les services Google"), "Google services bullet must be dropped")
            XCTAssertFalse(chunk.text.contains("Suivre les interruptions de service"), "Interruptions bullet must be dropped")
            XCTAssertFalse(chunk.text.contains("Mesurer l'engagement"), "Engagement bullet must be dropped")
            XCTAssertFalse(chunk.text.contains("Développer de nouveaux services"), "Development bullet must be dropped")
            XCTAssertFalse(chunk.text.contains("Diffuser des annonces"), "Ads bullet must be dropped")
            XCTAssertFalse(chunk.text.contains("contenus personnalisés"), "Personalized content bullet must be dropped")
            XCTAssertFalse(chunk.text.contains("annonces personnalisées"), "Personalized ads bullet must be dropped")
            XCTAssertFalse(chunk.text.contains("Tout accepter"), "Chunk must not contain consent acceptance calls")
        }
        XCTAssertEqual(chunks.count, 1, "Only the real news paragraph must become a RAG chunk")
        XCTAssertTrue(chunks.contains { $0.text.contains("La mission spatiale") }, "Real news paragraph must be chunked")
    }

    @MainActor
    func testWebScrapingServiceExtractMarkdownStripsCookieBanner() async throws {
        let service = WebScrapingService()
        let sampleHTML = """
        <!DOCTYPE html>
        <html>
        <head><title>Le Figaro Actualités</title></head>
        <body>
        <div id="consent-bump" class="consent-bump">
            <p>Nous utilisons des cookies et des données, y compris des adresses IP, pour :</p>
            <ul>
                <li>Proposer les services Google et s'assurer qu'ils fonctionnent correctement</li>
            </ul>
            <p>Si vous sélectionnez "Tout accepter", nous utiliserons aussi des cookies et des données</p>
            <button>Tout accepter</button>
        </div>
        <main>
            <h1>Le Figaro Actualités</h1>
            <p>Le Figaro est un journal quotidien français fondé en 1826.</p>
        </main>
        </body>
        </html>
        """
        let (title, markdown) = try await service.extractMarkdown(from: sampleHTML)
        XCTAssertFalse(markdown.contains("cookies et des données"), "Markdown must not contain cookie consent")
        XCTAssertFalse(markdown.contains("Tout accepter"), "Markdown must not contain accept button")
        XCTAssertTrue(markdown.contains("Le Figaro") || title.contains("Le Figaro"), "Real content must be extracted")
    }
}
