//
//  PDFAnswerAnalyzer.swift
//  SilicIA
//
//  Created by Eddy Barraud on 06/04/2026.
//

import Foundation

/// Structured result of PDF citation analysis.
struct PDFCitationAnalysis {
    /// Page numbers extracted from the response text.
    let extractedPageNumbers: [Int]
    /// RAGChunks that correspond to cited pages.
    let citedChunks: [RAGChunk]
    /// Response text with enhanced markdown links for pages.
    let enhancedText: String
}
