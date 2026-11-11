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

struct SharedTopBarView: View {
    @Bindable var settingsStore: AppSettingsStore = .shared
    var showContextSelector: Bool = true
    var onNew: () -> Void
    var onHistory: () -> Void
    var onSettings: () -> Void

    private var settings: AppSettings {
        settingsStore.settings
    }

    var body: some View {
        ZStack {
            if showContextSelector {
                SourceToggleButtons(settingsStore: settingsStore)
            }

            HStack(spacing: 4) {
                headerIconButton(
                    systemImage: "square.and.pencil",
                    label: L.t("common.new", language: settings.language),
                    action: onNew
                )

                Spacer()

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
        }
        .padding()
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
