# RAGChunk

> God node · 31 connections · `SilicIA/Services/RAGContextService.swift`

**Community:** [RAG Retrieval & Chunking](RAG_Retrieval_&_Chunking.md)

## Connections by Relation

### calls
- .chunkParagraphs() `EXTRACTED`
- .makeConfig() `INFERRED`
- .testQueryLanguageDetectionAndFrenchNLEmbeddingRanking() `INFERRED`
- .testDuplicateSearchContextCallBehavior() `INFERRED`
- .testSearchContextReplyHonoursTokenBudget() `INFERRED`
- .testNumericAndReferenceRelevanceBoosts() `INFERRED`
- .testRAGContextServiceRankingAnd4096Budgeting() `INFERRED`
- .testTwoStageCosinePreFiltering() `INFERRED`
- .testTwoStageDCTCosineCapsOutputAtTwiceTokenBudget() `INFERRED`

### contains
- RAGContextService.swift `EXTRACTED`

### implements
- Identifiable `EXTRACTED`

### references
- [ChatService](ChatService.md) `EXTRACTED`
- String `EXTRACTED`
- .selectContext() `EXTRACTED`
- .collectChunks() `EXTRACTED`
- .runSummaryGeneration() `EXTRACTED`
- RAGSearchTool `EXTRACTED`
- Configuration `EXTRACTED`
- .figureRelevanceBoost() `EXTRACTED`
- .generateSummaryWithFoundationModels() `EXTRACTED`
- .wordEmbeddingSemanticScore() `EXTRACTED`
- .cosineRelevanceScore() `EXTRACTED`
- .nlEmbeddingRelevanceScore() `EXTRACTED`
- .relevanceScore() `EXTRACTED`
- RankedRAGChunk `EXTRACTED`
- .dctCosineRelevanceScore() `EXTRACTED`
- .makePDFPageChunks() `EXTRACTED`
- Int `EXTRACTED`
- .chunkResultsForRAG() `EXTRACTED`
- .makeImageChunk() `EXTRACTED`
- .makeFixtureChunks() `EXTRACTED`

---

*Part of the graphify knowledge wiki. See [index](index.md) to navigate.*