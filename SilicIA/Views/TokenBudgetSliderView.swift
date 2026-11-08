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
            // MARK: - Reasoning Level Selector (Concise / Standard / Detailed)
            VStack(alignment: .leading, spacing: 6) {
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

                Picker("", selection: $settings.outputProfileKind) {
                    ForEach(TokenBudgeting.OutputProfileKind.allCases, id: \.self) { kind in
                        let profile = TokenBudgeting.outputProfile(forResponseTokens: kind.implicitResponseTokens)
                        Text(profile.localizedName(for: language)).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Divider()

            // MARK: - Implicit Input (Context) & Output (Response) Summary
            VStack(alignment: .leading, spacing: 6) {
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
            }
        }
        .disabled(!FoundationModelAvailability.check().isAvailable)
        .opacity(!FoundationModelAvailability.check().isAvailable ? 0.5 : 1.0)
    }
}
