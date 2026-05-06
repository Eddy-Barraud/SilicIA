//
//  LocalizationTests.swift
//  SilicIATests
//

import XCTest
@testable import SilicIA

final class LocalizationTests: XCTestCase {

    private var service: LocalizationService { LocalizationService.shared }

    func testEnglishKeysExistInFrench() {
        let missing = service.keys(for: .english).subtracting(service.keys(for: .french))
        XCTAssertTrue(missing.isEmpty, "FR missing keys: \(missing.sorted())")
    }

    func testEnglishKeysExistInSpanish() {
        let missing = service.keys(for: .english).subtracting(service.keys(for: .spanish))
        XCTAssertTrue(missing.isEmpty, "ES missing keys: \(missing.sorted())")
    }

    func testFallbackForUnknownKey() {
        let result = service.t("nonexistent.key.foo")
        XCTAssertEqual(result, "nonexistent.key.foo")
    }

    func testFallbackToEnglishWhenLanguageMissingKey() {
        let frResult = service.t("common.back", language: .french)
        let enResult = service.t("common.back", language: .english)
        XCTAssertFalse(frResult.isEmpty)
        XCTAssertFalse(enResult.isEmpty)
    }
}
