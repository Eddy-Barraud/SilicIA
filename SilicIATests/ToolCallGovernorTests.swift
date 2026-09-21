//
//  ToolCallGovernorTests.swift
//  SilicIATests
//
//  Verifies the tool-call loop breaker: it allows normal use, refuses exact
//  duplicates, caps the expensive  tool tightly, and enforces a
//  duplicates, caps the expensive `webSearch` tool tightly, and enforces a
//  hard total-call ceiling — the guarantees that stop a runaway model from
//  overflowing the 4096-token window ().
//  overflowing the 4096-token window (`exceededContextWindowSize`).
//

import XCTest
@testable import SilicIA

final class ToolCallGovernorTests: XCTestCase {

    func testAllowanceAndDuplicateRefusal() async {
        let governor = ToolCallGovernor()
        let decision = await governor.evaluate(tool: "searchContext", arguments: "factorial")
        XCTAssertEqual(decision, .allow)
        XCTAssertNil(decision.refusalMessage)

        _ = await governor.evaluate(tool: "webSearch", arguments: "how to calculate factorial n")
        // Same query (different case / spacing) is treated as a duplicate.
        let dup = await governor.evaluate(tool: "webSearch", arguments: "  How To Calculate Factorial N ")
        XCTAssertEqual(dup, .duplicate(count: 2))
        XCTAssertNotNil(dup.refusalMessage)
    }

    func testToolBudgetCaps() async {
        // Default expensive cap: webSearch capped at 2 distinct calls
        let defaultGovernor = ToolCallGovernor()
        let first = await defaultGovernor.evaluate(tool: "webSearch", arguments: "q1")
        let second = await defaultGovernor.evaluate(tool: "webSearch", arguments: "q2")
        let third = await defaultGovernor.evaluate(tool: "webSearch", arguments: "q3")
        XCTAssertEqual(first, .allow)
        XCTAssertEqual(second, .allow)
        XCTAssertEqual(third, .toolBudgetReached(tool: "webSearch", cap: 2))

        // Custom expensive cap and non-expensive tool immunity
        let customGovernor = ToolCallGovernor(maxTotalCalls: 20, maxExpensiveToolCalls: 3)
        for i in 1...3 {
            let d = await customGovernor.evaluate(tool: "webSearch", arguments: "query \(i)")
            XCTAssertEqual(d, .allow, "distinct webSearch #\(i) should be allowed")
        }
        let fourth = await customGovernor.evaluate(tool: "webSearch", arguments: "query 4")
        XCTAssertEqual(fourth, .toolBudgetReached(tool: "webSearch", cap: 3))

        for i in 1...4 {
            let d = await customGovernor.evaluate(tool: "calculate", arguments: "\(i) + \(i)")
            XCTAssertEqual(d, .allow, "distinct calculate #\(i) should be allowed")
        }

        // Additional tool-specific cap
        let toolCapGov = ToolCallGovernor(maxTotalCalls: 10, maxExpensiveToolCalls: 2, additionalToolCaps: ["searchContext": 3])
        for i in 1...3 {
            let d = await toolCapGov.evaluate(tool: "searchContext", arguments: "query \(i)")
            XCTAssertEqual(d, .allow, "distinct searchContext #\(i) should be allowed")
        }
        let fourthSearch = await toolCapGov.evaluate(tool: "searchContext", arguments: "query 4")
        XCTAssertEqual(fourthSearch, .toolBudgetReached(tool: "searchContext", cap: 3))
    }

    func testTotalBudgetCeilingStopsCallsAndRepeatedDuplicates() async {
        let governor = ToolCallGovernor(maxTotalCalls: 5, maxExpensiveToolCalls: 10)
        for i in 1...5 {
            _ = await governor.evaluate(tool: "calculate", arguments: "expr \(i)")
        }
        let over = await governor.evaluate(tool: "currentDateTime", arguments: "iso")
        XCTAssertEqual(over, .totalBudgetReached(cap: 5))
        XCTAssertNotNil(over.refusalMessage)

        // Spamming duplicate also hits total ceiling
        let spamGovernor = ToolCallGovernor(maxTotalCalls: 4, maxExpensiveToolCalls: 10)
        var sawTotalCeiling = false
        for _ in 1...10 {
            let d = await spamGovernor.evaluate(tool: "webSearch", arguments: "same query")
            if case .totalBudgetReached = d { sawTotalCeiling = true }
        }
        XCTAssertTrue(sawTotalCeiling, "spamming a duplicate must eventually hit the total ceiling")
    }
}
