//
//  ConversationsListView.swift
//  SilicIA
//
//  Created by Eddy Barraud on 06/04/2026.
//

import SwiftUI
import SwiftData

/// Displays a list of saved conversations with options to load or delete.
/// Inspired by FoundationChat (https://github.com/Dimillian/FoundationChat)
struct ConversationsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @State private var showClearAllConfirmation = false
    @State private var language = AppSettings.load().language

    var onLoadConversation: (Conversation) -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onDismiss) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text(L.t("common.back", language: language))
                            .fontWeight(.medium)
                    }
                }
                .buttonStyle(.bordered)
                .help(L.t("conversations.backHelp", language: language))

                Text(L.t("conversations.title", language: language))
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()

                if !conversations.isEmpty {
                    Button(action: { showClearAllConfirmation = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                            Text(L.t("conversations.clearAll", language: language))
                                .fontWeight(.medium)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
            .padding()
#if os(iOS)
            .background(Color(.secondarySystemBackground))
#elseif os(macOS)
            .background(Color(nsColor: .controlBackgroundColor))
#else
            .background(Color.gray.opacity(0.1))
#endif

            if conversations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(L.t("conversations.empty.title", language: language))
                        .font(.body)
                        .foregroundColor(.secondary)
                    Text(L.t("conversations.empty.subtitle", language: language))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
#if os(iOS)
                .background(Color(.systemBackground))
#elseif os(macOS)
                .background(Color(nsColor: .textBackgroundColor))
#else
                .background(Color.clear)
#endif
            } else {
                List(conversations) { conversation in
                    conversationRow(conversation)
                }
                .listStyle(.plain)
            }
        }
        .alert(L.t("conversations.deleteAll.confirmTitle", language: language), isPresented: $showClearAllConfirmation) {
            Button(L.t("conversations.clearAll", language: language), role: .destructive) {
                for conversation in conversations {
                    modelContext.delete(conversation)
                }
                _ = saveContext()
                _ = DroppedPDFStore.clearAll()
            }
            Button(L.t("common.cancel", language: language), role: .cancel) {}
        } message: {
            Text(L.t("conversations.deleteAll.confirmMessage", language: language))
        }
    }

    @ViewBuilder
    private func conversationRow(_ conversation: Conversation) -> some View {
        HStack(spacing: 0) {
            Button(action: {
                onLoadConversation(conversation)
            }) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(conversation.title ?? L.t("conversations.untitled", language: language))
                            .font(.body)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .foregroundColor(.primary)
                        Spacer()
                        Text(formatTimestamp(conversation.updatedAt))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let lastMessage = conversation.messages.last {
                        Text(lastMessage.content)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "message.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(L.t("conversations.messageCount", language: language, Int64(conversation.messages.count)))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            Button(action: {
                modelContext.delete(conversation)
                _ = saveContext()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                }
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .help(L.t("conversations.deleteHelp", language: language))
            .padding(.leading, 8)
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day, .hour, .minute], from: date, to: now)

        if let day = components.day, day >= 1 {
            return L.t("conversations.timestamp.daysAgo", language: language, Int64(day))
        } else if let hour = components.hour, hour >= 1 {
            return L.t("conversations.timestamp.hoursAgo", language: language, Int64(hour))
        } else if let minute = components.minute, minute >= 1 {
            return L.t("conversations.timestamp.minutesAgo", language: language, Int64(minute))
        } else {
            return L.t("conversations.timestamp.justNow", language: language)
        }
    }

    /// Saves the SwiftData context and logs non-fatal failures in debug builds.
    @discardableResult
    private func saveContext() -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            #if DEBUG
            print("[ConversationsListView] Failed to save model context: \(error.localizedDescription)")
            #endif
            return false
        }
    }
}

#Preview {
    ConversationsListView(onLoadConversation: { _ in }, onDismiss: {})
        .modelContainer(for: [Conversation.self, Message.self], inMemory: true)
}
