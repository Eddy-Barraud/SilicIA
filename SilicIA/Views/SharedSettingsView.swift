//
//  SharedSettingsView.swift
//  SilicIA
//
//  Unified settings view shared between SearchView and ChatView.
//

import SwiftUI

struct SharedSettingsView: View {
    @Binding var isPresented: Bool
    var mode: ChatViewMode = .full

    @Bindable private var settingsStore = AppSettingsStore.shared

    private var settings: AppSettings {
        get { settingsStore.settings }
        nonmutating set { settingsStore.settings = newValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { isPresented = false }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text(L.t("common.back", language: settings.language))
                            .fontWeight(.medium)
                    }
                }
                .buttonStyle(.glass)
                .accessibilityLabel(L.t("common.back", language: settings.language))

                Spacer()
            }
            .padding()

            ScrollView {
                settingsPanel
                    .padding()
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(L.t("common.settings", language: settings.language))
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }

            Divider()

            // Temperature Slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L.t("chat.settings.temperature", language: settings.language))
                        .font(.subheadline)
                    Spacer()
                    Text(String(format: "%.2f", settings.temperature))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Slider(value: $settingsStore.settings.temperature, in: AppSettings.temperatureRange, step: 0.05)
            }
            .disabled(!FoundationModelAvailability.check().isAvailable)
            .opacity(!FoundationModelAvailability.check().isAvailable ? 0.5 : 1.0)

            // Token Budget (Unified Input/Output Slider)
            TokenBudgetSliderView(
                settings: $settingsStore.settings,
                language: settings.language
            )

            // Context Sources (mutually exclusive: Offline, Wiki, Web)
            if mode != .pdfTalkme {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L.t("chat.settings.searchSources", language: settings.language))
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Picker("", selection: $settingsStore.settings.contextSourceKind) {
                        ForEach(ContextSourceKind.allCases) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    switch settingsStore.settings.contextSourceKind {
                    case .web:
                        HStack {
                            Text(L.t("chat.settings.maxDDG", language: settings.language))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(settings.maxDuckDuckGoResults)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(settings.maxDuckDuckGoResults) },
                                set: { settings.maxDuckDuckGoResults = Int($0) }
                            ),
                            in: Double(AppSettings.maxDuckDuckGoResultsRange.lowerBound)...Double(AppSettings.maxDuckDuckGoResultsRange.upperBound),
                            step: 1
                        )

                    case .wiki:
                        HStack {
                            Text(L.t("chat.settings.wikiSource", language: settings.language))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: $settingsStore.settings.wikipediaSource) {
                                Text(L.t("chat.settings.wikiSource.online", language: settings.language))
                                    .tag(WikipediaSource.online)
                                Text(L.t("chat.settings.wikiSource.wikiFast", language: settings.language))
                                    .tag(WikipediaSource.wikiFast)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(maxWidth: 200)
                        }

                        HStack {
                            Text(L.t("chat.settings.maxWiki", language: settings.language))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(settings.maxWikipediaResults)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(settings.maxWikipediaResults) },
                                set: { settings.maxWikipediaResults = Int($0) }
                            ),
                            in: Double(AppSettings.maxWikipediaResultsRange.lowerBound)...Double(AppSettings.maxWikipediaResultsRange.upperBound),
                            step: 1
                        )

                    case .offline:
                        HStack(spacing: 4) {
                            Image(systemName: "wifi.slash")
                            Text(L.t("chat.settings.offlineMode", language: settings.language))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            // Reader View and Summary Toggle
            if mode != .pdfTalkme {
                VStack(alignment: .leading, spacing: 4) {
                    let isModelAvailable = FoundationModelAvailability.check().isAvailable
                    Toggle(isOn: $settingsStore.settings.isReaderViewAndSummaryEnabled) {
                        Text(L.t("search.settings.readerViewAndSummaryToggle", language: settings.language))
                            .font(.subheadline)
                    }
                    .disabled(!isModelAvailable)
                    .opacity(!isModelAvailable ? 0.5 : 1.0)

                    if !isModelAvailable {
                        Text(FoundationModelAvailability.appleIntelligenceRequiredNotice(language: settings.language))
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
            }

            // Model Language
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L.t("chat.settings.modelLanguage", language: settings.language))
                        .font(.subheadline)
                    Spacer()
                    Text(settings.language.rawValue)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Picker("Language", selection: $settingsStore.settings.language) {
                    ForEach(ModelLanguage.allCases, id: \.self) { lang in
                        Text(lang.rawValue).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding()
        .glassCard(cornerRadius: 16)
    }
}
