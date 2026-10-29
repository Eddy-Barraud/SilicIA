# App Settings & Tool Test Fixtures

> 21 nodes · cohesion 0.17

## Key Concepts

- **SilicIA** (24 connections) — `TestRAG/test.swift`
- **XCTest** (23 connections) — `SilicIATests/WikipediaQueryCleanerTests.swift`
- **AppSettingsStoreTests.swift** (4 connections) — `SilicIATests/AppSettingsStoreTests.swift`
- **AppSettingsStore.swift** (3 connections) — `SilicIA/Models/AppSettingsStore.swift`
- **CalculatorToolTests.swift** (3 connections) — `SilicIATests/CalculatorToolTests.swift`
- **ChatServicePDFChunkPolicyTests.swift** (3 connections) — `SilicIATests/ChatServicePDFChunkPolicyTests.swift`
- **LaTeXStreamSegmenterTests.swift** (3 connections) — `SilicIATests/LaTeXStreamSegmenterTests.swift`
- **LocalizationTests.swift** (3 connections) — `SilicIATests/LocalizationTests.swift`
- **MathAccuracyTests.swift** (3 connections) — `SilicIATests/MathAccuracyTests.swift`
- **ModelLanguageTests.swift** (3 connections) — `SilicIATests/ModelLanguageTests.swift`
- **MonetizationTests.swift** (3 connections) — `SilicIATests/MonetizationTests.swift`
- **PromptLoaderTests.swift** (3 connections) — `SilicIATests/PromptLoaderTests.swift`
- **RAGSearchToolTests.swift** (3 connections) — `SilicIATests/RAGSearchToolTests.swift`
- **SanitizerTests.swift** (3 connections) — `SilicIATests/SanitizerTests.swift`
- **TokenBudgetingTests.swift** (3 connections) — `SilicIATests/TokenBudgetingTests.swift`
- **ToolCallGovernorTests.swift** (3 connections) — `SilicIATests/ToolCallGovernorTests.swift`
- **ToolCallingPromptTests.swift** (3 connections) — `SilicIATests/ToolCallingPromptTests.swift`
- **ToolKitBudgetTests.swift** (3 connections) — `SilicIATests/ToolKitBudgetTests.swift`
- **ToolTranscriptRecorderTests.swift** (3 connections) — `SilicIATests/ToolTranscriptRecorderTests.swift`
- **WebSearchServiceTests.swift** (3 connections) — `SilicIATests/WebSearchServiceTests.swift`
- **Observation** (2 connections) — `SilicIATests/AppSettingsStoreTests.swift`

## Relationships

- [RAG & PDF Chunking Tests](RAG_&_PDF_Chunking_Tests.md) (8 shared connections)
- [Model Loading & Inference Engine](Model_Loading_&_Inference_Engine.md) (4 shared connections)
- [SilicIA Product Overview & Models](SilicIA_Product_Overview_&_Models.md) (2 shared connections)
- [Wikipedia Query Normalizer](Wikipedia_Query_Normalizer.md) (2 shared connections)
- [LaTeX Stream Segmentation](LaTeX_Stream_Segmentation.md) (2 shared connections)
- [Dual Web Search & Tests](Dual_Web_Search_&_Tests.md) (2 shared connections)
- [Multi-Query Search Sources Tool](Multi-Query_Search_Sources_Tool.md) (1 shared connections)
- [System Framework Integrations](System_Framework_Integrations.md) (1 shared connections)
- [AppSettings Store Persistence](AppSettings_Store_Persistence.md) (1 shared connections)
- [AppSettings Store Unit Tests](AppSettings_Store_Unit_Tests.md) (1 shared connections)
- [On-Device Calculator Tool](On-Device_Calculator_Tool.md) (1 shared connections)
- [RAG Retrieval & Chunking](RAG_Retrieval_&_Chunking.md) (1 shared connections)

## Source Files

- `SilicIA/Models/AppSettingsStore.swift`
- `SilicIATests/AppSettingsStoreTests.swift`
- `SilicIATests/CalculatorToolTests.swift`
- `SilicIATests/ChatServicePDFChunkPolicyTests.swift`
- `SilicIATests/LaTeXStreamSegmenterTests.swift`
- `SilicIATests/LocalizationTests.swift`
- `SilicIATests/MathAccuracyTests.swift`
- `SilicIATests/ModelLanguageTests.swift`
- `SilicIATests/MonetizationTests.swift`
- `SilicIATests/PromptLoaderTests.swift`
- `SilicIATests/RAGSearchToolTests.swift`
- `SilicIATests/SanitizerTests.swift`
- `SilicIATests/TokenBudgetingTests.swift`
- `SilicIATests/ToolCallGovernorTests.swift`
- `SilicIATests/ToolCallingPromptTests.swift`
- `SilicIATests/ToolKitBudgetTests.swift`
- `SilicIATests/ToolTranscriptRecorderTests.swift`
- `SilicIATests/WebSearchServiceTests.swift`
- `SilicIATests/WikipediaQueryCleanerTests.swift`
- `TestRAG/test.swift`

## Audit Trail

- EXTRACTED: 68 (100%)
- INFERRED: 0 (0%)
- AMBIGUOUS: 0 (0%)

---

*Part of the graphify knowledge wiki. See [index](index.md) to navigate.*