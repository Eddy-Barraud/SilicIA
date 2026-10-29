# Graph Report - SilicIA  (2026-10-29)

## Corpus Check
- 334 files · ~104,183 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 14 file(s) not represented in the graph (top: (none) 4, .entitlements 3, .plist 2)

## Summary
- 1448 nodes · 3459 edges · 69 communities (47 shown, 22 thin omitted)
- Extraction: 92% EXTRACTED · 8% INFERRED · 0% AMBIGUOUS · INFERRED: 261 edges (avg confidence: 0.85)
- Token cost: 28,277 input · 3,500 output

## Community Hubs (Navigation)
- RAG Retrieval & Chunking
- SwiftData Conversation Persistence
- On-Device LLM & Privacy Policy
- Dual Web Search & Tests
- Chat Interface & Streaming
- Web Content Scraping & Errors
- Image Analysis & Visual Grounding
- Foundation Model Hardware Availability
- Search Assist View & Grounding
- LaTeX Stream Segmentation
- System Prompt Template Loader
- App Store Screenshot Generation
- Safari Share Extension
- GitHub Actions Build CI
- Multi-Query Search Sources Tool
- GitHub Release & Notarization CI
- Xcode Test Workflow CI
- Keyboard Dismiss Gesture Handler
- Tool Calling Governor & Rate Limiting
- Web Search Scraper Verification CI
- On-Device Calculator Tool
- System Framework Integrations
- Network Constants & App Navigation
- App Settings & Tool Test Fixtures
- Markdown Rendering & Code Blocks
- Dropped File Context Store
- In-App Purchase StoreKit Manager
- Model Loading & Inference Engine
- PDF Text Extraction & Storage
- URL Attachment Input Row
- UI Localization String Resolution
- PDF File Picker & Importer
- Tool Calling Prompt Unit Tests
- Web Search Engine Unit Tests
- PDF Page Rendering & Preview
- RAG Relevance Scoring Engine
- Navigation Tabs & Views Container
- App Configuration & Token Budgets
- Chat History Sidebar View
- Settings Serialization & Coding Keys
- System Date & Time Tool
- Tool Call Transcript Recorder
- App Entry Point & Lifecycle
- Glassmorphic Message Bubble Styling
- Search Result Cards & Safari View
- Wikipedia Query Normalizer
- Glassmorphic Design System Components
- SilicIA Product Overview & Models
- Tool Budgeting & Execution Assembly
- RAG & PDF Chunking Tests
- macOS Application Delegate Lifecycle
- Search Relevance Match Score Badge
- SwiftUI View Rendering Test Suite
- GitHub Development Helper CLI
- AppSettings Store Persistence
- Token Budget Slider Controls
- Search Source Toggle Controls
- Streaming LaTeX Math Display
- Legacy Settings Migration Keys
- Web Scraped HTML to Markdown
- AppSettings Store Unit Tests
- Build & Contribution Guidelines
- Brand Logo Icon Generation
- Shell Build Automation Script
- Build and Run Shell Script
- TestRAG French Wiki Benchmark
- Offline Chat Mode Concept
- Token Budgeting Engine Concept

## God Nodes (most connected - your core abstractions)
1. `ModelLanguage` - 86 edges
2. `ChatService` - 76 edges
3. `ChatView` - 69 edges
4. `SearchView` - 66 edges
5. `WebSearchService` - 56 edges
6. `RAGContextService` - 52 edges
7. `WebScrapingService` - 41 edges
8. `AIService` - 39 edges
9. `SearchResult` - 38 edges
10. `RAGChunk` - 31 edges

## Surprising Connections (you probably didn't know these)
- `Scientific PDF Test Fixtures (PFAS CMC)` --semantically_similar_to--> `DroppedPDFStore`  [INFERRED] [semantically similar]
  SilicIATests/2025.PFAS.CMC.pdf → SilicIA/Services/DroppedPDFStore.swift
- `SilicIATests Suite` --references--> `WebSearchServiceTests`  [INFERRED]
  BUILDING.md → SilicIATests/WebSearchServiceTests.swift
- `Multi-Language UI & Prompts` --implements--> `ModelLanguage`  [EXTRACTED]
  README.md → SilicIA/Models/AppSettings.swift
- `SwiftData Chat Persistence` --implements--> `Conversation`  [EXTRACTED]
  README.md → SilicIA/Models/Conversation.swift
