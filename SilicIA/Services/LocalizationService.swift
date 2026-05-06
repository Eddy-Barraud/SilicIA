//
//  LocalizationService.swift
//  SilicIA
//

import Foundation

@MainActor
final class LocalizationService {
    static let shared = LocalizationService()

    private var strings: [String: [String: String]] = [:]

    private init() {
        load()
    }

    func keys(for language: ModelLanguage) -> Set<String> {
        Set((strings[language.code] ?? [:]).keys)
    }

    func load() {
        var merged: [String: [String: String]] = [:]
        let codes = ModelLanguage.allCases.map(\.code)
        let subdirs: [String?] = [nil, "Localization", "Resources/Localization"]
        var seen = Set<URL>()
        for subdir in subdirs {
            guard let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: subdir) else { continue }
            for url in urls {
                guard seen.insert(url).inserted else { continue }
                let filename = url.deletingPathExtension().lastPathComponent
                guard let matchedCode = codes.first(where: { filename.hasSuffix(".\($0)") }) else { continue }
                guard let data = try? Data(contentsOf: url),
                      let dict = try? JSONDecoder().decode([String: String].self, from: data) else { continue }
                merged[matchedCode, default: [:]].merge(dict) { _, new in new }
            }
        }
        strings = merged
    }

    func t(_ key: String, language: ModelLanguage? = nil, _ args: CVarArg...) -> String {
        let lang = language ?? .english
        let resolved = strings[lang.code]?[key]
            ?? strings[ModelLanguage.english.code]?[key]
            ?? key
        guard !args.isEmpty else { return resolved }
        return String(format: resolved, arguments: args)
    }
}

@MainActor let L = LocalizationService.shared
