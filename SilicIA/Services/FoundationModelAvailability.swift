//
//  FoundationModelAvailability.swift
//  SilicIA
//
//  Created by Eddy Barraud on 18/05/2026.
//

import Foundation
import FoundationModels
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Snapshot of whether Apple Intelligence's on-device language model is
/// usable by the app on this device.
///
/// SilicIA's generated answers are built on Foundation Models, but the app
/// no longer blocks unsupported users: when the model is unavailable the
/// chat and search surfaces stay usable (web search + retrieval-ranked
/// source cards keep working) and an inline notice — produced from this
/// type — explains how to enable Apple Intelligence, or that the device
/// can't run it.
enum FoundationModelAvailability {
    /// Result of `check()`. The `.unavailable` case carries a structured
    /// `Reason` so the UI can decide whether to offer a "open Settings"
    /// affordance and which copy to show.
    enum State: Equatable {
        case available
        case unavailable(Reason)

        var isAvailable: Bool {
            if case .available = self { return true }
            return false
        }

        /// The unavailability reason, or `nil` when the model is available.
        var reason: Reason? {
            if case .unavailable(let reason) = self { return reason }
            return nil
        }
    }

    /// Why the on-device model can't be used, normalized away from the
    /// shifting `SystemLanguageModel.Availability.UnavailableReason` set.
    enum Reason: Equatable {
        /// The hardware can't run Apple Intelligence at all — nothing the
        /// user can change.
        case deviceNotEligible
        /// Apple Intelligence is supported but switched off in Settings.
        case notEnabled
        /// The model is still downloading / preparing.
        case modelNotReady
        /// Any other / future reason.
        case other

        /// Whether the user can plausibly fix this themselves from Settings
        /// (turning Apple Intelligence on, or waiting for the download). When
        /// false (`deviceNotEligible`), the notice tells the user the device
        /// simply isn't compatible and omits the Settings button.
        var isUserFixable: Bool {
            switch self {
            case .notEnabled, .modelNotReady: return true
            case .deviceNotEligible, .other: return false
            }
        }

        init?(stringValue: String) {
            switch stringValue {
            case "deviceNotEligible": self = .deviceNotEligible
            case "notEnabled": self = .notEnabled
            case "modelNotReady": self = .modelNotReady
            case "other": self = .other
            default: return nil
            }
        }

        var stringValue: String {
            switch self {
            case .deviceNotEligible: return "deviceNotEligible"
            case .notEnabled: return "notEnabled"
            case .modelNotReady: return "modelNotReady"
            case .other: return "other"
            }
        }
    }

