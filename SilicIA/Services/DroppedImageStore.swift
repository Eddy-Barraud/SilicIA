//
//  DroppedImageStore.swift
//  SilicIA
//
//  Created by Eddy Barraud on 06/05/2026.
//

import Foundation

/// Stores dropped/shared images in a stable temporary folder and manages cleanup.
enum DroppedImageStore {
    private static let store = DroppedFileStore(
        folderName: "SilicIADroppedImages",
        defaultExtension: "jpg",
        allowedExtensions: [
            "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "bmp"
        ]
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
