//
//  MarkdownContentView.swift
//  SilicIA
//
//  A dedicated Markdown renderer for Reader Mode and document displays.
//  Parses CommonMark / GFM blocks (headings, code blocks, blockquotes,
//  lists, tables, horizontal rules, and paragraphs) and styles them
//  cleanly with macOS native typography and glass styling.
//

import SwiftUI

/// Block structure extracted from raw Markdown text.
enum MarkdownBlock: Identifiable {
    case heading(level: Int, text: String)
    case quote(String)
    case code(language: String, code: String)
    case table(headers: [String], rows: [[String]])
    case unorderedList([String])
    case orderedList([String])
    case horizontalRule
    case paragraph(String)

    var id: String {
        switch self {
        case .heading(let level, let text):
            return "h\(level)-\(text.hashValue)"
        case .quote(let text):
            return "q-\(text.hashValue)"
        case .code(let lang, let code):
            return "c-\(lang)-\(code.hashValue)"
        case .table(let headers, let rows):
            return "t-\(headers.joined())-\(rows.count)"
        case .unorderedList(let items):
            return "ul-\(items.joined().hashValue)"
        case .orderedList(let items):
            return "ol-\(items.joined().hashValue)"
        case .horizontalRule:
            return "hr-\(UUID().uuidString)"
        case .paragraph(let text):
            return "p-\(text.hashValue)"
        }
    }
}

/// Parses raw Markdown text into structured blocks.
enum MarkdownBlockParser {
    static func parse(markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let rawLines = markdown.components(separatedBy: "\n")
        var i = 0

        while i < rawLines.count {
            let line = rawLines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Blank line
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Code fence (``` or ~~~)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let fence = String(trimmed.prefix(3))
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < rawLines.count {
                    if rawLines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                        i += 1
                        break
                    }
                    codeLines.append(rawLines[i])
                    i += 1
                }
                blocks.append(.code(language: lang, code: codeLines.joined(separator: "\n")))
                continue
            }

            // Horizontal rule (--- or *** or ___)
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.horizontalRule)
                i += 1
                continue
            }

            // Headings (# ... ######)
            if trimmed.hasPrefix("#") {
                var level = 0
                for ch in trimmed {
                    if ch == "#" { level += 1 } else { break }
                }
                if level >= 1 && level <= 6 {
                    let rest = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                    blocks.append(.heading(level: level, text: rest))
                    i += 1
                    continue
                }
            }

            // Blockquote (> ...)
            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while i < rawLines.count {
                    let curTrimmed = rawLines[i].trimmingCharacters(in: .whitespaces)
                    if curTrimmed.hasPrefix(">") {
                        let text = String(curTrimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                        quoteLines.append(text)
                        i += 1
                    } else if !curTrimmed.isEmpty && !quoteLines.isEmpty {
                        quoteLines.append(curTrimmed)
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.quote(quoteLines.joined(separator: "\n")))
                continue
            }

            // Table check (| Header 1 | Header 2 |) followed by separator (| --- | --- |)
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && (i + 1 < rawLines.count) {
                let nextTrimmed = rawLines[i + 1].trimmingCharacters(in: .whitespaces)
                if nextTrimmed.hasPrefix("|") && (nextTrimmed.contains("---") || nextTrimmed.contains("-|-")) {
                    let headers = trimmed.split(separator: "|", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }
                    i += 2 // skip header and separator
                    var rows: [[String]] = []
                    while i < rawLines.count {
                        let rTrimmed = rawLines[i].trimmingCharacters(in: .whitespaces)
                        if rTrimmed.hasPrefix("|") && rTrimmed.hasSuffix("|") {
                            let cells = rTrimmed.split(separator: "|", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }
                            rows.append(cells)
                            i += 1
                        } else {
                            break
                        }
                    }
                    blocks.append(.table(headers: headers, rows: rows))
                    continue
                }
            }

            // Unordered list (- item, * item, + item)
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                var items: [String] = []
                while i < rawLines.count {
                    let curTrimmed = rawLines[i].trimmingCharacters(in: .whitespaces)
                    if curTrimmed.hasPrefix("- ") || curTrimmed.hasPrefix("* ") || curTrimmed.hasPrefix("+ ") {
                        items.append(String(curTrimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                        i += 1
                    } else if !curTrimmed.isEmpty && !items.isEmpty && !curTrimmed.hasPrefix("#") {
                        items[items.count - 1] += " " + curTrimmed
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.unorderedList(items))
                continue
            }

            // Ordered list (1. item, 2. item)
            if let firstSpace = trimmed.firstIndex(of: " "),
               let dotIndex = trimmed.firstIndex(of: "."),
               dotIndex < firstSpace,
               Int(trimmed[..<dotIndex]) != nil {
                var items: [String] = []
                while i < rawLines.count {
                    let curTrimmed = rawLines[i].trimmingCharacters(in: .whitespaces)
                    if let fSpace = curTrimmed.firstIndex(of: " "),
                       let dIdx = curTrimmed.firstIndex(of: "."),
                       dIdx < fSpace,
                       Int(curTrimmed[..<dIdx]) != nil {
                        items.append(String(curTrimmed[curTrimmed.index(after: fSpace)...]).trimmingCharacters(in: .whitespaces))
                        i += 1
                    } else if !curTrimmed.isEmpty && !items.isEmpty && !curTrimmed.hasPrefix("#") {
                        items[items.count - 1] += " " + curTrimmed
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.orderedList(items))
                continue
            }

            // Regular paragraph
            var paragraphLines: [String] = []
            while i < rawLines.count {
                let curTrimmed = rawLines[i].trimmingCharacters(in: .whitespaces)
                if curTrimmed.isEmpty ||
                   curTrimmed.hasPrefix("#") ||
                   curTrimmed.hasPrefix(">") ||
                   curTrimmed.hasPrefix("```") ||
                   curTrimmed.hasPrefix("~~~") ||
                   curTrimmed == "---" ||
                   curTrimmed.hasPrefix("- ") ||
                   curTrimmed.hasPrefix("* ") ||
                   (curTrimmed.hasPrefix("|") && curTrimmed.hasSuffix("|")) {
                    break
                }
                paragraphLines.append(rawLines[i])
                i += 1
            }
            if !paragraphLines.isEmpty {
                blocks.append(.paragraph(paragraphLines.joined(separator: "\n")))
            }
        }

        return blocks
    }
}

