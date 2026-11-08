//
//  DroppedTextFileStore.swift
//  SilicIA
//
//  Created by Antigravity on 08/11/2026.
//

import Foundation

/// Stores dropped text and Markdown files (.md, .txt) in a stable temporary folder and manages cleanup.
enum DroppedTextFileStore {
    private static let store = DroppedFileStore(
        folderName: "SilicIADroppedTextFiles",
        defaultExtension: "txt",
        allowedExtensions: ["txt", "md", "markdown", "text"]
    )

    static var storageDirectory: URL {
        store.storageDirectory
    }

    static func persist(_ sourceURL: URL, preferredFileName: String? = nil) -> URL? {
        store.persist(sourceURL, preferredFileName: preferredFileName)
    }

    @discardableResult
    static func clearAll() -> Bool {
        store.clearAll()
    }
}
