//
//  TokenBudgetSliderView.swift
//  SilicIA
//
//  A unified control for configuring the total token budget (global speed vs precision)
//  and splitting tokens between context (input) and response (output),
//  with live output profile indicators (Concise, Standard, Detailed).
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

    private var outputProfile: TokenBudgeting.OutputProfile {
        TokenBudgeting.outputProfile(forResponseTokens: settings.maxResponseTokens)
    }

    private var profileBadgeColor: Color {
        switch outputProfile.kind {
        case .concise:
            return .teal
        case .standard:
            return .blue
        case .detailed:
            return .purple
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - Slider 1: Total Token Budget (Global Speed vs Precision)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L.t("settings.tokenBudget.totalTitle", language: language))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(settings.totalTokensBudget) tokens")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }

                Text(L.t("settings.tokenBudget.speedNotice", language: language))
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Slider(
                    value: Binding(
                        get: { Double(settings.totalTokensBudget) },
                        set: { settings.setTotalTokensBudget(Int($0)) }
                    ),
                    in: Double(AppSettings.totalTokensBudgetRange.lowerBound)...Double(AppSettings.totalTokensBudgetRange.upperBound),
                    step: 100
                )
            }

            Divider()

            // MARK: - Slider 2: Split (Context vs Response) with Dynamic Profile Badge
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L.t("settings.tokenBudget.splitTitle", language: language))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    Spacer()
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
                        HStack(spacing: 4) {
                            Text(outputProfile.localizedName(for: language))
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(profileBadgeColor.opacity(0.18))
                                .foregroundColor(profileBadgeColor)
                                .clipShape(Capsule())

                            Text(L.t("settings.tokenBudget.response", language: language))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

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
                            settings.maxResponseTokens = max(
                                AppSettings.maxResponseTokensRange.lowerBound,
                                settings.totalTokensBudget - context
                            )
                        }
                    ),
                    in: Double(AppSettings.maxContextTokensRange.lowerBound)...Double(max(AppSettings.maxContextTokensRange.lowerBound, settings.totalTokensBudget - AppSettings.maxResponseTokensRange.lowerBound)),
                    step: 50
                )
            }
        }
        .disabled(!FoundationModelAvailability.check().isAvailable)
        .opacity(!FoundationModelAvailability.check().isAvailable ? 0.5 : 1.0)
    }
}
