//
//  PlatformUI.swift
//  SilicIA
//
//  Cross-platform UI primitives shared between ChatView and SearchView.
//

import SwiftUI
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - Semantic background colors

extension Color {
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
