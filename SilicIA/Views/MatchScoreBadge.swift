//
//  MatchScoreBadge.swift
//  SilicIA
//
//  Created by Eddy Barraud on 17/05/2026.
//

import SwiftUI

/// Small circular progress ring used on search-result cards to display how
/// much that source contributed to the RAG-grounded answer.
///
/// The ring fills clockwise from 12 o'clock proportional to `percent`,
/// which is expected in `[0, 100]` (any out-of-range value is clamped).
/// The number inside the ring is rounded to the nearest integer.
struct MatchScoreBadge: View {
    let percent: Double
    /// Localisation language for the accessibility label. The visible
    /// text is just the percentage — no translation needed.
    var language: ModelLanguage = .english

    private var clampedPercent: Double { min(100, max(0, percent)) }
    private var progress: Double { clampedPercent / 100 }
    private var displayPercent: Int { Int(clampedPercent.rounded()) }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.0001))   // hit-test area; keeps ring on top
            Circle()
                .stroke(Color.green.opacity(0.18), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.green,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))       // start at 12 o'clock
                .animation(.easeInOut(duration: 0.5), value: progress)
            Text("\(displayPercent)%")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.green)
                .monospacedDigit()
        }
        .frame(width: 34, height: 34)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(
            format: L.t("search.result.matchScoreAccessibility", language: language),
            displayPercent
        )))
    }
}
