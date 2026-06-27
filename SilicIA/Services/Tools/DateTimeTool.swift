//
//  DateTimeTool.swift
//  SilicIA
//
//  Foundation Models tool that returns the current date and time in the
//  user's language. Small on-device models have no clock and no concept
//  of "today" or "in two days" — they tend to anchor relative time
//  references against their training data cut-off, which is usually
//  months or years stale by the time a user is talking to them.
//

import Foundation
import FoundationModels

struct DateTimeTool: Tool {

    @Generable
    struct Arguments {
        @Guide(description: "Optional format hint. 'datetime' (default) returns date and time. 'date' returns the date only. 'time' returns the time only. 'iso' returns an ISO-8601 timestamp.")
        let format: String?
    }

    let name = "currentDateTime"
    let description = """
    Get the current date and time. Call this whenever the user references \
    relative time ("today", "now", "next week", "in two days", "soon", \
    "this month", "this year") or asks how recent something is, BEFORE \
    answering — you have no internal clock. Returns the value in the \
    user's language.
    """

    /// Language to format the human-readable answer in. ISO output is
    /// language-agnostic so the language only affects 'datetime', 'date',
    /// and 'time' modes.
    let language: ModelLanguage

    /// Test seam: inject a custom `Date` so tests aren't time-sensitive.
    /// Defaults to `Date()` in production. Not a public API — kept
    /// `internal` and only invoked from CalculatorTool-style test helpers.
    var dateProvider: @Sendable () -> Date = { Date() }

    /// Shared per-generation loop breaker. Optional so direct callers /
    /// tests are unaffected.
    var governor: ToolCallGovernor?

    func call(arguments: Arguments) async throws -> String {
        #if DEBUG
        print("[Tool:currentDateTime] called with format=\(arguments.format ?? "default")")
        #endif

        if let governor {
            let decision = await governor.evaluate(tool: name, arguments: arguments.format ?? "default")
            if case .allow = decision {
                // continue
            } else if let refusal = decision.refusalMessage {
                return refusal
            }
        }

        let now = dateProvider()
        let format = (arguments.format ?? "datetime").lowercased()

        switch format {
        case "iso":
            // RFC3339 / ISO8601, UTC. Trivially parseable by the model
            // if it wants to do downstream arithmetic.
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.string(from: now)

        case "date":
            return localizedString(date: now, mode: .dateOnly)

        case "time":
            return localizedString(date: now, mode: .timeOnly)

        case "datetime", "":
            return localizedString(date: now, mode: .both)

        default:
            // Unknown format — fall back to the safest answer rather than
            // surfacing an error the model would just retry.
            return localizedString(date: now, mode: .both)
        }
    }

    private enum Mode { case dateOnly, timeOnly, both }

    private func localizedString(date: Date, mode: Mode) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: localeIdentifier(for: language))
        switch mode {
        case .dateOnly:
            formatter.dateStyle = .full
            formatter.timeStyle = .none
        case .timeOnly:
            formatter.dateStyle = .none
            formatter.timeStyle = .short
        case .both:
            formatter.dateStyle = .full
            formatter.timeStyle = .short
        }
        return formatter.string(from: date)
    }

    private func localeIdentifier(for language: ModelLanguage) -> String {
        switch language {
        case .french: return "fr_FR"
        case .spanish: return "es_ES"
        case .english: return "en_US"
        }
    }
}
