import XCTest
import PDFKit
import FoundationModels
@testable import SilicIA

final class PDFPageSummaryBenchmarkTests: XCTestCase {

    struct PageBatch {
        let pageNumbers: [Int] // 1-based
        let combinedContent: String
        let estimatedTokens: Int
    }

    func testPDFPageSummaryWithBatchingAndSingleParagraph() async throws {
        try XCTSkipUnless(
            FoundationModelAvailability.check().isAvailable,
            "Apple Intelligence unavailable on this host"
        )

        let pdfURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("2025.PFAS.CMC.pdf")

        guard let document = PDFDocument(url: pdfURL) else {
            return XCTFail("Could not load PDF at \(pdfURL.path)")
        }

        print("📄 Document has \(document.pageCount) pages")
        let query = "critical micelle concentration (CMC) of PFAS surfactants and equation 5"

        // 1. Extract text from pages
        let ocrStartTime = CFAbsoluteTimeGetCurrent()
        let analyses = await ImageAnalysisService.extractPDFPageAnalyses(from: pdfURL)
        let ocrDuration = CFAbsoluteTimeGetCurrent() - ocrStartTime
        print(String(format: "⏱️ Vision OCR for %d pages took %.2fs (%.2fs/page)", analyses.count, ocrDuration, ocrDuration / Double(max(1, analyses.count))))

        // 2. Batch pages: if two consecutive pages fit in 3500 tokens, merge them into 1 batch
        let maxSinglePageTokens = 4000
        let maxMergedPagesTokens = 3500
        var batches: [PageBatch] = []

        var i = 0
        while i < analyses.count {
            let p1Num = i + 1
            let p1Text = analyses[i].recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
            let p1Tokens = TokenBudgeting.estimatedTokens(forApproxCharacters: p1Text.count)

            if i + 1 < analyses.count {
                let p2Num = i + 2
                let p2Text = analyses[i + 1].recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
                let p2Tokens = TokenBudgeting.estimatedTokens(forApproxCharacters: p2Text.count)

                if p1Tokens + p2Tokens <= maxMergedPagesTokens {
                    // Merge two pages
                    let combined = """
--- Page \(p1Num) ---
\(p1Text)

--- Page \(p2Num) ---
\(p2Text)
"""
                    batches.append(PageBatch(
                        pageNumbers: [p1Num, p2Num],
                        combinedContent: combined,
                        estimatedTokens: p1Tokens + p2Tokens
                    ))
                    i += 2
                    continue
                }
            }

            // Single page (capped at 4000 tokens for safety)
            let cappedChars = maxSinglePageTokens * TokenBudgeting.avgCharsPerToken
            let cappedText = String(p1Text.prefix(cappedChars))
            batches.append(PageBatch(
                pageNumbers: [p1Num],
                combinedContent: cappedText,
                estimatedTokens: min(p1Tokens, maxSinglePageTokens)
            ))
            i += 1
        }

        print("\n📦 Created \(batches.count) batches from \(analyses.count) pages:")
        for (idx, b) in batches.enumerated() {
            let pageLabel = b.pageNumbers.count == 1 ? "Page \(b.pageNumbers[0])" : "Pages \(b.pageNumbers[0])-\(b.pageNumbers[1])"
            print("  Batch \(idx + 1): \(pageLabel) | ~\(b.estimatedTokens) tokens (\(b.combinedContent.count) chars)")
        }

        print("\n================ BENCHMARK: MODEL SUMMARY PER BATCH ================\n")

        var batchDurations: [Double] = []
        var batchOutputLengths: [Int] = []
        var batchOutputWords: [Int] = []

        for (idx, batch) in batches.enumerated() {
            let isMerged = batch.pageNumbers.count > 1
            let promptParagraphs = isMerged ? "two paragraphs" : "one paragraph"
            let targetNoun = isMerged ? "pages below" : "page below"
            let headerNoun = isMerged ? "Pages content:" : "Page content:"

            let prompt = """
The user query is: \(query)
Summarize in \(promptParagraphs) the content of the \(targetNoun), and preserve important numbers, dates, equations. Put more weight to content relevant to the user query.
\(headerNoun)
\(batch.combinedContent)
"""

            let session = DynamicSessionCoordinator.shared.acquireSession(
                mode: .webPageSummary,
                instructions: "You are a precise technical summarizer. Summarize in \(promptParagraphs), preserving important numbers, dates, and equations.",
                temperature: 0.3,
                maxResponseTokens: isMerged ? 500 : 300,
                reasoningLevelOverride: .light
            )
            let options = GenerationOptions(
                temperature: 0.3,
                maximumResponseTokens: isMerged ? 500 : 300
            )

            let startTime = CFAbsoluteTimeGetCurrent()
            do {
                let response = try await session.respond(to: prompt, options: options)
                let duration = CFAbsoluteTimeGetCurrent() - startTime
                let output = String(describing: response.content).trimmingCharacters(in: .whitespacesAndNewlines)
                let wordCount = output.split(whereSeparator: \.isWhitespace).count
                let tokenEstimate = TokenBudgeting.estimatedTokens(forApproxCharacters: output.count)

                batchDurations.append(duration)
                batchOutputLengths.append(output.count)
                batchOutputWords.append(wordCount)

                let pageLabel = isMerged ? "Pages \(batch.pageNumbers[0])-\(batch.pageNumbers[1])" : "Page \(batch.pageNumbers[0])"
                print(String(format: "📄 Batch %2d (%@) | Input: %5d chars (~%4d tokens) | Output: %4d chars (~%3d tokens, %3d words) | Duration: %5.2fs",
                             idx + 1,
                             pageLabel,
                             batch.combinedContent.count,
                             batch.estimatedTokens,
                             output.count,
                             tokenEstimate,
                             wordCount,
                             duration))
                #if DEBUG
                print("--- Summary Preview ---")
                let preview = output.components(separatedBy: "\n").filter { !$0.isEmpty }.prefix(2).joined(separator: " / ")
                print(String(preview.prefix(250)))
                print("-----------------------")
                #endif
            } catch {
                print("❌ Batch \(idx + 1) failed: \(error)")
            }
        }

        let totalDuration = batchDurations.reduce(0, +)
        let avgDuration = totalDuration / Double(max(1, batchDurations.count))
        let avgChars = Double(batchOutputLengths.reduce(0, +)) / Double(max(1, batchOutputLengths.count))
        let avgWords = Double(batchOutputWords.reduce(0, +)) / Double(max(1, batchOutputWords.count))

        print("\n================ BENCHMARK SUMMARY (BATCHED + 1/2 PARAGRAPHS) ================")
        print(String(format: "Total Batches Evaluated: %d (from %d pages)", batchDurations.count, analyses.count))
        print(String(format: "Total LLM Time: %.2fs (compared to 141.79s unbatched)", totalDuration))
        print(String(format: "Average Time per Batch: %.2fs", avgDuration))
        print(String(format: "Average Output Length: %.0f chars (~%.0f tokens, %.0f words)", avgChars, avgChars / 3.0, avgWords))
        print("==============================================================================\n")

        XCTAssertFalse(batchDurations.isEmpty, "Should have processed at least 1 batch")
    }
}
