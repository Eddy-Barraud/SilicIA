//
//  PDFContextBudgetingTests.swift
//  SilicIATests
//
//  Unit tests verifying:
//  1. PDF context token calculation maximizing the 4000 total token window based on reasoning level.
//  2. ChatService PDF page batching: merging consecutive pages <= 3500 tokens and safety capping at 4000 tokens.
//

import XCTest
import FoundationModels
@testable import SilicIA

final class PDFContextBudgetingTests: XCTestCase {

    func testReasoningTokensReservation() {
        XCTAssertEqual(TokenBudgeting.reasoningTokens(for: .light), 200)
        XCTAssertEqual(TokenBudgeting.reasoningTokens(for: .moderate), 400)
        XCTAssertEqual(TokenBudgeting.reasoningTokens(for: .deep), 800)
    }

    func testMaxPDFInputContextTokensAcrossReasoningLevels() {
        XCTAssertEqual(TokenBudgeting.maxTotalTokensLimit, 4000)

        let maxOutputTokens = 600
        let staticOverhead = TokenBudgeting.instructionTokens + TokenBudgeting.promptOverheadTokens // 100 + 80 = 180

        // Light: 4000 - (180 + 200 + 600) = 3020
        let lightInputTokens = TokenBudgeting.maxPDFInputContextTokens(
            maxOutputTokens: maxOutputTokens,
            reasoningLevel: .light
        )
        XCTAssertEqual(lightInputTokens, 3020)

        // Moderate: 4000 - (180 + 400 + 600) = 2820
        let moderateInputTokens = TokenBudgeting.maxPDFInputContextTokens(
            maxOutputTokens: maxOutputTokens,
            reasoningLevel: .moderate
        )
        XCTAssertEqual(moderateInputTokens, 2820)

        // Deep: 4000 - (180 + 800 + 600) = 2420
        let deepInputTokens = TokenBudgeting.maxPDFInputContextTokens(
            maxOutputTokens: maxOutputTokens,
            reasoningLevel: .deep
        )
        XCTAssertEqual(deepInputTokens, 2420)

        // Verify total combined tokens sum to exactly 4000
        let lightTotal = lightInputTokens + 200 + maxOutputTokens + staticOverhead
        XCTAssertEqual(lightTotal, 4000)

        let modTotal = moderateInputTokens + 400 + maxOutputTokens + staticOverhead
        XCTAssertEqual(modTotal, 4000)

        let deepTotal = deepInputTokens + 800 + maxOutputTokens + staticOverhead
        XCTAssertEqual(deepTotal, 4000)
    }

    func testMaxPDFInputContextCharacters() {
        let maxOutputTokens = 600
        let expectedTokens = TokenBudgeting.maxPDFInputContextTokens(
            maxOutputTokens: maxOutputTokens,
            reasoningLevel: .moderate
        )
        let expectedChars = expectedTokens * TokenBudgeting.avgCharsPerToken
        XCTAssertEqual(
            TokenBudgeting.maxPDFInputContextCharacters(maxOutputTokens: maxOutputTokens, reasoningLevel: .moderate),
            expectedChars
        )
    }

    func testRAGContextServicePDFBudgeting() {
        let maxOutputTokens = 600

        let nonPDFBudget = RAGContextService.calculate4096BudgetedContextCharacters(
            maxOutputTokens: maxOutputTokens,
            isPDFSource: false,
            reasoningLevel: .moderate
        )

        let pdfBudget = RAGContextService.calculate4096BudgetedContextCharacters(
            maxOutputTokens: maxOutputTokens,
            isPDFSource: true,
            reasoningLevel: .moderate
        )

        let expectedPDFChars = TokenBudgeting.maxPDFInputContextCharacters(
            maxOutputTokens: maxOutputTokens,
            reasoningLevel: .moderate
        )

        XCTAssertEqual(pdfBudget, expectedPDFChars)
        // PDF fills the available window up to the 4000 token ceiling, which is larger than the standard conservative profile
        XCTAssertGreaterThan(pdfBudget, nonPDFBudget)
    }

    func testMakePDFPageBatchesSinglePage() {
        let pages = ["This is a single page text about surfactant chemistry."]
        let batches = ChatService.makePDFPageBatches(pages: pages)

        XCTAssertEqual(batches.count, 1)
        XCTAssertFalse(batches[0].isMerged)
        XCTAssertEqual(batches[0].pageNumbers, [1])
        XCTAssertEqual(batches[0].combinedContent, pages[0])
    }

    func testMakePDFPageBatchesMergedWhenUnder3500Tokens() {
        // Create 2 pages with ~500 tokens each (~1500 chars each)
        let page1 = String(repeating: "Page 1 chemical analysis. ", count: 60)
        let page2 = String(repeating: "Page 2 experimental results. ", count: 60)

        let batches = ChatService.makePDFPageBatches(pages: [page1, page2], maxMergedTokens: 3500)

        XCTAssertEqual(batches.count, 1)
        XCTAssertTrue(batches[0].isMerged)
        XCTAssertEqual(batches[0].pageNumbers, [1, 2])
        XCTAssertTrue(batches[0].combinedContent.contains("--- Page 1 ---"))
        XCTAssertTrue(batches[0].combinedContent.contains("--- Page 2 ---"))
    }

    func testMakePDFPageBatchesSeparateWhenExceeding3500Tokens() {
        // Create 2 pages with ~2000 tokens each (~6000 chars each, sum = 4000 > 3500)
        let page1 = String(repeating: "Page 1 lengthy discussion of results. ", count: 160)
        let page2 = String(repeating: "Page 2 lengthy thermodynamic proofs. ", count: 160)

        let batches = ChatService.makePDFPageBatches(pages: [page1, page2], maxMergedTokens: 3500)

        XCTAssertEqual(batches.count, 2)
        XCTAssertFalse(batches[0].isMerged)
        XCTAssertEqual(batches[0].pageNumbers, [1])
        XCTAssertFalse(batches[1].isMerged)
        XCTAssertEqual(batches[1].pageNumbers, [2])
    }

    func testMakePDFPageBatchesOddNumberOfPages() {
        // 3 pages: 1 and 2 merge, 3 remains separate
        let page1 = String(repeating: "Short text for page 1. ", count: 30)
        let page2 = String(repeating: "Short text for page 2. ", count: 30)
        let page3 = String(repeating: "Short text for page 3. ", count: 30)

        let batches = ChatService.makePDFPageBatches(pages: [page1, page2, page3], maxMergedTokens: 3500)

        XCTAssertEqual(batches.count, 2)
        XCTAssertTrue(batches[0].isMerged)
        XCTAssertEqual(batches[0].pageNumbers, [1, 2])
        XCTAssertFalse(batches[1].isMerged)
        XCTAssertEqual(batches[1].pageNumbers, [3])
    }

    func testMakePDFPageBatchesCappedAt4000TokensSafety() {
        // Page exceeding 4000 tokens (e.g. 5000 tokens = 15000 chars)
        let hugePage = String(repeating: "Huge text string filling the page. ", count: 500)
        XCTAssertGreaterThan(hugePage.count, 4000 * TokenBudgeting.avgCharsPerToken)

        let batches = ChatService.makePDFPageBatches(pages: [hugePage], maxSingleTokens: 4000)

        XCTAssertEqual(batches.count, 1)
        XCTAssertFalse(batches[0].isMerged)
        XCTAssertEqual(batches[0].combinedContent.count, 4000 * TokenBudgeting.avgCharsPerToken)
    }
}
