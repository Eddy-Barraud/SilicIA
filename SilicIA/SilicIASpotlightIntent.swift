//
//  SilicIASpotlightIntent.swift
//  SilicIA
//
//  Created by Copilot on 31/03/2026.
//

import AppIntents
import Foundation

/// Spotlight-triggerable search entry point for SilicIA.
struct OpenSilicIASearchIntent: AppIntent {
    static var title: LocalizedStringResource = "Search with SilicIA"
    static var description = IntentDescription("Open SilicIA Search Assist with your query.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Query")
    var query: String

    func perform() async throws -> some IntentResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result()
        }

        guard let encodedQuery = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "SilicIA://search?q=\(encodedQuery)") else {
            return .result()
        }

        return .result(opensIntent: OpenURLIntent(url))
    }
}
