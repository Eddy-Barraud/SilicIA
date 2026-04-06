//
//  Message.swift
//  SilicIA
//
//  Created by Eddy Barraud on 06/04/2026.
//

import SwiftData
import Foundation

/// Represents a single message in a conversation, persisted via SwiftData.
@Model
final class Message {
    /// Unique identifier for the message.
    var id: UUID
    /// Role of the message sender: "user" or "assistant".
    var role: String
    /// The text content of the message.
    var content: String
    /// Optional citations for assistant responses.
    var citations: String?
    /// Timestamp when the message was created.
    var timestamp: Date

    init(id: UUID = UUID(), role: String, content: String, citations: String? = nil, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.citations = citations
        self.timestamp = timestamp
    }
}
