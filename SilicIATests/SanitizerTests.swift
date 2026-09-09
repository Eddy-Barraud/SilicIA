//
//  SanitizerTests.swift
//  SilicIATests
//
//  Tests for ModelOutputLaTeXSanitizer, focused on the dollar-escape
//  pass. Model output frequently contains currency `$` adjacent to
//  digits which the LaTeX renderer would otherwise interpret as an
//  inline-math opener, swallowing the rest of the message into
//  malformed math.
//  Tests for ModelOutputLaTeXSanitizer currency escaping and LaTeX math delimiter preservation.
//

import XCTest
@testable import SilicIA

final class SanitizerTests: XCTestCase {

    // MARK: - Currency escape: prefix form

    func testEscapesPrefixCurrencyBeforeDigit() {
        let input = "The total is $1025.75."
        let output = ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: input)
        XCTAssertEqual(output, #"The total is \$1025.75."#)
    func testCurrencyEscaping() {
        // Prefix currency before digit
        XCTAssertEqual(
            ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: "The total is $1025.75."),
            #"The total is \$1025.75."#
        )
        // Inside bold
        XCTAssertEqual(
            ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: "Cost: **$100**"),
            #"Cost: **\$100**"#
        )
        // Multiple prefix currencies
        XCTAssertEqual(
            ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: "Was $500, now $399.99"),
            #"Was \$500, now \$399.99"#
        )
        // Suffix currency (French/Quebec style)
        XCTAssertEqual(
            ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: "Le total est 1025.75$."),
            #"Le total est 1025.75\$."#
        )
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
    func testAlreadyEscapedNotDoubleEscaped() {
        let input = #"The total is \$1025.75."#
        let output = ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: input)
        XCTAssertEqual(output, input, "Already-escaped `\\$` was re-escaped: \(output)")
        XCTAssertEqual(ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: input), input)
    }

    // MARK: - Display math `$$` is preserved
    func testMathDelimitersPreserved() {
        // Display math with letters or digits
        XCTAssertEqual(ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: "$$E = mc^2$$"), "$$E = mc^2$$")
        XCTAssertEqual(ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: "$$1 + x = 2$$"), "$$1 + x = 2$$")

    /// `$$E = mc^2$$` must not be touched by the currency escape; the
    /// trailing `$` of the opener IS followed by content but that content
    /// doesn't start with a digit here.
    func testPreservesDisplayMathDelimitersInLetterContent() {
        let input = "$$E = mc^2$$"
        let output = ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: input)
        XCTAssertEqual(output, input)
        // Inline math with letters or LaTeX commands
        XCTAssertEqual(ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: "Compute $x + y$."), "Compute $x + y$.")
        XCTAssertEqual(ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: #"Half is $\frac{1}{2}$."#), #"Half is $\frac{1}{2}$."#)
    }

    /// Edge case: `$$1+x$$` where the second `$` of the opener IS followed
    /// by a digit. The currency pass must skip it because it's part of `$$`.
    func testPreservesDisplayMathWhenOpenerPrecedesDigit() {
        let input = "$$1 + x = 2$$"
    func testDigitAdjacentClosingDollars() {
        // Balanced math closing delimiter following a digit must not escape
        let input = #"coefficients $a_3$, $a_2$, $a_1$ et $a_0$"#
        let output = ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: input)
        XCTAssertEqual(output, input,
                       "Display-math `$$` opener was wrongly escaped when followed by a digit: \(output)")
    }

    // MARK: - Regular math `$...$` left alone

    func testPreservesInlineMathWithLetters() {
        let input = "Compute $x + y$."
        let output = ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: input)
        XCTAssertFalse(output.contains(#"\$"#))
        XCTAssertEqual(output, input)
    }

    /// `$\frac{1}{2}$` — math command starts with `\`, no escape.
    func testPreservesInlineMathStartingWithBackslashCommand() {
        let input = #"Half is $\frac{1}{2}$ of the total."#
        let output = ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: input)
        XCTAssertEqual(output, input)
    }
    func testCurrencyAndMathCoexistenceAndFullPipeline() {
        // Interleaved currency and math
        let mixed = #"price $5 for $x$ items"#
        let escapedMixed = ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: mixed)
        XCTAssertTrue(escapedMixed.contains(#"\$5"#))
        XCTAssertTrue(escapedMixed.contains("$x$"))

    // MARK: - Real-world failure case from the user's invoice run
        // Real-world invoice text
        let invoice = "The total invoice amount is **932.50 €**. Converting to USD: $932.50 × 1.10 = **$1025.75**."
        let escapedInvoice = ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: invoice)
        XCTAssertTrue(escapedInvoice.contains(#"\$932.50"#))
        XCTAssertTrue(escapedInvoice.contains(#"\$1025.75"#))

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
        // Full pipeline pass
        let finalized = ModelOutputLaTeXSanitizer.finalizeSanitizedText("Final price: $1025.75 USD. Math: $a_3$.")
        XCTAssertTrue(finalized.contains(#"\$1025.75"#))
        XCTAssertFalse(finalized.contains(#"\$a_3"#))
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

    // MARK: - Inline math whose closing `$` follows a digit

    /// `$a_3$` must NOT have its closing `$` escaped as currency — the close
    /// is a delimiter even though it follows the digit `3`. The old regex
    /// escaped it, mis-pairing every following span and garbling the render.
    func testInlineMathClosingDollarAfterDigitIsNotEscaped() {
        let input = #"coefficients $a_3$, $a_2$, $a_1$ et $a_0$"#
        let output = ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: input)
        // No `$` should have been escaped — these are all balanced math spans.
        XCTAssertFalse(output.contains(#"\$"#), "math delimiters were wrongly escaped: \(output)")
        XCTAssertEqual(output, input)
    }

    /// Real math interleaved with real currency: only the currency `$` is
    /// escaped, the math delimiters are preserved.
    func testCurrencyAndMathCoexist() {
        let input = #"price $5 for $x$ items"#
        let output = ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: input)
        XCTAssertTrue(output.contains(#"\$5"#), "currency not escaped: \(output)")
        XCTAssertTrue(output.contains("$x$"), "math span broken: \(output)")
    }

    /// A digit-adjacent closing `$` survives the FULL pipeline (regression
    /// for the spline-coefficients render).
    func testDigitAdjacentMathSurvivesFullPipeline() {
        let input = #"4 coefficients : $a_3$, $a_2$, $a_1$ et $a_0$."#
        let output = ModelOutputLaTeXSanitizer.finalizeSanitizedText(input)
        XCTAssertFalse(output.contains(#"\$"#), "math delimiter escaped in pipeline: \(output)")
    }
}
