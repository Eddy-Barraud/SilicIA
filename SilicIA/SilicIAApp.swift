//
//  SilicIAApp.swift
//  SilicIA
//
//  Created by Eddy Barraud on 23/03/2026.
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

@main
/// Application entry point that launches the main content window.
struct SilicIAApp: App {
    init() {
        _ = LocalizationService.shared
    }
    private static let sharedAppGroupIdentifier = "group.fr.trevalim.silicia.shared"
    private static let sharedInboxDirectoryName = "IncomingSharedFiles"

    @State private var sharedURLs: [String] = []
    @State private var sharedPDFs: [URL] = []
    @State private var sharedImages: [URL] = []
    @State private var pendingSearchQuery: String?

    private static let imageFileExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "bmp"
    ]
#if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
#endif

    /// Declares the app's primary window scene.
    var body: some Scene {
        WindowGroup {
            ContentView(
                sharedURLs: $sharedURLs,
                sharedPDFs: $sharedPDFs,
                sharedImages: $sharedImages,
                pendingSearchQuery: $pendingSearchQuery
            )
                .onOpenURL { url in
                    handleIncomingURL(url)
                    // The URL handler might have failed to parse names (e.g.
                    // share-extension URL got truncated); always sweep the
                    // app-group inbox as a safety net.
                    drainSharedInbox()
                }
#if os(macOS)
                .onAppear {
                    appDelegate.onOpenURLs = { urls in
                        for url in urls {
                            handleIncomingURL(url)
                        }
                        drainSharedInbox()
                    }
                    let pending = appDelegate.drainPendingURLs()
                    if !pending.isEmpty {
                        for url in pending {
                            handleIncomingURL(url)
                        }
                    }
                    // Sweep inbox on every cold-start so files dropped while
                    // the main app was closed get picked up.
                    drainSharedInbox()
                }
#else
                .onAppear {
                    // iOS: same idea — pick up anything the share extension
                    // dropped, in case the URL deep-link didn't fire.
                    drainSharedInbox()
                }
#endif
        }
        #if os(macOS)
            .defaultSize(width: 500, height: 900)
        #endif
        .modelContainer(for: [Conversation.self, Message.self])
    }

    /// Routes incoming shared URLs and files to chat context.
    private func handleIncomingURL(_ url: URL) {
        if url.isFileURL {
            let ext = url.pathExtension.lowercased()
            if ext == "pdf" {
                sharedPDFs = [url]
                return
            }
            if Self.imageFileExtensions.contains(ext) {
                sharedImages = [url]
                return
            }
        }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           url.scheme?.lowercased() == "silicia",
            let queryItems = components.queryItems {
            if components.host?.lowercased() == "share" || components.path.lowercased().contains("share") {
                let incomingURLs = queryItems
                    .filter { $0.name == "url" }
                    .compactMap(\.value)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                let incomingSharedPDFNames = queryItems
                    .filter { $0.name == "sharedPDF" }
                    .compactMap(\.value)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                let incomingSharedImageNames = queryItems
                    .filter { $0.name == "sharedImage" }
                    .compactMap(\.value)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }

                if !incomingURLs.isEmpty {
                    sharedURLs = incomingURLs
                }

                let importedSharedPDFs = importSharedPDFs(fileNames: incomingSharedPDFNames)
                if !importedSharedPDFs.isEmpty {
                    sharedPDFs = importedSharedPDFs
                }

                let importedSharedImages = importSharedImages(fileNames: incomingSharedImageNames)
                if !importedSharedImages.isEmpty {
                    sharedImages = importedSharedImages
                }

                if !incomingURLs.isEmpty || !importedSharedPDFs.isEmpty || !importedSharedImages.isEmpty {
                    return
                }
            }

            if (components.host?.lowercased() == "search" || components.path.lowercased().contains("search")),
               queryItems.first(where: { $0.name == "q" || $0.name == "query" })?.value == nil {
                pendingSearchQuery = ""
                return
            }
            if let searchQuery = queryItems.first(where: { $0.name == "q" || $0.name == "query" })?.value,
               !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pendingSearchQuery = searchQuery
                return
            }
            if let sharedURL = queryItems.first(where: { $0.name == "url" })?.value,
               !sharedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sharedURLs = [sharedURL]
                return
            }
        }

        let absolute = url.absoluteString
        if absolute.hasPrefix("http://") || absolute.hasPrefix("https://") {
            sharedURLs = [absolute]
        }
    }

    private func importSharedPDFs(fileNames: [String]) -> [URL] {
        guard !fileNames.isEmpty,
              let groupContainer = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: Self.sharedAppGroupIdentifier
              ) else {
            return []
        }

        let inboxDirectory = groupContainer.appendingPathComponent(Self.sharedInboxDirectoryName, isDirectory: true)
        var imported: [URL] = []

        for fileName in fileNames {
            guard URL(fileURLWithPath: fileName).pathExtension.lowercased() == "pdf" else { continue }
            let sourceURL = inboxDirectory.appendingPathComponent(fileName)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else { continue }
            if let persistedURL = DroppedPDFStore.persist(sourceURL, preferredFileName: fileName) {
                imported.append(persistedURL)
                try? FileManager.default.removeItem(at: sourceURL)
            }
        }

        return imported
    }

    private func importSharedImages(fileNames: [String]) -> [URL] {
        guard !fileNames.isEmpty,
              let groupContainer = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: Self.sharedAppGroupIdentifier
              ) else {
            return []
        }

        let inboxDirectory = groupContainer.appendingPathComponent(Self.sharedInboxDirectoryName, isDirectory: true)
        var imported: [URL] = []

        for fileName in fileNames {
            let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
            guard Self.imageFileExtensions.contains(ext) else { continue }
            let sourceURL = inboxDirectory.appendingPathComponent(fileName)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else { continue }
            if let persistedURL = DroppedImageStore.persist(sourceURL, preferredFileName: fileName) {
                imported.append(persistedURL)
                try? FileManager.default.removeItem(at: sourceURL)
            }
        }

        return imported
    }

    /// Scans the app-group inbox for any leftover files dropped there by the
    /// share extension and imports them. Resilient fallback for cases where
    /// the share-extension URL scheme failed to deep-link us with explicit
    /// filenames in the query string (a known issue on iOS share sheets).
    /// Anything found here is treated as "user-shared" and surfaces in
    /// `sharedPDFs` / `sharedImages` exactly as if it had come through the
    /// regular URL-scheme path.
    @discardableResult
    private func drainSharedInbox() -> Bool {
        guard let groupContainer = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.sharedAppGroupIdentifier
        ) else { return false }

        let inbox = groupContainer.appendingPathComponent(Self.sharedInboxDirectoryName, isDirectory: true)
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: inbox.path),
              !contents.isEmpty else {
            return false
        }

        var newPDFs: [URL] = []
        var newImages: [URL] = []
        for fileName in contents {
            let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
            let sourceURL = inbox.appendingPathComponent(fileName)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else { continue }
            if ext == "pdf" {
                if let persisted = DroppedPDFStore.persist(sourceURL, preferredFileName: fileName) {
                    newPDFs.append(persisted)
                    try? FileManager.default.removeItem(at: sourceURL)
                }
            } else if Self.imageFileExtensions.contains(ext) {
                if let persisted = DroppedImageStore.persist(sourceURL, preferredFileName: fileName) {
                    newImages.append(persisted)
                    try? FileManager.default.removeItem(at: sourceURL)
                }
            }
        }

        if !newPDFs.isEmpty { sharedPDFs = newPDFs }
        if !newImages.isEmpty { sharedImages = newImages }
        return !newPDFs.isEmpty || !newImages.isEmpty
    }
}

#if os(macOS)
/// Receives URLs and files opened by macOS (Finder/Preview/Safari share flows).
final class AppDelegate: NSObject, NSApplicationDelegate {
    var onOpenURLs: (([URL]) -> Void)?
    private var pendingURLs: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        if let onOpenURLs {
            onOpenURLs(urls)
        } else {
            pendingURLs.append(contentsOf: urls)
        }
    }

    func drainPendingURLs() -> [URL] {
        defer { pendingURLs.removeAll() }
        return pendingURLs
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
            return true
    }
}
#endif
