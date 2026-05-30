//
//  PlatformUI.swift
//  SilicIA
//
//  Cross-platform UI primitives shared between ChatView and SearchView.
//  Both views independently defined identical copies of these
//  semantic-color accessors, the clipboard helper, and the progressive
//  LaTeX renderer; centralising them keeps the two screens visually and
//  behaviourally in lock-step.
//

import SwiftUI
import LaTeXSwiftUI
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - Semantic background colors

extension Color {
    /// Background for grouped controls / settings panels. Maps to the
    /// platform's standard "control" surface so the app respects light /
    /// dark mode and accessibility contrast settings automatically.
    static var platformControlBackground: Color {
        #if os(macOS)
        return Color(NSColor.controlBackgroundColor)
        #else
        return Color(UIColor.secondarySystemBackground)
        #endif
    }

    /// Background for editable text surfaces (the composer / search bar).
    static var platformTextBackground: Color {
        #if os(macOS)
        return Color(NSColor.textBackgroundColor)
        #else
        return Color(UIColor.systemBackground)
        #endif
    }

    /// Background for the whole window / screen behind scrollable content.
    static var platformWindowBackground: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(UIColor.systemGroupedBackground)
        #endif
    }
}

// MARK: - Clipboard

enum PlatformClipboard {
    /// Copies plain text to the system pasteboard on macOS / iOS.
    static func copyPlainText(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }
}

// MARK: - Progressive LaTeX renderer

/// Renders model output that may contain LaTeX math.
///
/// While the answer is still streaming we show it as plain `Text`: the
/// LaTeX parser chokes on half-written `$...$` / `\[...\]` delimiters and
/// flickers error glyphs on every token. Once streaming completes we hand
/// the finalised, sanitised string to `LaTeX` for proper math rendering.
///
/// Reads `colorScheme` from the environment so the text colour tracks
/// light / dark mode without the call site having to thread it in.
struct ProgressiveLaTeXText: View {
    let text: String
    let isStreaming: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if isStreaming {
            Text(text)
                .font(.body)
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LaTeX(ModelOutputLaTeXSanitizer.finalizeSanitizedText(text))
                .font(.body)
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .frame(maxWidth: .infinity, alignment: .leading)
                #if DEBUG
                .errorMode(.error)
                #endif
        }
    }
}
