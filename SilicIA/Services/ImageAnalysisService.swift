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
    /// into rows by its `.boundingBox` Y-coordinate, then sorts within each
    /// row by X-coordinate. Cells inside a row are separated by 4 spaces so
    /// the downstream pipeline's `RAGChunker.convertWhitespaceAlignedTables`
    /// can detect the table and emit a Markdown pipe block.
    ///
    /// Vision's bounding boxes always reflect the *visual* layout, not the
    /// PDF's drawing order, so rows recombine correctly even for column-major
    /// invoice/quote PDFs where PDFKit's `page.string` returns
    /// "all descriptions → all quantities → all prices".
    ///
    /// Returns an empty string when the request produced no observations.
    private static func reconstructLayout(from request: VNRecognizeTextRequest) -> String {
        guard let observations = request.results, !observations.isEmpty else {
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

        var rows: [[VNRecognizedTextObservation]] = []
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

        // Within each row, sort left-to-right and join by 4 spaces. The
        // wide separator survives into the chunker pipeline and triggers
        // `convertWhitespaceAlignedTables` to emit a Markdown pipe row.
        let lines: [String] = rows.compactMap { row in
            let leftToRight = row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            let cells = leftToRight.compactMap { $0.topCandidates(1).first?.string }
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !cells.isEmpty else { return nil }
            return cells.joined(separator: "    ")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
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
    struct PDFPageAnalysisResult {
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

    // MARK: - Helpers

    private static func makeTextRequest(languages: [String]) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
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

    /// Loads a `CGImage` from disk using ImageIO. Works on both macOS and iOS
    /// without pulling in `NSImage` / `UIImage`.
    private static func loadCGImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
