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
}

/// User-configurable settings controlling search and summary behavior.
struct AppSettings: Codable, Equatable {
    var maxSearchResults: Int = 5
    var maxResponseTokens: Int = 700
    var temperature: Double = 0.3
    var maxScrapingCharacters: Int = 3000
    var language: ModelLanguage = .french

    private static let storageKey = "SilicIA.AppSettings"

    /// Loads settings from UserDefaults and falls back to defaults if unavailable.
    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return AppSettings()
        }

        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            return AppSettings()
        }
    }

    /// Persists settings in UserDefaults for future launches.
    func save() {
        do {
            let data = try JSONEncoder().encode(self)
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } catch {
            #if DEBUG
            print("[AppSettings] Failed to save settings: \(error)")
            #endif
        }
    }

    // Value ranges for validation
    static let maxSearchResultsRange = 1...20
    static let maxResponseTokensRange = 500...3000
    static let temperatureRange = 0.0...1.0
    static let maxScrapingCharactersRange = 1000...10000
}
