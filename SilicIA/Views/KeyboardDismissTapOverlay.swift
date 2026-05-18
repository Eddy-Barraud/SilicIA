//
//  KeyboardDismissTapOverlay.swift
//  SilicIA
//
//  Created by GitHub Copilot on 26/04/2026.
//

import SwiftUI

#if canImport(UIKit)
import UIKit

/// Captures taps anywhere in the view tree except text inputs, and calls `onTapOutsideTextInput`.
///
/// The previous implementation tried to attach its window-level
/// recognizer from `updateUIView`, but at that point the underlying
/// `UIView` is usually not yet a child of a `UIWindow`, so
/// `uiView.window` returns nil and attachment is silently skipped —
/// breaking the "tap anywhere to dismiss the keyboard" UX. The fix is
/// a `WindowTrackingView` that calls back the coordinator from
/// `didMoveToWindow`, which fires at the precise moment a `UIWindow`
/// becomes available.
struct KeyboardDismissTapOverlay: UIViewRepresentable {
    let onTapOutsideTextInput: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = WindowTrackingView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attachRecognizer(to: window)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTapOutsideTextInput = onTapOutsideTextInput
        // Defensive: in case `didMoveToWindow` fired before we wired
        // up the closure (unlikely, but cheap), attach now.
        context.coordinator.attachRecognizer(to: uiView.window)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detachRecognizer()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTapOutsideTextInput: onTapOutsideTextInput)
    }

    private final class WindowTrackingView: UIView {
        var onWindowChange: ((UIWindow?) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            onWindowChange?(window)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTapOutsideTextInput: () -> Void
        private weak var attachedWindow: UIWindow?
        private var recognizer: UITapGestureRecognizer?

        init(onTapOutsideTextInput: @escaping () -> Void) {
            self.onTapOutsideTextInput = onTapOutsideTextInput
        }

        func attachRecognizer(to window: UIWindow?) {
            guard let window else {
                detachRecognizer()
                return
            }
            guard attachedWindow !== window else { return }

            detachRecognizer()

            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            window.addGestureRecognizer(recognizer)

            attachedWindow = window
            self.recognizer = recognizer
        }

        func detachRecognizer() {
            if let recognizer, let attachedWindow {
                attachedWindow.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            attachedWindow = nil
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            onTapOutsideTextInput()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let touchedView = touch.view else { return true }
            return !Self.isTextInputView(touchedView)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        private static func isTextInputView(_ view: UIView) -> Bool {
            var current: UIView? = view
            while let candidate = current {
                if candidate is UITextField || candidate is UITextView {
                    return true
                }
                current = candidate.superview
            }
            return false
        }
    }
}
#endif
