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
    /// Filename of the *primary* PDF this conversation is anchored to, if
    /// any. Used as the cheap first-pass query key when reopening a PDF.
    /// Equals `pdfFilenames.first` whenever the conversation was created
    /// with at least one PDF in context.
    var pdfFilename: String?
    /// Security-scoped bookmark to the primary PDF.
    var pdfBookmark: Data?
    /// SHA-256 of the primary PDF's bytes (lazy, set in the background).
    var pdfChecksum: String?
    /// Normalized base filenames of *every* PDF that was in context when
    /// this conversation last sent a message. Order is preserved so the
    /// host (PDFtalkme) can restore the same tab arrangement.
    var pdfFilenames: [String] = []
    /// Security-scoped bookmarks for every PDF in `pdfFilenames`, aligned
    /// by index. Storing a parallel array (rather than a `[Codable]` of
    /// pairs) keeps the migration trivial — SwiftData treats both
    /// `[String]` and `[Data]` as primitive arrays.
    var pdfBookmarks: [Data] = []

    init(
        id: UUID = UUID(),
        messages: [Message] = [],
        title: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        contextSources: String = "{}",
        pdfFilename: String? = nil,
        pdfBookmark: Data? = nil,
        pdfChecksum: String? = nil,
        pdfFilenames: [String] = [],
        pdfBookmarks: [Data] = []
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
        self.pdfFilenames = pdfFilenames
        self.pdfBookmarks = pdfBookmarks
    }
}
