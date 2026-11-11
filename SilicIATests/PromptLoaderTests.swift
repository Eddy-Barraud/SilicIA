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

    func testPromptTemplatesLoadFromDisk() {
        for language in [ModelLanguage.english, .french, .spanish] {
            // Search tool calling prompt with U-shaped layout
            let prompt = PromptLoader.loadPrompt(
                mode: "normal",
                feature: "search",
                variant: "tool_calling",
                language: language,
                replacements: [
                    "query": "Test query",
                    "corpusHint": "Sample hint",
                    "keyPoints": "1 to 3",
                    "maxOutputTokens": "200",
                    "maxOutputSentences": "10",
                    "structureDirective": "1. Direct answer",
                    "lengthDirective": "Target length: 8 sentences.",
                    "groundingContext": "Grounding snippet\n\n"
                ]
            )
            XCTAssertNotNil(prompt, "Missing prompt file for \(language.code)")
            if let prompt {
                XCTAssertTrue(prompt.contains("Test query"))
                XCTAssertTrue(prompt.contains("Grounding snippet"))
                XCTAssertFalse(prompt.contains("{{query}}"))
            }

            // Corpus hints
            let cached = PromptLoader.loadPrompt(mode: "normal", feature: "search", variant: "corpus_hint.cached", language: language, replacements: ["count": "5"])
            XCTAssertTrue(cached?.contains("5") == true)

            // Profile directives
            let structure = PromptLoader.loadPrompt(mode: "profile", feature: "structure", variant: "concise", language: language, replacements: ["keyPointsRange": "2 to 3"])
            XCTAssertNotNil(structure)
            XCTAssertFalse(structure?.contains("{{") == true)
        }
    }

    func testToolKitComponentsAndInstructionsAppendix() {
        for language in [ModelLanguage.english, .french, .spanish] {
            // Components
            XCTAssertNotNil(PromptLoader.loadPrompt(mode: "normal", feature: "toolkit", variant: "header", language: language))
            XCTAssertTrue(PromptLoader.loadPrompt(mode: "normal", feature: "toolkit", variant: "tool.calculate", language: language)?.contains("calculate") == true)
            XCTAssertTrue(PromptLoader.loadPrompt(mode: "normal", feature: "toolkit", variant: "tool.current_date_time", language: language)?.contains("currentDateTime") == true)
            XCTAssertTrue(PromptLoader.loadPrompt(mode: "normal", feature: "toolkit", variant: "tool.search_sources.both", language: language)?.contains("searchSources") == true)

            // Appendix assembly
            let full = ToolKit.instructionsAppendix(for: language, tone: .chat, webSearchAvailable: true, hasCorpus: true)
            XCTAssertTrue(full.contains("searchContext"))
            XCTAssertTrue(full.contains("calculate"))
            XCTAssertTrue(full.contains("currentDateTime"))
            XCTAssertTrue(full.contains("searchSources"))

            let noWeb = ToolKit.instructionsAppendix(for: language, tone: .chat, webSearchAvailable: false, hasCorpus: false)
            XCTAssertFalse(noWeb.contains("searchSources"))
            XCTAssertTrue(noWeb.contains("calculate"))
        }
    }
}
