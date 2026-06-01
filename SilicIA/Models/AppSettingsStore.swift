//
//  AppSettingsStore.swift
//  SilicIA
//
//  App-wide observable wrapper around `AppSettings`. A single source of
//  truth so every screen reflects a settings change the instant it happens
//  anywhere — most visibly the output language driving ContentView's top
//  tab bar while the picker lives in a nested settings sub-page — and so
//  persistence is automatic (no scattered `.onChange { save() }`).
//
//  Previously each view kept its own `@State settings = AppSettings.load()`,
//  saved on change, and reloaded on appear. That left copies out of sync:
//  ContentView never saw a language change made inside ChatView/SearchView.
//  Routing every view through this shared object fixes that by construction.
//

import Foundation
import Combine

/// Shared, observable settings store. Use `AppSettingsStore.shared`; mutate
/// `settings` (or any of its fields through a binding) and the change
/// publishes to all observers and persists automatically.
@MainActor
final class AppSettingsStore: ObservableObject {
    static let shared = AppSettingsStore()

    /// The live settings. Any mutation re-publishes to observers and writes
    /// through to UserDefaults via `AppSettings.save()`.
    @Published var settings: AppSettings {
        didSet { settings.save() }
    }

    private init() {
        settings = AppSettings.load()
    }
}
