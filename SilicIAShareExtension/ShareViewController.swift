//
//  ShareViewController.swift
//  SilicIAShareExtension
//
//  Created by Copilot on 18/04/2026.
//

import Foundation
import UniformTypeIdentifiers
import os
#if os(macOS)
import AppKit
typealias PlatformShareViewController = NSViewController
#else
import UIKit
typealias PlatformShareViewController = UIViewController
#endif

/// Unified-log channel that the share extension writes diagnostic events
/// into. Inspect with Console.app on a connected Mac: filter the device
/// for subsystem `fr.trevalim.silicia.shareextension`.
private let osLog = Logger(
    subsystem: "fr.trevalim.silicia.shareextension",
    category: "ShareViewController"
)

/// Tee logger that writes to both the unified log AND a plain-text file
/// inside the app-group container so users without Console.app access
/// can still inspect what happened. File path:
/// macOS: `~/Library/Group Containers/group.fr.trevalim.silicia.shared/share-debug.log`
/// iOS: surfaced inside the main app's app-group dir; open via Files-app
/// if the container is exposed.
private enum ShareLog {
    private static let fileName = "share-debug.log"
    private static let appGroupID = "group.fr.trevalim.silicia.shared"
    private static let maxLogBytes = 64 * 1024
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static var logFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName, isDirectory: false)
    }

    static func info(_ message: String) {
        osLog.info("\(message, privacy: .public)")
        appendLine(prefix: "INFO ", message)
    }

    static func error(_ message: String) {
        osLog.error("\(message, privacy: .public)")
        appendLine(prefix: "ERROR", message)
    }

    private static func appendLine(prefix: String, _ message: String) {
        guard let url = logFileURL else { return }
        let line = "\(isoFormatter.string(from: Date())) \(prefix) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        rotateIfNeeded(at: url)
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    private static func rotateIfNeeded(at url: URL) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        if size > maxLogBytes {
            // Truncate to the last half of the file, prefixed with a rotation marker.
            if let handle = try? FileHandle(forReadingFrom: url) {
                handle.seek(toFileOffset: UInt64(size / 2))
                let tail = handle.readDataToEndOfFile()
                try? handle.close()
                var rotated = "--- log rotated \(isoFormatter.string(from: Date())) ---\n".data(using: .utf8) ?? Data()
                rotated.append(tail)
                try? rotated.write(to: url)
            }
        }
    }
}

/// Adapter that forwards calls from existing code to `ShareLog`.
private struct ShareLogForwarder {
    func info(_ msg: String) { ShareLog.info(msg) }
    func error(_ msg: String) { ShareLog.error(msg) }
}
private let shareLog = ShareLogForwarder()

final class ShareViewController: PlatformShareViewController {
    private static let appGroupIdentifier = "group.fr.trevalim.silicia.shared"
    private static let inboxDirectoryName = "IncomingSharedFiles"
    private static let imageFileExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "bmp"
    ]
    private static let defaultImageExtension = "jpg"
    private var didProcessInput = false

#if os(macOS)
    override func viewDidAppear() {
        super.viewDidAppear()
        launchShareProcessingIfNeeded()
    }
#else
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        launchShareProcessingIfNeeded()
    }
