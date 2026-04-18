//
//  PDFCitation.swift
//  PDFtalkme
//
//  Created by OpenCode on 18/04/2026.
//

import Foundation

struct PDFCitation: Identifiable, Codable, Equatable {
    let id: String
    let rank: Int
    let source: String
    let page: Int?
    let snippet: String?
    let isPriority: Bool

    init(
        id: String = UUID().uuidString,
        rank: Int,
        source: String,
        page: Int?,
        snippet: String?,
        isPriority: Bool
    ) {
        self.id = id
        self.rank = rank
        self.source = source
        self.page = page
        self.snippet = snippet
        self.isPriority = isPriority
    }
}

struct PDFCitationFocusRequest: Equatable {
    let citation: PDFCitation
    let requestID: UUID

    init(citation: PDFCitation, requestID: UUID = UUID()) {
        self.citation = citation
        self.requestID = requestID
    }
}