- `SwiftData Chat Persistence` --implements--> `Message`  [EXTRACTED]
  README.md → SilicIA/Models/Message.swift

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **RAG Retrieval Pipeline Components** — readme_rag_pipeline, silicia_services_chatservice_chatservice, silicia_services_ragcontextservice, silicia_services_tokenbudgeting_tokenbudgeting, silicia_services_aiservice_aiservice [INFERRED 0.95]
- **Privacy-Preserving On-Device Architecture** — privacy_local_processing_guarantee, readme_on_device_llm, silicia_services_aiservice_aiservice, silicia_models_conversation_conversation [INFERRED 0.95]
- **Multilingual UI & System Prompt Ecosystem** — readme_multilanguage_support, silicia_services_localizationservice_localizationservice, silicia_models_appsettings_modellanguage, silicia_services_promptloader_promptloader, silicia_prompts_system_prompt_framework [INFERRED 0.95]

## Communities (69 total, 22 thin omitted)

### Community 0 - "RAG Retrieval & Chunking"
Cohesion: 0.06
Nodes (16): Accelerate, RAG Retrieval Pipeline, HTMLSanitizer, MarkdownSegment, prose, table, RAGChunk, RAGChunker (+8 more)

### Community 1 - "SwiftData Conversation Persistence"
Cohesion: 0.07
Nodes (10): SwiftData Chat Persistence, Conversation, Message, Search Tool Calling Definition, ChatMessage, ChatService, Role, assistant (+2 more)

### Community 2 - "On-Device LLM & Privacy Policy"
Cohesion: 0.06
Nodes (16): Local Processing Guarantee, SilicIA Privacy Policy, On-Device LLM (Apple Intelligence), Local LLM Chat Showcase, Privacy Feature Showcase, SearchResponse, SearchResult, AIService (+8 more)

### Community 3 - "Dual Web Search & Tests"
Cohesion: 0.06
Nodes (17): SilicIATests Suite, Dual Web Search Architecture, Multi-Language UI & Prompts, Dual Web Search Showcase, ModelLanguage, .code, english, french (+9 more)

### Community 4 - "Chat Interface & Streaming"
Cohesion: 0.08
Nodes (19): ChatView, .attachmentMenu, .body, .chatHeaderView, .chatSettingsPage, .composerView, .effectiveIsWebSearchEnabled, .effectiveUseDuckDuckGo (+11 more)

### Community 5 - "Web Content Scraping & Errors"
Cohesion: 0.08
Nodes (19): HTMLConversionError, conversionFailed, emptyContent, .errorDescription, excessiveDOMDepth, excessiveElementCount, inputTooLarge, ReaderWebPageContent (+11 more)

### Community 6 - "Image Analysis & Visual Grounding"
Cohesion: 0.08
Nodes (10): ImageIO, ArticleRowProjection, ImageAnalysisResult, .isEmpty, ImageAnalysisService, LayoutObservation, PDFPageAnalysisResult, .isEmpty (+2 more)

### Community 7 - "Foundation Model Hardware Availability"
Cohesion: 0.06
Nodes (22): .isReaderViewAndSummaryEnabled, FoundationModelAvailability, Reason, deviceNotEligible, .isUserFixable, modelNotReady, notEnabled, other (+14 more)

### Community 8 - "Search Assist View & Grounding"
Cohesion: 0.09
Nodes (20): Search Prompt Instructions, SearchView, .body, .chatButtonTitle, .defaultScrapingCharactersFromContextTokens, .effectiveContextTokens, .emptyStateView, .exampleQueryChips (+12 more)

### Community 9 - "LaTeX Stream Segmentation"
Cohesion: 0.12
Nodes (5): LaTeXStreamSegmenter, ModelOutputLaTeXSanitizer, .body, LaTeXStreamSegmenterTests, SanitizerTests

### Community 10 - "System Prompt Template Loader"
Cohesion: 0.12
Nodes (9): System Prompt Framework, BundleToken, PromptLoader, Configuration, ToolCallingTone, chat, search, ToolKit (+1 more)

### Community 11 - "App Store Screenshot Generation"
Cohesion: 0.10
Nodes (16): draw_text_wrapped(), load_font(), main(), make_phone_mockup(), pill_badge(), radial_glow(), render_slide(), vertical_gradient() (+8 more)

### Community 13 - "GitHub Actions Build CI"
Cohesion: 0.07
Nodes (26): GitHub Automation & CI, env, runs-on, steps, CODE_SIGN_IDENTITY, CODE_SIGNING_ALLOWED, CODE_SIGNING_REQUIRED, DEVELOPMENT_TEAM (+18 more)

### Community 14 - "Multi-Query Search Sources Tool"
Cohesion: 0.14
Nodes (7): Arguments, SearchSourcesTool, WebSourcesTool, WikiSourcesTool, SourceFunnel, CapturedResultsBox, TestRAGMain

