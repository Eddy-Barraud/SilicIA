//
//  CalculatorTool.swift
//  SilicIA
//
//  Foundation Models tool that evaluates arithmetic expressions exactly.
//
//  Why: small on-device models are unreliable at multi-digit arithmetic.
//  They routinely misplace decimal points, swap digits, and confuse
//  percentages with currency. Offloading the math to NSExpression
//  eliminates an entire class of numerical hallucinations — the model
//  identifies the operands, calls the tool, and integrates the exact
//  result into its answer.
//

import Foundation
import FoundationModels

/// Tool that evaluates a single arithmetic expression and returns its
/// exact numeric value as a string.
///
/// Supported operators: `+`, `-`, `*`, `/`, parentheses, unary minus.
/// Decimal separators: both `.` and `,` are accepted (the French/Spanish
/// `,` is normalised to `.` before parsing) so the model can copy values
/// straight out of the user's documents without manual conversion.
///
/// Input is validated against an allow-list of characters before parsing
/// so a malicious expression can't reach `NSExpression`'s broader
/// key-path / function syntax.
struct CalculatorTool: Tool {

    /// Inputs the model fills out when calling the tool. The `@Guide`
    /// annotation surfaces inline to the model alongside the schema so
    /// it knows exactly what shape of expression is expected.
    @Generable
    struct Arguments {
        @Guide(description: "An arithmetic expression to evaluate, e.g. '64.24 * 2', '(1234 + 567) / 3', '15% of 200' is NOT supported — convert to '200 * 0.15'. Only digits, the operators + - * /, and parentheses are allowed.")
        let expression: String
    }

    let name = "calculate"
    let description = """
    Evaluate an arithmetic expression exactly. Use this for any non-trivial \
    math instead of computing in your head — small models routinely make \
    arithmetic mistakes. Returns the exact numeric result as a string. \
    Accepts +, -, *, /, parentheses, and unary minus.
    """

    /// Characters allowed in an expression. Anything outside this set is
    /// rejected before reaching NSExpression — defence in depth, since
    /// NSExpression's full grammar includes key-path access and selector
    /// invocation that we don't want exposed to a model-generated string.
    private static let allowedCharacters: CharacterSet = {
        var set = CharacterSet(charactersIn: "0123456789.+-*/() \t")
        return set
    }()

    func call(arguments: Arguments) async throws -> String {
        // Accept FR/ES-style decimal commas. Do this BEFORE the allow-list
        // check so `1,5 * 2` validates after `,` → `.` normalisation.
        let normalised = arguments.expression
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")

        guard !normalised.isEmpty else {
            return "Error: empty expression"
        }
        guard normalised.unicodeScalars.allSatisfy({ Self.allowedCharacters.contains($0) }) else {
            return "Error: expression contains unsupported characters (allowed: digits, + - * / parentheses)"
        }

        // Promote bare integer literals to doubles so NSExpression doesn't
        // perform integer division — `10 / 4` would otherwise evaluate to
        // 2; forcing `10.0 / 4.0` yields 2.5 as expected.
        let doublified = Self.promoteIntegersToDoubles(normalised)

        guard let value = Self.evaluate(doublified) else {
            return "Error: could not evaluate '\(arguments.expression)'"
        }

        // Format: trim a trailing ".0" so integer results read as integers.
        // Keep enough precision (up to 10 significant digits) so financial
        // values like 77.08 don't get rounded.
        return Self.format(value)
    }

    /// Cached regex matching contiguous integer literals that are NOT
    /// already part of a decimal (no `.` or digit on either side).
    /// `64.24` is left alone (both halves anchored to the `.`);
    /// `10 / 4` matches `10` and `4` independently.
    private static let integerLiteralRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?<![.\d])(\d+)(?![.\d])"#,
        options: []
    )

    private static func promoteIntegersToDoubles(_ expression: String) -> String {
        guard let regex = integerLiteralRegex else { return expression }
        let range = NSRange(expression.startIndex..., in: expression)
        return regex.stringByReplacingMatches(
            in: expression,
            options: [],
            range: range,
            withTemplate: "$1.0"
        )
    }

    /// Parses + evaluates an arithmetic expression via NSExpression. Returns
    /// nil if NSExpression rejects the syntax. Wrapped in `try?` because
    /// `NSExpression(format:)` raises Objective-C exceptions on malformed
    /// input — defending against that requires the allow-list above.
    private static func evaluate(_ expression: String) -> Double? {
        let predicateExpr = NSExpression(format: expression)
        let value = predicateExpr.expressionValue(with: nil, context: nil)
        if let n = value as? NSNumber {
            return n.doubleValue
        }
        return nil
    }

    private static func format(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0,
           abs(value) < 1e15 {
            return String(format: "%.0f", value)
        }
        // %.10g picks the shortest representation that preserves the value
        // up to 10 significant figures. Good for financial maths.
        return String(format: "%.10g", value)
    }
}
