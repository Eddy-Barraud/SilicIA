//
//  SharedTopBarView.swift
//  SilicIA
//
//  Unified top bar shared between SearchView and ChatView.
//  Provides:
//  - Left: New button ("square.and.pencil") to clear/reset conversation or search
//  - Center: Context source selector (Offline, Wiki, Web) via SourceToggleButtons
//  - Right: History ("clock.arrow.circlepath") and Settings ("gearshape") buttons
//

import SwiftUI

/// Unified top bar shared between `SearchView` and `ChatView`.
///
/// Features:
/// - Left: New conversation/search button (`square.and.pencil`)
/// - Center: Context source selector (`Offline`, `Wiki`, `Web`) via `SourceToggleButtons`
/// - Right: History drawer toggle (`clock.arrow.circlepath`) and Settings toggle (`gearshape`)
struct SharedTopBarView: View {
    /// Observable settings store driving live localization and context mode.
    @Bindable var settingsStore: AppSettingsStore = .shared

    /// Whether to render the central `SourceToggleButtons` context selector.
    var showContextSelector: Bool = true

    /// Callback triggered when tapping the "New" button to start fresh.
    var onNew: () -> Void

    /// Callback triggered when tapping the "History" button.
    var onHistory: () -> Void

    /// Callback triggered when tapping the "Settings" button.
    var onSettings: () -> Void

    private var settings: AppSettings {
        settingsStore.settings
    }

    var body: some View {
        HStack(spacing: 4) {
            headerIconButton(
                systemImage: "square.and.pencil",
                label: L.t("common.new", language: settings.language),
                action: onNew
            )

            if showContextSelector {
                Spacer(minLength: 0)
                SourceToggleButtons(settingsStore: settingsStore)
                Spacer(minLength: 0)
            } else {
                Spacer()
            }

            headerIconButton(
                systemImage: "clock.arrow.circlepath",
                label: L.t("common.history", language: settings.language),
                action: onHistory
            )

            headerIconButton(
                systemImage: "gearshape",
                label: L.t("common.settings", language: settings.language),
                action: onSettings
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func headerIconButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}
