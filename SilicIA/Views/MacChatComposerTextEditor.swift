//
//  MacChatComposerTextEditor.swift
//  SilicIA
//
//  macOS-only multiline text editor for the chat composer that maps
//  plain Return → submit and Shift+Return → newline.
//
//  Why this exists: SwiftUI's `TextField(axis: .vertical) + .onKeyPress`
//  combination is unreliable on macOS — the underlying NSTextView's
//  `keyDown(with:)` races SwiftUI's key-press chain. On some configs
//  Return inserts a newline; on others AppKit's default "field commit"
//  fires and selects all the text without ever invoking the submit
//  closure. Both behaviors break "press Enter to send" for the chat
//  composer.
//
//  Subclassing NSTextView gives us the only reliable interception
//  point: we override keyDown directly and decide what to do before
//  AppKit dispatches the key.
//

#if os(macOS)

import SwiftUI
import AppKit

/// SwiftUI-friendly NSTextView wrapper. Plain Return calls `onSubmit`;
/// Shift+Return inserts a newline (delegated to NSTextView's default).
/// All other keys go through unchanged.
struct MacChatComposerTextEditor: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var font: NSFont = .preferredFont(forTextStyle: .body)
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = SubmittingTextView()
        textView.delegate = context.coordinator
        textView.font = font
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.drawsBackground = false
        textView.textContainer?.lineFragmentPadding = 4
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.string = text
        textView.onSubmit = onSubmit
        textView.placeholderString = placeholder
        context.coordinator.textView = textView

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SubmittingTextView else { return }
        // Refresh the submit closure each cycle so it captures the latest
        // `messageInput` / `chatService` state from the SwiftUI view.
        textView.onSubmit = onSubmit
        if textView.string != text {
            // Preserve selection where possible — replacing the whole
            // string would otherwise jump the caret to the end on every
            // SwiftUI re-render.
            let selectedRange = textView.selectedRange()
            textView.string = text
            let safeLocation = min(selectedRange.location, textView.string.count)
            textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
        }
        textView.placeholderString = placeholder
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        let onSubmit: () -> Void
        weak var textView: SubmittingTextView?

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self._text = text
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }

    /// NSTextView subclass that intercepts Return (no modifiers) to call
    /// `onSubmit`, leaving Shift+Return / Option+Return for newline
    /// insertion via the default NSTextView behavior.
    ///
    /// Also draws a `placeholderString` when the view is empty — SwiftUI's
    /// TextField gives you that for free, but NSTextView doesn't.
    final class SubmittingTextView: NSTextView {
        var onSubmit: (() -> Void)?
        var placeholderString: String = "" {
            didSet { needsDisplay = true }
        }

        override func keyDown(with event: NSEvent) {
            // Return key code on macOS is 36. The numeric-keypad Enter is 76.
            // Treat both as submit so the keyboard layout doesn't matter.
            let isReturn = event.keyCode == 36 || event.keyCode == 76
            let hasShift = event.modifierFlags.contains(.shift)
            if isReturn && !hasShift {
                onSubmit?()
                return
            }
            super.keyDown(with: event)
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            // Placeholder rendering — only when empty + not first-responder
            // (matching the SwiftUI TextField convention where focus hides
            // the placeholder).
            guard string.isEmpty,
                  !placeholderString.isEmpty,
                  let textContainer,
                  let layoutManager else {
                return
            }
            let inset = textContainerInset
            let glyphRect = layoutManager.usedRect(for: textContainer)
            let originX = inset.width + textContainer.lineFragmentPadding
            let originY = inset.height + glyphRect.minY
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font ?? NSFont.preferredFont(forTextStyle: .body),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            (placeholderString as NSString).draw(
                at: NSPoint(x: originX, y: originY),
                withAttributes: attributes
            )
        }
    }
}

#endif
