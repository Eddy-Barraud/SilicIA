# AIService

> God node · 39 connections · `SilicIA/Services/AIService.swift`

**Community:** [On-Device LLM & Privacy Policy](On-Device_LLM_&_Privacy_Policy.md)

## Connections by Relation

### calls
- [SearchView](SearchView.md) `INFERRED`
- [WebSearchService](WebSearchService.md) `INFERRED`
- [RAGContextService](RAGContextService.md) `INFERRED`
- [WebScrapingService](WebScrapingService.md) `INFERRED`
- RAGChunker `INFERRED`
- .testPresidentsOfFourthRepublicInFrenchAcrossThreeProfiles() `INFERRED`
- .testAIServiceTimingExcludesStreaming() `INFERRED`
- .testBelowThresholdResultsSkipDownloadAndReceiveZeroPercentScore() `INFERRED`
- .testSummarizeRespectsUserMaxScrapingResultsWithoutProfileClamping() `INFERRED`
- .testUnconvertibleSourcesAreDeletedFromRAGAndSearchResults() `INFERRED`
- .testKeywordQueryDoesNotLeakModelSelfIntroduction() `INFERRED`
- .testSwiftDataSetupProducesMarkdownWithoutArrayLaTeX() `INFERRED`

### contains
- TimingMetric `EXTRACTED`
- AIService.swift `EXTRACTED`

### implements
- On-Device LLM (Apple Intelligence) `EXTRACTED`

### inherits
- ObservableObject `EXTRACTED`

### method
- .summarize() `EXTRACTED`
- .runSummaryGeneration() `EXTRACTED`
- .toolCallingSearchPrompt() `EXTRACTED`
- .generateSummaryWithFoundationModels() `EXTRACTED`
- .buildInstructions() `EXTRACTED`
- .summarizeWebPage() `EXTRACTED`
- .loadSearchCorpusHint() `EXTRACTED`
- .summaryContextUtilizationFactor() `EXTRACTED`
- .chunkResultsForRAG() `EXTRACTED`
- .classifyGenerationError() `EXTRACTED`
- .localizedSearchContextBlock() `EXTRACTED`
- .noteGenerationFailure() `EXTRACTED`
- .debugLog() `EXTRACTED`
- .appendUniqueResults() `EXTRACTED`

### rationale_for
- Local Processing Guarantee `INFERRED`

### references
- [SearchResult](SearchResult.md) `EXTRACTED`
- String `EXTRACTED`
- Int `EXTRACTED`
- Bool `EXTRACTED`
- Double `EXTRACTED`
- .summaryCard `INFERRED`
- Void `EXTRACTED`
- .handleChatButtonTap() `INFERRED`

---

*Part of the graphify knowledge wiki. See [index](index.md) to navigate.*