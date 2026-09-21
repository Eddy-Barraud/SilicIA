//
//  CalculatorToolTests.swift
//  SilicIATests
//
//  Unit tests for the Foundation Models `CalculatorTool`.
//

import XCTest
@testable import SilicIA

final class CalculatorToolTests: XCTestCase {

    private let tool = CalculatorTool()

    override func setUp() {
        super.setUp()
        CalculatorTool.resetLoopGuardForTesting()
    }

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

        // 16! crosses precision cap
        let overCap = try await tool.call(arguments: .init(expression: "16!"))
        XCTAssertTrue(overCap.hasPrefix("Error"), "16! should exceed precision cap: \(overCap)")
    }

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
        XCTAssertTrue(sawStop, "Loop guard did not engage on repeated identical calls")

        // Does NOT trigger on distinct expressions
        CalculatorTool.resetLoopGuardForTesting()
        for i in 1...7 {
            let output = try await tool.call(arguments: .init(expression: "\(i)+\(i)"))
            XCTAssertFalse(output.contains("STOP CALLING THIS TOOL"))
        }
    }

    func testGovernorIntegration() async throws {
        // Soft refusal on duplicate without recorder
        var governedTool = CalculatorTool()
        governedTool.governor = ToolCallGovernor()
        _ = try await governedTool.call(arguments: .init(expression: "10 / 4"))
        let duplicate = try await governedTool.call(arguments: .init(expression: "10 / 4"))
        XCTAssertTrue(
            duplicate.localizedCaseInsensitiveContains("do not repeat") ||
            duplicate.localizedCaseInsensitiveContains("write your final answer now")
        )

        // Throws duplicate ToolError with recovery recorder
        var recordedTool = CalculatorTool()
        recordedTool.governor = ToolCallGovernor()
        recordedTool.transcriptRecorder = ToolTranscriptRecorder()
        _ = try await recordedTool.call(arguments: .init(expression: "10 / 4"))
        do {
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
