//
//  StreamingLaTeXText.swift
//  SilicIA
//
//  Live, sentence-by-sentence LaTeX rendering of a streaming model answer.
//
//  The model streams tokens into a growing string. Rather than wait for the
//  whole answer before rendering math (the old `ProgressiveLaTeXText`
//  behaviour) or feed the LaTeX parser half-written `$...$` (which flickers
//  error glyphs), this view:
//
//    1. splits the accumulated text into math-balanced segments at sentence
//       / display-math boundaries (`LaTeXStreamSegmenter`),
//    2. reveals one completed segment at a time on a small delay, growing a
//       "committed" prefix that is rendered as real `LaTeX`, and
//    3. shows the still-incomplete trailing sentence as dim plain text so
//       the stream stays visibly live.
//
//  When streaming ends, everything is flushed and rendered as LaTeX.
//

import SwiftUI
import LaTeXSwiftUI

/// Owns the reveal cadence. An `@Observable` (not view state) so a single
/// long-running pump can read the latest streamed text — a SwiftUI `.task`
/// captured on a value-type View can't see later mutations.
@MainActor
@Observable
final class StreamingLaTeXReveal {
    /// Math-balanced prefix safe to render as LaTeX right now.
    private(set) var committedText = ""
    /// Trailing, still-incomplete sentence — shown as plain text.
    private(set) var pendingText = ""

    private var fullText = ""
    private var streaming = false
    private var boundaries: [Int] = []
    private var revealedCount = 0
    private var pump: Task<Void, Never>?
    private let revealDelay: Duration

    init(revealDelay: Duration = .milliseconds(90)) {
        self.revealDelay = revealDelay
    }

    /// Feed the latest streamed text + state. Idempotent; call on every change.
    func update(text: String, isStreaming: Bool) {
        fullText = text
        streaming = isStreaming
        boundaries = LaTeXStreamSegmenter.safeBoundaries(text)

        guard isStreaming else {
            // Done — reveal the entire answer (the final tail is complete even
            // if it doesn't end in a terminator).
            revealedCount = boundaries.count
            committedText = text
            pendingText = ""
            pump?.cancel()
            pump = nil
            return
        }

        // Cap any over-count from a shrink (shouldn't happen — text only grows).
        revealedCount = min(revealedCount, boundaries.count)
        recomputeVisible()
        startPumpIfNeeded()
    }

    /// Recomputes the committed / pending split from the current reveal count.
    private func recomputeVisible() {
        let length: Int
        if revealedCount > 0, !boundaries.isEmpty {
            length = boundaries[min(revealedCount, boundaries.count) - 1]
        } else {
            length = 0
        }
        committedText = String(fullText.prefix(length))
        pendingText = String(fullText.dropFirst(length))
    }

    private func startPumpIfNeeded() {
        guard pump == nil else { return }
        pump = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.revealedCount < self.boundaries.count {
                    try? await Task.sleep(for: self.revealDelay)
                    if Task.isCancelled { return }
                    self.revealedCount = min(self.revealedCount + 1, self.boundaries.count)
                    self.recomputeVisible()
                } else if !self.streaming {
                    return
                } else {
                    // Caught up; wait for more text to complete a sentence.
                    try? await Task.sleep(for: self.revealDelay)
                }
            }
        }
    }
}

/// Drop-in replacement for `ProgressiveLaTeXText` that renders streamed math
/// progressively. Same `(text:isStreaming:)` call site.
struct StreamingLaTeXText: View {
    let text: String
    let isStreaming: Bool
    var revealDelay: Duration = .milliseconds(90)

    @Environment(\.colorScheme) private var colorScheme
    @State private var reveal: StreamingLaTeXReveal

    init(text: String, isStreaming: Bool, revealDelay: Duration = .milliseconds(90)) {
        self.text = text
        self.isStreaming = isStreaming
        self.revealDelay = revealDelay
        _reveal = State(initialValue: StreamingLaTeXReveal(revealDelay: revealDelay))
    }

    private var foreground: Color { colorScheme == .dark ? .white : .black }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !reveal.committedText.isEmpty {
                LaTeX(ModelOutputLaTeXSanitizer.finalizeSanitizedText(reveal.committedText))
                    .font(.body)
                    .foregroundColor(foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    #if DEBUG
                    .errorMode(.error)
                    #endif
            }

            if !reveal.pendingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Not-yet-finalised sentence: plain text, dimmed, so the user
                // sees live progress without half-rendered math.
                Text(reveal.pendingText)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.easeOut(duration: 0.15), value: reveal.committedText)
        .onChange(of: text, initial: true) {
            reveal.update(text: text, isStreaming: isStreaming)
        }
        .onChange(of: isStreaming) {
            reveal.update(text: text, isStreaming: isStreaming)
        }
    }
}
