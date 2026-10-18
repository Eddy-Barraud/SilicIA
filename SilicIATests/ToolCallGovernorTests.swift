//
//  ToolCallGovernorTests.swift
//  SilicIATests
//
//  Verifies the tool-call loop breaker: it allows normal use, refuses exact
//  duplicates, caps the expensive `searchSources` tool tightly (1 call), and enforces a
//  hard total-call ceiling — the guarantees that stop a runaway model from
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

        _ = await governor.evaluate(tool: "searchSources", arguments: "how to calculate factorial n")
        // Same query (different case / spacing) is treated as a duplicate.
        let dup = await governor.evaluate(tool: "searchSources", arguments: "  How To Calculate Factorial N ")
        XCTAssertEqual(dup, .duplicate(count: 2))
        XCTAssertNotNil(dup.refusalMessage)
    }

    func testToolBudgetCaps() async {
        // Default expensive cap: searchSources capped at 1 call
        let defaultGovernor = ToolCallGovernor()
        let first = await defaultGovernor.evaluate(tool: "searchSources", arguments: "q1")
        let second = await defaultGovernor.evaluate(tool: "searchSources", arguments: "q2")
        XCTAssertEqual(first, .allow)
        XCTAssertEqual(second, .toolBudgetReached(tool: "searchSources", cap: 1))

        // Custom expensive cap and non-expensive tool immunity
        let customGovernor = ToolCallGovernor(maxTotalCalls: 20, maxExpensiveToolCalls: 3, expensiveToolName: "searchSources")
        for i in 1...3 {
            let d = await customGovernor.evaluate(tool: "searchSources", arguments: "query \(i)")
            XCTAssertEqual(d, .allow, "distinct searchSources #\(i) should be allowed")
        }
        let fourth = await customGovernor.evaluate(tool: "searchSources", arguments: "query 4")
        XCTAssertEqual(fourth, .toolBudgetReached(tool: "searchSources", cap: 3))

        for i in 1...4 {
            let d = await customGovernor.evaluate(tool: "calculate", arguments: "\(i) + \(i)")
            XCTAssertEqual(d, .allow, "distinct calculate #\(i) should be allowed")
        }

        // Additional tool-specific cap
        let toolCapGov = ToolCallGovernor(maxTotalCalls: 10, maxExpensiveToolCalls: 1, expensiveToolName: "searchSources", additionalToolCaps: ["searchContext": 3])
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
        let spamGovernor = ToolCallGovernor(maxTotalCalls: 4, maxExpensiveToolCalls: 10, expensiveToolName: "searchSources")
        var sawTotalCeiling = false
        for _ in 1...10 {
            let d = await spamGovernor.evaluate(tool: "searchSources", arguments: "same query")
            if case .totalBudgetReached = d { sawTotalCeiling = true }
        }
        XCTAssertTrue(sawTotalCeiling, "spamming a duplicate must eventually hit the total ceiling")
    }
}
