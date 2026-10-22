//
//  AppSettings.swift
//  SilicIA
//
//  Created by Claude on 23/03/2026.
//

import Foundation
import NaturalLanguage

/// Supported output languages for generated model responses.
nonisolated enum ModelLanguage: String, CaseIterable, Codable, Sendable {
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

    var nlLanguage: NLLanguage {
        switch self {
        case .english: return .english
        case .french: return .french
        case .spanish: return .spanish
        }
    }

    static func systemPreferred(preferredLanguages: [String] = Locale.preferredLanguages) -> ModelLanguage {
        for identifier in preferredLanguages {
            let lowered = identifier.lowercased()
            if lowered.hasPrefix("fr") { return .french }
            if lowered.hasPrefix("es") { return .spanish }
            if lowered.hasPrefix("en") { return .english }
        }
        return .english
    }
}

/// User-configurable settings controlling search and summary behavior.
struct AppSettings: Codable, Equatable {
    var maxDuckDuckGoResults: Int = 4
    var maxWikipediaResults: Int = 2
    var totalTokensBudget: Int = 2500
    var maxResponseTokens: Int = 500
    var temperature: Double = 0.7
    var maxContextTokens: Int = 2000
    private var _isReaderViewAndSummaryEnabled: Bool = false
    var isReaderViewAndSummaryEnabled: Bool {
        get {
            guard FoundationModelAvailability.check().isAvailable else { return false }
            return _isReaderViewAndSummaryEnabled
        }
        set {
            _isReaderViewAndSummaryEnabled = newValue
        }
    }
    /// Compatibility alias for isReaderViewAndSummaryEnabled
    var isWebSummariesEnabled: Bool {
        get { isReaderViewAndSummaryEnabled }
        set { isReaderViewAndSummaryEnabled = newValue }
    }
    var useDuckDuckGo: Bool = true
    var useWikipedia: Bool = true
    var language: ModelLanguage = .systemPreferred()

    /// Combined per-search result cap exposed for callers that still need a single number
    /// (e.g. results display limit, scraping cap).
    var maxSearchResults: Int { maxDuckDuckGoResults + maxWikipediaResults }

    private static let storageKey = "SilicIA.AppSettings"
    private static let defaultSettings = AppSettings()

    private enum CodingKeys: String, CodingKey {
        case maxDuckDuckGoResults
        case maxWikipediaResults
        case totalTokensBudget
        case maxResponseTokens
        case temperature
        case maxContextTokens
        case isReaderViewAndSummaryEnabled
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

        totalTokensBudget = try container.decodeIfPresent(Int.self, forKey: .totalTokensBudget)
            ?? Self.defaultSettings.totalTokensBudget
        maxResponseTokens = try container.decodeIfPresent(Int.self, forKey: .maxResponseTokens)
            ?? Self.defaultSettings.maxResponseTokens
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature)
            ?? Self.defaultSettings.temperature
        if let readerAndSummary = try container.decodeIfPresent(Bool.self, forKey: .isReaderViewAndSummaryEnabled) {
            isReaderViewAndSummaryEnabled = readerAndSummary
        } else if let legacyWebSummaries = try container.decodeIfPresent(Bool.self, forKey: .isWebSummariesEnabled) {
            isReaderViewAndSummaryEnabled = legacyWebSummaries
        } else {
            isReaderViewAndSummaryEnabled = Self.defaultSettings.isReaderViewAndSummaryEnabled
        }
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
        try container.encode(totalTokensBudget, forKey: .totalTokensBudget)
        try container.encode(maxResponseTokens, forKey: .maxResponseTokens)
        try container.encode(temperature, forKey: .temperature)
        try container.encode(maxContextTokens, forKey: .maxContextTokens)
        try container.encode(isReaderViewAndSummaryEnabled, forKey: .isReaderViewAndSummaryEnabled)
        try container.encode(isReaderViewAndSummaryEnabled, forKey: .isWebSummariesEnabled)
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
    static let maxDuckDuckGoResultsRange = 4...12
    static let maxWikipediaResultsRange = 2...12
    /// Combined per-search cap derived from per-source ranges; used by callers that need a
    /// merged limit (e.g. clamping legacy `maxWebResults` style parameters).
    static let maxSearchResultsRange = 2...40
    static let defaultTotalTokensBudget = 2700
    static let totalTokensBudgetRange = 1000...4000
    static var totalTokensBudget: Int { defaultTotalTokensBudget }
    static let maxResponseTokensRange = 250...3500
    static let temperatureRange = 0.3...1.0
    static let maxContextTokensRange = 250...3500

    /// Re-allocates response and context tokens proportionately when the total token budget changes.
    mutating func setTotalTokensBudget(_ newTotal: Int) {
        let clampedTotal = min(max(newTotal, Self.totalTokensBudgetRange.lowerBound), Self.totalTokensBudgetRange.upperBound)
        guard clampedTotal != totalTokensBudget else { return }
        let oldTotal = Double(max(1, totalTokensBudget))
        let responseRatio = Double(maxResponseTokens) / oldTotal
        totalTokensBudget = clampedTotal
        let rawResponse = Int(round(Double(clampedTotal) * responseRatio))
        let minResp = Self.maxResponseTokensRange.lowerBound
        let maxResp = max(minResp, clampedTotal - Self.maxContextTokensRange.lowerBound)
        maxResponseTokens = min(max(rawResponse, minResp), maxResp)
        maxContextTokens = max(Self.maxContextTokensRange.lowerBound, clampedTotal - maxResponseTokens)
    }

    static func maxAllowedContextTokens(forResponseTokens responseTokens: Int, totalBudget: Int = defaultTotalTokensBudget) -> Int {
        let clampedResponse = min(max(responseTokens, maxResponseTokensRange.lowerBound), maxResponseTokensRange.upperBound)
        return max(maxContextTokensRange.lowerBound, totalBudget - clampedResponse)
    }

    private func normalized() -> AppSettings {
        var copy = self
        copy.totalTokensBudget = min(max(copy.totalTokensBudget, Self.totalTokensBudgetRange.lowerBound), Self.totalTokensBudgetRange.upperBound)
        copy.maxDuckDuckGoResults = min(max(copy.maxDuckDuckGoResults, Self.maxDuckDuckGoResultsRange.lowerBound), Self.maxDuckDuckGoResultsRange.upperBound)
        copy.maxWikipediaResults = min(max(copy.maxWikipediaResults, Self.maxWikipediaResultsRange.lowerBound), Self.maxWikipediaResultsRange.upperBound)

        let maxAllowedResponse = max(Self.maxResponseTokensRange.lowerBound, copy.totalTokensBudget - Self.maxContextTokensRange.lowerBound)
        let responseUpper = min(Self.maxResponseTokensRange.upperBound, maxAllowedResponse)
        copy.maxResponseTokens = min(max(copy.maxResponseTokens, Self.maxResponseTokensRange.lowerBound), responseUpper)
        let maxAllowedContext = max(Self.maxContextTokensRange.lowerBound, copy.totalTokensBudget - copy.maxResponseTokens)
        copy.maxContextTokens = min(max(copy.maxContextTokens, Self.maxContextTokensRange.lowerBound), maxAllowedContext)

        copy.temperature = min(max(copy.temperature, Self.temperatureRange.lowerBound), Self.temperatureRange.upperBound)
        if !FoundationModelAvailability.check().isAvailable {
            copy.isReaderViewAndSummaryEnabled = false
        }
        return copy
    }
}
