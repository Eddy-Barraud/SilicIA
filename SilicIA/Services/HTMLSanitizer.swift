//
//  HTMLSanitizer.swift
//  SilicIA
//
//

import Foundation

/// Fast HTML tag stripper and entity decoder shared across WebSearchService and WebScrapingService.
enum HTMLSanitizer: Sendable {

    private nonisolated static let htmlCommentRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "<!--[\\s\\S]*?-->",
        options: []
    )

    private nonisolated static let nonContentBlockRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "<(script|style|svg|noscript|template)[^>]*>[\\s\\S]*?</\\1>",
        options: [.caseInsensitive]
    )

    private nonisolated static let consentDialogRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "<dialog[^>]*?(?:id|class|aria-label|aria-labelledby|role)=[\"'][^\"']*(?:cookie|consent|onetrust|didomi|cookiebot|usercentrics|tarteaucitron|axeptio|sp_message|cmplz|iubenda|gdpr)[^\"']*[\"'][^>]*>[\\s\\S]*?</dialog>",
        options: [.caseInsensitive]
    )

    private nonisolated static let consentAsideRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "<aside[^>]*?(?:id|class|aria-label|role)=[\"'][^\"']*(?:cookie|consent|onetrust|didomi|cookiebot|usercentrics|tarteaucitron|axeptio|sp_message|cmplz|iubenda|gdpr)[^\"']*[\"'][^>]*>[\\s\\S]*?</aside>",
        options: [.caseInsensitive]
    )

    private nonisolated static let consentFormRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "<form[^>]*?action=[\"'][^\"']*(?:consent\\.(?:youtube|google)\\.com|/consent|/cookie[_-]?consent)[^\"']*[\"'][^>]*>[\\s\\S]*?</form>",
        options: [.caseInsensitive]
    )

    private nonisolated static let consentWebComponentRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "<(ytd-consent-bump-v2-renderer|yt-confirm-dialog-renderer|cookie-banner|consent-banner)[^>]*>[\\s\\S]*?</\\1>",
        options: [.caseInsensitive]
    )

    private nonisolated static let cookieAttributeRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "\\b(?:cookie[_-]?(?:banner|consent|notice|modal|popup|bar|law|alert|box|container|message|overlay|policy|prompt|dialog|wrapper|view)|consent[_-]?(?:banner|modal|dialog|bump|container|popup|box|prompt|wrapper)|onetrust|didomi|cookiebot|cybotcookiebotdialog|usercentrics|qc[_-]cmp|tarteaucitron|axeptio|sp_message|cmplz|iubenda|gdpr[_-]?(?:banner|consent|modal|notice|popup)|cookieconsent|cookiebanner|cookienotice|cookiemodal|cookiepopup|consentbanner|consentmodal|consentdialog)\\b",
        options: [.caseInsensitive]
    )

    private nonisolated static let candidateContainerTagRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "<([a-zA-Z0-9_-]+)\\b([^>]*)>",
        options: [.caseInsensitive]
    )

    private nonisolated static let consentElementRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "<(p|li|h[1-6]|button|small|span|a)\\b[^>]*>([\\s\\S]*?)</\\1>",
        options: [.caseInsensitive]
    )

    private nonisolated static let emptyListRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "<(ul|ol)\\b[^>]*>\\s*</\\1>",
        options: [.caseInsensitive]
    )

    private nonisolated static let paragraphRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "<p\\b[^>]*>([\\s\\S]*?)</p>",
        options: [.caseInsensitive]
    )

    private nonisolated static let htmlTagRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "<[^>]+>",
        options: []
    )

    private nonisolated static let htmlEntityRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "&(#[0-9]+|#x[0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]+);",
        options: []
    )

    private nonisolated static let htmlBlockTagRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "</?(?:p|div|section|article|header|footer|h[1-6]|table|tr|blockquote)[^>]*>",
        options: [.caseInsensitive]
    )

    private nonisolated static let htmlBreakTagRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "<br\\s*/?>|</?li[^>]*>",
        options: [.caseInsensitive]
    )

    private nonisolated static let multipleNewlineRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "\n{3,}",
        options: []
    )

    private nonisolated static let namedEntities: [String: String] = [
        "nbsp": " ",
        "amp": "&",
        "lt": "<",
        "gt": ">",
        "quot": "\"",
        "apos": "'",
        "copy": "©",
        "reg": "®",
        "trade": "™",
        "mdash": "—",
        "ndash": "–",
        "hellip": "…",
        "laquo": "«",
        "raquo": "»",
        "lsquo": "‘",
        "rsquo": "’",
        "ldquo": "“",
        "rdquo": "”",
        "deg": "°",
        "plusmn": "±",
        "times": "×",
        "divide": "÷",
        "ne": "≠",
        "le": "≤",
        "ge": "≥",
        "infin": "∞",
        "para": "¶",
        "sect": "§",
        "bull": "•",
        "euro": "€",
        "pound": "£",
        "yen": "¥",
        "cent": "¢"
    ]

    /// Decodes HTML entities (named, decimal-numeric &#nnn;, and hex-numeric &#xNN;) in a single pass.
    nonisolated static func decodeEntities(_ text: String) -> String {
        guard let regex = htmlEntityRegex else { return text }
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)
        guard !matches.isEmpty else { return text }

        var result = ""
        result.reserveCapacity(text.count)
        var cursor = text.startIndex

        for match in matches {
            guard let fullRange = Range(match.range, in: text),
                  let groupRange = Range(match.range(at: 1), in: text) else {
                continue
            }
            if cursor < fullRange.lowerBound {
                result.append(contentsOf: text[cursor..<fullRange.lowerBound])
            }

            let token = String(text[groupRange])
            let decoded = decodeEntityToken(token) ?? String(text[fullRange])
            result.append(decoded)
            cursor = fullRange.upperBound
        }

        if cursor < text.endIndex {
            result.append(contentsOf: text[cursor...])
        }
        return result
    }

    private nonisolated static func decodeEntityToken(_ token: String) -> String? {
        if token.hasPrefix("#x") || token.hasPrefix("#X") {
            let hex = token.dropFirst(2)
            guard let codePoint = UInt32(hex, radix: 16),
                  let scalar = Unicode.Scalar(codePoint) else {
                return nil
            }
            return String(scalar)
        }
        if token.hasPrefix("#") {
            let digits = token.dropFirst()
            guard let codePoint = UInt32(digits, radix: 10),
                  let scalar = Unicode.Scalar(codePoint) else {
                return nil
            }
            return String(scalar)
        }
        return namedEntities[token]
    }

    /// Standalone action words, button labels, and short modal headers that indicate cookie/consent acceptance.
    private nonisolated static let consentActionPhrases: Set<String> = [
        // French
        "tout accepter", "accepter tout", "accepter les cookies", "accepter tous les cookies",
        "tout refuser", "refuser tout", "refuser les cookies", "continuer sans accepter", "poursuivre sans accepter",
        "paramétrer les cookies", "paramétrer vos choix", "paramètres des cookies", "personnaliser les choix",
        "gérer les cookies", "gérer mes préférences", "gérer mes choix", "gestion des cookies",
        "avant d'accéder à youtube", "before you continue to youtube",
        "avant d'accéder à google", "before you continue to google",
        "avant de continuer sur youtube", "avant de continuer sur google",
        // English
        "accept all cookies", "accept all", "accept cookies", "accept and close", "accept & close",
        "reject all cookies", "reject all", "decline all", "continue without accepting",
        "cookie preferences", "manage cookies", "cookie settings", "customize choices",
        // Spanish
        "aceptar todas las cookies", "aceptar todas", "aceptar cookies", "aceptar y cerrar",
        "rechazar todas", "rechazar cookies", "continuar sin aceptar", "configurar cookies",
        "preferencias de cookies", "gestionar cookies",
        // German
        "alle akzeptieren", "cookies akzeptieren", "alle ablehnen",
        "cookie-einstellungen", "einstellungen verwalten",
        // Italian
        "accetta tutti", "rifiuta tutti", "gestisci preferenze", "preferenze cookie"
    ]

    /// Key phrasing found in Google, YouTube, and CMP consent banners.
    private nonisolated static let consentKeyPhrases: [String] = [
        // YouTube / Google consent bump exact clauses (French)
        "proposer les services google et s'assurer qu'ils fonctionnent correctement",
        "suivre les interruptions de service et protéger contre le spam",
        "mesurer l'engagement de l'audience et les statistiques des sites",
        "développer de nouveaux services et les améliorer",
        "diffuser des annonces et évaluer leur efficacité",
        "proposer des contenus personnalisés en fonction de vos paramètres",
        "afficher des annonces personnalisées en fonction de vos paramètres",
        "si vous sélectionnez \"tout accepter\"",
        "si vous sélectionnez « tout accepter »",
        "si vous sélectionnez tout accepter",
        "si vous sélectionnez \"tout refuser\"",
        "si vous sélectionnez « tout refuser »",
        "si vous sélectionnez tout refuser",
        "cookies et des données, y compris des adresses ip",
        "avant d'accéder à youtube",
        "avant d'accéder à google",
        "avant de continuer sur youtube",
        "avant de continuer sur google",
        // YouTube / Google consent bump exact clauses (English)
        "deliver google services and maintain them",
        "track outages and protect against spam, fraud, and abuse",
        "measure audience engagement and site statistics",
        "develop and improve new services",
        "deliver and measure the effectiveness of ads",
        "show personalized content, depending on your settings",
        "show personalized ads, depending on your settings",
        "if you choose to \"accept all\"",
        "if you choose to accept all",
        "if you choose to \"reject all\"",
        "if you choose to reject all",
        "cookies and data, including ip addresses",
        "before you continue to youtube",
        "before you continue to google"
    ]

    /// Determines whether plain text or markdown segment corresponds to cookie consent boilerplate.
    nonisolated static func isCookieConsentText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()

        // 1. Short standalone actions, button labels, and modal headers (<= 120 chars)
        if trimmed.count <= 120 {
            let cleanShort = lower.trimmingCharacters(in: CharacterSet(charactersIn: "\"'«»[]() \t\n\r-*•#"))
            if consentActionPhrases.contains(cleanShort) {
                return true
            }
            for action in consentActionPhrases {
                if cleanShort == action || cleanShort.hasPrefix(action) {
                    return true
                }
            }
        }

        // 2. High-confidence consent clauses (Google, YouTube, CMP boilerplate)
        for phrase in consentKeyPhrases {
            if lower.contains(phrase) {
                return true
            }
        }

        // 3. Cookie keyword in combination with consent action / explanation
        let hasCookieWord = lower.contains("cookie")
            || lower.contains("cookies")
            || lower.contains("témoin")
            || lower.contains("témoins")
            || lower.contains("galleta")
            || lower.contains("galletas")
            || lower.contains("consent")
            || lower.contains("gdpr")

        if hasCookieWord {
            let cookieActions = [
                "tout accepter", "accepter tout", "accepter les", "refuser tout", "tout refuser", "paramétrer", "gérer mes", "personnaliser",
                "nous utilisons", "ce site utilise", "notre site utilise", "en poursuivant", "en cliquant",
                "accept all", "accept cookies", "reject all", "decline all", "manage cookies", "customize choices", "cookie preferences", "cookie settings",
                "we use cookies", "this site uses cookies", "this website uses cookies", "by continuing to use", "by clicking accept",
                "adresses ip", "ip addresses", "données personnelles", "personal data", "partenaires", "partners",
                "stocker et/ou accéder", "store and/or access", "finalités suivantes", "following purposes",
                "politique relative aux cookies", "politique de cookies", "cookie policy"
            ]
            for action in cookieActions {
                if lower.contains(action) {
                    return true
                }
            }
        }

        return false
    }

    /// Fast scanner removing cookie consent banners, modals, and acceptance blocks from HTML.
    nonisolated static func removeCookieConsent(from html: String) -> String {
        let lower = html.lowercased()
        guard lower.contains("cookie")
            || lower.contains("consent")
            || lower.contains("onetrust")
            || lower.contains("didomi")
            || lower.contains("cookiebot")
            || lower.contains("usercentrics")
            || lower.contains("tarteaucitron")
            || lower.contains("axeptio")
            || lower.contains("sp_message")
            || lower.contains("cmplz")
            || lower.contains("iubenda")
            || lower.contains("gdpr")
            || lower.contains("témoin")
            || lower.contains("galleta")
            || lower.contains("tout accepter")
            || lower.contains("accept all")
            || lower.contains("avant d'accéder")
            || lower.contains("before you continue") else {
            return html
        }

        var cleaned = html

        // 1. Strip non-content blocks (scripts, styles, templates) first so scanner avoids JS/CSS noise
        if let nonContentRegex = nonContentBlockRegex {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = nonContentRegex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "\n")
        }

        // 2. Strip standalone consent forms, dialogs, asides, and custom web components
        if let formRegex = consentFormRegex {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = formRegex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "\n")
        }
        if let dialogRegex = consentDialogRegex {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = dialogRegex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "\n")
        }
        if let asideRegex = consentAsideRegex {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = asideRegex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "\n")
        }
        if let webCompRegex = consentWebComponentRegex {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = webCompRegex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "\n")
        }

        // 3. Strip balanced container tags (<div id="consent-bump">, <section class="cookie-modal">, etc.)
        cleaned = removeCookieConsentContainers(from: cleaned)

        // 4. Strip standalone consent elements (<p>, <li>, <h2>, <button>, etc.)
        if let elemRegex = consentElementRegex {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            let matches = elemRegex.matches(in: cleaned, options: [], range: range)
            if !matches.isEmpty {
                var rangesToRemove: [Range<String.Index>] = []
                for match in matches {
                    guard let fullRange = Range(match.range, in: cleaned),
                          let contentRange = Range(match.range(at: 2), in: cleaned) else {
                        continue
                    }
                    let inner = String(cleaned[contentRange])
                    let plain = rawHTMLToPlainText(inner).trimmingCharacters(in: .whitespacesAndNewlines)
                    if isCookieConsentText(plain) {
                        rangesToRemove.append(fullRange)
                    }
                }
                for r in rangesToRemove.reversed() {
                    cleaned.replaceSubrange(r, with: "\n")
                }
            }
        }

        // 5. Clean up any empty <ul> / <ol> blocks left behind by stripped <li> consent items
        if let emptyListRegex = emptyListRegex {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = emptyListRegex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }

        return cleaned
    }

    nonisolated private static func removeCookieConsentContainers(from html: String) -> String {
        guard let tagRegex = candidateContainerTagRegex else { return html }
        var result = html
        var searchIndex = result.startIndex
        let candidateTags: Set<String> = [
            "div", "section", "aside", "dialog", "form", "footer", "nav", "header",
            "ytd-consent-bump-v2-renderer", "yt-confirm-dialog-renderer", "cookie-banner", "consent-banner"
        ]
        let protectedTags: Set<String> = ["html", "head", "body", "main", "article"]

        while searchIndex < result.endIndex {
            let currentSearchRange = NSRange(searchIndex..<result.endIndex, in: result)
            guard let match = tagRegex.firstMatch(in: result, options: [], range: currentSearchRange),
                  let fullRange = Range(match.range, in: result),
                  let tagRange = Range(match.range(at: 1), in: result),
                  let attrRange = Range(match.range(at: 2), in: result) else {
                break
            }

            let tagName = String(result[tagRange]).lowercased()
            let attrs = String(result[attrRange])
            let openTagStart = fullRange.lowerBound
            let openTagEnd = fullRange.upperBound

            // If tag is self-closing (<tag ... />), advance past it
            let trimmedAttrs = attrs.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedAttrs.hasSuffix("/") {
                searchIndex = openTagEnd
                continue
            }

            // Protected structural tags or non-candidate tags must never be removed as an entire container
            if protectedTags.contains(tagName) || !candidateTags.contains(tagName) {
                searchIndex = openTagEnd
                continue
            }

            let hasCookieAttribute: Bool = {
                guard let attrRegex = cookieAttributeRegex else { return false }
                return attrRegex.firstMatch(
                    in: attrs,
                    options: [],
                    range: NSRange(attrs.startIndex..., in: attrs)
                ) != nil
            }()

            // Balanced closing tag finder
            var depth = 1
            var scan = openTagEnd
            var closeTagEnd: String.Index? = nil
            let maxScanDistance = 35_000
            let scanLimit = result.index(openTagStart, offsetBy: maxScanDistance, limitedBy: result.endIndex) ?? result.endIndex

            while scan < scanLimit {
                guard let nextLt = result[scan..<scanLimit].firstIndex(of: "<") else { break }
                let afterLt = result.index(after: nextLt)
                guard afterLt < scanLimit else { break }

                if result[afterLt] == "/" { // Closing tag candidate </tag>
                    let nameStart = result.index(after: afterLt)
                    let nameLimit = result.index(nameStart, offsetBy: tagName.count, limitedBy: scanLimit) ?? scanLimit
                    if result.distance(from: nameStart, to: nameLimit) == tagName.count &&
                        result[nameStart..<nameLimit].caseInsensitiveCompare(tagName) == .orderedSame {
                        if nameLimit < scanLimit && (result[nameLimit] == ">" || result[nameLimit].isWhitespace) {
                            if let gt = result[nameLimit..<scanLimit].firstIndex(of: ">") {
                                depth -= 1
                                if depth == 0 {
                                    closeTagEnd = result.index(after: gt)
                                    break
                                }
                                scan = result.index(after: gt)
                                continue
                            }
                        }
                    }
                } else { // Opening tag candidate <tag ...>
                    let nameLimit = result.index(afterLt, offsetBy: tagName.count, limitedBy: scanLimit) ?? scanLimit
                    if result.distance(from: afterLt, to: nameLimit) == tagName.count &&
                        result[afterLt..<nameLimit].caseInsensitiveCompare(tagName) == .orderedSame {
                        if nameLimit < scanLimit && (result[nameLimit] == ">" || result[nameLimit].isWhitespace || result[nameLimit] == "/") {
                            if let gt = result[nameLimit..<scanLimit].firstIndex(of: ">") {
                                let isSelfClosing = result[result.index(before: gt)] == "/"
                                if !isSelfClosing {
                                    depth += 1
                                }
                                scan = result.index(after: gt)
                                continue
                            }
                        }
                    }
                }
                scan = result.index(after: nextLt)
            }

            guard depth == 0, let endIdx = closeTagEnd else {
                searchIndex = openTagEnd
                continue
            }

            var shouldRemove = hasCookieAttribute
            if !shouldRemove {
                // For containers without explicit cookie attributes, only remove if:
                // 1. It does NOT contain major content containers or headers (article, main, h1, h2, h3)
                // 2. The inner plain text is short (<= 1500 chars)
                // 3. The inner text is cookie consent boilerplate
                let innerHTML = String(result[openTagEnd..<endIdx])
                let lowerInner = innerHTML.lowercased()
                let hasMajorContent = lowerInner.contains("<article")
                    || lowerInner.contains("<main")
                    || lowerInner.contains("<h1")
                    || lowerInner.contains("<h2")
                    || lowerInner.contains("<h3")

                if !hasMajorContent {
                    let plain = rawHTMLToPlainText(innerHTML).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !plain.isEmpty && plain.count <= 1500 && isCookieConsentText(plain) {
                        shouldRemove = true
                    }
                }
            }

            if shouldRemove {
                result.replaceSubrange(openTagStart..<endIdx, with: "\n")
                searchIndex = openTagStart
            } else {
                searchIndex = openTagEnd
            }
        }

        return result
    }

    /// Strips non-content blocks, comments, and HTML tags without cookie stripping (used internally).
    nonisolated private static func rawHTMLToPlainText(_ html: String) -> String {
        var text = html
        if let nonContentRegex = nonContentBlockRegex {
            text = nonContentRegex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: ""
            )
        }
        if let commentRegex = htmlCommentRegex {
            text = commentRegex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: ""
            )
        }
        if let tagRegex = htmlTagRegex {
            text = tagRegex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: " "
            )
        }
        return decodeEntities(text)
    }

    /// Strips cookie consent, non-content blocks, HTML comments and tags, and decodes HTML entities.
    nonisolated static func htmlToPlainText(_ html: String) -> String {
        let withoutCookies = removeCookieConsent(from: html)
        return rawHTMLToPlainText(withoutCookies)
    }

    /// Strips cookie consent, HTML comments and tags while converting block tags into newlines,
    /// preserving paragraph and list structure suitable for RAG chunking.
    nonisolated static func htmlToPlainTextWithStructure(_ html: String) -> String {
        var text = removeCookieConsent(from: html)
        if let nonContentRegex = nonContentBlockRegex {
            text = nonContentRegex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: ""
            )
        }
        if let commentRegex = htmlCommentRegex {
            text = commentRegex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: ""
            )
        }
        if let breakRegex = htmlBreakTagRegex {
            text = breakRegex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: "\n"
            )
        }
        if let blockRegex = htmlBlockTagRegex {
            text = blockRegex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: "\n\n"
            )
        }
        if let tagRegex = htmlTagRegex {
            text = tagRegex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: " "
            )
        }
        text = decodeEntities(text)
        let lines = text.components(separatedBy: "\n").map { line in
            line.replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        text = lines.joined(separator: "\n")
        if let newlineRegex = multipleNewlineRegex {
            text = newlineRegex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: "\n\n"
            )
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strips HTML tags only.
    nonisolated static func stripTags(_ text: String, replacement: String = "") -> String {
        guard let tagRegex = htmlTagRegex else { return text }
        return tagRegex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: replacement
        )
    }
}

