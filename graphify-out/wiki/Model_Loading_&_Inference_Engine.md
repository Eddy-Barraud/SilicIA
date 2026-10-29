# Model Loading & Inference Engine

> 17 nodes · cohesion 0.20

## Key Concepts

- **XCTestCase** (23 connections)
- **RAGSearchTool** (14 connections) — `SilicIA/Services/Tools/RAGSearchTool.swift`
- **.call()** (12 connections) — `SilicIA/Services/Tools/RAGSearchTool.swift`
- **.testDuplicateSearchContextCallBehavior()** (6 connections) — `SilicIATests/RAGSearchToolTests.swift`
- **.testSearchContextReplyHonoursTokenBudget()** (6 connections) — `SilicIATests/RAGSearchToolTests.swift`
- **.excerpt()** (5 connections) — `SilicIA/Services/Tools/RAGSearchTool.swift`
- **Arguments** (4 connections) — `SilicIA/Services/Tools/RAGSearchTool.swift`
- **String** (4 connections)
- **RAGSearchToolTests** (4 connections) — `SilicIATests/RAGSearchToolTests.swift`
- **.systemPreferred()** (3 connections) — `SilicIA/Models/AppSettings.swift`
- **.queryTerms()** (3 connections) — `SilicIA/Services/Tools/RAGSearchTool.swift`
- **Int** (3 connections)
- **ChatServicePDFChunkPolicyTests** (3 connections) — `SilicIATests/ChatServicePDFChunkPolicyTests.swift`
- **ModelLanguageTests** (3 connections) — `SilicIATests/ModelLanguageTests.swift`
- **ToolTranscriptRecorderTests** (3 connections) — `SilicIATests/ToolTranscriptRecorderTests.swift`
- **.testPDFPageChunkPolicy()** (2 connections) — `SilicIATests/ChatServicePDFChunkPolicyTests.swift`
- **.testSystemPreferredLanguageResolution()** (2 connections) — `SilicIATests/ModelLanguageTests.swift`

## Relationships

- [RAG Retrieval & Chunking](RAG_Retrieval_&_Chunking.md) (7 shared connections)
- [Tool Calling Governor & Rate Limiting](Tool_Calling_Governor_&_Rate_Limiting.md) (6 shared connections)
- [On-Device LLM & Privacy Policy](On-Device_LLM_&_Privacy_Policy.md) (4 shared connections)
- [Dual Web Search & Tests](Dual_Web_Search_&_Tests.md) (4 shared connections)
- [Tool Call Transcript Recorder](Tool_Call_Transcript_Recorder.md) (4 shared connections)
- [App Settings & Tool Test Fixtures](App_Settings_&_Tool_Test_Fixtures.md) (4 shared connections)
- [Tool Budgeting & Execution Assembly](Tool_Budgeting_&_Execution_Assembly.md) (2 shared connections)
- [SwiftData Conversation Persistence](SwiftData_Conversation_Persistence.md) (2 shared connections)
- [Image Analysis & Visual Grounding](Image_Analysis_&_Visual_Grounding.md) (2 shared connections)
- [LaTeX Stream Segmentation](LaTeX_Stream_Segmentation.md) (2 shared connections)
- [System Framework Integrations](System_Framework_Integrations.md) (1 shared connections)
- [Multi-Query Search Sources Tool](Multi-Query_Search_Sources_Tool.md) (1 shared connections)

## Source Files

- `SilicIA/Models/AppSettings.swift`
- `SilicIA/Services/Tools/RAGSearchTool.swift`
- `SilicIATests/ChatServicePDFChunkPolicyTests.swift`
- `SilicIATests/ModelLanguageTests.swift`
- `SilicIATests/RAGSearchToolTests.swift`
- `SilicIATests/ToolTranscriptRecorderTests.swift`

## Audit Trail

- EXTRACTED: 59 (81%)
- INFERRED: 14 (19%)
- AMBIGUOUS: 0 (0%)

---

*Part of the graphify knowledge wiki. See [index](index.md) to navigate.*