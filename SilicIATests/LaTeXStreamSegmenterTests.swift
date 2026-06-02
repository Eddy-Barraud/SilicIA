//
//  LaTeXStreamSegmenterTests.swift
//  SilicIATests
//
//  Verifies the safe-cut-point detection that lets StreamingLaTeXText render
//  streamed math progressively: boundaries land only at sentence / display
//  ends with balanced delimiters, open math defers a boundary, and currency
//  `$` is not mistaken for inline math.
//

import XCTest
@testable import SilicIA

final class LaTeXStreamSegmenterTests: XCTestCase {

    func testNoBoundaryUntilFirstSentenceCompletes() {
        XCTAssertTrue(LaTeXStreamSegmenter.safeBoundaries("The value is").isEmpty)
        XCTAssertTrue(LaTeXStreamSegmenter.safeBoundaries("Computing the result").isEmpty)
    }

    func testSingleSentenceBoundaryAtPeriod() {
        let text = "This is one sentence."
        let b = LaTeXStreamSegmenter.safeBoundaries(text)
        XCTAssertEqual(b, [text.count])
    }

    func testTwoSentencesTwoBoundaries() {
        let text = "First sentence. Second sentence."
        let b = LaTeXStreamSegmenter.safeBoundaries(text)
        XCTAssertEqual(b.count, 2)
        XCTAssertEqual(String(text.prefix(b[0])), "First sentence.")
    }

    func testBalancedInlineMathCommitsAtSentenceEnd() {
        let text = "The solution is $x = 1$ today."
        let b = LaTeXStreamSegmenter.safeBoundaries(text)
        XCTAssertEqual(b, [text.count])
    }

    /// The closing `$` of inline math must close even when it follows a digit
    /// (`...1$`) — the regression that previously left math open forever.
    func testInlineMathClosesEvenWhenClosingDollarFollowsDigit() {
        let text = "We get $a = 1$ and $b = 2$ here."
        let b = LaTeXStreamSegmenter.safeBoundaries(text)
        XCTAssertEqual(b, [text.count])
    }

    func testOpenInlineMathDefersBoundary() {
        // `$x` opens inline math and is never closed → the trailing period is
        // inside math, so there's no safe boundary yet.
        let text = "Let $x be the value."
        XCTAssertTrue(LaTeXStreamSegmenter.safeBoundaries(text).isEmpty)
    }

    func testCurrencyDollarIsNotMath() {
        // `$5.00` is currency (adjacent to digits), so the sentence still
        // commits normally and the inner `.` (between digits) is not a cut.
        let text = "It costs $5.00 today."
        let b = LaTeXStreamSegmenter.safeBoundaries(text)
        XCTAssertEqual(b, [text.count])
    }

    func testClosedDisplayBlockIsBoundaryWithoutTerminator() {
        let text = "Equation: \\[ x = 1 \\] and more"
        let b = LaTeXStreamSegmenter.safeBoundaries(text)
        XCTAssertFalse(b.isEmpty, "a closed display block should be a safe boundary")
        let committed = String(text.prefix(b[0]))
        XCTAssertTrue(committed.hasSuffix("\\]"), "boundary should land right after the display close: \(committed)")
    }

    func testOpenDisplayBlockDefersBoundary() {
        let text = "See \\[ x = 1. The rest"
        XCTAssertTrue(LaTeXStreamSegmenter.safeBoundaries(text).isEmpty)
    }

    func testNewlineIsBoundary() {
        let text = "Line one\nLine two."
        let b = LaTeXStreamSegmenter.safeBoundaries(text)
        XCTAssertEqual(b.count, 2)
        XCTAssertEqual(String(text.prefix(b[0])), "Line one\n")
    }

    func testDisplayDollarsBalanced() {
        let text = "Here: $$a + b$$ then done."
        let b = LaTeXStreamSegmenter.safeBoundaries(text)
        XCTAssertFalse(b.isEmpty)
        // Final boundary covers the whole balanced string.
        XCTAssertEqual(b.last, text.count)
    }
}
