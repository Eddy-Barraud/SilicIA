//
//  CalculatorToolTests.swift
//  SilicIATests
//
//  Unit tests for the Foundation Models `CalculatorTool`. Focuses on the
//  pure arithmetic + input-validation surface — the actual Foundation
//  Models hand-off (model decides to call the tool) is integration-tested
//  manually since it requires the on-device LM.
//  Unit tests for the Foundation Models `CalculatorTool`.
//

import XCTest
@testable import SilicIA

final class CalculatorToolTests: XCTestCase {

    private let tool = CalculatorTool()

    override func setUp() {
        super.setUp()
        // Loop-guard state is process-wide static. Wipe it before each test
        // so a single test never observes another test's counters.
        CalculatorTool.resetLoopGuardForTesting()
    }

    // MARK: - Basic arithmetic

    func testIntegerAddition() async throws {
        let output = try await tool.call(arguments: .init(expression: "2 + 3"))
        XCTAssertEqual(output, "5")
    func testBasicArithmetic() async throws {
        let cases: [(String, String)] = [
            ("2 + 3", "5"),
            ("12 * 12", "144"),
            ("10 / 4", "2.5"),
            ("(1 + 2) * 3", "9"),
            ("-5 + 3", "-2")
        ]
        for (expression, expected) in cases {
            let output = try await tool.call(arguments: .init(expression: expression))
            XCTAssertEqual(output, expected, "Failed for '\(expression)'")
        }
    }

    func testIntegerMultiplication() async throws {
        let output = try await tool.call(arguments: .init(expression: "12 * 12"))
        XCTAssertEqual(output, "144")
    func testDecimalAndCommaFormatting() async throws {
        let cases: [(String, String)] = [
            ("1,5 * 2", "3"),
            ("64,24 * 2", "128.48"),
            ("77.08 * 2", "154.16")
        ]
        for (expression, expected) in cases {
            let output = try await tool.call(arguments: .init(expression: expression))
            XCTAssertEqual(output, expected, "Failed for '\(expression)'")
        }
    }

    func testDivisionWithDecimal() async throws {
        let output = try await tool.call(arguments: .init(expression: "10 / 4"))
        XCTAssertEqual(output, "2.5")
    func testRejectsInvalidSyntax() async throws {
        let invalidExpressions = [
            "FUNCTION(123, 'abs')",
            "self.value",
            "   "
        ]
        for expr in invalidExpressions {
            let output = try await tool.call(arguments: .init(expression: expr))
            XCTAssertTrue(output.hasPrefix("Error"), "Expected error for '\(expr)', got: \(output)")
        }
    }

    func testParentheses() async throws {
        let output = try await tool.call(arguments: .init(expression: "(1 + 2) * 3"))
        XCTAssertEqual(output, "9")
    }
    func testFactorialEvaluationAndPrecisionCap() async throws {
        // Valid factorials
        let cases: [(String, String)] = [
            ("0!", "1"),
            ("5!", "120"),
            ("3! + 4!", "30"),
            ("15!", "1307674368000")
        ]
        for (expression, expected) in cases {
            let result = try await tool.call(arguments: .init(expression: expression))
            XCTAssertEqual(result, expected, "Failed for '\(expression)'")
        }

    func testUnaryMinus() async throws {
        let output = try await tool.call(arguments: .init(expression: "-5 + 3"))
        XCTAssertEqual(output, "-2")
        // 16! crosses precision cap
        let overCap = try await tool.call(arguments: .init(expression: "16!"))
        XCTAssertTrue(overCap.hasPrefix("Error"), "16! should exceed precision cap: \(overCap)")
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

    // MARK: - Factorial

    /// Regression for the loop-bug the user hit: model emitted `5!`, the
    /// allow-list rejected it as unsupported, and the model just retried
    /// the same broken input dozens of times. Native factorial support
    /// short-circuits the loop at its source.
    func testFactorialOfSmallInteger() async throws {
        let output = try await tool.call(arguments: .init(expression: "5!"))
        XCTAssertEqual(output, "120", "5! should evaluate to 120, got \(output)")
    }

    func testFactorialOfZeroIsOne() async throws {
        let output = try await tool.call(arguments: .init(expression: "0!"))
        XCTAssertEqual(output, "1", "0! should evaluate to 1, got \(output)")
    }

    func testFactorialEmbeddedInExpression() async throws {
        // 3! + 4! = 6 + 24 = 30
        let output = try await tool.call(arguments: .init(expression: "3! + 4!"))
        XCTAssertEqual(output, "30")
    }

    func testFactorialOfFifteenMaxSupported() async throws {
        // 15! = 1_307_674_368_000 — largest n whose value fits in Double's
        // 2^53 exact-integer range, so the result prints as a clean integer
        // instead of falling back to scientific notation.
        let output = try await tool.call(arguments: .init(expression: "15!"))
        XCTAssertEqual(output, "1307674368000")
    }

    /// 16! crosses the precision boundary; the tool should reject the
    /// expression with a recoverable error rather than silently lose
    /// trailing digits to Double rounding.
    func testFactorialAboveCapRejected() async throws {
        let output = try await tool.call(arguments: .init(expression: "16!"))
        XCTAssertTrue(output.hasPrefix("Error"),
                      "16! should be rejected (above the precision cap), got: \(output)")
    }

    // MARK: - Loop guard

    /// Identical expression called more than the threshold times in the
    /// window must trigger the stop-directive so the model breaks out of
    /// a tool-call loop instead of retrying forever.
    func testLoopGuardTriggersOnRepeatedIdenticalCalls() async throws {
        // Use an expression the allow-list rejects so each call would
        // otherwise return the same Error message — perfect feedstock for
        // the model's retry loop.
    func testLoopGuard() async throws {
        // Triggers on repeated identical bad expressions
        let badExpression = "abc!"
        var sawStop = false
        for _ in 0..<6 {
            let output = try await tool.call(arguments: .init(expression: badExpression))
            if output.contains("STOP CALLING THIS TOOL") {
                sawStop = true
                break
            }
        }
        XCTAssertTrue(sawStop,
                      "Loop guard did not engage after repeated identical calls")
    }
        XCTAssertTrue(sawStop, "Loop guard did not engage on repeated identical calls")

    /// Different expressions in a row must NOT trigger the loop guard —
    /// otherwise legitimate sequences (e.g. multiple steps of a long
    /// calculation) would be incorrectly blocked.
    func testLoopGuardDoesNotTriggerOnDifferentExpressions() async throws {
        let expressions = ["1+1", "2+2", "3+3", "4+4", "5+5", "6+6", "7+7"]
        for expr in expressions {
            let output = try await tool.call(arguments: .init(expression: expr))
            XCTAssertFalse(output.contains("STOP CALLING THIS TOOL"),
                           "Loop guard wrongly fired on distinct expression \(expr): \(output)")
        // Does NOT trigger on distinct expressions
        CalculatorTool.resetLoopGuardForTesting()
        for i in 1...7 {
            let output = try await tool.call(arguments: .init(expression: "\(i)+\(i)"))
            XCTAssertFalse(output.contains("STOP CALLING THIS TOOL"))
        }
    }

    func testGovernorDuplicateReturnsRefusalInsteadOfThrowing() async throws {
    func testGovernorIntegration() async throws {
        // Soft refusal on duplicate without recorder
        var governedTool = CalculatorTool()
        governedTool.governor = ToolCallGovernor()

        _ = try await governedTool.call(arguments: .init(expression: "10 / 4"))
        let duplicate = try await governedTool.call(arguments: .init(expression: "10 / 4"))

        XCTAssertTrue(
            duplicate.localizedCaseInsensitiveContains("do not repeat") ||
            duplicate.localizedCaseInsensitiveContains("write your final answer now"),
            "Duplicate governed calculator call should return a soft refusal, got: \(duplicate)"
            duplicate.localizedCaseInsensitiveContains("write your final answer now")
        )
    }

    func testGovernorDuplicateThrowsWhenRecoveryRecorderIsPresent() async throws {
        var governedTool = CalculatorTool()
        governedTool.governor = ToolCallGovernor()
        governedTool.transcriptRecorder = ToolTranscriptRecorder()

        _ = try await governedTool.call(arguments: .init(expression: "10 / 4"))

        // Throws duplicate ToolError with recovery recorder
        var recordedTool = CalculatorTool()
        recordedTool.governor = ToolCallGovernor()
        recordedTool.transcriptRecorder = ToolTranscriptRecorder()
        _ = try await recordedTool.call(arguments: .init(expression: "10 / 4"))
        do {
            _ = try await governedTool.call(arguments: .init(expression: "10 / 4"))
            XCTFail("Expected duplicate governed calculator call to abort when recovery recorder is present")
            _ = try await recordedTool.call(arguments: .init(expression: "10 / 4"))
            XCTFail("Expected duplicate ToolError")
        } catch let error as ToolError {
            guard case .duplicate(let toolName, let count) = error else {
                return XCTFail("Expected duplicate ToolError, got \(error)")
            }
            XCTAssertEqual(toolName, "calculate")
            XCTAssertEqual(count, 2)
        }
    }
}
