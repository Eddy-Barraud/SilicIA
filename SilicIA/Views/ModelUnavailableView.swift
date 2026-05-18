//
//  ModelUnavailableView.swift
//  SilicIA
//
//  Created by Eddy Barraud on 18/05/2026.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Full-screen blocking page shown when Apple Intelligence is not
/// available on this device. SilicIA has no NLP fallback, so the only
/// useful affordance is "close the app and re-launch after fixing the
/// device" — there is no way to dismiss back into a working state.
struct ModelUnavailableView: View {
    /// Already-localized reason text from `FoundationModelAvailability`.
    let message: String

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64, weight: .regular))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text(FoundationModelAvailability.alertTitle)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button(action: closeApp) {
                Text(FoundationModelAvailability.closeButtonLabel)
                    .frame(maxWidth: 320)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    /// Quits the app. On macOS uses the standard `NSApplication.terminate`
    /// path; on iOS we use `exit(0)` — Apple discourages programmatic
    /// termination in normal flows, but this screen is the explicit
    /// "the app cannot function" state and there is nothing else to do.
    private func closeApp() {
        #if os(macOS)
        NSApplication.shared.terminate(nil)
        #else
        exit(0)
        #endif
    }
}

#Preview {
    ModelUnavailableView(
        message: "This device does not support Apple Intelligence. SilicIA requires it to work."
    )
}
