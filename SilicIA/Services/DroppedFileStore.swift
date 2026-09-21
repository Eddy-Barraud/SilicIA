//
//  DroppedFileStore.swift
//  SilicIA
//
//  Created by Copilot on 21/09/2026.
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
        let candidate = preferredFileName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")

        let sourceName = sourceURL.lastPathComponent
        let fallback = sourceName.isEmpty ? "dropped.\(defaultExtension)" : sourceName
        let chosen = (candidate?.isEmpty == false ? candidate! : fallback)
        let chosenExt = (chosen as NSString).pathExtension.lowercased()
        if allowedExtensions.contains(chosenExt) {
            return chosen
        }
        return "\(chosen).\(defaultExtension)"
    }
}

