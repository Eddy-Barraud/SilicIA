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
import Observation

/// Shared, observable settings store. Use `AppSettingsStore.shared`; mutate
/// `settings` (or any of its fields through a binding) and the change is
/// observed by all readers and persists automatically.
///
/// Uses the Observation framework (`@Observable`) rather than
/// `ObservableObject`/`@Published`. Because this is one shared instance read
/// by several screens at once, a `@Published` mutation could fire
/// `objectWillChange` while a parent view (e.g. ContentView's tab bar) was
/// mid-update, tripping SwiftUI's "Publishing changes from within view
/// updates is not allowed" warning. `@Observable` tracks property reads
/// granularly and doesn't use `objectWillChange`, so cross-view shared
/// mutations are handled without that constraint.
@MainActor
@Observable
final class AppSettingsStore {
    static let shared = AppSettingsStore()

    /// The live settings. Any mutation is observed by readers and writes
    /// through to UserDefaults via `AppSettings.save()`.
    var settings: AppSettings {
        didSet { settings.save() }
    }

    private init() {
        settings = AppSettings.load()
    }
}
