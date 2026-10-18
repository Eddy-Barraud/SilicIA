//
//  TokenBudgetSliderView.swift
//  SilicIA
//
//  A unified slider control for configuring the 4096-token budget,
//  splitting tokens between context (input) on the left and response (output)
//  on the right, showing exact token counts and estimated word counts.
//

import SwiftUI

struct TokenBudgetSliderView: View {
    @Binding var settings: AppSettings
    let language: ModelLanguage

    private var estimatedContextWords: Int {
        TokenBudgeting.estimatedContextWords(forTokens: settings.maxContextTokens)
    }

    private var estimatedOutputWords: Int {
        TokenBudgeting.estimatedOutputWords(forTokens: settings.maxResponseTokens)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L.t("settings.tokenBudget.title", language: language))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(AppSettings.totalTokensBudget) tokens")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.t("settings.tokenBudget.context", language: language))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(L.t("settings.tokenBudget.tokens", language: language, Int64(settings.maxContextTokens)))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(L.t("settings.tokenBudget.approxWords", language: language, Int64(estimatedContextWords)))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(L.t("settings.tokenBudget.response", language: language))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(L.t("settings.tokenBudget.tokens", language: language, Int64(settings.maxResponseTokens)))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(L.t("settings.tokenBudget.approxWords", language: language, Int64(estimatedOutputWords)))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Slider(
                value: Binding(
                    get: { Double(settings.maxContextTokens) },
                    set: { newValue in
                        let context = Int(newValue)
                        settings.maxContextTokens = context
                        settings.maxResponseTokens = AppSettings.totalTokensBudget - context
                    }
                ),
                in: Double(AppSettings.maxContextTokensRange.lowerBound)...Double(AppSettings.totalTokensBudget - AppSettings.maxResponseTokensRange.lowerBound),
                step: 50
            )
        }
        .disabled(!FoundationModelAvailability.check().isAvailable)
        .opacity(!FoundationModelAvailability.check().isAvailable ? 0.5 : 1.0)
    }
}
