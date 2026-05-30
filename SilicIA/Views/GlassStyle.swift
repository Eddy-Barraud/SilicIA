//
//  GlassStyle.swift
//  SilicIA
//
//  Shared Liquid Glass styling for the iOS 26 / macOS 26 design language.
//  Centralised so ChatView and SearchView present identical glass
//  surfaces (composer, search bar, cards, settings panels) and so the
//  whole app can be re-tuned from one place.
//
//  Liquid Glass automatically adapts to light / dark appearance and to
//  the content behind it — these helpers deliberately avoid hardcoded
//  fills so the system material does the work. Pair foreground text with
//  the semantic `.primary` / `.secondary` colors (never literal black /
//  white) so contrast tracks the system theme.
//

import SwiftUI

extension View {
    /// Wraps a surface in the regular Liquid Glass material clipped to a
    /// rounded rectangle. Use for the large input islands — the chat
    /// composer and the search bar — that float above scrolling content.
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }

    /// Glass material tinted with the accent colour, for surfaces that
    /// should read as "active" (e.g. the web-search chip when enabled).
    func glassAccentCard(cornerRadius: CGFloat = 12) -> some View {
        glassEffect(.regular.tint(.accentColor.opacity(0.5)), in: .rect(cornerRadius: cornerRadius))
    }

    /// Lighter-weight glass for secondary, nested surfaces — assistant
    /// message bubbles, context rows, result cards — that sit inside an
    /// already-glassy or scrolling region. Uses the same regular material
    /// but a smaller default radius to match smaller elements.
    func glassTile(cornerRadius: CGFloat = 12) -> some View {
        glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}

// MARK: - Subtle solid-fill helpers
// Used for content surfaces (message bubbles, summary card, result cards,
// example chips) that sit directly on the system window background. Glass
// looks great when there is rich content behind it to refract; on a plain
// background it reads as dark/grey. These helpers use very light solid fills
// instead — the same visual language as iMessage and Apple News cards.

extension View {
    /// iMessage "sent" style: solid accent fill. Because the fill is opaque,
    /// the caller should ensure foreground text uses `.white` / `.primary`
    /// so it reads on the coloured background in both light and dark mode.
    func accentBubble(cornerRadius: CGFloat = 14) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.accentColor)
        )
    }

    /// iMessage "received" style: very subtle secondary tint so the assistant
    /// reply area is identifiable without competing with the window background.
    func receivedBubble(cornerRadius: CGFloat = 14) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.secondary.opacity(0.1))
        )
    }

    /// Light accent-tinted card — used for the AI summary card and the
    /// first-guess card. A hairline accent border reinforces the tint.
    func subtleAccentCard(cornerRadius: CGFloat = 16) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.accentColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.accentColor.opacity(0.2), lineWidth: 0.5)
                )
        )
    }

    /// Minimal secondary-tinted tile — used for result cards, context rows,
    /// and example-query chips that need a light separating surface without
    /// a strong visual weight.
    func subtleTile(cornerRadius: CGFloat = 12) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.primary.opacity(0.05))
        )
    }

    /// Accent-tinted chip — used for the web-search "enabled" indicator in
    /// the composer. A shade lighter than `subtleAccentCard` so it reads as
    /// an inline status chip rather than a section card.
    func subtleAccentChip(cornerRadius: CGFloat = 10) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.accentColor.opacity(0.12))
        )
    }
}

/// Resolves the platform system color used for chat bubbles and control
/// backgrounds. Defined once here so `MessageBubble` and the messages
/// scroll container can share the same colour without keeping duplicate
/// platform-branching code in every view.
struct PlatformColors {
    /// Background for assistant message bubbles and the messages scroll area.
    /// Matches `NSColor.controlBackgroundColor` on macOS and
    /// `UIColor.secondarySystemBackground` on iOS — a light neutral that
    /// reads clearly on the window background in both light and dark mode.
    static var controlBackground: Color {
        #if os(macOS)
        return Color(NSColor.controlBackgroundColor)
        #else
        return Color(UIColor.secondarySystemBackground)
        #endif
    }

    /// Background for the messages scroll container itself.
    /// `NSColor.textBackgroundColor` on macOS, `UIColor.systemBackground`
    /// on iOS — slightly warmer / lighter than `controlBackground`.
    static var textBackground: Color {
        #if os(macOS)
        return Color(NSColor.textBackgroundColor)
        #else
        return Color(UIColor.systemBackground)
        #endif
    }
}

/// Chat-bubble style that restores the pre-glass look users preferred:
/// a very light accent tint for sent messages and the platform control-
/// background colour for received messages. Both adapt automatically to
/// light / dark mode via system semantic colours.
struct MessageBubbleGlass: ViewModifier {
    let isUser: Bool

    func body(content: Content) -> some View {
        if isUser {
            // Light accent tint (15 % opacity) — reads as "your message"
            // without the heavy contrast of a solid colour.
            content
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.15))
                )
        } else {
            // Platform control background — the same neutral the system uses
            // for text-input fields and secondary panels.
            content
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(PlatformColors.controlBackground)
                )
        }
    }
}
