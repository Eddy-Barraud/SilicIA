//
//  PDFtalkmeApp.swift
//  PDFtalkme
//
//  Created by OpenCode on 18/04/2026.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct PDFtalkmeApp: App {
    @StateObject private var openRouter = PDFOpenRouter.shared
#if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
#endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL(perform: handleIncomingURL)
#if os(macOS)
                .onAppear {
                    appDelegate.onOpenURLs = { urls in
                        openRouter.enqueue(urls, openInNewTabs: true)
                    }

                    let pending = appDelegate.drainPendingURLs()
                    if !pending.isEmpty {
                        openRouter.enqueue(pending)
                    }
                }
#endif
        }
        .defaultSize(width: 1460, height: 940)

        #if os(macOS)
        .commands {
            CommandMenu("Find") {
                Button("Find in PDF") {
                    NotificationCenter.default.post(name: .pdfTalkmeOpenFind, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }
        #endif
    }

    private func handleIncomingURL(_ url: URL) {
        openRouter.enqueue([url], openInNewTabs: true)
    }
}

#if os(macOS)
final class AppDelegate: NSObject, NSApplicationDelegate {
    var onOpenURLs: (([URL]) -> Void)?
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let onOpenURLs {
            onOpenURLs(urls)
        } else {
            pendingURLs.append(contentsOf: urls)
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        if let onOpenURLs {
            onOpenURLs([url])
        } else {
            pendingURLs.append(url)
        }
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        if let onOpenURLs {
            onOpenURLs(urls)
        } else {
            pendingURLs.append(contentsOf: urls)
        }
        sender.reply(toOpenOrPrint: .success)
    }

    func drainPendingURLs() -> [URL] {
        defer { pendingURLs.removeAll() }
        return pendingURLs
    }

    @objc func askPDF(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>?) {
        let classes: [AnyClass] = [NSURL.self]
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        guard let urls = pboard.readObjects(forClasses: classes, options: options) as? [URL] else {
            error?.pointee = "No files were provided." as NSString
            return
        }

        let pdfURLs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        guard !pdfURLs.isEmpty else {
            error?.pointee = "Please select at least one PDF file." as NSString
            return
        }

        if let onOpenURLs {
            onOpenURLs(pdfURLs)
        } else {
            pendingURLs.append(contentsOf: pdfURLs)
        }
    }
}
#endif
