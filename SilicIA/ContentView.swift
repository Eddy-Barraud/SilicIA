//
//  ContentView.swift
//  Privducai
//
//  Created by Eddy Barraud on 23/03/2026.
//

import SwiftUI
import SwiftData

/// Root container that switches between Search Assist and Chat experiences.
struct ContentView: View {
    /// Available tabs shown in the segmented control.
    private enum AppTab: String, CaseIterable, Identifiable {
        case searchAssist = "Search Assist"
        case chat = "Chat"

        var id: String { rawValue }

        func displayName(language: ModelLanguage) -> String {
            switch self {
            case .searchAssist: return L.t("contentView.tab.searchAssist", language: language)
            case .chat: return L.t("contentView.tab.chat", language: language)
            }
        }
    }

    @AppStorage("contentView.selectedTab") private var selectedTabRawValue: String = AppTab.searchAssist.rawValue
    @Environment(\.modelContext) private var modelContext
    @Binding var sharedURLs: [String]
    @Binding var sharedPDFs: [URL]
    @Binding var sharedImages: [URL]
    @Binding var pendingSearchQuery: String?
    @StateObject private var chatService = ChatService()
    /// Observe the persisted settings blob so the top tab bar re-localises
    /// live: language is changed in a settings sub-page that lives *inside*
    /// this view, so ContentView never re-inits — without observing the
    /// UserDefaults key, the tab labels stay frozen in the launch language.
    /// The value isn't read directly; its change drives a re-render, and the
    /// `language` computed below re-reads the fresh setting.
    @AppStorage(AppSettings.storageKey) private var appSettingsBlob: Data?

    /// Current output language, re-read on every render so it tracks changes
    /// made elsewhere in the app.
    private var language: ModelLanguage { AppSettings.load().language }

    private var selectedTab: AppTab {
        get { AppTab(rawValue: selectedTabRawValue) ?? .searchAssist }
        nonmutating set { selectedTabRawValue = newValue.rawValue }
    }

    private var selectedTabBinding: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { selectedTab = $0 }
        )
    }

    /// Renders the tab picker and currently selected application screen.
    var body: some View {
        VStack(spacing: 0) {
            // Finder-style toolbar: a full-width bar with an ultra-thin
            // material background (same visual layer as macOS window chrome)
            // anchored to the top edge. The Divider below it plays the role
            // of Finder's pane separator — it makes the toolbar read as a
            // distinct layer sitting above the content, not a floating island
            // inside it. The segmented picker sits centred inside the bar,
            // width-capped so it doesn't stretch edge-to-edge on large
            // windows (Finder's toolbar icons are also centred, not
            // full-width).
            HStack {
                Picker("Application", selection: selectedTabBinding) {
                    Text(AppTab.searchAssist.displayName(language: language)).tag(AppTab.searchAssist)
                    Text(AppTab.chat.displayName(language: language)).tag(AppTab.chat)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)

            Divider()

            Group {
                switch selectedTab {
                case .searchAssist:
                    SearchView(
                        initialQuery: pendingSearchQuery,
                        onInitialQueryHandled: {
                            pendingSearchQuery = nil
                        },
                        chatService: chatService,
                        onOfflineQuery: { query in
                            selectedTab = .chat
                            chatService.modelContext = modelContext
                            Task {
                                let settings = AppSettings.load()
                                await chatService.sendMessage(
                                    query,
                                    contextInput: "",
                                    pdfURLs: [],
                                    imageURLs: [],
                                    includeWebSearch: false,
                                    maxDuckDuckGoResults: settings.maxDuckDuckGoResults,
                                    maxWikipediaResults: settings.maxWikipediaResults,
                                    language: settings.language,
                                    temperature: settings.temperature,
                                    maxResponseTokens: settings.maxResponseTokens,
                                    maxContextTokens: settings.maxContextTokens,
                                    useDuckDuckGo: settings.useDuckDuckGo,
                                    useWikipedia: settings.useWikipedia
                                )
                            }
                        },
                        onChatMore: { query, answer, citations in
                            chatService.modelContext = modelContext
                            chatService.startConversationFromSearch(
                                query: query,
                                answer: answer,
                                citations: citations
                            )
                            selectedTab = .chat
                        },
                        onAttachmentsDropped: { pdfs, images in
                            if !pdfs.isEmpty { sharedPDFs.append(contentsOf: pdfs) }
                            if !images.isEmpty { sharedImages.append(contentsOf: images) }
                            if !pdfs.isEmpty || !images.isEmpty {
                                selectedTab = .chat
                            }
                        }
                    )
                case .chat:
                    ChatView(
                        sharedURLs: $sharedURLs,
                        sharedPDFs: $sharedPDFs,
                        sharedImages: $sharedImages,
                        chatService: chatService
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: sharedURLs) {
            if !sharedURLs.isEmpty {
                selectedTab = .chat
            }
        }
        .onChange(of: sharedPDFs) {
            if !sharedPDFs.isEmpty {
                selectedTab = .chat
            }
        }
        .onChange(of: sharedImages) {
            if !sharedImages.isEmpty {
                selectedTab = .chat
            }
        }
        .onChange(of: pendingSearchQuery) {
            if pendingSearchQuery != nil {
                selectedTab = .searchAssist
            }
        }
    }
}

#Preview {
    ContentView(
        sharedURLs: .constant([]),
        sharedPDFs: .constant([]),
        sharedImages: .constant([]),
        pendingSearchQuery: .constant(nil)
    )
        .frame(width: 900, height: 700)
}
