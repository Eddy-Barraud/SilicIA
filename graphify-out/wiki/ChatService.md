# ChatService

> God node · 76 connections · `SilicIA/Services/ChatService.swift`

**Community:** [SwiftData Conversation Persistence](SwiftData_Conversation_Persistence.md)

## Connections by Relation

### calls
- [WebSearchService](WebSearchService.md) `INFERRED`
- [RAGContextService](RAGContextService.md) `INFERRED`
- [WebScrapingService](WebScrapingService.md) `INFERRED`
- RAGChunker `INFERRED`
- ContentView `INFERRED`
- .testMainViewsRenderWithoutCrashing() `INFERRED`

### contains
- ChatService.swift `EXTRACTED`

### implements
- RAG Retrieval Pipeline `EXTRACTED`

### inherits
- ObservableObject `EXTRACTED`

### method
- .sendMessage() `EXTRACTED`
- .collectChunks() `EXTRACTED`
- .assembleToolCallingPrompt() `EXTRACTED`
- .preAnalyzeContext() `EXTRACTED`
- .discoverWebResults() `EXTRACTED`
- .streamClassicalFallback() `EXTRACTED`
- .streamToolTranscriptRecovery() `EXTRACTED`
- .regenerateAssistantMessage() `EXTRACTED`
- .persistMessage() `EXTRACTED`
- .pdfBaseFilename() `EXTRACTED`
- .buildInstructions() `EXTRACTED`
- .startConversationFromSearch() `EXTRACTED`
- .buildToolCallingPrompt() `EXTRACTED`
- .buildToolTranscriptRecoveryPrompt() `EXTRACTED`
- .makeContextKey() `EXTRACTED`
- .debugContext() `EXTRACTED`
- .updateAssistantMessage() `EXTRACTED`
- .makePDFPageChunks() `EXTRACTED`
- .clampedMaxDuckDuckGoResults() `EXTRACTED`
- .clampedMaxWikipediaResults() `EXTRACTED`
- *…and 28 more `method` connection(s) not listed (lowest-degree first to go)*

### references
- [ChatView](ChatView.md) `EXTRACTED`
- [SearchView](SearchView.md) `EXTRACTED`
- String `EXTRACTED`
- [RAGChunk](RAGChunk.md) `EXTRACTED`
- ChatMessage `EXTRACTED`
- Int `EXTRACTED`
- Conversation `EXTRACTED`
- Bool `EXTRACTED`
- ModelAnsweringTests `EXTRACTED`
- URL `EXTRACTED`
- Double `EXTRACTED`
- .init() `EXTRACTED`
- Data `EXTRACTED`
- ModelContext `EXTRACTED`
- Task `EXTRACTED`
- UInt64 `EXTRACTED`
- Never `EXTRACTED`
- Void `EXTRACTED`
- Search Tool Calling Definition `INFERRED`

---

*Part of the graphify knowledge wiki. See [index](index.md) to navigate.*