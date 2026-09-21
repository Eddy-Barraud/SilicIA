//
//  LocalizationTests.swift
//  SilicIATests
//

import XCTest
@testable import SilicIA

final class LocalizationTests: XCTestCase {

    private var service: LocalizationService { LocalizationService.shared }

    func testAllLanguagesContainEnglishKeys() {
        let frMissing = service.keys(for: .english).subtracting(service.keys(for: .french))
        XCTAssertTrue(frMissing.isEmpty, "FR missing keys: \(frMissing.sorted())")

        let esMissing = service.keys(for: .english).subtracting(service.keys(for: .spanish))
        XCTAssertTrue(esMissing.isEmpty, "ES missing keys: \(esMissing.sorted())")
    }

    func testLocalizationLookupAndFallbacks() {
        let result = service.t("nonexistent.key.foo")
        XCTAssertEqual(result, "nonexistent.key.foo")

        let frResult = service.t("common.back", language: .french)
        let enResult = service.t("common.back", language: .english)
        XCTAssertFalse(frResult.isEmpty)
        XCTAssertFalse(enResult.isEmpty)
    }
}
