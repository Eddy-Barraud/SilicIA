# SwiftData Conversation Persistence

> 89 nodes · cohesion 0.07

## Key Concepts

- **ChatService** (76 connections) — `SilicIA/Services/ChatService.swift`
- **.sendMessage()** (41 connections) — `SilicIA/Services/ChatService.swift`
- **String** (34 connections)
- **.collectChunks()** (26 connections) — `SilicIA/Services/ChatService.swift`
- **ChatMessage** (20 connections) — `SilicIA/Services/ChatService.swift`
- **Int** (19 connections)
- **Conversation** (17 connections) — `SilicIA/Models/Conversation.swift`
- **Bool** (14 connections)
- **.assembleToolCallingPrompt()** (13 connections) — `SilicIA/Services/ChatService.swift`
- **.preAnalyzeContext()** (13 connections) — `SilicIA/Services/ChatService.swift`
- **.discoverWebResults()** (12 connections) — `SilicIA/Services/ChatService.swift`
- **.regenerateAssistantMessage()** (12 connections) — `SilicIA/Services/ChatService.swift`
- **.streamClassicalFallback()** (12 connections) — `SilicIA/Services/ChatService.swift`
- **.streamToolTranscriptRecovery()** (12 connections) — `SilicIA/Services/ChatService.swift`
- **ToolCallingPromptTests** (11 connections) — `SilicIATests/ToolCallingPromptTests.swift`
- **Message** (10 connections) — `SilicIA/Models/Message.swift`
- **.pdfBaseFilename()** (10 connections) — `SilicIA/Services/ChatService.swift`
- **.persistMessage()** (10 connections) — `SilicIA/Services/ChatService.swift`
- **URL** (10 connections)
- **.buildInstructions()** (9 connections) — `SilicIA/Services/ChatService.swift`
- **.startConversationFromSearch()** (9 connections) — `SilicIA/Services/ChatService.swift`
- **.buildToolCallingPrompt()** (8 connections) — `SilicIA/Services/ChatService.swift`
- **.buildToolTranscriptRecoveryPrompt()** (8 connections) — `SilicIA/Services/ChatService.swift`
- **.debugContext()** (7 connections) — `SilicIA/Services/ChatService.swift`
- **.makeContextKey()** (7 connections) — `SilicIA/Services/ChatService.swift`
- *... and 64 more nodes in this community*

## Relationships

- [Chat Interface & Streaming](Chat_Interface_&_Streaming.md) (17 shared connections)
- [On-Device LLM & Privacy Policy](On-Device_LLM_&_Privacy_Policy.md) (14 shared connections)
- [Dual Web Search & Tests](Dual_Web_Search_&_Tests.md) (14 shared connections)
- [RAG Retrieval & Chunking](RAG_Retrieval_&_Chunking.md) (12 shared connections)
- [Foundation Model Hardware Availability](Foundation_Model_Hardware_Availability.md) (7 shared connections)
- [Navigation Tabs & Views Container](Navigation_Tabs_&_Views_Container.md) (3 shared connections)
- [System Prompt Template Loader](System_Prompt_Template_Loader.md) (3 shared connections)
- [LaTeX Stream Segmentation](LaTeX_Stream_Segmentation.md) (3 shared connections)
- [Chat History Sidebar View](Chat_History_Sidebar_View.md) (2 shared connections)
- [SilicIA Product Overview & Models](SilicIA_Product_Overview_&_Models.md) (2 shared connections)
- [System Framework Integrations](System_Framework_Integrations.md) (2 shared connections)
- [Web Content Scraping & Errors](Web_Content_Scraping_&_Errors.md) (2 shared connections)

## Source Files

- `README.md`
- `SilicIA/Models/Conversation.swift`
- `SilicIA/Models/Message.swift`
- `SilicIA/Services/ChatService.swift`
- `SilicIA/prompts/prompt.normal.search.tool_calling.en.txt`
- `SilicIATests/ToolCallingPromptTests.swift`

## Audit Trail

- EXTRACTED: 342 (92%)
- INFERRED: 31 (8%)
- AMBIGUOUS: 0 (0%)

---

*Part of the graphify knowledge wiki. See [index](index.md) to navigate.*