### Community 15 - "GitHub Release & Notarization CI"
Cohesion: 0.08
Nodes (25): APPLE_APP_SPECIFIC_PASSWORD, APPLE_ID, APPLE_TEAM_ID, BUILD_CERTIFICATE_BASE64, GITHUB_TOKEN, P12_PASSWORD, jobs, release (+17 more)

### Community 16 - "Xcode Test Workflow CI"
Cohesion: 0.08
Nodes (25): CODE_SIGN_IDENTITY, CODE_SIGNING_ALLOWED, CODE_SIGNING_REQUIRED, DEVELOPMENT_TEAM, jobs, test, name, on (+17 more)

### Community 17 - "Keyboard Dismiss Gesture Handler"
Cohesion: 0.15
Nodes (3): Coordinator, KeyboardDismissTapOverlay, WindowTrackingView

### Community 18 - "Tool Calling Governor & Rate Limiting"
Cohesion: 0.14
Nodes (14): Decision, allow, .description, duplicate, .refusalMessage, toolBudgetReached, totalBudgetReached, ToolCallGovernor (+6 more)

### Community 19 - "Web Search Scraper Verification CI"
Cohesion: 0.08
Nodes (23): env, runs-on, steps, CODE_SIGN_IDENTITY, CODE_SIGNING_ALLOWED, CODE_SIGNING_REQUIRED, DEVELOPMENT_TEAM, jobs (+15 more)

### Community 20 - "On-Device Calculator Tool"
Cohesion: 0.17
Nodes (3): Arguments, CalculatorTool, CalculatorToolTests

### Community 21 - "System Framework Integrations"
Cohesion: 0.17
Nodes (7): Combine, Foundation, FoundationModels, NaturalLanguage, WikipediaSearchFallbackPage, WikipediaSearchFallbackResponse, StoreKit

### Community 22 - "Network Constants & App Navigation"
Cohesion: 0.11
Nodes (11): NetworkConstants, ChatViewMode, full, pdfTalkme, FilePickerKind, .allowedContentTypes, image, pdf (+3 more)

### Community 23 - "App Settings & Tool Test Fixtures"
Cohesion: 0.17
Nodes (3): Observation, SilicIA, XCTest

### Community 24 - "Markdown Rendering & Code Blocks"
Cohesion: 0.15
Nodes (13): MarkdownBlock, code, heading, horizontalRule, .id, orderedList, paragraph, quote (+5 more)

### Community 25 - "Dropped File Context Store"
Cohesion: 0.16
Nodes (4): DroppedFileStore, .storageDirectory, DroppedImageStore, .storageDirectory

### Community 27 - "Model Loading & Inference Engine"
Cohesion: 0.20
Nodes (6): Arguments, RAGSearchTool, ChatServicePDFChunkPolicyTests, ModelLanguageTests, RAGSearchToolTests, ToolTranscriptRecorderTests

### Community 29 - "URL Attachment Input Row"
Cohesion: 0.18
Nodes (5): PDF Analysis & Grounding, PDF Context & Citation Showcase, DroppedPDFStore, .storageDirectory, Scientific PDF Test Fixtures (PFAS CMC)

### Community 30 - "UI Localization String Resolution"
Cohesion: 0.20
Nodes (5): DebugRAGStorage, .debugRootDirectory, .promptsDirectory, .rankedChunksDirectory, .webpagesDirectory

### Community 33 - "Web Search Engine Unit Tests"
Cohesion: 0.24
Nodes (4): CitationLink, ReaderHTMLWebView, .body, .webPageSummaryOverlay

### Community 34 - "PDF Page Rendering & Preview"
Cohesion: 0.21
Nodes (5): Entitlements, .canAttachDocuments, .canExceedFreeOutputTokens, .canUseMultipleWebSourcesPerProvider, .hasPremiumAccess

### Community 35 - "RAG Relevance Scoring Engine"
Cohesion: 0.17
Nodes (4): AppIntents, SilicIAAppShortcuts, .appShortcuts, OpenSilicIASearchIntent

### Community 36 - "Navigation Tabs & Views Container"
Cohesion: 0.18
Nodes (9): AppTab, chat, .id, searchAssist, ContentView, .body, .language, .selectedTab (+1 more)

### Community 37 - "App Configuration & Token Budgets"
Cohesion: 0.18
Nodes (6): AppSettings, .isWebSummariesEnabled, .maxSearchResults, .totalTokensBudget, .maxAllowedContextTokensForCurrentResponse, .body

### Community 38 - "Chat History Sidebar View"
Cohesion: 0.21
Nodes (3): ConversationsListView, .body, .language

### Community 39 - "Settings Serialization & Coding Keys"
Cohesion: 0.17
Nodes (12): CodingKeys, isReaderViewAndSummaryEnabled, isWebSummariesEnabled, language, maxContextTokens, maxDuckDuckGoResults, maxResponseTokens, maxWikipediaResults (+4 more)

