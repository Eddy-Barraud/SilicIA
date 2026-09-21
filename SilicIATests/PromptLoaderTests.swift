//
//  PromptLoaderTests.swift
//  SilicIATests
//
//  Regression tests verifying prompt template loading from disk for
//  toolCallingSearchPrompt and ToolKit instructions appendix across
//  English, French, and Spanish.
//

import XCTest
@testable import SilicIA

final class PromptLoaderTests: XCTestCase {

    func testSearchToolCallingPromptLoadsFromDisk() {
        for language in [ModelLanguage.english, .french, .spanish] {
            let prompt = PromptLoader.loadPrompt(
                mode: "normal",
                feature: "search",
                variant: "tool_calling",
                language: language,
                replacements: [
                    "query": "Test query",
                    "corpusHint": "Sample hint",
                    "keyPoints": "1 to 3",
                    "maxOutputTokens": "200"
                ]
            )

            XCTAssertNotNil(prompt, "Missing prompt file for language: \(language.code)")
            guard let prompt = prompt else { continue }
            XCTAssertTrue(prompt.contains("Test query"))
            XCTAssertTrue(prompt.contains("Sample hint"))
            XCTAssertTrue(prompt.contains("200"))
            XCTAssertFalse(prompt.contains("{{query}}"))
            XCTAssertFalse(prompt.contains("{{corpusHint}}"))
            XCTAssertFalse(prompt.contains("Format de sortie requis : LaTeX"))
            XCTAssertFalse(prompt.contains("Required output format: LaTeX"))
        }
    }

    func testSearchCorpusHintsLoadFromDisk() {
        for language in [ModelLanguage.english, .french, .spanish] {
            let cached = PromptLoader.loadPrompt(
                mode: "normal",
                feature: "search",
                variant: "corpus_hint.cached",
                language: language,
                replacements: ["count": "5"]
            )
            XCTAssertNotNil(cached, "Missing cached corpus hint for \(language.code)")
            XCTAssertTrue(cached?.contains("5") == true)
            XCTAssertTrue(cached?.contains("searchContext") == true)

            let web = PromptLoader.loadPrompt(
                mode: "normal",
                feature: "search",
                variant: "corpus_hint.web",
                language: language
            )
            XCTAssertNotNil(web, "Missing web corpus hint for \(language.code)")
            XCTAssertTrue(web?.contains("webSearch") == true)

            let direct = PromptLoader.loadPrompt(
                mode: "normal",
                feature: "search",
                variant: "corpus_hint.direct",
                language: language
            )
            XCTAssertNotNil(direct, "Missing direct corpus hint for \(language.code)")
        }
    }

    func testToolKitComponentsLoadFromDisk() {
        for language in [ModelLanguage.english, .french, .spanish] {
            let header = PromptLoader.loadPrompt(mode: "normal", feature: "toolkit", variant: "header", language: language)
            XCTAssertNotNil(header, "Missing toolkit header for \(language.code)")

            let calc = PromptLoader.loadPrompt(mode: "normal", feature: "toolkit", variant: "tool.calculate", language: language)
            XCTAssertNotNil(calc, "Missing calculate tool prompt for \(language.code)")
            XCTAssertTrue(calc?.contains("calculate") == true)

            let dt = PromptLoader.loadPrompt(mode: "normal", feature: "toolkit", variant: "tool.current_date_time", language: language)
            XCTAssertNotNil(dt, "Missing currentDateTime tool prompt for \(language.code)")
            XCTAssertTrue(dt?.contains("currentDateTime") == true)

            let web = PromptLoader.loadPrompt(mode: "normal", feature: "toolkit", variant: "tool.web_search", language: language)
            XCTAssertNotNil(web, "Missing webSearch tool prompt for \(language.code)")
            XCTAssertTrue(web?.contains("webSearch") == true)

            let scChat = PromptLoader.loadPrompt(mode: "normal", feature: "toolkit", variant: "tool.search_context.chat", language: language)
            XCTAssertNotNil(scChat, "Missing searchContext chat prompt for \(language.code)")

            let scSearch = PromptLoader.loadPrompt(mode: "normal", feature: "toolkit", variant: "tool.search_context.search", language: language)
            XCTAssertNotNil(scSearch, "Missing searchContext search prompt for \(language.code)")

            let footerSearch = PromptLoader.loadPrompt(mode: "normal", feature: "toolkit", variant: "footer.with_search", language: language)
            XCTAssertNotNil(footerSearch, "Missing footer with_search for \(language.code)")

            let footerDirect = PromptLoader.loadPrompt(mode: "normal", feature: "toolkit", variant: "footer.direct", language: language)
            XCTAssertNotNil(footerDirect, "Missing footer direct for \(language.code)")
        }
    }

    func testToolKitInstructionsAppendixAssembly() {
        for language in [ModelLanguage.english, .french, .spanish] {
            let fullAppendix = ToolKit.instructionsAppendix(
                for: language,
                tone: .chat,
                webSearchAvailable: true,
                hasCorpus: true
            )
            XCTAssertTrue(fullAppendix.contains("searchContext"))
            XCTAssertTrue(fullAppendix.contains("calculate"))
            XCTAssertTrue(fullAppendix.contains("currentDateTime"))
            XCTAssertTrue(fullAppendix.contains("webSearch"))

            let noWebAppendix = ToolKit.instructionsAppendix(
                for: language,
                tone: .chat,
                webSearchAvailable: false,
                hasCorpus: false
            )
            XCTAssertFalse(noWebAppendix.contains("searchContext"))
            XCTAssertTrue(noWebAppendix.contains("calculate"))
            XCTAssertTrue(noWebAppendix.contains("currentDateTime"))
            XCTAssertFalse(noWebAppendix.contains("webSearch"))
        }
    }
}

