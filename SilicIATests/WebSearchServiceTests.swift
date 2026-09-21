//
//  WebSearchServiceTests.swift
//  SilicIATests
//
//  Integration tests verifying that DuckDuckGo and Wikipedia search providers
//  fetch, parse, and return effective web data for concrete natural-language questions.
//

import XCTest
@testable import SilicIA

final class WebSearchServiceTests: XCTestCase {

    @MainActor
    func testDuckDuckGoRetrievesEffectiveWebData() async throws {
        let service = WebSearchService()
        let query = "Swift programming language Apple"

        let results = try await service.search(
            query: query,
            maxDuckDuckGoResults: 3,
            maxWikipediaResults: 0,
            language: .english,
            useDuckDuckGo: true,
            useWikipedia: false
        )

        XCTAssertFalse(results.isEmpty, "DuckDuckGo should return results for '\(query)'")
        guard let first = results.first else {
            XCTFail("No DuckDuckGo results returned")
            return
        }

        XCTAssertFalse(first.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Result title should not be empty")
        XCTAssertFalse(first.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Result URL should not be empty")
        XCTAssertTrue(first.url.hasPrefix("http://") || first.url.hasPrefix("https://"), "Result URL should be a valid web URL: \(first.url)")
        XCTAssertFalse(first.snippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Result snippet should not be empty")

        // Verify that returned results are semantically relevant to Swift / Apple
        let combinedText = results.map { "\($0.title) \($0.snippet)" }.joined(separator: " ").lowercased()
        let hasRelevantKeywords = combinedText.contains("swift")
            || combinedText.contains("apple")
            || combinedText.contains("programming")
            || combinedText.contains("language")
        XCTAssertTrue(hasRelevantKeywords, "DuckDuckGo results should contain relevant topic keywords")
    }

    @MainActor
    func testWikipediaAPIRetrievesEffectiveDataForConcreteQuestion() async throws {
        let service = WebSearchService()
        let question = "Who proposed the theory of general relativity?"

        let results = try await service.search(
            query: question,
            maxDuckDuckGoResults: 0,
            maxWikipediaResults: 2,
            language: .english,
            useDuckDuckGo: false,
            useWikipedia: true
        )

        XCTAssertFalse(results.isEmpty, "Wikipedia API should return results for question: '\(question)'")
        guard let topResult = results.first else {
            XCTFail("No Wikipedia results returned")
            return
        }

        XCTAssertTrue(topResult.url.contains("en.wikipedia.org"), "URL should be an English Wikipedia URL: \(topResult.url)")
        XCTAssertFalse(topResult.title.isEmpty, "Title should not be empty")

        let combinedText = results.map { "\($0.title) \($0.snippet)" }.joined(separator: " ").lowercased()
        let isRelativityOrEinstein = combinedText.contains("einstein")
            || combinedText.contains("relativity")
            || combinedText.contains("physic")
        XCTAssertTrue(isRelativityOrEinstein, "Top Wikipedia results should identify Einstein or Relativity for relativity question. Found: \(combinedText)")
    }

    @MainActor
    func testWikipediaMultilingualConcreteQuestions() async throws {
        let service = WebSearchService()

        // French concrete question
        let frQuestion = "Quelle est la capitale de l'Australie ?"
        let frResults = try await service.search(
            query: frQuestion,
            maxDuckDuckGoResults: 0,
            maxWikipediaResults: 2,
            language: .french,
            useDuckDuckGo: false,
            useWikipedia: true
        )
        XCTAssertFalse(frResults.isEmpty, "French Wikipedia should return results for '\(frQuestion)'")
        let frText = frResults.map { "\($0.title) \($0.snippet)" }.joined(separator: " ").lowercased()
        XCTAssertTrue(frText.contains("canberra") || frText.contains("australie"), "French Wikipedia should identify Canberra or Australie. Found: \(frText)")

        // Spanish concrete question
        let esQuestion = "¿Cuál es la capital de España?"
        let esResults = try await service.search(
            query: esQuestion,
            maxDuckDuckGoResults: 0,
            maxWikipediaResults: 2,
            language: .spanish,
            useDuckDuckGo: false,
            useWikipedia: true
        )
        XCTAssertFalse(esResults.isEmpty, "Spanish Wikipedia should return results for '\(esQuestion)'")
        let esText = esResults.map { "\($0.title) \($0.snippet)" }.joined(separator: " ").lowercased()
        XCTAssertTrue(esText.contains("madrid") || esText.contains("españa"), "Spanish Wikipedia should identify Madrid or España. Found: \(esText)")
    }
}