### Community 40 - "System Date & Time Tool"
Cohesion: 0.29
Nodes (6): Arguments, DateTimeTool, Mode, both, dateOnly, timeOnly

### Community 43 - "Glassmorphic Message Bubble Styling"
Cohesion: 0.18
Nodes (6): MessageBubbleGlass, PlatformColors, .controlBackground, .textBackground, Color, .platformWindowBackground

### Community 44 - "Search Result Cards & Safari View"
Cohesion: 0.24
Nodes (7): SafariServices, FeatureRow, .body, SearchResultCard, .body, .isWebSummariesEnabled, WebKit

### Community 47 - "SilicIA Product Overview & Models"
Cohesion: 0.22
Nodes (5): App Store Short Description, SilicIA Brand Identity & Icon Assets, SilicIA Assistant, Math & Factorial UI Rendering, SwiftData

### Community 49 - "RAG & PDF Chunking Tests"
Cohesion: 0.36
Nodes (4): AppKit, CoreGraphics, PDFKit, Vision

### Community 51 - "Search Relevance Match Score Badge"
Cohesion: 0.25
Nodes (5): MatchScoreBadge, .body, .clampedPercent, .displayPercent, .progress

### Community 53 - "GitHub Development Helper CLI"
Cohesion: 0.52
Nodes (6): check_build_status(), check_repo_stats(), create_feature_branch(), print_menu(), github-helper.sh script, view_recent_commits()

### Community 55 - "Token Budget Slider Controls"
Cohesion: 0.29
Nodes (6): .chatSettingsPanel, TokenBudgetSliderView, .estimatedContextWords, .estimatedOutputWords, .outputProfile, .profileBadgeColor

### Community 57 - "Streaming LaTeX Math Display"
Cohesion: 0.33
Nodes (3): LaTeXSwiftUI, StreamingLaTeXText, .foreground

### Community 58 - "Legacy Settings Migration Keys"
Cohesion: 0.40
Nodes (4): LegacyCodingKeys, maxContextWords, maxScrapingCharacters, maxSearchResults

### Community 59 - "Web Scraped HTML to Markdown"
Cohesion: 0.40
Nodes (4): HTMLToMarkdown, URL Context Extraction, Reeeed, Multi-Context Chat Showcase

### Community 61 - "Build & Contribution Guidelines"
Cohesion: 0.67
Nodes (3): Build & Tooling Configuration, Build Scripts (scripts/build.sh), Contributing Guidelines

## Knowledge Gaps
- **162 isolated node(s):** `searchAssist`, `chat`, `.id`, `.language`, `.selectedTabBinding` (+157 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 401 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **22 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ModelLanguage` connect `Dual Web Search & Tests` to `RAG Retrieval & Chunking`, `SwiftData Conversation Persistence`, `On-Device LLM & Privacy Policy`, `Navigation Tabs & Views Container`, `App Configuration & Token Budgets`, `Chat History Sidebar View`, `Foundation Model Hardware Availability`, `System Date & Time Tool`, `System Prompt Template Loader`, `Search Result Cards & Safari View`, `Multi-Query Search Sources Tool`, `Search Relevance Match Score Badge`, `System Framework Integrations`, `Token Budget Slider Controls`, `Model Loading & Inference Engine`?**
  _High betweenness centrality (0.158) - this node is a cross-community bridge._
- **Are the 7 inferred relationships involving `ChatService` (e.g. with `ContentView` and `Search Tool Calling Definition`) actually correct?**
  _`ChatService` has 7 INFERRED edges - model-reasoned connections that need verification._
- **What connects `searchAssist`, `chat`, `.id` to the rest of the system?**
  _162 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `RAG Retrieval & Chunking` be split into smaller, more focused modules?**
  _Cohesion score 0.058151609553478714 - nodes in this community are weakly interconnected._
- **Why does `ChatService` connect `SwiftData Conversation Persistence` to `RAG Retrieval & Chunking`, `PDF Page Rendering & Preview`, `Dual Web Search & Tests`, `Chat Interface & Streaming`, `Navigation Tabs & Views Container`, `Web Content Scraping & Errors`, `Foundation Model Hardware Availability`, `Search Assist View & Grounding`, `SwiftUI View Rendering Test Suite`, `System Framework Integrations`, `PDF File Picker & Importer`?**
  _High betweenness centrality (0.136) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `ChatView` (e.g. with `.body` and `.testMainViewsRenderWithoutCrashing()`) actually correct?**
  _`ChatView` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Should `SwiftData Conversation Persistence` be split into smaller, more focused modules?**
  _Cohesion score 0.07175689479060265 - nodes in this community are weakly interconnected._