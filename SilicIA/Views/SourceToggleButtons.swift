//
//  SourceToggleButtons.swift
//  SilicIA
//
//  Context source toggle buttons for Wikipedia and Internet.
//  Centered in both SearchView and ChatView headers, allowing users
//  to quickly toggle context sources or deactivate both for offline LLM mode.
//

import SwiftUI

struct SourceToggleButtons: View {
    var settingsStore: AppSettingsStore = .shared

    var body: some View {
        HStack(spacing: 8) {
            sourceButton(
                title: "Wikipedia",
                systemImage: "book.closed",
                isActive: settingsStore.settings.useWikipedia,
                action: {
                    settingsStore.settings.useWikipedia.toggle()
                }
            )

            sourceButton(
                title: "Internet",
                systemImage: "globe",
                isActive: settingsStore.settings.useDuckDuckGo,
                action: {
                    settingsStore.settings.useDuckDuckGo.toggle()
                }
            )
        }
    }

    private func sourceButton(
        title: String,
        systemImage: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.subheadline)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundStyle(isActive ? Color.green : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isActive ? Color.green.opacity(0.12) : Color.gray.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isActive ? Color.green.opacity(0.4) : Color.gray.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: isActive)
        .accessibilityLabel("\(title): \(isActive ? "Active" : "Inactive")")
    }
}
