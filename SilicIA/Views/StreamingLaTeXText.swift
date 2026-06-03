//
//  StreamingLaTeXText.swift
//  SilicIA
//
//  Live, block-by-block LaTeX rendering of a streaming model answer.
//
//  The model streams tokens into a growing string. We split it into
//  paragraph blocks (separated by blank lines). Every COMPLETED block —
//  i.e. every block except the one still being typed — is rendered as its
//  own `LaTeX` view; the block currently streaming is shown as dim plain
//  text so the stream stays visibly live. When streaming ends, the final
//  block is rendered too.
//
//  Why per-block instead of one growing LaTeX view:
//    - LaTeXSwiftUI's `LaTeX` does not re-parse when its input changes for
//      the same view identity, so a single growing view drops equations that
//      arrive after the first render.
//    - Forcing it to refresh with `.id(committedText)` re-created the WHOLE
//      view on every token, which re-rendered every equation repeatedly and
//      made their sizes fluctuate.
//  Paragraph blocks are append-only: earlier blocks never change as more
//  text streams in, so each completed block is parsed exactly once at a
//  stable size (identified by its position), and new blocks simply append.
//

import SwiftUI
import LaTeXSwiftUI

/// Drop-in replacement for `ProgressiveLaTeXText` that renders streamed math
/// progressively, block by block. Same `(text:isStreaming:)` call site.
struct StreamingLaTeXText: View {
    let text: String
    let isStreaming: Bool

    @Environment(\.colorScheme) private var colorScheme
    private var foreground: Color { colorScheme == .dark ? .white : .black }

    var body: some View {
        let blocks = LaTeXStreamSegmenter.paragraphBlocks(in: text)
        // While streaming, the last block is still being typed → show it as
        // plain text. Every earlier block is complete and stable. When
        // streaming ends, all blocks are complete.
        let committed = isStreaming ? Array(blocks.dropLast()) : blocks
        let pending = isStreaming ? (blocks.last ?? "") : ""

        #if DEBUG
        let _ = print("[StreamingLaTeX] render isStreaming=\(isStreaming) total=\(text.count) blocks=\(blocks.count) committed=\(committed.count)")
        #endif

        return VStack(alignment: .leading, spacing: 8) {
            // Stable identity = position. Blocks are append-only, so a given
            // index always maps to the same completed content; SwiftUI keeps
            // each block's LaTeX view across renders (parsed once, stable
            // size). Index — not content — because a stalled model can emit
            // identical paragraphs, which would collide under `id: \.self`.
            ForEach(Array(committed.enumerated()), id: \.offset) { _, block in
                LaTeX(ModelOutputLaTeXSanitizer.finalizeSanitizedText(block))
                    .font(.body)
                    .foregroundColor(foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    #if DEBUG
                    .errorMode(.error)
                    #endif
            }

            if !pending.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(pending)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