    /// Reads `SystemLanguageModel.default.availability` and maps it onto a
    /// `State`. Cheap and side-effect-free, so callers re-check it whenever
    /// they're about to need the model (the user may have toggled Apple
    /// Intelligence on while the app was running).
    static func check() -> State {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            return .unavailable(mapReason(reason))
        }
    }

    private static func mapReason(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> Reason {
        switch reason {
        case .deviceNotEligible: return .deviceNotEligible
        case .appleIntelligenceNotEnabled: return .notEnabled
        case .modelNotReady: return .modelNotReady
        @unknown default: return .other
        }
    }

    // MARK: - Localized copy

    /// Short headline for the inline notice.
    static func title(for reason: Reason, language: ModelLanguage) -> String {
        switch (language, reason) {
        case (.french, .deviceNotEligible):
            return "Appareil non compatible"
        case (.french, _):
            return "Apple Intelligence requise"
        case (.spanish, .deviceNotEligible):
            return "Dispositivo no compatible"
        case (.spanish, _):
            return "Se requiere Apple Intelligence"
        case (.english, .deviceNotEligible):
            return "Device not compatible"
        case (.english, _):
            return "Apple Intelligence required"
        }
    }

    /// Body text explaining the situation and pointing the user at the
    /// still-working web search. Tailored per reason so the actionable
    /// cases ("turn it on") read differently from the dead-end one
    /// ("your device can't run it").
    static func message(for reason: Reason, language: ModelLanguage) -> String {
        switch (language, reason) {
        // MARK: French
        case (.french, .deviceNotEligible):
            return "Cet appareil ne prend pas en charge Apple Intelligence, donc SilicIA ne peut pas générer de réponse rédigée. Vous pouvez toujours rechercher sur le web : les sources les plus pertinentes sont classées ci-dessous."
        case (.french, .notEnabled):
            return "Activez Apple Intelligence dans les Réglages pour générer des réponses rédigées. En attendant, vous pouvez rechercher sur le web : les sources les plus pertinentes sont classées ci-dessous."
        case (.french, .modelNotReady):
            return "Le modèle Apple Intelligence est en cours de téléchargement. Réessayez dans quelques instants. En attendant, vous pouvez rechercher sur le web : les sources les plus pertinentes sont classées ci-dessous."
        case (.french, .other):
            return "Apple Intelligence est indisponible pour le moment, donc SilicIA ne peut pas générer de réponse rédigée. Vous pouvez toujours rechercher sur le web : les sources les plus pertinentes sont classées ci-dessous."

        // MARK: Spanish
        case (.spanish, .deviceNotEligible):
            return "Este dispositivo no admite Apple Intelligence, por lo que SilicIA no puede generar una respuesta redactada. Aún puedes buscar en la web: las fuentes más relevantes aparecen ordenadas a continuación."
        case (.spanish, .notEnabled):
            return "Activa Apple Intelligence en Ajustes para generar respuestas redactadas. Mientras tanto, puedes buscar en la web: las fuentes más relevantes aparecen ordenadas a continuación."
        case (.spanish, .modelNotReady):
            return "El modelo de Apple Intelligence se está descargando. Inténtalo de nuevo en unos minutos. Mientras tanto, puedes buscar en la web: las fuentes más relevantes aparecen ordenadas a continuación."
        case (.spanish, .other):
            return "Apple Intelligence no está disponible en este momento, por lo que SilicIA no puede generar una respuesta redactada. Aún puedes buscar en la web: las fuentes más relevantes aparecen ordenadas a continuación."

        // MARK: English
        case (.english, .deviceNotEligible):
            return "This device doesn't support Apple Intelligence, so SilicIA can't generate a written answer. You can still search the web — the most relevant sources are ranked below."
        case (.english, .notEnabled):
            return "Turn on Apple Intelligence in Settings to generate written answers. In the meantime you can search the web — the most relevant sources are ranked below."
        case (.english, .modelNotReady):
            return "The Apple Intelligence model is still downloading. Try again in a few moments. In the meantime you can search the web — the most relevant sources are ranked below."
        case (.english, .other):
            return "Apple Intelligence is unavailable right now, so SilicIA can't generate a written answer. You can still search the web — the most relevant sources are ranked below."
        }
    }

    /// Label for the button that opens the Apple Intelligence settings page.
    /// Only shown for user-fixable reasons.
    static func settingsButtonLabel(language: ModelLanguage) -> String {
        switch language {
        case .french: return "Ouvrir les Réglages"
        case .spanish: return "Abrir Ajustes"
        case .english: return "Open Settings"
        }
    }

    /// Indication that a feature needs Apple Intelligence.
    static func appleIntelligenceRequiredNotice(language: ModelLanguage) -> String {
        switch language {
        case .french: return "Nécessite Apple Intelligence"
        case .spanish: return "Requiere Apple Intelligence"
        case .english: return "Requires Apple Intelligence"
        }
    }

    /// Indication that Tool Calling needs Apple Intelligence.
    static func toolCallingNotice(language: ModelLanguage) -> String {
        return appleIntelligenceRequiredNotice(language: language)
    }

    // MARK: - Opening Settings

    /// Opens the OS settings so the user can enable Apple Intelligence.
    ///
    /// There's no public deep-link to the Apple Intelligence pane, so we
    /// open the app's own settings on iOS (the closest reliable target) and
    /// System Settings on macOS. Best-effort — silently no-ops if the URL
    /// can't be opened.
    @MainActor
    static func openSettings() {
        #if os(macOS)
        // Try the Apple Intelligence & Siri pane, then fall back to the
        // System Settings root if that anchor isn't recognized.
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.speech?siri",
            "x-apple.systempreferences:"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
        #elseif canImport(UIKit)
        Task {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(url, options: [:])
            }
            
        }
        #endif
    }
}
