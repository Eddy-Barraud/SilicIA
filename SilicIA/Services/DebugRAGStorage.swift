//
//  DebugRAGStorage.swift
//  SilicIA
//
//  Debug helper to write downloaded webpages in Markdown (.md),
//  save ranked chunks (Rank -- chunk content), and log the complete
//  final prompt sent to Foundation Models.
//

import Foundation

public final class DebugRAGStorage: Sendable {
    public static let shared = DebugRAGStorage()

    private let fileManager = FileManager.default

    private var debugRootDirectory: URL {
        let baseDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseDir.appendingPathComponent("SilicIADebug", isDirectory: true)
    }

    private var webpagesDirectory: URL {
        debugRootDirectory.appendingPathComponent("Webpages", isDirectory: true)
    }

    private var rankedChunksDirectory: URL {
        debugRootDirectory.appendingPathComponent("RankedChunks", isDirectory: true)
    }

    private var promptsDirectory: URL {
        debugRootDirectory.appendingPathComponent("Prompts", isDirectory: true)
    }

    private init() {
        #if DEBUG
        ensureDirectoriesExist()
        #endif
    }

    private func ensureDirectoriesExist() {
        for dir in [webpagesDirectory, rankedChunksDirectory, promptsDirectory] {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Saves downloaded webpage as a .md file in local storage.
    public func saveDownloadedWebpage(markdown: String, title: String, url: URL?) {
        #if DEBUG
        ensureDirectoriesExist()

        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let hostOrTitle = (url?.host ?? title)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        let filename = "\(timestamp)_\(hostOrTitle.prefix(40)).md"
        let fileURL = webpagesDirectory.appendingPathComponent(filename)

        let header = """
        <!-- Title: \(title) -->
        <!-- Source URL: \(url?.absoluteString ?? "N/A") -->
        <!-- Saved At: \(Date()) -->

        """

        let content = header + markdown
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            print("[DebugRAGStorage] Saved webpage Markdown (\(content.count) chars) -> \(fileURL.path)")
        } catch {
            print("[DebugRAGStorage] Failed to save webpage Markdown: \(error)")
        }
        #endif
    }

    /// Saves ranked chunks to a text file with "Rank -- chunk content" formatting.
    public func saveRankedChunks(
        query: String,
        chunks: [(rank: Int, score: Double, source: String, text: String)]
    ) {
        #if DEBUG
        ensureDirectoriesExist()

        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let filename = "ranked_chunks_\(timestamp).txt"
        let fileURL = rankedChunksDirectory.appendingPathComponent(filename)

        var lines: [String] = []
        lines.append("Query: \(query)")
        lines.append("Timestamp: \(Date())")
        lines.append("Total Ranked Chunks: \(chunks.count)")
        lines.append("")
        lines.append("================================================================================")
        lines.append("Rank -- chunk content")
        lines.append("================================================================================")
        lines.append("")

        for chunk in chunks {
            lines.append("Rank \(chunk.rank) (Score: \(String(format: "%.4f", chunk.score)), Source: \(chunk.source)) --")
            lines.append(chunk.text)
            lines.append("")
            lines.append("--------------------------------------------------------------------------------")
            lines.append("")
        }

        let body = lines.joined(separator: "\n")
        do {
            try body.write(to: fileURL, atomically: true, encoding: .utf8)
            print("[DebugRAGStorage] Saved ranked chunks -> \(fileURL.path)")
        } catch {
            print("[DebugRAGStorage] Failed to save ranked chunks: \(error)")
        }
        #endif
    }

    /// Logs the final complete prompt including context sent to the model to console and disk.
    public func logFinalPrompt(_ prompt: String, label: String = "FoundationModels") {
        #if DEBUG
        ensureDirectoriesExist()

        print("┏━ [FINAL COMPLETE MODEL PROMPT: \(label)] ━━━━━━━━━━━━━━━━━━━━")
        print(prompt)
        print("┗━ [END OF PROMPT (\(prompt.count) chars)] ━━━━━━━━━━━━━━━━━━━━━━━━")

        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let filename = "prompt_\(timestamp)_\(label).txt"
        let fileURL = promptsDirectory.appendingPathComponent(filename)
        try? prompt.write(to: fileURL, atomically: true, encoding: .utf8)
        #endif
    }
}