/// SwiftUI View rendering full Markdown documents with styled block formatting.
struct MarkdownContentView: View {
    let markdown: String

    private func attributedInline(_ text: String) -> AttributedString {
        if let attr = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attr
        }
        return AttributedString(text)
    }

    var body: some View {
        let blocks = MarkdownBlockParser.parse(markdown: markdown)

        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let text):
                    headingView(level: level, text: text)

                case .quote(let text):
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor.opacity(0.7))
                            .frame(width: 3)
                        Text(attributedInline(text))
                            .font(.body)
                            .italic()
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.accentColor.opacity(0.04))
                    .cornerRadius(6)

                case .code(let lang, let code):
                    VStack(alignment: .leading, spacing: 4) {
                        if !lang.isEmpty {
                            HStack {
                                Spacer()
                                Text(lang.uppercased())
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                            }
                        }
                        ScrollView(.horizontal, showsIndicators: true) {
                            Text(code)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                                .padding(8)
                        }
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )

                case .table(let headers, let rows):
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 0) {
                            // Headers
                            HStack(spacing: 16) {
                                ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                                    Text(attributedInline(header))
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                        .frame(minWidth: 90, alignment: .leading)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background(Color.primary.opacity(0.06))

                            Divider()

                            // Rows
                            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                                HStack(spacing: 16) {
                                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                        Text(attributedInline(cell))
                                            .font(.footnote)
                                            .foregroundColor(.primary)
                                            .frame(minWidth: 90, alignment: .leading)
                                    }
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(rowIndex % 2 == 1 ? Color.primary.opacity(0.02) : Color.clear)

                                if rowIndex < rows.count - 1 {
                                    Divider()
                                }
                            }
                        }
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                    }

                case .unorderedList(let items):
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .font(.body)
                                    .fontWeight(.bold)
                                    .foregroundColor(.accentColor)
                                Text(attributedInline(item))
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.leading, 4)

                case .orderedList(let items):
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1).")
                                    .font(.body)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                Text(attributedInline(item))
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.leading, 4)

                case .horizontalRule:
                    Divider()
                        .padding(.vertical, 6)

                case .paragraph(let text):
                    Text(attributedInline(text))
                        .font(.body)
                        .lineSpacing(4)
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func headingView(level: Int, text: String) -> some View {
        let attr = attributedInline(text)
        switch level {
        case 1:
            Text(attr)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .padding(.top, 8)
                .padding(.bottom, 2)
        case 2:
            Text(attr)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .padding(.top, 6)
                .padding(.bottom, 1)
        case 3:
            Text(attr)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .padding(.top, 4)
        case 4:
            Text(attr)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        default:
            Text(attr)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
    }
}
