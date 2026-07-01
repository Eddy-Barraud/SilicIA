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
