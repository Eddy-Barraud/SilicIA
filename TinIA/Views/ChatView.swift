import SwiftUI

struct ChatView: View {
    @StateObject private var chatService = SimpleChatService()
    @State private var settings = AppSettings.load()
    @State private var showSettings = false
    @State private var messageInput = ""
    @State private var showPromotionPopup = false

    private var estimatedMaxOutputCharacters: Int {
        TokenBudgeting.estimatedOutputCharacters(forTokens: settings.maxResponseTokens)
    }

    private var estimatedMaxOutputSentences: Int {
        TokenBudgeting.estimatedOutputSentences(forTokens: settings.maxResponseTokens)
    }

    private var maxAllowedContextTokensForCurrentResponse: Int {
        AppSettings.maxAllowedContextTokens(forResponseTokens: settings.maxResponseTokens)
    }

    private var effectiveContextTokens: Int {
        min(settings.maxContextTokens, maxAllowedContextTokensForCurrentResponse)
    }

    private var estimatedMaxContextWords: Int {
        TokenBudgeting.estimatedContextWords(forTokens: effectiveContextTokens)
    }

    var body: some View {
        VStack(spacing: 12) {
            headerView

            if showSettings {
                settingsPanel
            }

            messagesView

            if let errorMessage = chatService.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            composerView

            Text("Download SilicIA for web search")
                .font(.footnote)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding()
        .onChange(of: settings) {
            settings.save()
        }
        .alert("Download SilicIA for history and more", isPresented: $showPromotionPopup) {
            Button("OK", role: .cancel) {}
        }
    }

    private var headerView: some View {
        HStack {
            Button {
                startOver()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.2.circlepath")
                    Text(settings.language == .french ? "Nouveau" : "Start Over")
                }
            }
            .buttonStyle(.bordered)

            Spacer()

            Button {
                showPromotionPopup = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                    Text(settings.language == .french ? "Historique" : "History")
                }
            }
            .buttonStyle(.bordered)

            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: "gear")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(settings.language == .french ? "Parametres de chat" : "Chat Settings")
                .font(.headline)

            Picker(settings.language == .french ? "Langue" : "Language", selection: $settings.language) {
                ForEach(ModelLanguage.allCases, id: \.self) { language in
                    Text(language.rawValue).tag(language)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(settings.language == .french ? "Temperature" : "Temperature")
                    Spacer()
                    Text(String(format: "%.2f", settings.temperature))
                        .foregroundColor(.secondary)
                }
                Slider(value: $settings.temperature, in: AppSettings.temperatureRange, step: 0.05)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(settings.language == .french ? "Tokens de reponse max" : "Max Response Tokens")
                    Spacer()
                    Text("\(settings.maxResponseTokens)")
                        .foregroundColor(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(settings.maxResponseTokens) },
                        set: {
                            settings.maxResponseTokens = Int($0)
                            settings.maxContextTokens = min(
                                settings.maxContextTokens,
                                AppSettings.maxAllowedContextTokens(forResponseTokens: settings.maxResponseTokens)
                            )
                        }
                    ),
                    in: Double(AppSettings.maxResponseTokensRange.lowerBound)...Double(AppSettings.maxResponseTokensRange.upperBound),
                    step: 100
                )

                Text(
                    settings.language == .french
                    ? "Sortie estimee : ~\(estimatedMaxOutputCharacters) caracteres (~\(estimatedMaxOutputSentences) phrases)"
                    : "Estimated output: ~\(estimatedMaxOutputCharacters) characters (~\(estimatedMaxOutputSentences) sentences)"
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(settings.language == .french ? "Tokens de contexte max" : "Max Context Tokens")
                    Spacer()
                    Text("\(effectiveContextTokens)")
                        .foregroundColor(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(effectiveContextTokens) },
                        set: { settings.maxContextTokens = Int($0) }
                    ),
                    in: Double(AppSettings.maxContextTokensRange.lowerBound)...Double(maxAllowedContextTokensForCurrentResponse),
                    step: 50
                )

                Text(
                    settings.language == .french
                    ? "Contexte estime : ~\(estimatedMaxContextWords) mots"
                    : "Estimated context: ~\(estimatedMaxContextWords) words"
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var messagesView: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if chatService.messages.isEmpty {
                    Text(settings.language == .french ? "Discutez avec le modele foundation." : "Chat with the foundation model.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(chatService.messages) { message in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(message.role == .user ? (settings.language == .french ? "Vous" : "You") : "Assistant")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(message.content)
                            .textSelection(.enabled)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: message.role == .assistant ? .leading : .trailing)
                    .background(
                        message.role == .user
                        ? Color.accentColor.opacity(0.15)
                        : Color(nsColor: .controlBackgroundColor)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if chatService.isResponding {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Thinking...")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var composerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    showPromotionPopup = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .foregroundColor(.secondary)
                        Text(settings.language == .french ? "Barre URL (SilicIA)" : "URL bar (SilicIA)")
                            .foregroundColor(.secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    showPromotionPopup = true
                } label: {
                    Label("Web", systemImage: "globe")
                }
                .buttonStyle(.bordered)

                Button {
                    showPromotionPopup = true
                } label: {
                    Label("PDF", systemImage: "doc.richtext")
                }
                .buttonStyle(.bordered)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Type a message", text: $messageInput, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        submitMessage()
                    }

                Button("Send") {
                    submitMessage()
                }
                .buttonStyle(.borderedProminent)
                .disabled(messageInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chatService.isResponding)
            }
        }
    }

    private func submitMessage() {
        let trimmed = messageInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let message = trimmed
        messageInput = ""

        Task {
            await chatService.sendMessage(message, settings: settings)
        }
    }

    private func startOver() {
        messageInput = ""
        chatService.resetConversation()
    }
}

#Preview {
    ChatView()
        .frame(width: 980, height: 720)
}
