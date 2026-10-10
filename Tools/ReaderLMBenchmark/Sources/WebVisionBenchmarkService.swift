import Foundation
import WebKit
import PDFKit
import Vision
import CoreGraphics

/// Re-implementation of SilicIA's "Web Vision" pipeline for benchmarking:
/// 1. Loads HTML in headless WKWebView with a 1080x1920 pt viewport
/// 2. Slices up to 1 page only (CGRect(0, 0, 1080, 1920))
/// 3. Renders high-fidelity PDF and saves to disk
/// 4. Analyzes the PDF page using Apple Vision at 300 DPI (VNRecognizeTextRequest + VNClassifyImageRequest)
/// 5. Reconstructs layout and converts tables to Markdown.
public final class WebVisionBenchmarkService: NSObject, @unchecked Sendable {
    public static let shared = WebVisionBenchmarkService()
    
    /// Viewport dimensions in points (1080 x 1920 pt) for high-density capture
    public static let viewport = CGSize(width: 1200, height: 2000)
    public static let maxPages: Int = 1
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
    
    public struct WebVisionResult {
        public let markdown: String
        public let pdfData: Data
        public let pdfByteSize: Int
        public let pageCount: Int
        public let renderToPdfMs: Double
        public let visionOcrMs: Double
        public let totalMs: Double
    }
    
    /// Pre-warms Apple Vision models (ANE/CoreML) so benchmark measurements don't include first-run framework compilation.
    public static func warmup() {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: 64,
            height: 64,
            bitsPerComponent: 8,
            bytesPerRow: 64 * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let dummyCG = context.makeImage() else { return }

        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        let classifyRequest = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: dummyCG, options: [:])
        try? handler.perform([textRequest, classifyRequest])
    }
    
    @MainActor
    public func process(html: String, baseURL: URL, maxCharacters: Int = 100_000) async throws -> WebVisionResult {
        let totalStart = CFAbsoluteTimeGetCurrent()
        
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webpagePreferences = WKWebpagePreferences()
        webpagePreferences.allowsContentJavaScript = false
        configuration.defaultWebpagePreferences = webpagePreferences
        
        let webView = WKWebView(frame: CGRect(origin: .zero, size: Self.viewport), configuration: configuration)
        webView.customUserAgent = Self.userAgent
        
        let navDelegate = NavigationDelegate()
        webView.navigationDelegate = navDelegate
        
        // Load HTML string into WKWebView
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            navDelegate.continuation = continuation
            webView.loadHTMLString(html, baseURL: baseURL)
        }
        
        // Short settle time for DOM layout & styling (200ms without JS overhead)
        try await Task.sleep(nanoseconds: 200_000_000)
        
        let pdfStart = CFAbsoluteTimeGetCurrent()
        // Generate single-page 1080x1920 slice PDF
        let pdfData = try await createRenderedPDF(from: webView)
        let renderToPdfMs = (CFAbsoluteTimeGetCurrent() - pdfStart) * 1000.0
        
        // Write PDF to temp file for Vision analysis
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
            pdfData: pdfData,
            pdfByteSize: pdfData.count,
            pageCount: analyses.count,
            renderToPdfMs: renderToPdfMs,
            visionOcrMs: visionOcrMs,
            totalMs: totalMs
        )
    }
    
    // MARK: - WKWebView PDF Generation (1080x1920 Single Page Slice)
    
    @MainActor
    private func createRenderedPDF(from webView: WKWebView) async throws -> Data {
        let script = """
        Math.max(document.documentElement.scrollHeight, document.body ? document.body.scrollHeight : 0, window.innerHeight)
        """
        let raw = try await webView.evaluateJavaScript(script)
        let totalHeight: CGFloat
        if let num = raw as? NSNumber {
            totalHeight = CGFloat(truncating: num)
        } else {
            totalHeight = Self.viewport.height
        }
        
        let sliceWidth = Self.viewport.width
        let sliceHeight = Self.viewport.height
        let totalPages = max(1, min(Int(ceil(totalHeight / sliceHeight)), Self.maxPages))
        
        let masterDoc = PDFDocument()
        for pageIndex in 0..<totalPages {
            let pageY = CGFloat(pageIndex) * sliceHeight
            let sliceRect = CGRect(x: 0, y: pageY, width: sliceWidth, height: sliceHeight)
            let config = WKPDFConfiguration()
            config.rect = sliceRect
            
            let sliceData: Data = try await withCheckedThrowingContinuation { continuation in
                webView.createPDF(configuration: config) { result in
                    switch result {
                    case .success(let data):
                        continuation.resume(returning: data)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            if let sliceDoc = PDFDocument(data: sliceData), let page = sliceDoc.page(at: 0) {
                masterDoc.insert(page, at: masterDoc.pageCount)
            }
        }
        
        guard let combinedData = masterDoc.dataRepresentation() else {
            throw NSError(domain: "WebVisionBenchmark", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to generate PDF data representation"])
        }
        return combinedData
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
        // 150 DPI for high-efficiency Vision OCR (150 / 72 ≈ 2.083x)
        let dpiScale: CGFloat = 100.0 / 72.0
        let targetSize = CGSize(
            width: max(1, pageSize.width * dpiScale),
            height: max(1, pageSize.height * dpiScale)
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
