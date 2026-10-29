# WebSearchService

> God node · 56 connections · `SilicIA/Services/WebSearchService.swift`

**Community:** [Dual Web Search & Tests](Dual_Web_Search_&_Tests.md)

## Connections by Relation

### calls
- [ChatService](ChatService.md) `INFERRED`
- [SearchView](SearchView.md) `INFERRED`
- [AIService](AIService.md) `INFERRED`
- .makeConfig() `INFERRED`
- .main() `INFERRED`
- .testSearchSourcesToolExecution() `INFERRED`
- .testDuckDuckGoRequestPacerStaggersConcurrentRequests() `INFERRED`
- .testDuckDuckGoRetrievesEffectiveWebData() `INFERRED`
- .testSearchWikipediaAccentedFrenchTitleRetrievesFullContent() `INFERRED`
- .testSearchWikipediaRetrievesCleanMarkdownWithoutHTML() `INFERRED`
- .testWikipediaAPIRetrievesEffectiveDataForConcreteQuestion() `INFERRED`
- .testWikipediaMultilingualConcreteQuestions() `INFERRED`

### contains
- WebSearchService.swift `EXTRACTED`

### implements
- Dual Web Search Architecture `EXTRACTED`

### inherits
- ObservableObject `EXTRACTED`

### method
- .search() `EXTRACTED`
- .executeWikipediaSearch() `EXTRACTED`
- .executeDuckDuckGoSearch() `EXTRACTED`
- .executeSearch() `EXTRACTED`
- .debugLog() `EXTRACTED`
- .singleQuerySnippetSimilarity() `EXTRACTED`
- .searchWikipedia() `EXTRACTED`
- .snippetSimilarity() `EXTRACTED`
- .fetchWikipediaPageDetails() `EXTRACTED`
- .parseDuckDuckGoHTMLResults() `EXTRACTED`
- .searchDuckDuckGo() `EXTRACTED`
- .fetchWikipediaFallbackKeys() `EXTRACTED`
- .convertWikipediaHTMLToMarkdown() `EXTRACTED`
- .wikipediaWithHTMLURL() `EXTRACTED`
- .wikipediaReadablePageURL() `EXTRACTED`
- .wikipediaHost() `EXTRACTED`
- .mergeInterleavedDeduplicatedResults() `EXTRACTED`
- .htmlToPlainText() `EXTRACTED`
- .detectTextLanguage() `EXTRACTED`
- .extractWikipediaArticleKey() `EXTRACTED`
- *…and 9 more `method` connection(s) not listed (lowest-degree first to go)*

### references
- [WebScrapingService](WebScrapingService.md) `EXTRACTED`
- String `EXTRACTED`
- SourceFunnel `EXTRACTED`
- Configuration `EXTRACTED`
- Double `EXTRACTED`
- URLSession `EXTRACTED`
- Error `EXTRACTED`
- CharacterSet `EXTRACTED`
- JSONDecoder `EXTRACTED`
- ContinuousClock `EXTRACTED`
- ClosedRange `EXTRACTED`
- Set `EXTRACTED`

---

*Part of the graphify knowledge wiki. See [index](index.md) to navigate.*