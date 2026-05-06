//
//  AppSettings.swift
//  SilicIA
//
//  Created by Claude on 23/03/2026.
//

import Foundation

/// Supported output languages for generated model responses.
enum ModelLanguage: String, CaseIterable, Codable {
    case french = "French"
    case english = "English"
    case spanish = "Spanish"

    var code: String {
        switch self {
        case .english: return "en"
        case .french: return "fr"
        case .spanish: return "es"
        }
    }
}

/// User-configurable settings controlling search and summary behavior.
struct AppSettings: Codable, Equatable {
    var maxDuckDuckGoResults: Int = 6
    var maxWikipediaResults: Int = 2
    var maxResponseTokens: Int = 1500
    var temperature: Double = 0.7
    var maxContextTokens: Int = 2400
    var isFirstGuessEnabled: Bool = true
    var isWebSummariesEnabled: Bool = false
    var useDuckDuckGo: Bool = true
    var useWikipedia: Bool = true
    var language: ModelLanguage = .english

    /// Combined per-search result cap exposed for callers that still need a single number
    /// (e.g. results display limit, scraping cap).
    var maxSearchResults: Int { maxDuckDuckGoResults + maxWikipediaResults }

    private static let storageKey = "SilicIA.AppSettings"
    private static let defaultSettings = AppSettings()

    private enum CodingKeys: String, CodingKey {
        case maxDuckDuckGoResults
        case maxWikipediaResults
        case maxResponseTokens
        case temperature
        case maxContextTokens
        case isFirstGuessEnabled
        case isWebSummariesEnabled
        case useDuckDuckGo
        case useWikipedia
        case language
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case maxContextWords
        case maxScrapingCharacters
        case maxSearchResults
    }

    init() {}

