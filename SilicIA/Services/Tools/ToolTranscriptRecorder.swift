//
//  ToolTranscriptRecorder.swift
//  SilicIA
//
//  Records successful tool replies so, if a tool-calling turn later
//  overflows the model context window, we can restart from the last
//  known-good tool state instead of discarding all gathered evidence.
//

import Foundation

actor ToolTranscriptRecorder {

    struct Entry: Sendable {
        let tool: String
        let arguments: String
        let result: String
    }

    private var entries: [Entry] = []
    private let maxEntries: Int

    init(maxEntries: Int = 6) {
        self.maxEntries = max(1, maxEntries)
    }

    func record(tool: String, arguments: String, result: String) {
        let trimmedArguments = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedResult = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedResult.isEmpty else { return }
        entries.append(Entry(tool: tool, arguments: trimmedArguments, result: trimmedResult))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func hasEntries() -> Bool {
        !entries.isEmpty
    }

    func renderedTranscript(characterBudget: Int, maxRenderedEntries: Int = 4) -> String {
        guard characterBudget > 0, !entries.isEmpty else { return "" }

        var chosen: [Entry] = []
        var used = 0
        let entryCap = max(1, maxRenderedEntries)

        for entry in entries.reversed() {
            guard chosen.count < entryCap else { break }
            let block = render(entry: entry, characterBudget: max(160, characterBudget / max(1, entryCap)))
            let separator = chosen.isEmpty ? 0 : 2
            guard used + separator + block.count <= characterBudget || chosen.isEmpty else { continue }
            chosen.append(entry)
            used += separator + block.count
        }

        let rendered = chosen
            .reversed()
            .map { render(entry: $0, characterBudget: max(160, characterBudget / max(1, chosen.count))) }
            .joined(separator: "\n\n")

        if rendered.count <= characterBudget {
            return rendered
        }
        return String(rendered.prefix(characterBudget)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func render(entry: Entry, characterBudget: Int) -> String {
        let trimmedArgs = entry.arguments.isEmpty ? "—" : entry.arguments
        let header = "Tool: \(entry.tool)\nArguments: \(trimmedArgs)\nResult:"
        let remaining = max(0, characterBudget - header.count - 1)
        let body: String
        if entry.result.count <= remaining {
            body = entry.result
        } else if remaining > 1 {
            body = String(entry.result.prefix(max(0, remaining - 1))).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        } else {
            body = ""
        }
        return "\(header)\n\(body)".trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
