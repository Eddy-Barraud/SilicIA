//
//  ViewRenderingTests.swift
//  SilicIATests
//
//  Smoke tests that each top-level view actually builds its `body` without
//  crashing. We host the view in an NSHostingController and force a layout
//  pass — this evaluates the SwiftUI body graph for real (catching
//  force-unwraps, missing environment, type-check explosions, etc.), which
//  a plain value-construction check would not.
//
//  macOS-only: the test bundle runs on the macOS SDK and uses AppKit's
//  hosting controller. Views are given an in-memory SwiftData container so
//  `@Environment(\.modelContext)` / `@Query` resolve.
//

#if os(macOS)
import XCTest
import SwiftUI
import SwiftData
import AppKit
@testable import SilicIA

@MainActor
final class ViewRenderingTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Conversation.self, Message.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// Hosts `view`, forces `body` evaluation + a layout pass, and asserts
    /// the hierarchy materialised. Reaching the end without a crash is the
    /// real assertion.
    private func assertRenders<V: View>(
        _ view: V,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let host = NSHostingController(rootView: view)
        let rootView = host.view              // forces loadView → body evaluation
        rootView.frame = NSRect(x: 0, y: 0, width: 420, height: 840)
        rootView.layoutSubtreeIfNeeded()
        XCTAssertNotNil(rootView, file: file, line: line)
    }

    func testContentViewRenders() throws {
        let container = try makeContainer()
        assertRenders(
            ContentView(
                sharedURLs: .constant([]),
                sharedPDFs: .constant([]),
                sharedImages: .constant([]),
                pendingSearchQuery: .constant(nil)
            )
            .modelContainer(container)
        )
    }

    func testSearchViewRenders() throws {
        let container = try makeContainer()
        assertRenders(
            SearchView(chatService: ChatService())
                .modelContainer(container)
        )
    }

    func testChatViewRenders() throws {
        let container = try makeContainer()
        assertRenders(
            ChatView(
                sharedURLs: .constant([]),
                sharedPDFs: .constant([]),
                sharedImages: .constant([]),
                chatService: ChatService()
            )
            .modelContainer(container)
        )
    }

    func testConversationsListViewRenders() throws {
        let container = try makeContainer()
        assertRenders(
            ConversationsListView(
                onLoadConversation: { _ in },
                onDismiss: {}
            )
            .modelContainer(container)
        )
    }

    /// The inline notice shown when Apple Intelligence is unavailable.
    func testModelAvailabilityNoticeRenders() {
        assertRenders(ModelAvailabilityNotice(reason: .notEnabled, language: .english))
    }

    /// The progressive LaTeX view renders in both the mid-stream and the
    /// finished states (with inline + display math present).
    func testStreamingLaTeXTextRendersWhileStreaming() {
        assertRenders(
            StreamingLaTeXText(
                text: "The solution is $x = 1$. Next we compute \\[ y = 2 \\] and",
                isStreaming: true
            )
        )
    }

    func testStreamingLaTeXTextRendersWhenComplete() {
        assertRenders(
            StreamingLaTeXText(
                text: "The solution is $x = 1$. The total is $5.00.",
                isStreaming: false
            )
        )
    }

    /// Each tab renders in every supported language (drives the localized
    /// tab-bar labels through the real localization path).
    func testContentViewRendersInAllLanguages() throws {
        let container = try makeContainer()
        let original = AppSettingsStore.shared.settings
        defer { AppSettingsStore.shared.settings = original }

        for language in ModelLanguage.allCases {
            AppSettingsStore.shared.settings.language = language
            assertRenders(
                ContentView(
                    sharedURLs: .constant([]),
                    sharedPDFs: .constant([]),
                    sharedImages: .constant([]),
                    pendingSearchQuery: .constant(nil)
                )
                .modelContainer(container)
            )
        }
    }
}
#endif
