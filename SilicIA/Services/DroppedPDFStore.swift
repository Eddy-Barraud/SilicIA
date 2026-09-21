//
//  DroppedPDFStore.swift
//  SilicIA
//
//  Created by Copilot on 18/04/2026.
//

import Foundation

/// Stores dropped PDFs in a stable temporary folder and manages cleanup.
enum DroppedPDFStore {
    private static let store = DroppedFileStore(
        folderName: "SilicIADroppedPDFs",
        defaultExtension: "pdf",
        allowedExtensions: ["pdf"]
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
