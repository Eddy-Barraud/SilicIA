//
//  StreamingLaTeXText.swift
//  SilicIA
//
//  Live, sentence-by-sentence LaTeX rendering of a streaming model answer.
//
//  The model streams tokens into a growing string. Rather than wait for the
//  whole answer before rendering math (the old `ProgressiveLaTeXText`
//  behaviour) or feed the LaTeX parser a half-written `$...$` / `\[...\]`
//  (which flickers error glyphs), this view renders the longest
//  math-balanced prefix — every sentence / display block completed so far —
//  as real `LaTeX`, and shows the still-incomplete trailing sentence as dim
//  plain text so the stream stays visibly live.
//
//  The split is a PURE function of the inputs (`text`, `isStreaming`):
//    - committed = `text` up to the last safe boundary (LaTeXStreamSegmenter)
//    - pending   = the remainder, shown as plain text while streaming
//    - when not streaming, committed = the whole answer, pending = ""
//
//  IMPORTANT: `LaTeXSwiftUI.LaTeX` does NOT re-parse when its input string
//  changes for the same view identity — it renders once. During streaming
//  the committed prefix grows (a completed equation moves from `pending` into
//  `committed`), so without forcing a refresh the equation would silently
//  vanish (rendered by a stale LaTeX view that never updated) until the view
//  was rebuilt (e.g. visiting Settings and back). We therefore tag the LaTeX
//  view with `.id(committed)` so SwiftUI re-creates it whenever the committed
//  text changes — a fresh parse, every time it grows.
//

import SwiftUI
import LaTeXSwiftUI

/// Drop-in replacement for `ProgressiveLaTeXText` that renders streamed math
/// progressively. Same `(text:isStreaming:)` call site.
struct StreamingLaTeXText: View {
    let text: String
    let isStreaming: Bool

    @Environment(\.colorScheme) private var colorScheme
    private var foreground: Color { colorScheme == .dark ? .white : .black }

    /// Splits the current text into the math-balanced prefix to render as
    /// LaTeX and the trailing incomplete remainder. Once streaming ends the
    /// whole answer is committed (its final sentence is complete even without
    /// a trailing terminator).
    private var split: (committed: String, pending: String) {
        guard isStreaming else { return (text, "") }
        let boundaries = LaTeXStreamSegmenter.safeBoundaries(text)
        let length = boundaries.last ?? 0
        return (String(text.prefix(length)), String(text.dropFirst(length)))
    }

    var body: some View {
        let parts = split
        #if DEBUG
        let _ = print("[StreamingLaTeX] render isStreaming=\(isStreaming) total=\(text.count) committed=\(parts.committed.count) pending=\(parts.pending.count)")
        #endif
        return VStack(alignment: .leading, spacing: 2) {
            if !parts.committed.isEmpty {
                LaTeX(ModelOutputLaTeXSanitizer.finalizeSanitizedText(parts.committed))
                    .font(.body)
                    .foregroundColor(foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    #if DEBUG
                    .errorMode(.error)
                    #endif
                    // Force a fresh parse whenever the committed text grows —
                    // LaTeXSwiftUI won't re-render the same view on input change.
                    .id(parts.committed)
            }

            if !parts.pending.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Not-yet-finalised sentence: plain text, dimmed, so the user
                // sees live progress without half-rendered math.
                Text(parts.pending)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
