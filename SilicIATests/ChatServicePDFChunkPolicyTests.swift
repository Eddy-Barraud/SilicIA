import XCTest
@testable import SilicIA

final class ChatServicePDFChunkPolicyTests: XCTestCase {

    func testPDFPageChunkPolicy() async {
        // Fits within context budget: stays whole
        let pageText = """
        Thermodynamically, the CMC manifests as a distinct change in the slope of the osmotic pressure or chemical potential with increasing surfactant concentration.
        In the absence of alternative information for initializing the optimization of ion-water interactions, Nieto-Draghi et al.43 proposed that partial osmotic pressures could be used as initial values.
        """

        let singleChunks = await ChatService.makePDFPageChunks(
            text: pageText,
            source: "PDF: fixture page 1",
            pdfPage: 1,
            maxContextTokens: 2916
        )
        XCTAssertEqual(singleChunks.count, 1, "A single page that fits the context budget should stay whole")
        XCTAssertEqual(singleChunks.first?.text, pageText.trimmingCharacters(in: .whitespacesAndNewlines))

        // Oversized page: falls back to chunking
        let oversizedText = String(repeating: "Long sentence content that keeps filling the page without ending too quickly. ", count: 300)
        let multiChunks = await ChatService.makePDFPageChunks(
            text: oversizedText,
            source: "PDF: oversized page 1",
            pdfPage: 1,
            maxContextTokens: 300
        )
        XCTAssertGreaterThan(multiChunks.count, 1, "Oversized pages should still be chunked")
        XCTAssertTrue(multiChunks.allSatisfy { $0.pdfPage == 1 })
    }
}
