//
//  ImageAnalysisService.swift
//  SilicIA
//
//  Created by Eddy Barraud on 06/05/2026.
//

import Foundation
import Vision
import CoreGraphics
import ImageIO
import PDFKit

/// Result of analyzing a single image with Apple Vision: OCR text and
/// classification labels with confidence scores. Either field may be empty;
/// callers should treat a fully empty result as "nothing useful was extracted".
struct ImageAnalysisResult {
    let recognizedText: String
    let labels: [(label: String, confidence: Float)]

    var isEmpty: Bool {
        recognizedText.isEmpty && labels.isEmpty
    }
}

struct LayoutObservation {
    let text: String
    let boundingBox: CGRect
}

/// On-device image analysis using Apple's Vision framework.
///
/// Two Vision requests are run on every image:
/// - `VNRecognizeTextRequest` for OCR (also reused by the PDF page analyzer)
/// - `VNClassifyImageRequest` for high-level content labels (cat, beach, …)
///
/// Everything happens locally on the device; no network calls.
enum ImageAnalysisService {
    /// OCR recognition languages. Used by image OCR, the PDF page analyzer,
    /// and the layout-aware OCR path.
    static let defaultRecognitionLanguages: [String] = ["fr-FR", "en-US"]

    /// Minimum confidence for a classification label to be kept.
    private static let classificationConfidenceThreshold: Float = 0.15

    /// Maximum number of classification labels returned in the result.
    private static let maxClassificationLabels = 8

    private struct ArticleRowProjection {
        let left: String?
        let right: String?
    }

    /// Runs OCR + classification on the image at `url`. Returns `nil` if the
    /// file cannot be decoded as an image at all.
    static func analyze(imageAt url: URL) async -> ImageAnalysisResult? {
        guard let cgImage = loadCGImage(at: url) else {
            #if DEBUG
            print("[ImageAnalysisService] Could not load CGImage at \(url.path)")
            #endif
            return nil
        }

        let textRequest = makeTextRequest(languages: defaultRecognitionLanguages)
        let classifyRequest = VNClassifyImageRequest()

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([textRequest, classifyRequest])
        } catch {
            #if DEBUG
            print("[ImageAnalysisService] Vision request failed: \(error.localizedDescription)")
            #endif
            // Return whatever partial result is available; both requests may
            // still have populated their `results` even if one failed.
        }

        let recognizedText = extractRecognizedText(from: textRequest)
        let labels = extractTopLabels(from: classifyRequest)

