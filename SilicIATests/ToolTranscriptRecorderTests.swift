import XCTest
@testable import SilicIA

final class ToolTranscriptRecorderTests: XCTestCase {

    func testRenderedTranscriptBudgetingAndEmptyState() async {
        let emptyRecorder = ToolTranscriptRecorder()
        let emptyRendered = await emptyRecorder.renderedTranscript(characterBudget: 200)
        XCTAssertEqual(emptyRendered, "")

        let recorder = ToolTranscriptRecorder(maxEntries: 3)
        await recorder.record(tool: "searchContext", arguments: "equation 6", result: "Nc is the number of carbons.")
        await recorder.record(tool: "calculate", arguments: "log(2)", result: "0.6931471806")
        await recorder.record(tool: "currentDateTime", arguments: "date", result: "Saturday, June 28, 2026")

        let rendered = await recorder.renderedTranscript(characterBudget: 220, maxRenderedEntries: 2)

        XCTAssertTrue(rendered.contains("calculate") || rendered.contains("currentDateTime"))
        XCTAssertFalse(rendered.contains("searchContext"),
                       "Oldest entry should be dropped first when only two recent entries fit")
        XCTAssertLessThanOrEqual(rendered.count, 220)
    }
}
