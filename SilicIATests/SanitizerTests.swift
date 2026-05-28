//
//  SanitizerTests.swift
//  SilicIATests
//
//  Tests for ModelOutputLaTeXSanitizer, focused on the dollar-escape
//  pass. Model output frequently contains currency `$` adjacent to
//  digits which the LaTeX renderer would otherwise interpret as an
//  inline-math opener, swallowing the rest of the message into
//  malformed math.
//

import XCTest
@testable import SilicIA

final class SanitizerTests: XCTestCase {

    // MARK: - Currency escape: prefix form

    func testEscapesPrefixCurrencyBeforeDigit() {
        let input = "The total is $1025.75."
        let output = ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: input)
        XCTAssertEqual(output, #"The total is \$1025.75."#)
    }

    func testEscapesPrefixCurrencyInsideMarkdownBold() {
        let input = "Cost: **$100**"
        let output = ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: input)
        XCTAssertEqual(output, #"Cost: **\$100**"#)
    }

    func testEscapesMultiplePrefixCurrencies() {
        let input = "Was $500, now $399.99"
        let output = ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: input)
        XCTAssertEqual(output, #"Was \$500, now \$399.99"#)
    }

    // MARK: - Currency escape: suffix form

    /// French/Quebec style: `1025$` with the symbol after the number.
    func testEscapesSuffixCurrencyAfterDigit() {
        let input = "Le total est 1025.75$."
        let output = ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: input)
        XCTAssertEqual(output, #"Le total est 1025.75\$."#)
    }

    // MARK: - Already-escaped is not double-escaped

    func testDoesNotDoubleEscapeAlreadyEscapedDollar() {
        let input = #"The total is \$1025.75."#
        let output = ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: input)
        XCTAssertEqual(output, input, "Already-escaped `\\$` was re-escaped: \(output)")
    }

    // MARK: - Display math `$$` is preserved

    /// `$$E = mc^2$$` must not be touched by the currency escape; the
    /// trailing `$` of the opener IS followed by content but that content
    /// doesn't start with a digit here.
    func testPreservesDisplayMathDelimitersInLetterContent() {
        let input = "$$E = mc^2$$"
        let output = ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: input)
        XCTAssertEqual(output, input)
    }

    /// Edge case: `$$1+x$$` where the second `$` of the opener IS followed
    /// by a digit. The currency pass must skip it because it's part of `$$`.
    func testPreservesDisplayMathWhenOpenerPrecedesDigit() {
        let input = "$$1 + x = 2$$"
        let output = ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: input)
        XCTAssertEqual(output, input,
                       "Display-math `$$` opener was wrongly escaped when followed by a digit: \(output)")
    }

    // MARK: - Regular math `$...$` left alone

    func testPreservesInlineMathWithLetters() {
        let input = "Compute $x + y$."
        let output = ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: input)
        XCTAssertEqual(output, input)
    }

    /// `$\frac{1}{2}$` — math command starts with `\`, no escape.
    func testPreservesInlineMathStartingWithBackslashCommand() {
        let input = #"Half is $\frac{1}{2}$ of the total."#
        let output = ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: input)
        XCTAssertEqual(output, input)
    }

    // MARK: - Real-world failure case from the user's invoice run

    /// Reproduces the exact malformed string the model produced for
    /// "What's the total invoice amount, and convert to USD assuming
    /// 1.10 €/$?" — combining markdown bold with mid-message currency.
    func testInvoiceUSDConversionMessage() {
        let input = "The total invoice amount is **932.50 €**. Converting to USD: $932.50 × 1.10 = **$1025.75**."
        let output = ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: input)
        XCTAssertTrue(output.contains(#"\$932.50"#),
                      "Prefix currency `$932.50` wasn't escaped: \(output)")
        XCTAssertTrue(output.contains(#"\$1025.75"#),
                      "Prefix currency `$1025.75` wasn't escaped: \(output)")
    }

    // MARK: - Full pipeline still produces the escape

    /// `finalizeSanitizedText` runs other passes too. Verify the currency
    /// escape survives them.
    func testCurrencyEscapeSurvivesFullPipeline() {
        let input = "Final price: $1025.75 USD."
        let output = ModelOutputLaTeXSanitizer.finalizeSanitizedText(input)
        XCTAssertTrue(output.contains(#"\$1025.75"#),
                      "Currency escape lost during full sanitization pipeline: \(output)")
    }
}
