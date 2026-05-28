//
//  CalculatorToolTests.swift
//  SilicIATests
//
//  Unit tests for the Foundation Models `CalculatorTool`. Focuses on the
//  pure arithmetic + input-validation surface — the actual Foundation
//  Models hand-off (model decides to call the tool) is integration-tested
//  manually since it requires the on-device LM.
//

import XCTest
@testable import SilicIA

final class CalculatorToolTests: XCTestCase {

    private let tool = CalculatorTool()

    // MARK: - Basic arithmetic

    func testIntegerAddition() async throws {
        let output = try await tool.call(arguments: .init(expression: "2 + 3"))
        XCTAssertEqual(output, "5")
    }

    func testIntegerMultiplication() async throws {
        let output = try await tool.call(arguments: .init(expression: "12 * 12"))
        XCTAssertEqual(output, "144")
    }

    func testDivisionWithDecimal() async throws {
        let output = try await tool.call(arguments: .init(expression: "10 / 4"))
        XCTAssertEqual(output, "2.5")
    }

    func testParentheses() async throws {
        let output = try await tool.call(arguments: .init(expression: "(1 + 2) * 3"))
        XCTAssertEqual(output, "9")
    }

    func testUnaryMinus() async throws {
        let output = try await tool.call(arguments: .init(expression: "-5 + 3"))
        XCTAssertEqual(output, "-2")
    }

    // MARK: - Locale-friendly inputs

    /// French/Spanish users write "1,5" not "1.5"; the model copies values
    /// straight out of their documents. The tool must accept both.
    func testFrenchDecimalCommaAccepted() async throws {
        let output = try await tool.call(arguments: .init(expression: "1,5 * 2"))
        XCTAssertEqual(output, "3")
    }

    func testInvoiceLineTotalExample() async throws {
        // Real example: 2 amortisseurs at 64,24 € each = 128,48 €
        let output = try await tool.call(arguments: .init(expression: "64,24 * 2"))
        XCTAssertEqual(output, "128.48")
    }

    // MARK: - Validation

    /// Anything outside the allow-list must be rejected before reaching
    /// NSExpression — defends against the model passing a key-path or
    /// function-style expression.
    func testRejectsAlphabeticCharacters() async throws {
        let output = try await tool.call(arguments: .init(expression: "FUNCTION(123, 'abs')"))
        XCTAssertTrue(output.hasPrefix("Error"),
                      "Alphabetic input wasn't rejected: \(output)")
    }

    func testRejectsKeyPathSyntax() async throws {
        let output = try await tool.call(arguments: .init(expression: "self.value"))
        XCTAssertTrue(output.hasPrefix("Error"))
    }

    func testRejectsEmptyExpression() async throws {
        let output = try await tool.call(arguments: .init(expression: "   "))
        XCTAssertTrue(output.hasPrefix("Error"))
    }

    // MARK: - Precision

    func testFinancialPrecisionPreserved() async throws {
        // Real invoice math: 77.08 × 2 = 154.16 (decimal precision matters)
        let output = try await tool.call(arguments: .init(expression: "77.08 * 2"))
        XCTAssertEqual(output, "154.16")
    }
}
