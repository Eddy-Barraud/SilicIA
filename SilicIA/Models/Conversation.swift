//
//  Conversation.swift
//  SilicIA
//
//  Created by Eddy Barraud on 06/04/2026.
//

import SwiftData
import Foundation

/// Represents a persistent chat conversation with associated messages.
/// Inspired by FoundationChat (https://github.com/Dimillian/FoundationChat)
@Model
final class Conversation {
    /// Unique identifier for the conversation.
    var id: UUID
    /// Ordered list of messages in the conversation, with cascade delete rule.
    @Relationship(deleteRule: .cascade)
    var messages: [Message]
    /// Optional auto-generated title derived from the first user message.
    var title: String?
    /// Timestamp when the conversation was created.
    var createdAt: Date
    /// Timestamp of the last message (used for sorting).
    var updatedAt: Date
    /// JSON string storing context sources used in the conversation.
    var contextSources: String
    /// Filename of the primary PDF this conversation is anchored to, if any.
    /// Used as the cheap first-pass key when reopening a PDF.
    var pdfFilename: String?
    /// Security-scoped bookmark to the primary PDF — lets us reopen the file
    /// after the user moves it or relaunches the app under the sandbox.
    var pdfBookmark: Data?
    /// SHA-256 of the primary PDF's bytes. Computed lazily in the background
    /// and used as a fallback identifier when filename + bookmark fail.
    var pdfChecksum: String?

    init(
        id: UUID = UUID(),
        messages: [Message] = [],
        title: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        contextSources: String = "{}",
        pdfFilename: String? = nil,
        pdfBookmark: Data? = nil,
        pdfChecksum: String? = nil
    ) {
        self.id = id
        self.messages = messages
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.contextSources = contextSources
        self.pdfFilename = pdfFilename
        self.pdfBookmark = pdfBookmark
        self.pdfChecksum = pdfChecksum
    }
}
