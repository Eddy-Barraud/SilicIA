import Foundation
import WebKit
import PDFKit
import Vision
import CoreGraphics

/// Re-implementation of SilicIA's "Web Vision" pipeline for benchmarking:
/// 1. Loads HTML in headless WKWebView (using file:// URL or loadHTMLString)
/// 2. Computes full-height content rect
/// 3. Renders full-height page to PDF via webView.createPDF(configuration:)
/// 4. Analyzes PDF pages using Apple Vision (layout-aware VNRecognizeTextRequest + VNClassifyImageRequest)
/// 5. Reconstructs reading order and formats tables to Markdown via RAG tabularization.
public final class WebVisionBenchmarkService: NSObject, @unchecked Sendable {
    public static let shared = WebVisionBenchmarkService()
    
    private static let viewport = CGSize(width: 1280, height: 960)
    private static let maxRenderedPages: CGFloat = 20.0
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
    
    public struct WebVisionResult {
        public let markdown: String
        public let pdfByteSize: Int
        public let pageCount: Int
        public let renderToPdfMs: Double
        public let visionOcrMs: Double
        public let totalMs: Double
    }
    
    @MainActor
    public func process(html: String, baseURL: URL, maxCharacters: Int = 100_000) async throws -> WebVisionResult {
        let totalStart = CFAbsoluteTimeGetCurrent()
        
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: CGRect(origin: .zero, size: Self.viewport), configuration: configuration)
        webView.customUserAgent = Self.userAgent
        
        let navDelegate = NavigationDelegate()
        webView.navigationDelegate = navDelegate
        
