//
//  SilicIASpotlightIntent.swift
//  SilicIA
//
//

import AppIntents
import Foundation

/// Spotlight-triggerable search entry point for SilicIA.
struct OpenSilicIASearchIntent: AppIntent {
    static var title: LocalizedStringResource = "Open SilicIA Search"
    static var description = IntentDescription("Open SilicIA Search Assist.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        guard let url = URL(string: "SilicIA://search") else {
            return .result()
        }

        return .result(opensIntent: OpenURLIntent(url))
    }
}