        return ImageAnalysisResult(recognizedText: recognizedText, labels: labels)
    }

    /// Runs OCR on `cgImage` and reconstructs the **visual reading order** by
    /// grouping each `VNRecognizedTextObservation` into rows by its `.boundingBox`
    /// Y-coordinate, then sorting within each row by X-coordinate. Cells inside
    /// a row are separated by 4 spaces so the downstream pipeline's
    /// `RAGChunker.convertWhitespaceAlignedTables` can detect the table and
    /// emit a Markdown pipe block.
    ///
    /// This is the antidote to PDFKit's `page.string` returning column-major
    /// dumps (all descriptions → all quantities → all prices), which happens
    /// when an invoice/quote PDF stores text in column-major drawing order.
    /// Vision's bounding boxes always reflect the *visual* layout, not the
    /// drawing order, so rows recombine correctly here.
    ///
    /// Returns `nil` when Vision fails or produces no observations.
    static func recognizeTextWithLayout(
        in cgImage: CGImage,
        languages: [String] = defaultRecognitionLanguages
    ) -> String? {
        let request = makeTextRequest(languages: languages)
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            #if DEBUG
            print("[ImageAnalysisService] OCR-with-layout request failed: \(error.localizedDescription)")
            #endif
            return nil
        }
        let text = reconstructLayout(from: request)
        return text.isEmpty ? nil : text
    }

    /// Reconstructs the **visual reading order** from a populated
    /// `VNRecognizeTextRequest`. Groups each `VNRecognizedTextObservation`
    /// into rows by its `.boundingBox` Y-coordinate, then renders either:
    /// - row-major (tables, invoices, forms), or
    /// - column-major for consecutive 2-column prose blocks (journal papers),
    ///   so the text reads left-column top→bottom, then right-column top→bottom.
    ///
    /// Vision's bounding boxes always reflect the *visual* layout, not the
    /// PDF's drawing order, so rows recombine correctly even for column-major
    /// invoice/quote PDFs where PDFKit's `page.string` returns
    /// "all descriptions → all quantities → all prices".
    ///
    /// Returns an empty string when the request produced no observations.
    private static func reconstructLayout(from request: VNRecognizeTextRequest) -> String {
        let observations: [LayoutObservation] = (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string.trimmingCharacters(in: .whitespaces),
                  !text.isEmpty else {
                return nil
            }
            return LayoutObservation(text: text, boundingBox: observation.boundingBox)
        }
        return reconstructLayout(from: observations)
    }

    /// Shared reading-order reconstruction used by Vision-backed OCR and unit
    /// tests. Input observations are assumed to be Vision-normalized page
    /// coordinates (`boundingBox` in [0,1] with origin at bottom-left).
    static func reconstructLayout(from observations: [LayoutObservation]) -> String {
        guard !observations.isEmpty else {
            return ""
        }

        // Sort top-to-bottom. Vision coordinates: origin is bottom-left,
        // so higher midY = higher up on the page.
        let topToBottom = observations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }

        // Compute a page-wide median observation height as the row-grouping
        // tolerance. Using each observation's own height is unstable:
        //  - Subscripts/superscripts in equations have very small bounding
        //    boxes (height ≈ 0.008) — their halfHeight is far too tight,
        //    causing them to form spurious new rows instead of joining the
        //    main text row they belong to.
        //  - Large chapter titles have tall boxes — their halfHeight is so
        //    loose it can pull in text from adjacent rows.
        // The page-wide median is a stable proxy for body-text line height
        // and scales correctly from footnote-dense pages to poster-sized PDFs.
        let sortedHeights = topToBottom.map { $0.boundingBox.height }.sorted()
        let medianHeight = sortedHeights[sortedHeights.count / 2]
        // 60% of median line height as grouping window — tight enough to
        // separate adjacent text lines while wide enough to absorb the
        // vertical jitter of subscript/superscript observations.
        let rowTolerance = medianHeight * 0.6

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

        // Render row-major by default, but when a run of rows looks like
        // article prose in two columns, switch that run to column-major
        // reading order. This avoids "line 1 left, line 1 right, line 2 left,
        // line 2 right" interleaving on scientific PDFs, while still keeping
        // tables row-wise so columns survive.
        var lines: [String] = []
        var pendingArticleRows: [ArticleRowProjection] = []

        func flushArticleBlock() {
            guard !pendingArticleRows.isEmpty else { return }
            let leftColumn = pendingArticleRows.compactMap(\.left)
            let rightColumn = pendingArticleRows.compactMap(\.right)
            if pendingArticleRows.count >= 2 && !leftColumn.isEmpty && !rightColumn.isEmpty {
                lines.append(reflowProseLines(leftColumn))
                if !rightColumn.isEmpty {
                    lines.append("")
                    lines.append(reflowProseLines(rightColumn))
                }
            } else {
                for row in pendingArticleRows {
                    let cells = [row.left, row.right].compactMap { $0 }
                    guard !cells.isEmpty else { continue }
                    lines.append(cells.joined(separator: "    "))
                }
            }
            pendingArticleRows.removeAll(keepingCapacity: true)
        }

        for row in rows {
            let leftToRight = row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            if let projection = articleRowProjection(from: leftToRight) {
                pendingArticleRows.append(projection)
                continue
            }

            flushArticleBlock()
            let cells = leftToRight.map { $0.text }.filter { !$0.isEmpty }
            guard !cells.isEmpty else { continue }
            lines.append(cells.joined(separator: "    "))
        }
        flushArticleBlock()

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Projects a Vision row onto left/right article columns when it looks
    /// like two-column prose rather than a table. Rows with observations
    /// outside the left/right text bands are rejected so table/header lines
    /// stay row-major.
    private static func articleRowProjection(from row: [LayoutObservation]) -> ArticleRowProjection? {
        guard !row.isEmpty else { return nil }

        var left: [LayoutObservation] = []
        var right: [LayoutObservation] = []

        for observation in row {
            if observation.boundingBox.width > 0.55 {
                return nil
            } else if observation.boundingBox.minX < 0.24 && observation.boundingBox.maxX <= 0.50 {
                left.append(observation)
            } else if observation.boundingBox.minX >= 0.45 {
                right.append(observation)
            } else {
                return nil
            }
        }

        let leftText = left.sorted { $0.boundingBox.minX < $1.boundingBox.minX }.map(\.text).joined(separator: " ")
        let rightText = right.sorted { $0.boundingBox.minX < $1.boundingBox.minX }.map(\.text).joined(separator: " ")

        let leftValue = leftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rightValue = rightText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard leftValue.count >= 18 || rightValue.count >= 18 else { return nil }
        return ArticleRowProjection(
            left: leftValue.isEmpty ? nil : leftValue,
            right: rightValue.isEmpty ? nil : rightValue
        )
    }

    private static func reflowProseLines(_ lines: [String]) -> String {
        var result = ""
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if result.isEmpty {
                result = trimmed
            } else if result.hasSuffix("-") {
                result.removeLast()
                result += trimmed
            } else {
                result += " " + trimmed
            }
        }
        return result
    }

    /// Runs OCR on an already-decoded `CGImage`. Returns the recognized text or
    /// `nil` if Vision threw or produced an empty result.
    ///
    /// This is the shared OCR primitive used by image attachments.
    static func recognizeText(in cgImage: CGImage, languages: [String] = defaultRecognitionLanguages) -> String? {
        let request = makeTextRequest(languages: languages)
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            #if DEBUG
            print("[ImageAnalysisService] OCR request failed: \(error.localizedDescription)")
            #endif
            return nil
        }
        let text = extractRecognizedText(from: request)
        return text.isEmpty ? nil : text
    }

    /// Result of analyzing a single PDF page with Vision. Combines
    /// layout-aware OCR text (rows recombined in visual reading order so
    /// tables survive) with high-level image classification labels that
    /// describe charts, diagrams, photos, and scanned content the OCR
    /// pass can't see. Either field may be empty; callers should treat a
    /// fully empty result as "nothing useful was extracted".
    struct PDFPageAnalysisResult: Sendable {
        let recognizedText: String
        let labels: [(label: String, confidence: Float)]

        var isEmpty: Bool {
            recognizedText.isEmpty && labels.isEmpty
        }
    }

    /// Analyzes a single rendered PDF page with the Vision framework.
    ///
    /// This is the primary PDF RAG extraction primitive: every page is
    /// rendered to a `CGImage` and run through both
    /// - `VNRecognizeTextRequest` (layout-aware OCR — rows recombined by
    ///   bounding-box Y so tables, invoices, and equations survive intact),
    ///   and
    /// - `VNClassifyImageRequest` (high-level content labels — "chart",
    ///   "diagram", "table", "screenshot", …) so the model gets a hint
    ///   about non-textual content (a plot, a figure, a scanned photo)
    ///   that OCR alone can't describe.
    ///
    /// Replaces the previous PDFKit `page.string` extraction path, which:
    /// - returned text in the PDF's *drawing order* (column-major dumps
    ///   for many invoice templates — all descriptions, then all
    ///   quantities, then all prices),
    /// - silently dropped equations and figures,
    /// - and needed a fragile `looksColumnMajor` heuristic to decide when
    ///   to fall back to OCR.
    ///
    /// Vision sees the page's *visual* layout, so rows recombine correctly
    /// regardless of how the PDF stores its text, and the classification
    /// pass surfaces image content the model would otherwise never see.
    ///
    /// - Parameter cgImage: A rendered raster of the PDF page.
    /// - Parameter languages: OCR recognition languages. Defaults to
    ///   `defaultRecognitionLanguages`.
    /// - Returns: `nil` if Vision can't decode the image at all.
    static func analyzePDFPage(
        cgImage: CGImage,
        languages: [String] = defaultRecognitionLanguages
    ) -> PDFPageAnalysisResult? {
        let textRequest = makeTextRequest(languages: languages)
        let classifyRequest = VNClassifyImageRequest()

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([textRequest, classifyRequest])
        } catch {
            #if DEBUG
            print("[ImageAnalysisService] PDF page Vision request failed: \(error.localizedDescription)")
            #endif
            // Return whatever partial result is available; both requests may
            // still have populated their `results` even if one failed.
        }

        let recognizedText = reconstructLayout(from: textRequest)
        let labels = extractTopLabels(from: classifyRequest)

        let result = PDFPageAnalysisResult(recognizedText: recognizedText, labels: labels)
        return result.isEmpty ? nil : result
    }

    /// Extracts a Vision analysis (layout-aware OCR text + image
    /// classification labels) for every page of a PDF file URL.
    static func extractPDFPageAnalyses(
        from url: URL,
        progress: (@MainActor @Sendable (_ completedPages: Int, _ totalPages: Int) -> Void)? = nil
    ) async -> [PDFPageAnalysisResult] {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let document = PDFDocument(url: url) else {
            #if DEBUG
            print("[ImageAnalysisService] Failed to open PDF at \(url.path)")
            #endif
            return []
        }

        if document.isLocked, document.unlock(withPassword: "") {
            #if DEBUG
            print("[ImageAnalysisService] Unlocked a PDF with empty password")
            #endif
        }

        let totalPages = document.pageCount
        guard totalPages > 0 else { return [] }

        let workerCount = min(totalPages, max(1, min(ProcessInfo.processInfo.activeProcessorCount, 4)))
        let empty = PDFPageAnalysisResult(recognizedText: "", labels: [])
        var analyses = Array(repeating: empty, count: totalPages)
        var nextPageIndex = workerCount
        var completedPages = 0

        await withTaskGroup(of: (Int, PDFPageAnalysisResult).self) { group in
            for pageIndex in 0..<workerCount {
                group.addTask {
                    (pageIndex, Self.analyzePDFPage(at: pageIndex, in: url) ?? empty)
                }
            }

            while let (pageIndex, analysis) = await group.next() {
                analyses[pageIndex] = analysis
                completedPages += 1
                if let progress {
                    await progress(completedPages, totalPages)
                }

                if nextPageIndex < totalPages, !Task.isCancelled {
                    let scheduledPageIndex = nextPageIndex
                    nextPageIndex += 1
                    group.addTask {
                        (scheduledPageIndex, Self.analyzePDFPage(at: scheduledPageIndex, in: url) ?? empty)
                    }
                }
            }
        }

        #if DEBUG
        let analyzedPageCount = analyses.filter { !$0.isEmpty }.count
        print("[ImageAnalysisService] extractPDFPageAnalyses pdf=\(url.lastPathComponent) pages=\(totalPages) analyzed=\(analyzedPageCount)")
        #endif
        return analyses
    }

    // MARK: - Helpers

    private static func makeTextRequest(languages: [String]) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = languages
        return request
    }

    private static func extractRecognizedText(from request: VNRecognizeTextRequest) -> String {
        (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractTopLabels(from request: VNClassifyImageRequest) -> [(label: String, confidence: Float)] {
        let observations = request.results ?? []
        return observations
            .filter { $0.confidence >= classificationConfidenceThreshold }
            .prefix(maxClassificationLabels)
            .map { (label: $0.identifier, confidence: $0.confidence) }
    }

    private static func analyzePDFPage(at pageIndex: Int, in url: URL) -> PDFPageAnalysisResult? {
        guard !Task.isCancelled,
              let document = PDFDocument(url: url),
              let page = document.page(at: pageIndex),
              let cgImage = renderedCGImage(for: page),
              let analysis = analyzePDFPage(cgImage: cgImage) else {
            return nil
        }
        return analysis
    }

    /// Renders `page` to a `CGImage` at approximately 300 DPI for Vision.
    private static func renderedCGImage(for page: PDFPage) -> CGImage? {
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
        #if os(macOS)
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        return image.cgImage
        #endif
    }

    /// Loads a `CGImage` from disk using ImageIO. Works on both macOS and iOS
    /// without pulling in `NSImage` / `UIImage`.
    private static func loadCGImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
