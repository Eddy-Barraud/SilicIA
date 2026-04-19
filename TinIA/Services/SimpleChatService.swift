import Foundation
import FoundationModels
import Combine

@MainActor
final class SimpleChatService: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isResponding = false
    @Published var errorMessage: String?

    func resetConversation() {
        messages = []
        errorMessage = nil
        isResponding = false
    }

    func sendMessage(
        _ message: String,
        settings: AppSettings
    ) async {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }

        messages.append(ChatMessage(role: .user, content: trimmedMessage))
        errorMessage = nil

        isResponding = true
        defer { isResponding = false }

        let effectiveMaxOutputTokens = TokenBudgeting.clampedOutputTokens(
            requestedMaxTokens: settings.maxResponseTokens,
            instructionTokens: TokenBudgeting.instructionTokens,
            promptOverheadTokens: TokenBudgeting.promptOverheadTokens,
            minContextTokens: TokenBudgeting.minContextTokens
        )

        let effectiveMaxContextTokens = TokenBudgeting.clampedContextTokens(
            requestedContextTokens: settings.maxContextTokens,
            maxOutputTokens: effectiveMaxOutputTokens,
            settingsRange: AppSettings.maxContextTokensRange,
            instructionTokens: TokenBudgeting.instructionTokens,
            promptOverheadTokens: TokenBudgeting.promptOverheadTokens,
            minContextTokens: TokenBudgeting.minContextTokens
        )

        let maxPromptContextCharacters = TokenBudgeting.maxContextCharacters(
            maxOutputTokens: effectiveMaxOutputTokens,
            contextUtilizationFactor: 1.0
        )
        let maxContextCharacters = min(
            TokenBudgeting.estimatedContextCharacters(forTokens: effectiveMaxContextTokens),
            maxPromptContextCharacters
        )

        let historyMessages: [ChatMessage]
        if let last = messages.last, last.role == .user, last.content == trimmedMessage {
            historyMessages = Array(messages.dropLast())
        } else {
            historyMessages = messages
        }

        var history = historyMessages
            .suffix(6)
            .map { item in
                item.role == .assistant ? "Assistant: \(item.content)" : "User: \(item.content)"
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if history.count > maxContextCharacters {
            history = String(history.suffix(maxContextCharacters))
        }

        let contextWordEstimate = TokenBudgeting.estimatedContextWords(forTokens: effectiveMaxContextTokens)
        history = TokenBudgeting.truncateToApproxWordCount(history, maxWords: contextWordEstimate)

        do {
            let instructions = buildInstructions(for: settings.language)
            let session = LanguageModelSession(instructions: instructions)
            let maxOutputCharacters = TokenBudgeting.estimatedOutputCharacters(forTokens: effectiveMaxOutputTokens)
            let prompt = buildPrompt(
                history: history,
                question: trimmedMessage,
                language: settings.language,
                maxOutputCharacters: maxOutputCharacters,
                maxOutputTokens: effectiveMaxOutputTokens
            )
            let options = GenerationOptions(
                temperature: settings.temperature,
                maximumResponseTokens: effectiveMaxOutputTokens
            )
            let response = try await session.respond(to: prompt, options: options)
            let content = normalizeModelOutput(String(describing: response.content))
            messages.append(ChatMessage(role: .assistant, content: content))
        } catch {
            let fallback = "I couldn't generate a response with the foundation model right now. Please try again."
            messages.append(ChatMessage(role: .assistant, content: fallback))
            errorMessage = error.localizedDescription
        }
    }

    private func buildInstructions(for language: ModelLanguage) -> String {
        PromptLoader.loadPrompt(mode: "normal", feature: "chat", variant: "instructions", language: language)
            ?? fallbackInstructions(for: language)
    }

    private func buildPrompt(
        history: String,
        question: String,
        language: ModelLanguage,
        maxOutputCharacters: Int,
        maxOutputTokens: Int
    ) -> String {
        PromptLoader.loadPrompt(
            mode: "normal",
            feature: "chat",
            language: language,
            replacements: [
                "history": history,
                "context": "",
                "question": question,
                "maxOutputCharacters": "\(maxOutputCharacters)",
                "maxOutputTokens": "\(maxOutputTokens)"
            ]
        ) ?? fallbackPrompt(
            history: history,
            question: question,
            language: language,
            maxOutputCharacters: maxOutputCharacters,
            maxOutputTokens: maxOutputTokens
        )
    }

    private func fallbackInstructions(for language: ModelLanguage) -> String {
        if language == .french {
            return """
            Vous etes un assistant utile.
            Repondez clairement et avec concision.
            Repondez dans la meme langue que la question.
            """
        }

        return """
        You are a helpful assistant.
        Respond clearly and concisely.
        Respond in the same language as the question.
        """
    }

    private func fallbackPrompt(
        history: String,
        question: String,
        language: ModelLanguage,
        maxOutputCharacters: Int,
        maxOutputTokens: Int
    ) -> String {
        if language == .french {
            return """
            Conversation :
            \(history)

            Question :
            \(question)

            Reponds de facon concise.
            Limite de sortie : \(maxOutputTokens) tokens maximum (environ \(maxOutputCharacters) caracteres).
            """
        }

        return """
        Conversation:
        \(history)

        User question:
        \(question)

        Answer concisely.
        Output limit: \(maxOutputTokens) tokens maximum (about \(maxOutputCharacters) characters).
        """
    }

    private func normalizeModelOutput(_ raw: String) -> String {
        var normalized = raw
        normalized = normalized.replacingOccurrences(of: "\\\\", with: "\\")
        normalized = normalized.replacingOccurrences(of: "\\n", with: "\n")
        normalized = normalized.replacingOccurrences(of: "\\t", with: "\t")
        normalized = normalized.replacingOccurrences(of: "\\r", with: "\r")
        normalized = normalized.replacingOccurrences(of: "\\$", with: "$")
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let content: String
}
