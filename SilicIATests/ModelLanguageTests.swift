//
//  ModelLanguageTests.swift
//  SilicIATests
//

import XCTest
@testable import SilicIA

final class ModelLanguageTests: XCTestCase {

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
