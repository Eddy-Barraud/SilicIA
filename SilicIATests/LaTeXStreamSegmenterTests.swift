//
//  LaTeXStreamSegmenterTests.swift
//  SilicIATests
//
//  Verifies the safe-cut-point detection that lets StreamingLaTeXText render
//  streamed math progressively: boundaries land only at sentence / display
//  ends with balanced delimiters, open math defers a boundary, and currency
//  `$` is not mistaken for inline math.
//  Verifies safe cut points for progressive streaming LaTeX rendering.
//

import XCTest
@testable import SilicIA

final class LaTeXStreamSegmenterTests: XCTestCase {

    // MARK: - Paragraph blocks (stable per-block rendering)

    func testParagraphBlocksSplitOnBlankLines() {
    func testParagraphBlocks() {
        // Normal paragraph splitting
        let text = "Intro paragraph.\n\n$$\nE = mc^2\n$$\n\nClosing paragraph."
        let blocks = LaTeXStreamSegmenter.paragraphBlocks(in: text)
        XCTAssertEqual(blocks, ["Intro paragraph.", "$$\nE = mc^2\n$$", "Closing paragraph."])
    }

    func testParagraphBlocksCollapseMultipleBlankLines() {
        let text = "A\n\n\n\nB"
        XCTAssertEqual(LaTeXStreamSegmenter.paragraphBlocks(in: text), ["A", "B"])
    }
        // Collapsing multiple blank lines
        XCTAssertEqual(LaTeXStreamSegmenter.paragraphBlocks(in: "A\n\n\n\nB"), ["A", "B"])

    func testParagraphBlocksAreAppendOnlyAsTextGrows() {
        // Earlier blocks must be byte-identical as more text streams in, so a
        // given index keeps mapping to the same completed content.
        // Single block
        XCTAssertEqual(LaTeXStreamSegmenter.paragraphBlocks(in: "Just one line."), ["Just one line."])

        // Append-only stability as text streams in
        let partial = LaTeXStreamSegmenter.paragraphBlocks(in: "First.\n\n$$\nx\n$$\n\nSec")
        let grown = LaTeXStreamSegmenter.paragraphBlocks(in: "First.\n\n$$\nx\n$$\n\nSecond block.")
        XCTAssertEqual(Array(partial.dropLast()), Array(grown.dropLast()))
        XCTAssertEqual(grown.first, "First.")
    }

    func testParagraphBlocksSingleBlock() {
        XCTAssertEqual(LaTeXStreamSegmenter.paragraphBlocks(in: "Just one line."), ["Just one line."])
    }

    func testNoBoundaryUntilFirstSentenceCompletes() {
    func testSentenceBoundaries() {
        // Incomplete sentence has no boundary
        XCTAssertTrue(LaTeXStreamSegmenter.safeBoundaries("The value is").isEmpty)
        XCTAssertTrue(LaTeXStreamSegmenter.safeBoundaries("Computing the result").isEmpty)
    }

    func testSingleSentenceBoundaryAtPeriod() {
        let text = "This is one sentence."
        let b = LaTeXStreamSegmenter.safeBoundaries(text)
        XCTAssertEqual(b, [text.count])
    }
        // Single complete sentence
        let s1 = "This is one sentence."
        XCTAssertEqual(LaTeXStreamSegmenter.safeBoundaries(s1), [s1.count])

    func testTwoSentencesTwoBoundaries() {
        let text = "First sentence. Second sentence."
        let b = LaTeXStreamSegmenter.safeBoundaries(text)
        // Multiple complete sentences
        let s2 = "First sentence. Second sentence."
        let b = LaTeXStreamSegmenter.safeBoundaries(s2)
        XCTAssertEqual(b.count, 2)
        XCTAssertEqual(String(text.prefix(b[0])), "First sentence.")
        XCTAssertEqual(String(s2.prefix(b[0])), "First sentence.")
    }

    func testBalancedInlineMathCommitsAtSentenceEnd() {
        let text = "The solution is $x = 1$ today."
        let b = LaTeXStreamSegmenter.safeBoundaries(text)
        XCTAssertEqual(b, [text.count])
    }
    func testMathBoundaryHandling() {
        // Balanced math commits at sentence end
        let balanced = "The solution is $x = 1$ today."
        XCTAssertEqual(LaTeXStreamSegmenter.safeBoundaries(balanced), [balanced.count])

    /// The closing `$` of inline math must close even when it follows a digit
    /// (`...1$`) — the regression that previously left math open forever.
    func testInlineMathClosesEvenWhenClosingDollarFollowsDigit() {
        let text = "We get $a = 1$ and $b = 2$ here."
        let b = LaTeXStreamSegmenter.safeBoundaries(text)
        XCTAssertEqual(b, [text.count])
    }
        // Closing dollar after digit
        let digitClose = "We get $a = 1$ and $b = 2$ here."
        XCTAssertEqual(LaTeXStreamSegmenter.safeBoundaries(digitClose), [digitClose.count])

    func testOpenInlineMathDefersBoundary() {
        // `$x` opens inline math and is never closed → the trailing period is
        // inside math, so there's no safe boundary yet.
        let text = "Let $x be the value."
        XCTAssertTrue(LaTeXStreamSegmenter.safeBoundaries(text).isEmpty)
        // Open inline math defers boundary
        XCTAssertTrue(LaTeXStreamSegmenter.safeBoundaries("Let $x be the value.").isEmpty)

        // Closed display block is boundary without period terminator
        let display = "Equation: \\[ x = 1 \\] and more"
        let displayBoundaries = LaTeXStreamSegmenter.safeBoundaries(display)
        XCTAssertFalse(displayBoundaries.isEmpty)
        XCTAssertTrue(String(display.prefix(displayBoundaries[0])).hasSuffix("\\]"))

        // Open display block defers boundary
        XCTAssertTrue(LaTeXStreamSegmenter.safeBoundaries("See \\[ x = 1. The rest").isEmpty)
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
