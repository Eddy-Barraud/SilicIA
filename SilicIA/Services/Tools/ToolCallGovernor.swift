//
//  ToolCallGovernor.swift
//  SilicIA
//
//  Per-generation guard that breaks tool-call LOOPS.
//
//  Small on-device models sometimes get stuck calling tools over and over
//  — often the same tool with identical or near-identical arguments — and
//  never emit a final answer. Each reply (especially `webSearch`, which
//  packs several scraped pages) accumulates in the session transcript until
//  the 4096-token window overflows with
//  `GenerationError.exceededContextWindowSize`. Observed in the wild on a
//  plain "factorial n" query: the model fired `webSearch "how to calculate
//  factorial n"` three times in a row, then overflowed.
//
//  One governor is created per generation in `ToolKit.assemble` and shared
//  across every tool in that turn, so it sees the whole turn's call stream
//  and can:
//    - refuse exact-duplicate calls (return the result the model already
//      has + tell it to answer now),
//    - cap the expensive `webSearch` tool tightly (its replies dominate the
//      transcript), and
//    - enforce a hard ceiling on total tool calls as a safety net.
//
//  Refused calls return a short instruction string instead of doing the
//  work, so the transcript barely grows and the model is steered to
//  finalise its answer.
//

import Foundation

/// Shared, per-generation tool-call loop breaker. An `actor` because tools
/// may run concurrently within a single model turn.
actor ToolCallGovernor {

    /// What a tool should do with an incoming call.
    enum Decision: Equatable, CustomStringConvertible {
        /// Run the tool normally.
        case allow
        /// This exact (tool + arguments) call was already made; `count` is
        /// how many times now (including this one).
        case duplicate(count: Int)
        /// This tool hit its own per-turn ceiling.
        case toolBudgetReached(tool: String, cap: Int)
        /// The whole turn hit the total-call ceiling.
        case totalBudgetReached(cap: Int)

        var description: String {
            switch self {
            case .allow: return "allow"
            case .duplicate(let count): return "duplicate(#\(count))"
            case .toolBudgetReached(let tool, let cap): return "toolBudgetReached(\(tool), cap=\(cap))"
            case .totalBudgetReached(let cap): return "totalBudgetReached(cap=\(cap))"
            }
        }

        /// Model-facing instruction for a refused call. `nil` when allowed.
        var refusalMessage: String? {
            switch self {
            case .allow:
                return nil
            case .duplicate(let count):
                return """
                You already made this exact tool call (now \(count) times) and \
                the result is unchanged and already in the conversation above. \
                Do NOT repeat it. Write your final answer now using the \
                information you already have.
                """
            case .toolBudgetReached(let tool, let cap):
                return """
                You have reached the limit of \(cap) `\(tool)` calls for this \
                turn. Stop calling `\(tool)` and write your final answer now \
                from the information already gathered.
                """
            case .totalBudgetReached(let cap):
                return """
                You have reached the limit of \(cap) tool calls for this turn. \
                Stop calling tools and write your final answer now from the \
                information already gathered.
                """
            }
        }
    }

    /// Hard ceiling on total tool calls in one turn (safety net so even a
    /// model that spams refused calls terminates — every attempt, allowed
    /// or refused, counts).
    let maxTotalCalls: Int
    /// Tight ceiling on the "expensive" tool (`webSearch`) specifically. Its
    /// replies are the largest, so a few distinct calls already approach the
    /// window; distinct calls beyond this are refused.
    ///
    /// Kept in lock-step with `TokenBudgeting.webSearchReplyTokenCap`: the
    /// window-safety invariant is `cap × replyTokens + overhead ≤ 4096`.
    /// At 2 × 1000t the transcript stays comfortably inside the window; if
    /// you raise this, lower the per-reply cap (and vice-versa).
    let maxExpensiveToolCalls: Int
    /// Name of the tool treated as expensive for `maxExpensiveToolCalls`.
    private let expensiveToolName: String

    private var totalAttempts = 0
    private var perToolAllowed: [String: Int] = [:]
    private var signatureCounts: [String: Int] = [:]

    init(
        maxTotalCalls: Int = 8,
        maxExpensiveToolCalls: Int = 2,
        expensiveToolName: String = "webSearch"
    ) {
        self.maxTotalCalls = maxTotalCalls
        self.maxExpensiveToolCalls = maxExpensiveToolCalls
        self.expensiveToolName = expensiveToolName
    }

    /// Records an attempt and decides whether the tool should run. Call this
    /// at the TOP of every `Tool.call`, before any expensive work.
    func evaluate(tool: String, arguments: String) -> Decision {
        totalAttempts += 1
        let signature = "\(tool)::\(Self.normalize(arguments))"

        let decision: Decision
        if totalAttempts > maxTotalCalls {
            decision = .totalBudgetReached(cap: maxTotalCalls)
        } else {
            let priorSignature = signatureCounts[signature, default: 0]
            signatureCounts[signature] = priorSignature + 1
            if priorSignature > 0 {
                // Exact repeat — refuse without touching per-tool counts.
                decision = .duplicate(count: priorSignature + 1)
            } else {
                let priorTool = perToolAllowed[tool, default: 0]
                let cap = (tool == expensiveToolName) ? maxExpensiveToolCalls : maxTotalCalls
                if priorTool >= cap {
                    decision = .toolBudgetReached(tool: tool, cap: cap)
                } else {
                    perToolAllowed[tool] = priorTool + 1
                    decision = .allow
                }
            }
        }

        #if DEBUG
        print("[ToolGovernor] tool=\(tool) attempt=\(totalAttempts)/\(maxTotalCalls) decision=\(decision) args=\"\(arguments.prefix(80))\"")
        #endif
        return decision
    }

    /// Normalises arguments so trivially-different repeats (case, spacing)
    /// collapse to the same signature.
    private static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
