//
//  SanitizerTests.swift
//  SilicIATests
//
//  Tests for ModelOutputLaTeXSanitizer currency escaping and LaTeX math delimiter preservation.
//

import XCTest
@testable import SilicIA

final class SanitizerTests: XCTestCase {

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

    func testAlreadyEscapedNotDoubleEscaped() {
        let input = #"The total is \$1025.75."#
        XCTAssertEqual(ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: input), input)
    }

    func testMathDelimitersPreserved() {
        // Display math with letters or digits
        XCTAssertEqual(ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: "$$E = mc^2$$"), "$$E = mc^2$$")
        XCTAssertEqual(ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: "$$1 + x = 2$$"), "$$1 + x = 2$$")

        // Inline math with letters or LaTeX commands
        XCTAssertEqual(ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: "Compute $x + y$."), "Compute $x + y$.")
        XCTAssertEqual(ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: #"Half is $\frac{1}{2}$."#), #"Half is $\frac{1}{2}$."#)
    }

    func testDigitAdjacentClosingDollars() {
        // Balanced math closing delimiter following a digit must not escape
        let input = #"coefficients $a_3$, $a_2$, $a_1$ et $a_0$"#
        let output = ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: input)
        XCTAssertFalse(output.contains(#"\$"#))
        XCTAssertEqual(output, input)
    }

    func testCurrencyAndMathCoexistenceAndFullPipeline() {
        // Interleaved currency and math
        let mixed = #"price $5 for $x$ items"#
        let escapedMixed = ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: mixed)
        XCTAssertTrue(escapedMixed.contains(#"\$5"#))
        XCTAssertTrue(escapedMixed.contains("$x$"))

        // Real-world invoice text
        let invoice = "The total invoice amount is **932.50 €**. Converting to USD: $932.50 × 1.10 = **$1025.75**."
        let escapedInvoice = ModelOutputLaTeXSanitizer.escapeCurrencyDollars(in: invoice)
        XCTAssertTrue(escapedInvoice.contains(#"\$932.50"#))
        XCTAssertTrue(escapedInvoice.contains(#"\$1025.75"#))

        // Full pipeline pass
        let finalized = ModelOutputLaTeXSanitizer.finalizeSanitizedText("Final price: $1025.75 USD. Math: $a_3$.")
        XCTAssertTrue(finalized.contains(#"\$1025.75"#))
        XCTAssertFalse(finalized.contains(#"\$a_3"#))
    }
}