        // Load HTML string into WKWebView
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            navDelegate.continuation = continuation
            webView.loadHTMLString(html, baseURL: baseURL)
        }
        
        // Short settle time for DOM layout & styling (similar to SilicIA)
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        let pdfStart = CFAbsoluteTimeGetCurrent()
        // Compute content dimensions
        let contentRect = try await renderedContentRect(for: webView)
        let pdfData = try await createPDF(from: webView, rect: contentRect)
        let renderToPdfMs = (CFAbsoluteTimeGetCurrent() - pdfStart) * 1000.0
        
        // Write PDF to temp file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("webvision_\(UUID().uuidString)")
            .appendingPathExtension("pdf")
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        try pdfData.write(to: tempURL, options: .atomic)
        
        // Run Apple Vision OCR + Layout reconstruction
        let visionStart = CFAbsoluteTimeGetCurrent()
        let analyses = await extractPDFPageAnalyses(from: tempURL)
        let markdown = renderedPageText(from: analyses, maxCharacters: maxCharacters)
        let visionOcrMs = (CFAbsoluteTimeGetCurrent() - visionStart) * 1000.0
        
        let totalMs = (CFAbsoluteTimeGetCurrent() - totalStart) * 1000.0
        
        return WebVisionResult(
            markdown: markdown,
            pdfByteSize: pdfData.count,
            pageCount: analyses.count,
            renderToPdfMs: renderToPdfMs,
            visionOcrMs: visionOcrMs,
            totalMs: totalMs
        )
    }
    
    // MARK: - WKWebView Helpers
    
    @MainActor
    private func renderedContentRect(for webView: WKWebView) async throws -> CGRect {
        let script = """
        [
          Math.max(document.documentElement.scrollWidth, document.body ? document.body.scrollWidth : 0, window.innerWidth),
          Math.max(document.documentElement.scrollHeight, document.body ? document.body.scrollHeight : 0, window.innerHeight)
        ]
        """
        let raw = try await webView.evaluateJavaScript(script)
        guard let metrics = raw as? [NSNumber], metrics.count == 2 else {
            return CGRect(origin: .zero, size: Self.viewport)
        }
        return CGRect(
            origin: .zero,
            size: CGSize(
                width: max(CGFloat(truncating: metrics[0]), Self.viewport.width),
                height: min(
                    max(CGFloat(truncating: metrics[1]), Self.viewport.height),
                    Self.viewport.height * Self.maxRenderedPages
                )
            )
        )
    }
    
    @MainActor
    private func createPDF(from webView: WKWebView, rect: CGRect) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let configuration = WKPDFConfiguration()
            configuration.rect = rect
            webView.createPDF(configuration: configuration) { result in
                switch result {
                case .success(let data):
                    continuation.resume(returning: data)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private final class NavigationDelegate: NSObject, WKNavigationDelegate {
        var continuation: CheckedContinuation<Void, Error>?
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            continuation?.resume()
            continuation = nil
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
    
    // MARK: - Vision Analysis
    
    public struct PDFPageAnalysisResult: Sendable {
        public let recognizedText: String
        public let labels: [(label: String, confidence: Float)]
    }
    
    private struct LayoutObservation {
        let text: String
        let boundingBox: CGRect
    }
    
    private struct ArticleRowProjection {
        let left: String?
        let right: String?
    }
    
    @MainActor
    private func extractPDFPageAnalyses(from url: URL) async -> [PDFPageAnalysisResult] {
        guard let document = PDFDocument(url: url) else { return [] }
        let totalPages = document.pageCount
        guard totalPages > 0 else { return [] }
        
        var results: [PDFPageAnalysisResult] = []
        for pageIndex in 0..<totalPages {
            guard let page = document.page(at: pageIndex),
                  let cgImage = renderedCGImage(for: page) else {
                continue
            }
            if let analysis = analyzePDFPage(cgImage: cgImage) {
                results.append(analysis)
            }
        }
        return results
    }
    
    private func renderedCGImage(for page: PDFPage) -> CGImage? {
        let pageBounds = page.bounds(for: .mediaBox)
        let pageSize = pageBounds.size
        let nativeLonger = max(pageSize.width, pageSize.height)
        let targetLonger: CGFloat = 2500
        let maxLonger: CGFloat = 4096
        let scale = nativeLonger < targetLonger
            ? targetLonger / nativeLonger
            : (nativeLonger > maxLonger ? maxLonger / nativeLonger : 1)
        let targetSize = CGSize(
            width: max(1, pageSize.width * scale),
            height: max(1, pageSize.height * scale)
        )
        let image = page.thumbnail(of: targetSize, for: .mediaBox)
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
    
    private func analyzePDFPage(cgImage: CGImage) -> PDFPageAnalysisResult? {
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = false
        textRequest.recognitionLanguages = ["fr-FR", "en-US"]
        
        let classifyRequest = VNClassifyImageRequest()
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([textRequest, classifyRequest])
        
        let observations: [LayoutObservation] = (textRequest.results ?? []).compactMap { obs in
            guard let text = obs.topCandidates(1).first?.string.trimmingCharacters(in: .whitespaces),
                  !text.isEmpty else {
                return nil
            }
            return LayoutObservation(text: text, boundingBox: obs.boundingBox)
        }
        
        let recognizedText = reconstructLayout(from: observations)
        let labels = (classifyRequest.results ?? [])
            .filter { $0.confidence >= 0.15 }
            .prefix(8)
            .map { (label: $0.identifier, confidence: $0.confidence) }
        
        return PDFPageAnalysisResult(recognizedText: recognizedText, labels: labels)
    }
    
    private func reconstructLayout(from observations: [LayoutObservation]) -> String {
        guard !observations.isEmpty else { return "" }
        let topToBottom = observations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        let sortedHeights = topToBottom.map { $0.boundingBox.height }.sorted()
        let medianHeight = sortedHeights[sortedHeights.count / 2]
        let rowTolerance = max(medianHeight * 0.6, 0.005)
        
        var rows: [[LayoutObservation]] = []
        for obs in topToBottom {
            let y = obs.boundingBox.midY
            if var last = rows.last,
               let referenceY = last.first.map({ $0.boundingBox.midY }),
               abs(y - referenceY) <= rowTolerance {
                last.append(obs)
                rows[rows.count - 1] = last
            } else {
                rows.append([obs])
            }
        }
        
        var lines: [String] = []
        for row in rows {
            let leftToRight = row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            let cells = leftToRight.map { $0.text }.filter { !$0.isEmpty }
            guard !cells.isEmpty else { continue }
            lines.append(cells.joined(separator: "    "))
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func renderedPageText(from analyses: [PDFPageAnalysisResult], maxCharacters: Int) -> String {
        var sections: [String] = []
        for (pageIndex, analysis) in analyses.enumerated() {
            var pageSections: [String] = []
            let recognizedText = analysis.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !recognizedText.isEmpty {
                pageSections.append(recognizedText)
            }
            if !analysis.labels.isEmpty {
                let labelText = analysis.labels
                    .map { String(format: "%@ (%.2f)", $0.label, $0.confidence) }
                    .joined(separator: ", ")
                pageSections.append("Visual content: \(labelText)")
            }
            guard !pageSections.isEmpty else { continue }
            sections.append("## [Rendered Page \(pageIndex + 1)]\n\n" + pageSections.joined(separator: "\n\n"))
        }
        
        var text = convertWhitespaceAlignedTables(sections.joined(separator: "\n\n"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > maxCharacters {
            text = String(text.prefix(maxCharacters))
        }
        return text
    }
    
    // MARK: - Table Conversion
    
    private func convertWhitespaceAlignedTables(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var output: [String] = []
        var pending: [[String]] = []
        
        func flushTable() {
            guard !pending.isEmpty else { return }
            if pending.count >= 2,
               let maxCount = pending.map(\.count).max(),
               maxCount >= 3 {
                var counts: [Int: Int] = [:]
                for row in pending { counts[row.count, default: 0] += 1 }
                let columnCount = counts
                    .filter { $0.key >= 3 }
                    .max { a, b in a.value == b.value ? a.key > b.key : a.value < b.value }?.key ?? maxCount
                let normalized = pending.map { row -> [String] in
                    if row.count == columnCount {
                        return row
                    } else if row.count < columnCount {
                        return row + Array(repeating: "", count: columnCount - row.count)
                    } else {
                        let head = Array(row.prefix(columnCount - 1))
                        let tail = row.dropFirst(columnCount - 1).joined(separator: " ")
                        return head + [tail]
                    }
                }
                output.append("| " + normalized[0].joined(separator: " | ") + " |")
                output.append("|" + String(repeating: " --- |", count: columnCount))
                for row in normalized.dropFirst() {
                    output.append("| " + row.joined(separator: " | ") + " |")
                }
            } else {
                for row in pending {
                    output.append(row.joined(separator: " "))
                }
            }
            pending = []
        }
        
        for line in lines {
            let cells = splitTabularLine(line)
            if cells.count >= 3 {
                pending.append(cells)
            } else {
                flushTable()
                output.append(line)
            }
        }
        flushTable()
        return output.joined(separator: "\n")
    }
    
    private func splitTabularLine(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return [] }
        var cells: [String] = []
        var current = ""
        var spaceRun = 0
        var inLeading = true
        let separators: Set<Character> = [" ", "\t", "\u{00A0}"]
        for char in line {
            if separators.contains(char) {
                if !inLeading { spaceRun += 1 }
            } else {
                if spaceRun >= 2, !current.isEmpty {
                    cells.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                } else if spaceRun >= 1, !current.isEmpty {
                    current.append(" ")
                }
                current.append(char)
                spaceRun = 0
                inLeading = false
            }
        }
        if !current.isEmpty {
            cells.append(current.trimmingCharacters(in: .whitespaces))
        }
        return cells.filter { !$0.isEmpty }
    }
}
