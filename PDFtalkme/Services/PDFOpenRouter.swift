//
//  PDFOpenRouter.swift
//  PDFtalkme
//
//  Created by OpenCode on 18/04/2026.
//

import Foundation
import Combine

@MainActor
final class PDFOpenRouter: ObservableObject {
    static let shared = PDFOpenRouter()

    @Published var signal = UUID()

    private var pendingRequests: [PDFOpenRequest] = []

    private init() {}

    func enqueue(_ urls: [URL], openInNewTabs: Bool = true) {
        let filtered = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        guard !filtered.isEmpty else { return }
        pendingRequests.append(PDFOpenRequest(urls: filtered, openInNewTabs: openInNewTabs))
        signal = UUID()
    }

    func drain() -> [PDFOpenRequest] {
        defer { pendingRequests.removeAll() }
        return pendingRequests
    }
}

struct PDFOpenRequest {
    let urls: [URL]
    let openInNewTabs: Bool
}
