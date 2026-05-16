//
//  ShareViewController.swift
//  SilicIAShareExtension
//
//  Created by Copilot on 18/04/2026.
//

import Foundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
typealias PlatformShareViewController = NSViewController
#else
import UIKit
typealias PlatformShareViewController = UIViewController
#endif

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
            return
        }

        var sharedWebURLs: [String] = []
        var sharedPDFFileNames: [String] = []
        var sharedImageFileNames: [String] = []

        for item in extensionItems {
            let providers = item.attachments ?? []
            for provider in providers {
                if let sharedURL = await loadSharedWebURL(from: provider) {
                    sharedWebURLs.append(sharedURL.absoluteString)
                }

                if let storedPDFName = await persistSharedPDF(from: provider) {
                    sharedPDFFileNames.append(storedPDFName)
                    continue
                }

                if let storedImageName = await persistSharedImage(from: provider) {
                    sharedImageFileNames.append(storedImageName)
                }
            }
        }

        let deduplicatedWebURLs = deduplicated(sharedWebURLs)
        let deduplicatedPDFNames = deduplicated(sharedPDFFileNames)
        let deduplicatedImageNames = deduplicated(sharedImageFileNames)
        guard !deduplicatedWebURLs.isEmpty
            || !deduplicatedPDFNames.isEmpty
            || !deduplicatedImageNames.isEmpty else {
            return
        }

        guard let appURL = buildAppURL(
            sharedWebURLs: deduplicatedWebURLs,
            sharedPDFFileNames: deduplicatedPDFNames,
            sharedImageFileNames: deduplicatedImageNames
        ) else {
            return
        }

        _ = await openContainingApp(with: appURL)
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
        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier),
           let tempURL = await loadFileRepresentation(from: provider, typeIdentifier: UTType.pdf.identifier) {
            return persistPDF(at: tempURL, preferredFileName: provider.suggestedName)
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
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
           let tempURL = await loadFileRepresentation(from: provider, typeIdentifier: UTType.image.identifier) {
            return persistImage(at: tempURL, preferredFileName: provider.suggestedName ?? tempURL.lastPathComponent)
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let item = await loadItem(from: provider, typeIdentifier: UTType.fileURL.identifier),
           let sourceURL = extractURL(from: item),
           Self.imageFileExtensions.contains(sourceURL.pathExtension.lowercased()) {
            return persistImage(at: sourceURL, preferredFileName: provider.suggestedName ?? sourceURL.lastPathComponent)
        }

        return nil
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

        #if os(macOS)
        if !didOpenViaExtensionContext {
            return NSWorkspace.shared.open(url)
        }
        #endif

        return didOpenViaExtensionContext
    }

    private func deduplicated(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
