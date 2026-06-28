//
//  ToolCallGovernorTests.swift
//  SilicIATests
//
//  Verifies the tool-call loop breaker: it allows normal use, refuses exact
//  duplicates, caps the expensive `webSearch` tool tightly, and enforces a
//  hard total-call ceiling — the guarantees that stop a runaway model from
//  overflowing the 4096-token window (`exceededContextWindowSize`).
//

import XCTest
@testable import SilicIA

final class ToolCallGovernorTests: XCTestCase {

    func testFirstCallIsAllowed() async {
        let governor = ToolCallGovernor()
        let decision = await governor.evaluate(tool: "searchContext", arguments: "factorial")
        XCTAssertEqual(decision, .allow)
        XCTAssertNil(decision.refusalMessage)
    }

    func testExactDuplicateIsRefused() async {
        let governor = ToolCallGovernor()
        _ = await governor.evaluate(tool: "webSearch", arguments: "how to calculate factorial n")
        // Same query (different case / spacing) is treated as a duplicate.
        let dup = await governor.evaluate(tool: "webSearch", arguments: "  How To Calculate Factorial N ")
        XCTAssertEqual(dup, .duplicate(count: 2))
        XCTAssertNotNil(dup.refusalMessage)
    }

    /// The production default caps webSearch at 2 distinct calls, kept in
    /// lock-step with the 1000t per-reply ceiling so 2×1000 fits the window.
    func testDefaultExpensiveCapIsTwo() async {
        let governor = ToolCallGovernor()   // production defaults
        let first = await governor.evaluate(tool: "webSearch", arguments: "q1")
        let second = await governor.evaluate(tool: "webSearch", arguments: "q2")
        let third = await governor.evaluate(tool: "webSearch", arguments: "q3")
        XCTAssertEqual(first, .allow)
        XCTAssertEqual(second, .allow)
        XCTAssertEqual(third, .toolBudgetReached(tool: "webSearch", cap: 2))
    }

    func testWebSearchIsCappedAfterThreeDistinctQueries() async {
        let governor = ToolCallGovernor(maxTotalCalls: 20, maxExpensiveToolCalls: 3)
        for i in 1...3 {
            let d = await governor.evaluate(tool: "webSearch", arguments: "query \(i)")
            XCTAssertEqual(d, .allow, "distinct webSearch #\(i) should be allowed")
        }
        // 4th DISTINCT webSearch exceeds the expensive-tool cap.
        let fourth = await governor.evaluate(tool: "webSearch", arguments: "query 4")
        XCTAssertEqual(fourth, .toolBudgetReached(tool: "webSearch", cap: 3))
    }

    func testNonExpensiveToolsAreNotCappedByExpensiveLimit() async {
        let governor = ToolCallGovernor(maxTotalCalls: 20, maxExpensiveToolCalls: 3)
        // calculate is cheap — 4 DISTINCT calls all allowed (well under total).
        for i in 1...4 {
            let d = await governor.evaluate(tool: "calculate", arguments: "\(i) + \(i)")
            XCTAssertEqual(d, .allow, "distinct calculate #\(i) should be allowed")
        }
    }

    func testTotalCallCeilingStopsEverything() async {
        let governor = ToolCallGovernor(maxTotalCalls: 5, maxExpensiveToolCalls: 10)
        // Five distinct cheap calls consume the total budget.
        for i in 1...5 {
            _ = await governor.evaluate(tool: "calculate", arguments: "expr \(i)")
        }
        // The 6th attempt — even a brand-new tool/args — is refused.
        let over = await governor.evaluate(tool: "currentDateTime", arguments: "iso")
        XCTAssertEqual(over, .totalBudgetReached(cap: 5))
        XCTAssertNotNil(over.refusalMessage)
    }

    /// Refused calls keep counting toward the total ceiling, so a model that
    /// spams the SAME refused call still terminates.
    func testRepeatedDuplicatesStillHitTotalCeiling() async {
        let governor = ToolCallGovernor(maxTotalCalls: 4, maxExpensiveToolCalls: 10)
        var sawTotalCeiling = false
        for _ in 1...10 {
            let d = await governor.evaluate(tool: "webSearch", arguments: "same query")
            if case .totalBudgetReached = d { sawTotalCeiling = true }
        }
        XCTAssertTrue(sawTotalCeiling, "spamming a duplicate must eventually hit the total ceiling")
    }

    func testConfiguredSearchContextCapIsApplied() async {
        let governor = ToolCallGovernor(
            maxTotalCalls: 10,
            maxExpensiveToolCalls: 2,
            additionalToolCaps: ["searchContext": 3]
        )
        for i in 1...3 {
            let decision = await governor.evaluate(tool: "searchContext", arguments: "query \(i)")
            XCTAssertEqual(decision, .allow, "distinct searchContext #\(i) should be allowed")
        }
        let fourth = await governor.evaluate(tool: "searchContext", arguments: "query 4")
        XCTAssertEqual(fourth, .toolBudgetReached(tool: "searchContext", cap: 3))
    }
}
