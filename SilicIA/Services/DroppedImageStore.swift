//
//  DroppedImageStore.swift
//  SilicIA
//
//  Created by Eddy Barraud on 06/05/2026.
//

import Foundation

/// Stores dropped/shared images in a stable temporary folder and manages cleanup.
/// Mirrors `DroppedPDFStore` to keep the lifecycle of dropped attachments uniform.
enum DroppedImageStore {
    private static let folderName = "SilicIADroppedImages"
    private static let defaultExtension = "jpg"
    private static let allowedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "bmp"
    ]

    static var storageDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(folderName, isDirectory: true)
    }

    static func persist(_ sourceURL: URL, preferredFileName: String? = nil) -> URL? {
        let fileManager = FileManager.default

        // File-picker / drag-drop URLs are security-scoped on the sandboxed
        // macOS app: we must request access before any read or copy, otherwise
        // FileManager fails with EPERM and downstream Vision/PDFKit reads
        // surface a confusing "Operation not permitted".
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
            let destinationURL = uniqueDestinationURL(preferredFileName: preferredFileName, sourceURL: sourceURL)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            #if DEBUG
            print("[DroppedImageStore] Failed to persist image from \(sourceURL.path): \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    @discardableResult
    static func clearAll() -> Bool {
        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: storageDirectory.path) {
                try fileManager.removeItem(at: storageDirectory)
            }
            return true
        } catch {
            #if DEBUG
            print("[DroppedImageStore] Failed to clear temporary images: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    private static func uniqueDestinationURL(preferredFileName: String?, sourceURL: URL) -> URL {
        let fileManager = FileManager.default
        let rawName = normalizedRawName(preferredFileName: preferredFileName, sourceURL: sourceURL)
        let base = rawName.deletingPathExtension
        let rawExt = rawName.pathExtension.lowercased()
        let ext = allowedExtensions.contains(rawExt) ? rawExt : defaultExtension

        var index = 0
        while true {
            let suffix = index == 0 ? "" : " (\(index + 1))"
            let candidateName = "\(base)\(suffix).\(ext)"
            let candidateURL = storageDirectory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            index += 1
        }
    }

    private static func normalizedRawName(preferredFileName: String?, sourceURL: URL) -> String {
        let candidate = preferredFileName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")

        let sourceName = sourceURL.lastPathComponent
        let fallback = sourceName.isEmpty ? "dropped.\(defaultExtension)" : sourceName
        let chosen = (candidate?.isEmpty == false ? candidate! : fallback)
        let chosenExt = chosen.pathExtension.lowercased()
        if allowedExtensions.contains(chosenExt) {
            return chosen
        }
        return "\(chosen).\(defaultExtension)"
    }
}

private extension String {
    var deletingPathExtension: String {
        (self as NSString).deletingPathExtension
    }

    var pathExtension: String {
        (self as NSString).pathExtension
    }
}
