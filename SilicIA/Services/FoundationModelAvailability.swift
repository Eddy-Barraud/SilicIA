//
//  FoundationModelAvailability.swift
//  SilicIA
//
//  Created by Eddy Barraud on 18/05/2026.
//

import Foundation
import FoundationModels

/// Snapshot of whether Apple Intelligence's on-device language model is
/// usable by the app on this device. SilicIA is built around Foundation
/// Models — there is no NLP fallback — so when this is anything other
/// than `.available` the user has to be told up-front.
enum FoundationModelAvailability {
    /// Result of `check()`. The `.unavailable` case carries a localized
    /// reason string suitable for surfacing to the user.
    enum State: Equatable {
        case available
        case unavailable(reason: String)

        var isAvailable: Bool {
            if case .available = self { return true }
            return false
        }
    }

    /// Reads `SystemLanguageModel.default.availability` and turns it into
    /// a UI-friendly `State`. The reason text is rendered in the system
    /// locale (English / French / Spanish, with English as the default
    /// for unsupported locales) rather than the in-app `ModelLanguage`,
    /// because a user who hits this hasn't been able to configure
    /// anything yet.
    static func check() -> State {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            return .unavailable(reason: localizedReason(for: reason))
        }
    }

    // MARK: - Localization

    /// Three-letter language code derived from the current system locale.
    /// Falls back to `"en"` for anything we don't ship copy for.
    private static var systemLanguageCode: String {
        let code = Locale.current.language.languageCode?.identifier.lowercased() ?? "en"
        switch code {
        case "fr", "es": return code
        default: return "en"
        }
    }

    private static func localizedReason(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch (systemLanguageCode, reason) {
        case ("fr", .deviceNotEligible):
            return "Cet appareil ne prend pas en charge Apple Intelligence. SilicIA en a besoin pour fonctionner."
        case ("fr", .appleIntelligenceNotEnabled):
            return "Apple Intelligence est désactivée. Activez-la dans Réglages, puis relancez SilicIA."
        case ("fr", .modelNotReady):
            return "Le modèle Apple Intelligence est en cours de téléchargement. Réessayez dans quelques instants."
        case ("fr", _):
            return "Le modèle Apple Intelligence est indisponible sur cet appareil. SilicIA en a besoin pour fonctionner."

        case ("es", .deviceNotEligible):
            return "Este dispositivo no admite Apple Intelligence. SilicIA lo necesita para funcionar."
        case ("es", .appleIntelligenceNotEnabled):
            return "Apple Intelligence está desactivada. Actívala en Ajustes y vuelve a abrir SilicIA."
        case ("es", .modelNotReady):
            return "El modelo de Apple Intelligence se está descargando. Inténtalo de nuevo en unos minutos."
        case ("es", _):
            return "El modelo de Apple Intelligence no está disponible en este dispositivo. SilicIA lo necesita para funcionar."

        case (_, .deviceNotEligible):
            return "This device does not support Apple Intelligence. SilicIA requires it to work."
        case (_, .appleIntelligenceNotEnabled):
            return "Apple Intelligence is turned off. Enable it in Settings and reopen SilicIA."
        case (_, .modelNotReady):
            return "The Apple Intelligence model is still downloading. Try again in a few moments."
        case (_, _):
            return "The Apple Intelligence model is unavailable on this device. SilicIA requires it to work."
        }
    }

    /// Localized title for the blocking screen.
    static var alertTitle: String {
        switch systemLanguageCode {
        case "fr": return "Apple Intelligence requise"
        case "es": return "Se requiere Apple Intelligence"
        default:   return "Apple Intelligence required"
        }
    }

    /// Localized label for the "quit the app" button on the blocking screen.
    static var closeButtonLabel: String {
        switch systemLanguageCode {
        case "fr": return "Fermer SilicIA"
        case "es": return "Cerrar SilicIA"
        default:   return "Close SilicIA"
        }
    }
}
