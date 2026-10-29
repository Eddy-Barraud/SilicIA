# Tool Budgeting & Execution Assembly

> 9 nodes · cohesion 0.42

## Key Concepts

- **.assemble()** (20 connections) — `SilicIA/Services/Tools/ToolKit.swift`
- **.makeConfig()** (10 connections) — `SilicIATests/ToolKitBudgetTests.swift`
- **ToolKitBudgetTests** (7 connections) — `SilicIATests/ToolKitBudgetTests.swift`
- **.testIndependentSourceToggling()** (3 connections) — `SilicIATests/ToolKitBudgetTests.swift`
- **.testNoSearchSourcesToolWhenUnavailable()** (3 connections) — `SilicIATests/ToolKitBudgetTests.swift`
- **.testOfflineModeWhenBothSourcesDisabled()** (3 connections) — `SilicIATests/ToolKitBudgetTests.swift`
- **.testToolKitBudgetAndRAGToolSizing()** (3 connections) — `SilicIATests/ToolKitBudgetTests.swift`
- **Tool** (1 connections)
- **Bool** (1 connections)

## Relationships

- [System Prompt Template Loader](System_Prompt_Template_Loader.md) (4 shared connections)
- [Multi-Query Search Sources Tool](Multi-Query_Search_Sources_Tool.md) (4 shared connections)
- [On-Device LLM & Privacy Policy](On-Device_LLM_&_Privacy_Policy.md) (2 shared connections)
- [Model Loading & Inference Engine](Model_Loading_&_Inference_Engine.md) (2 shared connections)
- [SwiftData Conversation Persistence](SwiftData_Conversation_Persistence.md) (1 shared connections)
- [Tool Call Transcript Recorder](Tool_Call_Transcript_Recorder.md) (1 shared connections)
- [On-Device Calculator Tool](On-Device_Calculator_Tool.md) (1 shared connections)
- [System Date & Time Tool](System_Date_&_Time_Tool.md) (1 shared connections)
- [Tool Calling Governor & Rate Limiting](Tool_Calling_Governor_&_Rate_Limiting.md) (1 shared connections)
- [App Settings & Tool Test Fixtures](App_Settings_&_Tool_Test_Fixtures.md) (1 shared connections)
- [RAG Retrieval & Chunking](RAG_Retrieval_&_Chunking.md) (1 shared connections)
- [Dual Web Search & Tests](Dual_Web_Search_&_Tests.md) (1 shared connections)

## Source Files

- `SilicIA/Services/Tools/ToolKit.swift`
- `SilicIATests/ToolKitBudgetTests.swift`

## Audit Trail

- EXTRACTED: 25 (69%)
- INFERRED: 11 (31%)
- AMBIGUOUS: 0 (0%)

---

*Part of the graphify knowledge wiki. See [index](index.md) to navigate.*