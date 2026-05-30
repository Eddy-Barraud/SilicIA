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

/// Chat-bubble glass: accent-tinted for the user's own turns, neutral for
/// assistant replies. Extracted as a `ViewModifier` because the tint
/// branch can't be expressed as a single inline `.glassEffect` call.
struct MessageBubbleGlass: ViewModifier {
    let isUser: Bool

    func body(content: Content) -> some View {
        if isUser {
            content.glassEffect(
                .regular.tint(.accentColor.opacity(0.5)),
                in: .rect(cornerRadius: 14)
            )
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: 14))
        }
    }
}
