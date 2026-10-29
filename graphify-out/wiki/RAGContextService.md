# RAGContextService

> God node · 52 connections · `SilicIA/Services/RAGContextService.swift`

**Community:** [RAG Retrieval & Chunking](RAG_Retrieval_&_Chunking.md)

## Connections by Relation

### calls
- [ChatService](ChatService.md) `INFERRED`
- [AIService](AIService.md) `INFERRED`
- .call() `INFERRED`
- .main() `INFERRED`
- .testQueryLanguageDetectionAndFrenchNLEmbeddingRanking() `INFERRED`
- .testSearchSourcesToolExecution() `INFERRED`
- .testRAGContextServiceRankingAnd4096Budgeting() `INFERRED`
- .testTwoStageCosinePreFiltering() `INFERRED`
- .testTwoStageDCTCosineCapsOutputAtTwiceTokenBudget() `INFERRED`
- .testPDFContextRankingForEquationsAndFigures() `INFERRED`

### contains
- RAGContextService.swift `EXTRACTED`

### method
- .selectContext() `EXTRACTED`
- .figureRelevanceBoost() `EXTRACTED`
- .wordEmbeddingSemanticScore() `EXTRACTED`
- .numericRelevanceBoost() `EXTRACTED`
- .equationRelevanceBoost() `EXTRACTED`
- .nlEmbeddingRelevanceScore() `EXTRACTED`
- .relevanceScore() `EXTRACTED`
- .cosineRelevanceScore() `EXTRACTED`
- .dctCosineRelevanceScore() `EXTRACTED`
- .detectQueryLanguage() `EXTRACTED`
- .calculate4096BudgetedContextCharacters() `EXTRACTED`
- .resolveEmbedding() `EXTRACTED`
- .resolveWordEmbedding() `EXTRACTED`
- .dctUnitVector() `EXTRACTED`
- .contentTokens() `EXTRACTED`
- .tokenizeStatic() `EXTRACTED`
- .normalizedSourceScores() `EXTRACTED`
- .combinedTermVector() `EXTRACTED`
- .hasEquationIntent() `EXTRACTED`
- .extractEquationReferenceNumbers() `EXTRACTED`
- *…and 14 more `method` connection(s) not listed (lowest-degree first to go)*

### references
- String `EXTRACTED`
- SourceFunnel `EXTRACTED`
- Configuration `EXTRACTED`
- NLEmbedding `EXTRACTED`
- Set `EXTRACTED`
- NSRegularExpression `EXTRACTED`
- NLLanguage `EXTRACTED`

---

*Part of the graphify knowledge wiki. See [index](index.md) to navigate.*