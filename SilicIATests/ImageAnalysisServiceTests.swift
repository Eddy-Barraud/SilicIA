import XCTest
import CoreGraphics
import PDFKit
import Vision
#if os(macOS)
import AppKit
#endif
@testable import SilicIA

final class ImageAnalysisServiceTests: XCTestCase {

    func testTwoColumnArticleBlockReadsLeftColumnThenRightColumn() {
        let observations: [LayoutObservation] = [
            LayoutObservation(
                text: "Left column line one contains enough prose to look like a journal sentence.",
                boundingBox: CGRect(x: 0.08, y: 0.80, width: 0.34, height: 0.03)
            ),
            LayoutObservation(
                text: "Right column line one also contains enough prose to be treated as article text.",
                boundingBox: CGRect(x: 0.58, y: 0.80, width: 0.32, height: 0.03)
            ),
            LayoutObservation(
                text: "Left column line two continues the left-hand narrative before the right side starts.",
                boundingBox: CGRect(x: 0.08, y: 0.74, width: 0.34, height: 0.03)
            ),
            LayoutObservation(
                text: "Right column line two should only appear after the full left column has been emitted.",
                boundingBox: CGRect(x: 0.58, y: 0.74, width: 0.32, height: 0.03)
            )
        ]

        let text = ImageAnalysisService.reconstructLayout(from: observations)

        XCTAssertTrue(
            text.contains(
                """
                Left column line one contains enough prose to look like a journal sentence. Left column line two continues the left-hand narrative before the right side starts.

                Right column line one also contains enough prose to be treated as article text. Right column line two should only appear after the full left column has been emitted.
                """
            ),
            "Two-column article block was not rendered column-major:\n\(text)"
        )
    }

    func testTabularRowsStayRowMajor() {
        let observations: [LayoutObservation] = [
            LayoutObservation(text: "Description", boundingBox: CGRect(x: 0.08, y: 0.80, width: 0.22, height: 0.03)),
            LayoutObservation(text: "Qty", boundingBox: CGRect(x: 0.42, y: 0.80, width: 0.08, height: 0.03)),
            LayoutObservation(text: "Price", boundingBox: CGRect(x: 0.62, y: 0.80, width: 0.10, height: 0.03)),
            LayoutObservation(text: "Amortisseurs", boundingBox: CGRect(x: 0.08, y: 0.74, width: 0.22, height: 0.03)),
            LayoutObservation(text: "2", boundingBox: CGRect(x: 0.42, y: 0.74, width: 0.04, height: 0.03)),
            LayoutObservation(text: "154,17", boundingBox: CGRect(x: 0.62, y: 0.74, width: 0.10, height: 0.03))
        ]

        let text = ImageAnalysisService.reconstructLayout(from: observations)

        XCTAssertTrue(
            text.contains("Description    Qty    Price\nAmortisseurs    2    154,17"),
            "Table-like rows should stay row-major:\n\(text)"
        )
    }

    func testFixturePDFContainsExpectedTwoColumnSentences() {
        let pdfURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("2025.PFAS.CMC.page.3.pdf")

        guard let document = PDFDocument(url: pdfURL),
              let page = document.page(at: 0),
              let cgImage = renderedTestCGImage(for: page),
              let analysis = ImageAnalysisService.analyzePDFPage(cgImage: cgImage) else {
            return XCTFail("Failed to analyze fixture PDF at \(pdfURL.path)")
        }

        let normalizedOutput = normalizeForComparison(analysis.recognizedText)
        XCTAssertTrue(
            normalizedOutput.contains(
                normalizeForComparison("Thermodynamically, the CMC manifests as a distinct change in the slope of the osmotic pressure or chemical potential with increasing surfactant concentration.")
            ),
            "Expected the thermodynamics sentence to survive two-column OCR ordering.\nOCR output:\n\(analysis.recognizedText)"
        )
        XCTAssertTrue(
            normalizedOutput.contains(
                normalizeForComparison("In the absence of alternative information for initializing the optimization of ion−water interactions, Nieto-Draghi et al.43 proposed that partial osmotic pressures could be used as initial values.")
            ),
            "Expected the ion-water sentence to survive two-column OCR ordering.\nOCR output:\n\(analysis.recognizedText)"
        )
    }

    private func renderedTestCGImage(for page: PDFPage) -> CGImage? {
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

    private func normalizeForComparison(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{2212}", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
