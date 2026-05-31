//
//  TokenBudgeting.swift
//  SilicIA
//
//  Created by Copilot on 29/03/2026.
//

import Foundation

/// Shared token-budget helpers used across chat, search, and RAG selection.
enum TokenBudgeting {
    static let contextWindowLimit = 4096
    static let avgCharsPerToken = 3
    static let avgCharsPerSentence = 140
    static let avgCharsPerWord = 5

    // Shared budget assumptions used by chat/search prompts.
    static let instructionTokens = 100
    static let promptOverheadTokens = 80
    static let minContextTokens = 300

    /// Extra context-window tokens consumed in tool-calling mode beyond the
    /// baseline `instructionTokens`. Two contributors the baseline doesn't
    /// account for:
    ///   - the per-language tool-usage appendix appended to the system
    ///     instructions (`ToolKit.instructionsAppendix`, ~150 tokens), and
    ///   - the Foundation Models tool *schemas* — each `Tool`'s name,
    ///     description, and `@Generable` argument struct with its `@Guide`
    ///     prose — which the framework injects into the model's transcript
    ///     (~400 tokens for the four-tool kit).
    /// Used to shrink the pre-baked grounding context (see
    /// `maxToolGroundingCharacters`) so prompt + tool schemas + output still
    /// fit the 4096-token window when we ground a tool-calling turn.
    static let toolCallingOverheadTokens = 600

    /// Character budget for the pre-baked grounding context injected into a
    /// tool-calling prompt. Mirrors `maxContextCharacters` but reserves the
    /// additional `toolCallingOverheadTokens` so the grounding text plus the
    /// tool schemas plus the model's response coexist within the window.
    static func maxToolGroundingCharacters(maxOutputTokens: Int) -> Int {
        maxContextCharacters(
            maxOutputTokens: maxOutputTokens,
            contextUtilizationFactor: 1.0,
            instructionTokens: instructionTokens + toolCallingOverheadTokens
        )
    }

    /// Clamps requested output tokens so prompt + context + output fit the system context window.
    static func clampedOutputTokens(
        requestedMaxTokens: Int,
        instructionTokens: Int = instructionTokens,
        promptOverheadTokens: Int = promptOverheadTokens,
        minContextTokens: Int = minContextTokens
    ) -> Int {
        let maxOutputTokens = max(
            contextWindowLimit - instructionTokens - promptOverheadTokens - minContextTokens,
            1
        )
        return min(max(requestedMaxTokens, 1), maxOutputTokens)
    }

    /// Returns the context-token budget available once output/instructions are reserved.
    static func maxAvailableContextTokens(
        maxOutputTokens: Int,
        instructionTokens: Int = instructionTokens,
        promptOverheadTokens: Int = promptOverheadTokens,
        minContextTokens: Int = minContextTokens
    ) -> Int {
        let effectiveOutputTokens = clampedOutputTokens(
            requestedMaxTokens: maxOutputTokens,
            instructionTokens: instructionTokens,
            promptOverheadTokens: promptOverheadTokens,
            minContextTokens: minContextTokens
        )
        return max(contextWindowLimit - instructionTokens - promptOverheadTokens - effectiveOutputTokens, minContextTokens)
    }

    /// Clamps context tokens against both user settings and the current output-token budget.
    static func clampedContextTokens(
        requestedContextTokens: Int,
        maxOutputTokens: Int,
        settingsRange: ClosedRange<Int>,
        instructionTokens: Int = instructionTokens,
        promptOverheadTokens: Int = promptOverheadTokens,
        minContextTokens: Int = minContextTokens
    ) -> Int {
        let contextBudgetCap = maxAvailableContextTokens(
            maxOutputTokens: maxOutputTokens,
            instructionTokens: instructionTokens,
            promptOverheadTokens: promptOverheadTokens,
            minContextTokens: minContextTokens
        )
        let boundedUpper = min(settingsRange.upperBound, contextBudgetCap)
        let boundedLower = min(settingsRange.lowerBound, boundedUpper)
        return min(max(requestedContextTokens, boundedLower), boundedUpper)
    }

    static func estimatedOutputCharacters(forTokens tokens: Int) -> Int {
        max(tokens, 0) * avgCharsPerToken
    }

    static func estimatedOutputSentences(forTokens tokens: Int) -> Int {
        max(1, estimatedOutputCharacters(forTokens: tokens) / avgCharsPerSentence)
    }

    static func estimatedContextCharacters(forTokens tokens: Int) -> Int {
        max(tokens, 0) * avgCharsPerToken
    }

    /// Smallest tool reply we'll allow. Below this a tool call returns so
    /// little it's not worth the round-trip (a single search result with
    /// no room for surrounding context).
    static let toolOutputTokenBudgetFloor = 500

    /// Ceiling on a single `webSearch` reply, applied ON TOP of the shared
    /// `toolOutputTokenBudget`. webSearch is by far the largest tool reply —
    /// it packs several scraped pages — so it dominates the tool-calling
    /// transcript and was the main driver of context-window overflow.
    ///
    /// Now that `ToolCallGovernor` caps the NUMBER of distinct webSearch
    /// calls per turn (`maxExpensiveToolCalls`), we can afford a richer
    /// per-reply budget again: the window-safety guarantee is
    ///   `webSearchReplyTokenCap × maxExpensiveToolCalls + overhead ≤ 4096`.
    /// At 1000t × 2 calls = 2000t, plus ~700t real instructions/tool schemas
    /// + ~120t prompt + 500t response ≈ 3320t — comfortably inside 4096.
    /// This pairing mirrors `assumedConcurrentToolReplies = 2`.
    ///
    /// IMPORTANT: if you raise this, lower `ToolCallGovernor`'s
    /// `maxExpensiveToolCalls` (and vice-versa) so the product stays within
    /// the window. The other tools (searchContext, calculate,
    /// currentDateTime) keep the full shared budget.
    static let webSearchReplyTokenCap = 1000

