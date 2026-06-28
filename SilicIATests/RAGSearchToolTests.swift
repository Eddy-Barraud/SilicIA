import XCTest
@testable import SilicIA

final class RAGSearchToolTests: XCTestCase {

    func testSearchContextReplyHonoursTokenBudget() async throws {
        let filler = String(repeating: "Background filler text that should not dominate the reply. ", count: 120)
        let target = "Equation 4 defines the osmotic coefficient for the solute in DPD units."
        let chunk = RAGChunk(
            source: "PDF: fixture page 5",
            text: filler + target + filler,
            url: nil,
            pdfPage: 5
        )
        let tokenBudget = 200
        var tool = RAGSearchTool(chunks: [chunk], tokenBudget: tokenBudget)
        tool.governor = ToolCallGovernor()

        let output = try await tool.call(arguments: .init(query: "equation 4", maxResults: 1))

        XCTAssertLessThanOrEqual(
            output.count,
            TokenBudgeting.estimatedContextCharacters(forTokens: tokenBudget),
            "searchContext reply exceeded its advertised token budget"
        )
        XCTAssertTrue(
            output.localizedCaseInsensitiveContains("equation 4"),
            "Budgeted excerpt should keep the relevant query match in the returned passage"
        )
    }

    func testDuplicateSearchContextCallReturnsRefusalInsteadOfThrowing() async throws {
        let chunk = RAGChunk(
            source: "PDF: fixture page 6",
            text: "Equation 6 states log(CMC) = A - B Nc and the caption explains Nc is the number of carbons.",
            url: nil,
            pdfPage: 6
        )
        var tool = RAGSearchTool(chunks: [chunk], tokenBudget: 200)
        tool.governor = ToolCallGovernor()

        _ = try await tool.call(arguments: .init(query: "what is Nc in equation 6", maxResults: 1))
        let duplicate = try await tool.call(arguments: .init(query: "what is Nc in equation 6", maxResults: 1))

        XCTAssertTrue(
            duplicate.localizedCaseInsensitiveContains("do NOT repeat".lowercased()) ||
            duplicate.localizedCaseInsensitiveContains("write your final answer now".lowercased()),
            "Duplicate governed call should return a soft refusal, got: \(duplicate)"
        )
    }

    func testDuplicateSearchContextCallThrowsWhenRecoveryRecorderIsPresent() async throws {
        let chunk = RAGChunk(
            source: "PDF: fixture page 6",
            text: "Equation 6 states log(CMC) = A - B Nc and the caption explains Nc is the number of carbons.",
            url: nil,
            pdfPage: 6
        )
        var tool = RAGSearchTool(chunks: [chunk], tokenBudget: 200)
        tool.governor = ToolCallGovernor()
        tool.transcriptRecorder = ToolTranscriptRecorder()

        _ = try await tool.call(arguments: .init(query: "what is Nc in equation 6", maxResults: 1))

        do {
            _ = try await tool.call(arguments: .init(query: "what is Nc in equation 6", maxResults: 1))
            XCTFail("Expected duplicate governed call to abort when recovery recorder is present")
        } catch let error as ToolError {
            guard case .duplicate(let toolName, let count) = error else {
                return XCTFail("Expected duplicate ToolError, got \(error)")
            }
            XCTAssertEqual(toolName, "searchContext")
            XCTAssertEqual(count, 2)
        }
    }
}
