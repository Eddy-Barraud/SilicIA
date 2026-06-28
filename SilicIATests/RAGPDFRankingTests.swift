import XCTest
import CoreGraphics
import PDFKit
#if os(macOS)
import AppKit
#endif
@testable import SilicIA

final class RAGPDFRankingTests: XCTestCase {

    func testExplainEquation5PrefersPage6OfFullArticle() async {
        let result = await rankingResult(for: "explain equation 5")
        guard let best = result?.rankedChunks.first else {
            return XCTFail("No ranked chunks produced for full-article query")
        }

        XCTAssertEqual(best.chunk.pdfPage, 6,
                       "Query should select page 6, got page \(String(describing: best.chunk.pdfPage)) with score \(best.relevanceScore)")
        let normalized = normalizeForComparison(best.chunk.text)
        XCTAssertTrue(
            normalized.contains(normalizeForComparison("relationship of eq 5 for ionic surfactants")),
            "Top-ranked page did not contain the expected equation-5 reference.\nTop page text:\n\(best.chunk.text)"
        )
        XCTAssertTrue(
            normalized.contains("BCion") || normalized.contains("BC_ion"),
            "Top-ranked page did not contain the expected eq-5 formula line.\nTop page text:\n\(best.chunk.text)"
        )
    }

    func testDescribeFigure5PrefersFigure5Page() async {
        let result = await rankingResult(for: "describe figure 5")
        guard let best = result?.rankedChunks.first else {
            return XCTFail("No ranked chunks produced for figure-5 query")
        }

        XCTAssertEqual(best.chunk.pdfPage, 7,
                       "Query should select the PDF page that contains Figure 5, got page \(String(describing: best.chunk.pdfPage)) with score \(best.relevanceScore)")
        let normalized = normalizeForComparison(best.chunk.text)
        XCTAssertTrue(
            normalized.contains(normalizeForComparison("Figure 5. Chain length dependence of CMC values")),
            "Top-ranked page did not contain the expected Figure 5 caption.\nTop page text:\n\(best.chunk.text)"
        )
        XCTAssertTrue(
            normalized.contains(normalizeForComparison("logarithmic trend of the CMC with chain length")),
            "Top-ranked page did not contain the expected Figure 5 discussion.\nTop page text:\n\(best.chunk.text)"
        )
    }

    func testDescribeFigureOnPage8PrefersPage8() async {
        let result = await rankingResult(for: "describe figure on page 8")
        guard let best = result?.rankedChunks.first else {
            return XCTFail("No ranked chunks produced for page-8 figure query")
        }

        XCTAssertEqual(best.chunk.pdfPage, 8,
                       "Query should select PDF page 8 when the page is explicit, got page \(String(describing: best.chunk.pdfPage)) with score \(best.relevanceScore)")
        let normalized = normalizeForComparison(best.chunk.text)
        XCTAssertTrue(
            normalized.contains(normalizeForComparison("Figure S6-34")),
            "Top-ranked page did not contain the expected figure cue from page 8.\nTop page text:\n\(best.chunk.text)"
        )
    }

    private func rankingResult(for query: String) async -> RAGSelectionResult? {
        let chunks = makeFixtureChunks()
        guard !chunks.isEmpty else { return nil }
        return await RAGContextService().selectContext(
            chunks: chunks,
            query: query,
            maxOutputTokens: 1024
        )
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
