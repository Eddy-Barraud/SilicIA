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

    /// Shared per-generation loop breaker (cross-tool + total-call ceiling).
    /// Complements the process-wide static guard below: the governor stops
    /// the model burning its whole turn on tools, the static guard is a
    /// per-expression backstop. Optional so direct callers / tests are
    /// unaffected.
    var governor: ToolCallGovernor?

    func call(arguments: Arguments) async throws -> String {
        #if DEBUG
        print("[Tool:calculate] called with expression=\"\(arguments.expression)\"")
        #endif

        if let governor {
            let decision = await governor.evaluate(tool: name, arguments: arguments.expression)
            switch decision {
            case .allow:
                break
            case .duplicate(let count):
                throw ToolError.duplicate(tool: name, count: count)
            case .toolBudgetReached(let tool, let cap):
                throw ToolError.toolBudgetReached(tool: tool, cap: cap)
            case .totalBudgetReached(let cap):
                throw ToolError.totalBudgetReached(cap: cap)
            }
        }

        // Loop guard: small models sometimes get stuck calling a tool over
        // and over with the same broken input. Track recent calls; once we
        // cross the threshold for an identical expression, return an
        // explicit "stop" directive so the model breaks out of the loop.
        let callCount = Self.registerCallAndCheckLoop(arguments.expression)
        if callCount > Self.loopThreshold {
            return """
            STOP CALLING THIS TOOL. You have called `calculate` with the \
            expression "\(arguments.expression)" \(callCount) times — the \
            result will not change. Do not call this tool again with the \
            same input. Answer the user directly using your own arithmetic \
            knowledge (e.g. 5! = 5 × 4 × 3 × 2 × 1 = 120).
            """
        }

        // Accept FR/ES-style decimal commas. Do this BEFORE the allow-list
        // check so `1,5 * 2` validates after `,` → `.` normalisation.
        let normalised = arguments.expression
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")

        var expressionToEvaluate = normalised
        if normalised.contains("=") {
            let parts = normalised.components(separatedBy: "=")
            if let firstPart = parts.first {
                expressionToEvaluate = firstPart.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        guard !expressionToEvaluate.isEmpty else {
            return "Error: empty expression. Pass an arithmetic expression like '64.24 * 2' or '(1 + 2) * 3'."
        }

        // Expand factorial syntax `n!` into the equivalent product, so the
        // allow-list (which intentionally excludes `!`) still works and so
        // NSExpression sees a plain arithmetic expression. Capped at 20! to
        // stay inside Int64 range.
        let expanded = Self.expandFactorials(in: expressionToEvaluate)

        guard expanded.unicodeScalars.allSatisfy({ Self.allowedCharacters.contains($0) }) else {
            return """
            Error: '\(arguments.expression)' contains characters this tool \
            doesn't support. Only digits, decimal points, + - * /, and \
            parentheses are allowed. Convert powers, percents, and other \
            operations into equivalent arithmetic before calling — e.g. \
            '15% of 200' → '200 * 0.15', '2^10' → '2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2 * 2'. \
            If the conversion is impractical, answer the user from your own \
            knowledge instead of retrying this tool.
            """
        }

        // Promote bare integer literals to doubles so NSExpression doesn't
        // perform integer division — `10 / 4` would otherwise evaluate to
        // 2; forcing `10.0 / 4.0` yields 2.5 as expected.
        let doublified = Self.promoteIntegersToDoubles(expanded)

        guard let value = Self.evaluate(doublified) else {
            return """
            Error: could not evaluate '\(arguments.expression)'. The expression \
            may be syntactically invalid (e.g. unmatched parentheses, two \
            operators in a row). Try rewriting it, or answer the user \
            without the calculator.
            """
        }

        // Format: trim a trailing ".0" so integer results read as integers.
        // Keep enough precision (up to 10 significant digits) so financial
        // values like 77.08 don't get rounded.
        return Self.format(value)
    }

    // MARK: - Factorial expansion

    /// Cached regex matching `<digits>!` — the factorial-of-integer form
    /// the model is likely to emit when it sees factorial notation.
    private static let factorialRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(\d+)!"#,
        options: []
    )

    /// Largest `n` we'll expand. 15! = 1,307,674,368,000 sits comfortably
    /// below Double's 2^53 exact-integer boundary (~9 × 10¹⁵), so the
    /// result round-trips through NSExpression's Double arithmetic without
    /// precision loss. 16!–20! technically fit in Int64 but lose digits
    /// when promoted to Double, producing garbled output. For n above the
    /// cap we leave the `!` in place so the allow-list rejects it and the
    /// model knows to reformulate.
    private static let maxFactorialN = 15

    /// Replaces each `n!` occurrence in `expression` with its evaluated
    /// integer product wrapped in parens (so `2 * 5!` becomes `2 * (120)`).
    /// Leaves `n!` for n > 20 alone — those will be rejected downstream.
    private static func expandFactorials(in expression: String) -> String {
        guard let regex = factorialRegex else { return expression }
        let nsRange = NSRange(expression.startIndex..., in: expression)
        let matches = regex.matches(in: expression, options: [], range: nsRange)
        guard !matches.isEmpty else { return expression }

        var result = expression
        // Walk back-to-front so each replacement doesn't invalidate earlier
        // string indices.
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let digitsRange = Range(match.range(at: 1), in: result),
                  let n = Int(result[digitsRange]),
                  n >= 0, n <= Self.maxFactorialN else {
                continue
            }
            let factorial: Int = n == 0 ? 1 : (1...n).reduce(1, *)
            result.replaceSubrange(fullRange, with: "(\(factorial))")
        }
        return result
    }

    // MARK: - Loop guard

    /// Static counters of recent identical expressions. A tool is a value
    /// type, but the model may instantiate many sessions over a short
    /// window — keeping the cache here means every CalculatorTool instance
    /// in the process shares the same loop view.
    private static let recentCallsLock = NSLock()
    private static var recentCalls: [String: (count: Int, lastSeen: Date)] = [:]

    /// Identical expressions called more than this many times in
    /// `loopWindow` trigger the stop-directive response.
    private static let loopThreshold = 3
    private static let loopWindow: TimeInterval = 10

    /// Records this call, evicts stale entries, returns the running count
    /// of identical calls inside the window.
    private static func registerCallAndCheckLoop(_ expression: String) -> Int {
        recentCallsLock.lock()
        defer { recentCallsLock.unlock() }
        let now = Date()
        for (key, value) in recentCalls where now.timeIntervalSince(value.lastSeen) >= loopWindow {
            recentCalls.removeValue(forKey: key)
        }
        let previous = recentCalls[expression]?.count ?? 0
        let updated = previous + 1
        recentCalls[expression] = (count: updated, lastSeen: now)
        return updated
    }

    /// Test-only hook to wipe loop-guard state between cases.
    static func resetLoopGuardForTesting() {
        recentCallsLock.lock()
        defer { recentCallsLock.unlock() }
        recentCalls.removeAll()
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
