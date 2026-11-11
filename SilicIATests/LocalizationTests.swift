//
//  LocalizationTests.swift
//  SilicIATests
//

import XCTest
@testable import SilicIA

final class LocalizationTests: XCTestCase {

    private var service: LocalizationService { LocalizationService.shared }

    func testLocalizationKeysAndLookup() {
        // All languages must contain all English keys
        let frMissing = service.keys(for: .english).subtracting(service.keys(for: .french))
        XCTAssertTrue(frMissing.isEmpty, "FR missing keys: \(frMissing.sorted())")

        let esMissing = service.keys(for: .english).subtracting(service.keys(for: .spanish))
        XCTAssertTrue(esMissing.isEmpty, "ES missing keys: \(esMissing.sorted())")

        // Fallbacks
        XCTAssertEqual(service.t("nonexistent.key.foo"), "nonexistent.key.foo")
        XCTAssertFalse(service.t("common.back", language: .french).isEmpty)
        XCTAssertFalse(service.t("common.back", language: .english).isEmpty)
    }

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
}
