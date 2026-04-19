import Foundation

enum ModelLanguage: String, CaseIterable, Codable {
    case french = "French"
    case english = "English"
}

struct AppSettings: Codable, Equatable {
    var maxResponseTokens: Int = 1800
    var temperature: Double = 0.3
    var maxContextTokens: Int = 1200
    var language: ModelLanguage = .english

    private static let storageKey = "TinIA.AppSettings"
    private static let defaultSettings = AppSettings()

    private enum CodingKeys: String, CodingKey {
        case maxResponseTokens
        case temperature
        case maxContextTokens
        case language
    }

    init() {}

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

    func save() {
        do {
            let data = try JSONEncoder().encode(normalized())
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } catch {
            #if DEBUG
            print("[AppSettings] Failed to save settings: \(error.localizedDescription)")
            #endif
        }
    }

    static let maxResponseTokensRange = 500...3500
    static let temperatureRange = 0.1...1.0
    static let maxContextTokensRange = 300...3500

    static func maxAllowedContextTokens(forResponseTokens responseTokens: Int) -> Int {
        let clampedResponse = min(
            max(responseTokens, maxResponseTokensRange.lowerBound),
            maxResponseTokensRange.upperBound
        )
        let budgetCap = TokenBudgeting.maxAvailableContextTokens(maxOutputTokens: clampedResponse)
        return min(maxContextTokensRange.upperBound, max(maxContextTokensRange.lowerBound, budgetCap))
    }

    private func normalized() -> AppSettings {
        var copy = self
        copy.maxResponseTokens = min(
            max(copy.maxResponseTokens, Self.maxResponseTokensRange.lowerBound),
            Self.maxResponseTokensRange.upperBound
        )
        copy.maxContextTokens = TokenBudgeting.clampedContextTokens(
            requestedContextTokens: copy.maxContextTokens,
            maxOutputTokens: copy.maxResponseTokens,
            settingsRange: Self.maxContextTokensRange
        )
        copy.temperature = min(max(copy.temperature, Self.temperatureRange.lowerBound), Self.temperatureRange.upperBound)
        return copy
    }
}