    /// During a tool-calling turn the `LanguageModelSession` transcript
    /// accumulates: instructions + prompt + every tool call + every tool
    /// reply + the final response — and the whole thing must fit in the
    /// 4096-token window. The model may call several tools in one turn,
    /// so we size a *single* reply to leave room for a few of them plus
    /// the response. This divisor is "how many tool replies we assume can
    /// coexist in the transcript"; 2 is conservative enough to survive a
    /// two-tool turn (e.g. currentDateTime + webSearch) without overflow
    /// while still letting each reply be substantial.
    private static let assumedConcurrentToolReplies = 2

    /// Token cap allocated to each `Tool.call` reply when tool calling is
    /// active.
    ///
    /// Two forces balanced here:
    ///   - Use the window: scale with the response budget (verbose "deep"
    ///     profiles let tools return richer payloads; terse "fast"
    ///     profiles keep them tight) via a 2x multiplier — tool output is
    ///     referenced once and summarised into the answer, so ~twice the
    ///     response cap is a sensible working size.
    ///   - Respect the window: the result is capped by what's actually
    ///     left after instructions + prompt overhead + the response are
    ///     reserved, divided by `assumedConcurrentToolReplies`. This is
    ///     the fix for a latent overflow — a hardcoded ceiling (formerly
    ///     3000) plus a 1500-token deep response plus instructions
    ///     exceeded 4096 on a *single* tool call.
    static func toolOutputTokenBudget(forResponseTokens responseTokens: Int) -> Int {
        let effectiveResponseTokens = clampedOutputTokens(requestedMaxTokens: responseTokens)
        // Tokens left for the entire tool transcript once instructions,
        // overhead, and the model's own response are accounted for.
        let availableForTools = max(
            contextWindowLimit - instructionTokens - promptOverheadTokens - effectiveResponseTokens,
            0
        )
        // Window-safe cap for ONE reply: dividing by the assumed
        // concurrent-reply count guarantees that even
        // `assumedConcurrentToolReplies` replies of this size plus the
        // response and instructions stay under the window.
        let perReplyRoom = availableForTools / assumedConcurrentToolReplies

        // Preferred size: 2x the response cap, but at least the floor.
        let desired = max(toolOutputTokenBudgetFloor, effectiveResponseTokens * 2)

        // The window cap wins unconditionally. In the normal case
        // `perReplyRoom` is well above `desired`, so we get `desired`. In
        // the degenerate case where a huge response has eaten the window,
        // `perReplyRoom` drops below the floor and the floor yields — a
        // smaller-than-ideal tool reply is acceptable; overflowing the
        // window (which makes the model error out entirely) is not.
        return min(desired, perReplyRoom)
    }

    static func estimatedContextWords(forTokens tokens: Int) -> Int {
        max(1, estimatedContextCharacters(forTokens: tokens) / avgCharsPerWord)
    }

    static func estimatedTokens(forApproxWords words: Int) -> Int {
        max(1, Int((Double(max(words, 0)) * Double(avgCharsPerWord)) / Double(avgCharsPerToken)))
    }

    static func estimatedTokens(forApproxCharacters characters: Int) -> Int {
        max(0, Int(ceil(Double(max(characters, 0)) / Double(avgCharsPerToken))))
    }

    static func estimatedContextCharacters(forWords words: Int) -> Int {
        max(words, 0) * avgCharsPerWord
    }

    static func truncateToApproxWordCount(_ text: String, maxWords: Int) -> String {
        guard maxWords > 0 else { return "" }
        var wordsSeen = 0
        var inWord = false
        var cutIndex: String.Index?

        for index in text.indices {
            let character = text[index]
            let isWordCharacter = character.isLetter || character.isNumber
            if isWordCharacter {
                if !inWord {
                    wordsSeen += 1
                    if wordsSeen > maxWords {
                        cutIndex = index
                        break
                    }
                }
                inWord = true
            } else {
                inWord = false
            }
        }

        guard let cutIndex else {
            return text
        }

        return String(text[..<cutIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Computes how many context characters can be used while preserving room for output.
    static func maxContextCharacters(
        maxOutputTokens: Int,
        contextUtilizationFactor: Double,
        instructionTokens: Int = instructionTokens,
        promptOverheadTokens: Int = promptOverheadTokens,
        minContextTokens: Int = minContextTokens,
        avgCharsPerToken: Int = avgCharsPerToken
    ) -> Int {
        let effectiveOutputTokens = clampedOutputTokens(
            requestedMaxTokens: maxOutputTokens,
            instructionTokens: instructionTokens,
            promptOverheadTokens: promptOverheadTokens,
            minContextTokens: minContextTokens
        )
        let reservedTokens = instructionTokens + promptOverheadTokens + effectiveOutputTokens
        let availableTokens = max(contextWindowLimit - reservedTokens, 0)
        return Int(Double(availableTokens * avgCharsPerToken) * contextUtilizationFactor)
    }
}
