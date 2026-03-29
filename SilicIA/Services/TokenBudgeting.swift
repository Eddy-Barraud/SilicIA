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

    // Shared budget assumptions used by chat/search prompts.
    static let instructionTokens = 100
    static let promptOverheadTokens = 80
    static let minContextTokens = 300

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

    static func estimatedOutputCharacters(forTokens tokens: Int) -> Int {
        max(tokens, 0) * avgCharsPerToken
    }

    static func estimatedOutputSentences(forTokens tokens: Int) -> Int {
        max(1, estimatedOutputCharacters(forTokens: tokens) / avgCharsPerSentence)
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
