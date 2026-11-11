//
//  DroppedFileStore.swift
//  SilicIA
//
//

import Foundation

/// Unified file store for persisted attachments (PDFs, images) in the app's temporary folder.
/// Handles sandbox security scoping, directory lifecycle, collision-safe naming, and cleanup.
struct DroppedFileStore: Sendable {
    let folderName: String
    let defaultExtension: String
    let allowedExtensions: Set<String>

    var storageDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(folderName, isDirectory: true)
    }

    func persist(_ sourceURL: URL, preferredFileName: String? = nil) -> URL? {
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
            let normalizedStorageDirectory = storageDirectory.standardizedFileURL.resolvingSymlinksInPath()
            let normalizedSourceDirectory = sourceURL
                .standardizedFileURL
                .resolvingSymlinksInPath()
                .deletingLastPathComponent()
            if normalizedSourceDirectory == normalizedStorageDirectory {
                return sourceURL.standardizedFileURL
            }
            let destinationURL = uniqueDestinationURL(preferredFileName: preferredFileName, sourceURL: sourceURL)
            let normalizedDestination = destinationURL.standardizedFileURL.resolvingSymlinksInPath()
            // Ensure the destination strictly resides directly within the designated storage directory (prevent path traversal).
            guard normalizedDestination.deletingLastPathComponent().path == normalizedStorageDirectory.path else {
                return nil
            }
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            #if DEBUG
            print("[\(folderName)] Failed to persist file from \(sourceURL.path): \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    @discardableResult
    func clearAll() -> Bool {
        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: storageDirectory.path) {
                try fileManager.removeItem(at: storageDirectory)
            }
            return true
        } catch {
            #if DEBUG
            print("[\(folderName)] Failed to clear temporary files: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    private func uniqueDestinationURL(preferredFileName: String?, sourceURL: URL) -> URL {
        let fileManager = FileManager.default
        let rawName = normalizedRawName(preferredFileName: preferredFileName, sourceURL: sourceURL)
        let base = (rawName as NSString).deletingPathExtension
        let rawExt = (rawName as NSString).pathExtension.lowercased()
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

    private func normalizedRawName(preferredFileName: String?, sourceURL: URL) -> String {
        let candidate = preferredFileName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceName = sourceURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = sourceName.isEmpty ? "dropped.\(defaultExtension)" : sourceName
        var raw = (candidate?.isEmpty == false ? candidate! : fallback)

        // Strip directory traversal components, path separators, and colons
        raw = (raw as NSString).lastPathComponent
        raw = raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        while raw.contains("..") {
            raw = raw.replacingOccurrences(of: "..", with: "")
        }

        if raw.isEmpty || raw == "." {
            raw = "dropped.\(defaultExtension)"
        }

        let chosenExt = (raw as NSString).pathExtension.lowercased()
        if allowedExtensions.contains(chosenExt) {
            return raw
        }
        return "\(raw).\(defaultExtension)"
    }
}

