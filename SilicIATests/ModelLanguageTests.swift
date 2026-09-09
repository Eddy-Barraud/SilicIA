//
//  ModelLanguageTests.swift
//  SilicIATests
//

import XCTest
@testable import SilicIA

final class ModelLanguageTests: XCTestCase {

    func testSystemPreferredPicksFrench() {
        XCTAssertEqual(
            ModelLanguage.systemPreferred(preferredLanguages: ["fr-FR", "en-US"]),
            .french
        )
    func testSystemPreferredLanguageResolution() {
        let cases: [([String], ModelLanguage)] = [
            (["fr-FR", "en-US"], .french),
            (["es-ES", "en-US"], .spanish),
            (["de-DE", "it-IT"], .english),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(ModelLanguage.systemPreferred(preferredLanguages: input), expected)
        }
    }

    func testSystemPreferredPicksSpanish() {
        XCTAssertEqual(
            ModelLanguage.systemPreferred(preferredLanguages: ["es-ES", "en-US"]),
            .spanish
        )
    }

    func testSystemPreferredFallsBackToEnglish() {
        XCTAssertEqual(
            ModelLanguage.systemPreferred(preferredLanguages: ["de-DE", "it-IT"]),
            .english
        )
    }
}
