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

        let recognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = context.coordinator
        view.addGestureRecognizer(recognizer)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTapOutsideTextInput = onTapOutsideTextInput
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTapOutsideTextInput: onTapOutsideTextInput)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTapOutsideTextInput: () -> Void

        init(onTapOutsideTextInput: @escaping () -> Void) {
            self.onTapOutsideTextInput = onTapOutsideTextInput
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            onTapOutsideTextInput()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let touchedView = touch.view else { return true }
            return !Self.isTextInputView(touchedView)
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