    /// Loads settings from UserDefaults and falls back to defaults if unavailable.
    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return AppSettings().normalized()
        }

        do {
            return try JSONDecoder().decode(AppSettings.self, from: data).normalized()
        } catch {
            return AppSettings().normalized()
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)

        if let storedDDG = try container.decodeIfPresent(Int.self, forKey: .maxDuckDuckGoResults) {
            maxDuckDuckGoResults = storedDDG
        } else if let legacyTotal = try legacyContainer.decodeIfPresent(Int.self, forKey: .maxSearchResults) {
            // Pre-Task-6 builds had a single combined cap; keep it for DDG.
            maxDuckDuckGoResults = legacyTotal
        } else {
            maxDuckDuckGoResults = Self.defaultSettings.maxDuckDuckGoResults
        }
        maxWikipediaResults = try container.decodeIfPresent(Int.self, forKey: .maxWikipediaResults)
            ?? Self.defaultSettings.maxWikipediaResults

        maxResponseTokens = try container.decodeIfPresent(Int.self, forKey: .maxResponseTokens)
            ?? Self.defaultSettings.maxResponseTokens
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature)
            ?? Self.defaultSettings.temperature
        isFirstGuessEnabled = try container.decodeIfPresent(Bool.self, forKey: .isFirstGuessEnabled)
            ?? Self.defaultSettings.isFirstGuessEnabled
        isWebSummariesEnabled = try container.decodeIfPresent(Bool.self, forKey: .isWebSummariesEnabled)
            ?? Self.defaultSettings.isWebSummariesEnabled
        useDuckDuckGo = try container.decodeIfPresent(Bool.self, forKey: .useDuckDuckGo)
            ?? Self.defaultSettings.useDuckDuckGo
        useWikipedia = try container.decodeIfPresent(Bool.self, forKey: .useWikipedia)
            ?? Self.defaultSettings.useWikipedia
        language = try container.decodeIfPresent(ModelLanguage.self, forKey: .language)
            ?? Self.defaultSettings.language

        if let storedContextTokens = try container.decodeIfPresent(Int.self, forKey: .maxContextTokens) {
            maxContextTokens = storedContextTokens
        } else if let storedContextWords = try legacyContainer.decodeIfPresent(Int.self, forKey: .maxContextWords) {
            maxContextTokens = max(1, TokenBudgeting.estimatedTokens(forApproxWords: storedContextWords))
        } else if let legacyScrapeCharacters = try legacyContainer.decodeIfPresent(Int.self, forKey: .maxScrapingCharacters) {
            // Preserve user intent from older builds where context was configured in characters.
            maxContextTokens = max(1, legacyScrapeCharacters / TokenBudgeting.avgCharsPerToken)
        } else {
            maxContextTokens = Self.defaultSettings.maxContextTokens
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(maxDuckDuckGoResults, forKey: .maxDuckDuckGoResults)
        try container.encode(maxWikipediaResults, forKey: .maxWikipediaResults)
        try container.encode(maxResponseTokens, forKey: .maxResponseTokens)
        try container.encode(temperature, forKey: .temperature)
        try container.encode(maxContextTokens, forKey: .maxContextTokens)
        try container.encode(isFirstGuessEnabled, forKey: .isFirstGuessEnabled)
        try container.encode(isWebSummariesEnabled, forKey: .isWebSummariesEnabled)
        try container.encode(useDuckDuckGo, forKey: .useDuckDuckGo)
        try container.encode(useWikipedia, forKey: .useWikipedia)
        try container.encode(language, forKey: .language)
    }

    /// Persists settings in UserDefaults for future launches.
    func save() {
        do {
            let data = try JSONEncoder().encode(normalized())
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } catch {
            #if DEBUG
            print("[AppSettings] Failed to save settings: \(error)")
            #endif
        }
    }

    // Value ranges for validation
    static let maxDuckDuckGoResultsRange = 1...20
    static let maxWikipediaResultsRange = 1...20
    /// Combined per-search cap derived from per-source ranges; used by callers that need a
    /// merged limit (e.g. clamping legacy `maxWebResults` style parameters).
    static let maxSearchResultsRange = 2...40
    static let maxResponseTokensRange = 500...3500
    static let temperatureRange = 0.3...1.0
    static let maxContextTokensRange = 300...3500

    static func maxAllowedContextTokens(forResponseTokens responseTokens: Int) -> Int {
        let clampedResponse = min(max(responseTokens, maxResponseTokensRange.lowerBound), maxResponseTokensRange.upperBound)
        let budgetCap = TokenBudgeting.maxAvailableContextTokens(
            maxOutputTokens: clampedResponse,
            instructionTokens: TokenBudgeting.instructionTokens,
            promptOverheadTokens: TokenBudgeting.promptOverheadTokens,
            minContextTokens: TokenBudgeting.minContextTokens
        )
        return min(maxContextTokensRange.upperBound, max(maxContextTokensRange.lowerBound, budgetCap))
    }

    private func normalized() -> AppSettings {
        var copy = self
        copy.maxDuckDuckGoResults = min(max(copy.maxDuckDuckGoResults, Self.maxDuckDuckGoResultsRange.lowerBound), Self.maxDuckDuckGoResultsRange.upperBound)
        copy.maxWikipediaResults = min(max(copy.maxWikipediaResults, Self.maxWikipediaResultsRange.lowerBound), Self.maxWikipediaResultsRange.upperBound)
        copy.maxResponseTokens = min(max(copy.maxResponseTokens, Self.maxResponseTokensRange.lowerBound), Self.maxResponseTokensRange.upperBound)
        copy.maxContextTokens = TokenBudgeting.clampedContextTokens(
            requestedContextTokens: copy.maxContextTokens,
            maxOutputTokens: copy.maxResponseTokens,
            settingsRange: Self.maxContextTokensRange,
            instructionTokens: TokenBudgeting.instructionTokens,
            promptOverheadTokens: TokenBudgeting.promptOverheadTokens,
            minContextTokens: TokenBudgeting.minContextTokens
        )
        copy.temperature = min(max(copy.temperature, Self.temperatureRange.lowerBound), Self.temperatureRange.upperBound)
        return copy
    }
}