#endif

    private func launchShareProcessingIfNeeded() {
        guard !didProcessInput else { return }
        didProcessInput = true

        Task {
            await processSharedItems()
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func processSharedItems() async {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem],
              !extensionItems.isEmpty else {
            shareLog.error("processSharedItems: no input items")
            return
        }
        shareLog.info("processSharedItems started with \(extensionItems.count) item(s)")

        var sharedWebURLs: [String] = []
        var sharedPDFFileNames: [String] = []
        var sharedImageFileNames: [String] = []

        for (itemIndex, item) in extensionItems.enumerated() {
            let providers = item.attachments ?? []
            shareLog.info("item[\(itemIndex)] has \(providers.count) attachment(s)")
            for (providerIndex, provider) in providers.enumerated() {
                let types = provider.registeredTypeIdentifiers.joined(separator: ", ")
                shareLog.info("  provider[\(providerIndex)] types=[\(types)]")

                if let sharedURL = await loadSharedWebURL(from: provider) {
                    shareLog.info("  provider[\(providerIndex)] → web URL")
                    sharedWebURLs.append(sharedURL.absoluteString)
                }

                if let storedPDFName = await persistSharedPDF(from: provider) {
                    shareLog.info("  provider[\(providerIndex)] → PDF: \(storedPDFName)")
                    sharedPDFFileNames.append(storedPDFName)
                    continue
                }

                if let storedImageName = await persistSharedImage(from: provider) {
                    shareLog.info("  provider[\(providerIndex)] → image: \(storedImageName)")
                    sharedImageFileNames.append(storedImageName)
                }
            }
        }

        let deduplicatedWebURLs = deduplicated(sharedWebURLs)
        let deduplicatedPDFNames = deduplicated(sharedPDFFileNames)
        let deduplicatedImageNames = deduplicated(sharedImageFileNames)
        shareLog.info("dedup counts: urls=\(deduplicatedWebURLs.count) pdfs=\(deduplicatedPDFNames.count) images=\(deduplicatedImageNames.count)")
        guard !deduplicatedWebURLs.isEmpty
            || !deduplicatedPDFNames.isEmpty
            || !deduplicatedImageNames.isEmpty else {
            shareLog.error("processSharedItems: nothing forwardable extracted — returning without opening app")
            return
        }

        guard let appURL = buildAppURL(
            sharedWebURLs: deduplicatedWebURLs,
            sharedPDFFileNames: deduplicatedPDFNames,
            sharedImageFileNames: deduplicatedImageNames
        ) else {
            shareLog.error("processSharedItems: buildAppURL returned nil")
            return
        }
        shareLog.info("opening containing app with URL: \(appURL.absoluteString)")

        let opened = await openContainingApp(with: appURL)
        shareLog.info("openContainingApp returned \(opened)")
    }

    private func loadSharedWebURL(from provider: NSItemProvider) async -> URL? {
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let item = await loadItem(from: provider, typeIdentifier: UTType.url.identifier),
           let url = extractURL(from: item),
           !url.isFileURL,
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return url
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier),
           let item = await loadItem(from: provider, typeIdentifier: UTType.text.identifier),
           let string = item as? String,
           let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return url
        }

        return nil
    }

    private func persistSharedPDF(from provider: NSItemProvider) async -> String? {
        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            if let stored = await persistFileRepresentation(
                from: provider,
                typeIdentifier: UTType.pdf.identifier,
                allowedExtensions: ["pdf"],
                defaultExtension: "pdf",
                fallbackName: "shared.pdf",
                preferredFileName: provider.suggestedName
            ) {
                return stored
            }
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let item = await loadItem(from: provider, typeIdentifier: UTType.fileURL.identifier),
           let sourceURL = extractURL(from: item),
           sourceURL.pathExtension.lowercased() == "pdf" {
            return persistPDF(at: sourceURL, preferredFileName: provider.suggestedName ?? sourceURL.lastPathComponent)
        }

        return nil
    }

    private func persistSharedImage(from provider: NSItemProvider) async -> String? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
              || provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
            return nil
        }

        // Walk the provider's specific registered UTIs (e.g. public.heic,
        // public.jpeg, public.png) first — these often work where the
        // generic `public.image` parent UTI returns nil. Photos.app on iOS
        // is the most common case.
        let imageUTIs = provider.registeredTypeIdentifiers.filter { id in
            guard let utType = UTType(id) else { return false }
            return utType.conforms(to: .image)
        }
        let candidates = imageUTIs.isEmpty ? [UTType.image.identifier] : imageUTIs
        shareLog.info("persistSharedImage: candidate UTIs=[\(candidates.joined(separator: ", "))]")

        for typeID in candidates {
            // Pass 1: file representation (cheaper for large files, copies inside the closure).
            if let stored = await persistFileRepresentation(
                from: provider,
                typeIdentifier: typeID,
                allowedExtensions: Self.imageFileExtensions,
                defaultExtension: Self.fileExtension(for: typeID) ?? Self.defaultImageExtension,
                fallbackName: "shared.\(Self.defaultImageExtension)",
                preferredFileName: provider.suggestedName
            ) {
                shareLog.info("persistSharedImage: file representation succeeded for \(typeID)")
                return stored
            }
            shareLog.info("persistSharedImage: file representation returned nil for \(typeID) — trying data representation")

            // Pass 2: raw data fallback. Some Photos.app shares only expose
            // `loadDataRepresentation` reliably (especially HEIC originals).
            if let stored = await persistDataRepresentation(
                from: provider,
                typeIdentifier: typeID,
                allowedExtensions: Self.imageFileExtensions,
                defaultExtension: Self.fileExtension(for: typeID) ?? Self.defaultImageExtension,
                fallbackName: "shared.\(Self.defaultImageExtension)",
                preferredFileName: provider.suggestedName
            ) {
                shareLog.info("persistSharedImage: data representation succeeded for \(typeID)")
                return stored
            }
            shareLog.info("persistSharedImage: data representation returned nil for \(typeID)")
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let item = await loadItem(from: provider, typeIdentifier: UTType.fileURL.identifier),
           let sourceURL = extractURL(from: item),
           Self.imageFileExtensions.contains(sourceURL.pathExtension.lowercased()) {
            shareLog.info("persistSharedImage: file-URL fallback for \(sourceURL.lastPathComponent)")
            return persistImage(at: sourceURL, preferredFileName: provider.suggestedName ?? sourceURL.lastPathComponent)
        }

        shareLog.error("persistSharedImage: all paths exhausted, returning nil")
        return nil
    }

    /// Maps a UTType identifier (e.g. `public.heic`, `public.jpeg`) to the
    /// file extension we should save it under, so the host app's image
    /// pipeline can recognise it. Falls back to nil for types it doesn't
    /// know about — caller substitutes a default.
    private static func fileExtension(for typeID: String) -> String? {
        guard let utType = UTType(typeID),
              let ext = utType.preferredFilenameExtension else {
            return nil
        }
        return imageFileExtensions.contains(ext.lowercased()) ? ext.lowercased() : nil
    }

    /// Loads a file representation from the provider AND copies it to the
    /// app-group inbox *inside the completion handler* — required because
    /// iOS deletes the temp file the moment that closure returns (most
    /// visible when sharing images from Photos.app, which fails reliably if
    /// the copy happens later). Returns the persisted file name (in the
    /// inbox) or nil on failure.
    private func persistFileRepresentation(
        from provider: NSItemProvider,
        typeIdentifier: String,
        allowedExtensions: Set<String>,
        defaultExtension: String,
        fallbackName: String,
        preferredFileName: String?
    ) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error {
                    shareLog.error("loadFileRepresentation[\(typeIdentifier)] error: \(error.localizedDescription)")
                }
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                let stored = self.persistFile(
                    at: url,
                    preferredFileName: preferredFileName ?? url.lastPathComponent,
                    allowedExtensions: allowedExtensions,
                    defaultExtension: defaultExtension,
                    fallbackName: fallbackName
                )
                continuation.resume(returning: stored)
            }
        }
    }

    /// Loads the provider's bytes for `typeIdentifier` as raw `Data` and
    /// writes them to the app-group inbox. Used as a fallback when
    /// `persistFileRepresentation` returns nil — happens in practice for
    /// some Photos.app HEIC shares on iOS where only the data
    /// representation is exposed.
    private func persistDataRepresentation(
        from provider: NSItemProvider,
        typeIdentifier: String,
        allowedExtensions: Set<String>,
        defaultExtension: String,
        fallbackName: String,
        preferredFileName: String?
    ) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error {
                    shareLog.error("loadDataRepresentation[\(typeIdentifier)] error: \(error.localizedDescription)")
                }
                guard let data, !data.isEmpty,
                      let inbox = self.sharedInboxDirectoryURL() else {
                    continuation.resume(returning: nil)
                    return
                }

                do {
                    try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
                    // Synthesise a stand-in source URL purely so that
                    // `uniqueInboxDestinationURL` can derive a base name.
                    let synthSource = URL(fileURLWithPath: preferredFileName ?? fallbackName)
                    let destination = self.uniqueInboxDestinationURL(
                        in: inbox,
                        sourceURL: synthSource,
                        preferredFileName: preferredFileName,
                        allowedExtensions: allowedExtensions,
                        defaultExtension: defaultExtension,
                        fallbackName: fallbackName
                    )
                    try data.write(to: destination, options: .atomic)
                    continuation.resume(returning: destination.lastPathComponent)
                } catch {
                    shareLog.error("persistDataRepresentation write error: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func persistPDF(at sourceURL: URL, preferredFileName: String?) -> String? {
        persistFile(
            at: sourceURL,
            preferredFileName: preferredFileName,
            allowedExtensions: ["pdf"],
            defaultExtension: "pdf",
            fallbackName: "shared.pdf"
        )
    }

    private func persistImage(at sourceURL: URL, preferredFileName: String?) -> String? {
        persistFile(
            at: sourceURL,
            preferredFileName: preferredFileName,
            allowedExtensions: Self.imageFileExtensions,
            defaultExtension: Self.defaultImageExtension,
            fallbackName: "shared.\(Self.defaultImageExtension)"
        )
    }

    /// Copies a single file into the app-group inbox, generating a unique
    /// destination filename. Returns the destination's `lastPathComponent` so
    /// the host app can locate it again. Shared between PDF and image flows.
    private func persistFile(
        at sourceURL: URL,
        preferredFileName: String?,
        allowedExtensions: Set<String>,
        defaultExtension: String,
        fallbackName: String
    ) -> String? {
        let fileManager = FileManager.default
        guard let inboxDirectory = sharedInboxDirectoryURL() else {
            return nil
        }

        do {
            try fileManager.createDirectory(at: inboxDirectory, withIntermediateDirectories: true)
            let destinationURL = uniqueInboxDestinationURL(
                in: inboxDirectory,
                sourceURL: sourceURL,
                preferredFileName: preferredFileName,
                allowedExtensions: allowedExtensions,
                defaultExtension: defaultExtension,
                fallbackName: fallbackName
            )
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL.lastPathComponent
        } catch {
            return nil
        }
    }

    private func sharedInboxDirectoryURL() -> URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        ) else {
            return nil
        }

        return containerURL.appendingPathComponent(Self.inboxDirectoryName, isDirectory: true)
    }

    private func uniqueInboxDestinationURL(
        in directory: URL,
        sourceURL: URL,
        preferredFileName: String?,
        allowedExtensions: Set<String>,
        defaultExtension: String,
        fallbackName: String
    ) -> URL {
        let fileManager = FileManager.default
        let safeName = sanitizedFileName(
            preferredFileName: preferredFileName,
            sourceURL: sourceURL,
            allowedExtensions: allowedExtensions,
            defaultExtension: defaultExtension,
            fallbackName: fallbackName
        )
        let baseName = (safeName as NSString).deletingPathExtension
        let rawExt = (safeName as NSString).pathExtension.lowercased()
        let ext = allowedExtensions.contains(rawExt) ? rawExt : defaultExtension

        var index = 0
        while true {
            let suffix = index == 0 ? "" : " (\(index + 1))"
            let candidate = directory.appendingPathComponent("\(baseName)\(suffix).\(ext)")
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private func sanitizedFileName(
        preferredFileName: String?,
        sourceURL: URL,
        allowedExtensions: Set<String>,
        defaultExtension: String,
        fallbackName: String
    ) -> String {
        let rawName = preferredFileName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRaw = (rawName?.isEmpty == false ? rawName! : sourceURL.lastPathComponent)
        let safeRaw = normalizedRaw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = safeRaw.isEmpty ? fallbackName : safeRaw
        let fallbackExt = (fallback as NSString).pathExtension.lowercased()
        if allowedExtensions.contains(fallbackExt) {
            return fallback
        }
        return "\(fallback).\(defaultExtension)"
    }

    private func loadItem(from provider: NSItemProvider, typeIdentifier: String) async -> Any? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }

    private func loadFileRepresentation(from provider: NSItemProvider, typeIdentifier: String) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    private func extractURL(from item: Any) -> URL? {
        if let url = item as? URL {
            return url
        }

        if let nsURL = item as? NSURL {
            return nsURL as URL
        }

        if let data = item as? Data {
            return NSURL(absoluteURLWithDataRepresentation: data, relativeTo: nil) as URL?
        }

        if let string = item as? String {
            return URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return nil
    }

    private func buildAppURL(
        sharedWebURLs: [String],
        sharedPDFFileNames: [String],
        sharedImageFileNames: [String]
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "SilicIA"
        components.host = "share"
        var queryItems: [URLQueryItem] = []

        for value in sharedWebURLs {
            queryItems.append(URLQueryItem(name: "url", value: value))
        }

        for fileName in sharedPDFFileNames {
            queryItems.append(URLQueryItem(name: "sharedPDF", value: fileName))
        }

        for fileName in sharedImageFileNames {
            queryItems.append(URLQueryItem(name: "sharedImage", value: fileName))
        }

        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }

    private func openContainingApp(with url: URL) async -> Bool {
        let didOpenViaExtensionContext = await withCheckedContinuation { continuation in
            extensionContext?.open(url, completionHandler: { success in
                continuation.resume(returning: success)
            })
        }
        shareLog.info("extensionContext.open success=\(didOpenViaExtensionContext)")

        if didOpenViaExtensionContext { return true }

        #if os(macOS)
        return NSWorkspace.shared.open(url)
        #else
        // iOS: `extensionContext.open` is known to flake (often returns
        // false in share-sheet contexts even though the URL is openable).
        // Walk the responder chain to find an object that responds to
        // `openURL:` — a long-standing workaround that still works on
        // iOS 26. Done on the main actor since UIKit is main-isolated.
        return await MainActor.run {
            var responder: UIResponder? = self
            while let current = responder {
                if let app = current as? UIApplication {
                    app.open(url, options: [:], completionHandler: nil)
                    shareLog.info("opened via UIApplication.open (responder-chain)")
                    return true
                }
                let selector = NSSelectorFromString("openURL:")
                if current.responds(to: selector) {
                    _ = current.perform(selector, with: url)
                    shareLog.info("opened via responder-chain perform openURL:")
                    return true
                }
                responder = current.next
            }
            shareLog.error("responder-chain fallback failed: no openURL: target found")
            return false
        }
        #endif
    }

    private func deduplicated(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
