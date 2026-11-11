//
//  SourceToggleButtons.swift
//  SilicIA
//
//  Context source selector allowing only one source of context:
//  Offline, Wiki, or Web.
//  Styled to match the Reasoning Level Selector while keeping small icons.
//

import SwiftUI

/// Segmented context source selector allowing only one active context source:
/// `Offline` (pure on-device model knowledge), `Wiki` (Wikipedia / wiki_fast retrieval),
/// or `Web` (live web search via DuckDuckGo).
///
/// Designed with glass-morphic styling and subtle shadows matching the reasoning level selector.
struct SourceToggleButtons: View {
    /// Observable settings store binding controlling active context selection.
    @Bindable var settingsStore: AppSettingsStore = .shared

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ContextSourceKind.allCases) { source in
                let isSelected = settingsStore.settings.contextSourceKind == source
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        settingsStore.settings.contextSourceKind = source
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: source.systemImage)
                            .font(.subheadline)
                        Text(source.displayName)
                            .font(.subheadline)
                            .fontWeight(isSelected ? .semibold : .medium)
                    }
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(minHeight: 24)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(PlatformColors.controlBackground)
                                .shadow(color: .black.opacity(0.12), radius: 1, x: 0, y: 0.5)
                        }
                    }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel(source.displayName)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}
