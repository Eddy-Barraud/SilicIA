//
//  ModelAvailabilityNotice.swift
//  SilicIA
//
//  Created by Eddy Barraud on 06/06/2026.
//

import SwiftUI

/// Inline notice shown in place of a generated answer when Apple
/// Intelligence isn't available. Replaces the former full-screen blocking
/// `ModelUnavailableView`: the rest of the app keeps working (web search +
/// retrieval-ranked source cards), and this card just explains why there's
/// no written answer and — when the user can fix it — offers a shortcut to
/// the Settings app.
struct ModelAvailabilityNotice: View {
    let reason: FoundationModelAvailability.Reason
    let language: ModelLanguage
    var drawBackground: Bool = true

    var body: some View {
        if drawBackground {
            content
                .padding()
                .subtleAccentCard(cornerRadius: 16)
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)

                Text(FoundationModelAvailability.title(for: reason, language: language))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }

            Text(FoundationModelAvailability.message(for: reason, language: language))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if reason.isUserFixable {
                Button {
                    FoundationModelAvailability.openSettings()
                } label: {
                    Label(
                        FoundationModelAvailability.settingsButtonLabel(language: language),
                        systemImage: "gearshape"
                    )
                    .font(.subheadline)
                    .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `deviceNotEligible` is a hard dead-end (warning triangle); the other
    /// reasons are recoverable, so they get the friendlier Apple Intelligence
    /// sparkle-with-slash glyph.
    private var iconName: String {
        reason == .deviceNotEligible ? "exclamationmark.triangle.fill" : "sparkles"
    }
}

#Preview("Not enabled") {
    ModelAvailabilityNotice(reason: .notEnabled, language: .english)
        .padding()
}

#Preview("Device not eligible") {
    ModelAvailabilityNotice(reason: .deviceNotEligible, language: .english)
        .padding()
}
