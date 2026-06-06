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
        // Capture founding-user status on the very first launch, before any
        // UI appears, so everyone who arrives during the free era is
        // grandfathered. Idempotent on later launches. See FoundingUserStore.
        FoundingUserStore.registerLaunchIfNeeded()
        // Build the (currently dormant) monetization objects. Entitlements
        // observes the purchase manager, so they're constructed together and
        // injected into the environment for any future paywall / gating UI.
        let purchaseManager = PurchaseManager()
        _purchaseManager = StateObject(wrappedValue: purchaseManager)
        _entitlements = StateObject(wrappedValue: Entitlements(purchaseManager: purchaseManager))
    }
    private static let sharedAppGroupIdentifier = "group.fr.trevalim.silicia.shared"
    private static let sharedInboxDirectoryName = "IncomingSharedFiles"

    @State private var sharedURLs: [String] = []
    @State private var sharedPDFs: [URL] = []
    @State private var sharedImages: [URL] = []
    @State private var pendingSearchQuery: String?
    /// Dormant monetization plumbing. Wired into the environment now so a
    /// future paywall / gating UI can read them, but nothing consumes them
    /// while `Entitlements.paywallActive` is false.
    @StateObject private var purchaseManager: PurchaseManager
    @StateObject private var entitlements: Entitlements

    private static let imageFileExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "bmp"
    ]
#if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
#endif

    /// Declares the app's primary window scene.
    var body: some Scene {
        WindowGroup {
            // The app stays usable for everyone: when Apple Intelligence
            // isn't available, the chat/search surfaces surface an inline
            // notice and fall back to web search + ranked source cards
            // instead of a blocking screen.
            ContentView(
                sharedURLs: $sharedURLs,
                sharedPDFs: $sharedPDFs,
                sharedImages: $sharedImages,
                pendingSearchQuery: $pendingSearchQuery
            )
                .environmentObject(purchaseManager)
                .environmentObject(entitlements)
                // Dormant: only fetch product metadata once the paywall
                // is actually switched on, so v1 makes no StoreKit calls.
                .task {
                    if Entitlements.paywallActive {
                        await purchaseManager.loadProduct()
                    }
                }
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
#if os(macOS)
                .onAppear {
                    appDelegate.onOpenURLs = { urls in
                        for url in urls {
                            handleIncomingURL(url)
                        }
                    }
                    let pending = appDelegate.drainPendingURLs()
                    if !pending.isEmpty {
                        for url in pending {
                            handleIncomingURL(url)
                        }
                    }
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
