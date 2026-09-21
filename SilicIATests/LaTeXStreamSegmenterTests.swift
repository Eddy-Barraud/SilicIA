//
//  LaTeXStreamSegmenterTests.swift
//  SilicIATests
//
//  Verifies safe cut points for progressive streaming LaTeX rendering.
//

import XCTest
@testable import SilicIA

final class LaTeXStreamSegmenterTests: XCTestCase {

    func testParagraphBlocks() {
        // Normal paragraph splitting
        let text = "Intro paragraph.\n\n$$\nE = mc^2\n$$\n\nClosing paragraph."
        let blocks = LaTeXStreamSegmenter.paragraphBlocks(in: text)
        XCTAssertEqual(blocks, ["Intro paragraph.", "$$\nE = mc^2\n$$", "Closing paragraph."])

        // Collapsing multiple blank lines
        XCTAssertEqual(LaTeXStreamSegmenter.paragraphBlocks(in: "A\n\n\n\nB"), ["A", "B"])

        // Single block
        XCTAssertEqual(LaTeXStreamSegmenter.paragraphBlocks(in: "Just one line."), ["Just one line."])

        // Append-only stability as text streams in
        let partial = LaTeXStreamSegmenter.paragraphBlocks(in: "First.\n\n$$\nx\n$$\n\nSec")
        let grown = LaTeXStreamSegmenter.paragraphBlocks(in: "First.\n\n$$\nx\n$$\n\nSecond block.")
        XCTAssertEqual(Array(partial.dropLast()), Array(grown.dropLast()))
        XCTAssertEqual(grown.first, "First.")
    }

    func testSentenceBoundaries() {
        // Incomplete sentence has no boundary
        XCTAssertTrue(LaTeXStreamSegmenter.safeBoundaries("The value is").isEmpty)

        // Single complete sentence
        let s1 = "This is one sentence."
        XCTAssertEqual(LaTeXStreamSegmenter.safeBoundaries(s1), [s1.count])

        // Multiple complete sentences
        let s2 = "First sentence. Second sentence."
        let b = LaTeXStreamSegmenter.safeBoundaries(s2)
        XCTAssertEqual(b.count, 2)
        XCTAssertEqual(String(s2.prefix(b[0])), "First sentence.")
    }

    func testMathBoundaryHandling() {
        // Balanced math commits at sentence end
        let balanced = "The solution is $x = 1$ today."
        XCTAssertEqual(LaTeXStreamSegmenter.safeBoundaries(balanced), [balanced.count])

        // Closing dollar after digit
        let digitClose = "We get $a = 1$ and $b = 2$ here."
        XCTAssertEqual(LaTeXStreamSegmenter.safeBoundaries(digitClose), [digitClose.count])

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
        let text = "It costs $5.00 today."
        let b = LaTeXStreamSegmenter.safeBoundaries(text)
        XCTAssertEqual(b, [text.count])
    }
}
