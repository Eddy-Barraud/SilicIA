import XCTest
import CoreGraphics
import PDFKit
#if os(macOS)
import AppKit
#endif
@testable import SilicIA

final class RAGPDFRankingTests: XCTestCase {

    /// Tests that RAG context ranking correctly prefers the exact equation page,
    /// figure caption page, or explicitly requested page from a real PDF document.
    /// Runs a single OCR pass over the fixture to keep test execution fast.
    func testPDFContextRankingForEquationsAndFigures() async {
        let chunks = makeFixtureChunks()
        guard !chunks.isEmpty else {
            return XCTFail("Fixture PDF chunks could not be loaded")
        }
        let service = RAGContextService()

        // 1. Equation 5 lookup prefers page 6
        let eqResult = await service.selectContext(chunks: chunks, query: "explain equation 5", maxOutputTokens: 1024)
        guard let eqBest = eqResult.rankedChunks.first else {
            return XCTFail("No ranked chunks produced for equation-5 query")
        }
        XCTAssertEqual(eqBest.chunk.pdfPage, 6, "Equation 5 query should select page 6")
        let eqText = normalizeForComparison(eqBest.chunk.text)
        XCTAssertTrue(eqText.contains(normalizeForComparison("relationship of eq 5 for ionic surfactants")))
        XCTAssertTrue(eqText.contains("BCion") || eqText.contains("BC_ion"))

        // 2. Figure 5 lookup prefers page 7
        let figResult = await service.selectContext(chunks: chunks, query: "describe figure 5", maxOutputTokens: 1024)
        guard let figBest = figResult.rankedChunks.first else {
            return XCTFail("No ranked chunks produced for figure-5 query")
        }
        XCTAssertEqual(figBest.chunk.pdfPage, 7, "Figure 5 query should select page 7")
        let figText = normalizeForComparison(figBest.chunk.text)
        XCTAssertTrue(
            figText.contains(normalizeForComparison("Chain length dependence of CMC values")) &&
            figText.contains(normalizeForComparison("logarithmic trend of the CMC with chain length")),
            "figText was: \(figText)"
        )

        // 3. Explicit page 8 request prefers page 8
        let pageResult = await service.selectContext(chunks: chunks, query: "describe figure on page 8", maxOutputTokens: 1024)
        guard let pageBest = pageResult.rankedChunks.first else {
            return XCTFail("No ranked chunks produced for page-8 query")
        }
        XCTAssertEqual(pageBest.chunk.pdfPage, 8, "Explicit page 8 request should select page 8")
        let pageText = normalizeForComparison(pageBest.chunk.text)
        XCTAssertTrue(pageText.contains(normalizeForComparison("Figure S6-34")))
    }

    private func makeFixtureChunks() -> [RAGChunk] {
        let pdfURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("2025.PFAS.CMC.pdf")

        guard let document = PDFDocument(url: pdfURL) else {
            XCTFail("Failed to load fixture PDF at \(pdfURL.path)")
            return []
        }

        var chunks: [RAGChunk] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex),
                  let cgImage = renderedTestCGImage(for: page),
                  let analysis = ImageAnalysisService.analyzePDFPage(cgImage: cgImage) else {
                XCTFail("Failed to analyze page \(pageIndex + 1) of \(pdfURL.lastPathComponent)")
                return []
            }

            chunks.append(
                RAGChunk(
                    source: "PDF: \(pdfURL.lastPathComponent) page \(pageIndex + 1)",
                    text: analysis.recognizedText,
                    url: nil,
                    pdfPage: pageIndex + 1
                )
            )
        }
        return chunks
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
