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
struct KeyboardDismissTapOverlay: UIViewRepresentable {
    let onTapOutsideTextInput: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTapOutsideTextInput = onTapOutsideTextInput
        context.coordinator.attachRecognizerIfNeeded(from: uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detachRecognizer()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTapOutsideTextInput: onTapOutsideTextInput)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTapOutsideTextInput: () -> Void
        private weak var attachedView: UIView?
        private var recognizer: UITapGestureRecognizer?

        init(onTapOutsideTextInput: @escaping () -> Void) {
            self.onTapOutsideTextInput = onTapOutsideTextInput
        }

        func attachRecognizerIfNeeded(from uiView: UIView) {
            guard let window = uiView.window else { return }
            guard attachedView !== window else { return }

            detachRecognizer()

            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            window.addGestureRecognizer(recognizer)

            attachedView = window
            self.recognizer = recognizer
        }

        func detachRecognizer() {
            if let recognizer, let attachedView {
                attachedView.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            attachedView = nil
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
