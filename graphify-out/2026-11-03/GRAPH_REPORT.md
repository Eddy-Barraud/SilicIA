# Graph Report - SilicIA  (2026-11-03)

## Corpus Check
- 121 files · ~106,188 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 15 file(s) not represented in the graph (top: (none) 5, .entitlements 3, .plist 2)

## Summary
- 1524 nodes · 3648 edges · 64 communities (49 shown, 15 thin omitted)
- Extraction: 93% EXTRACTED · 7% INFERRED · 0% AMBIGUOUS · INFERRED: 268 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `7dada8b8`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- RAG Retrieval & Chunking
- SwiftData Conversation Persistence
- TokenBudgeting
- Dual Web Search & Tests
- Chat Interface & Streaming
- Web Content Scraping & Errors
- Image Analysis & Visual Grounding
- Foundation Model Hardware Availability
- Search Assist View & Grounding
- LaTeX Stream Segmentation
- .loadPrompt
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
- SwiftUI
- App Settings & Tool Test Fixtures
- Markdown Rendering & Code Blocks
- DroppedFileStore
- PurchaseManager
- Model Loading & Inference Engine
- .acquireSession
- .persist
- ReaderHTMLWebViewRepresentable
- AIService
- Web Search Engine Unit Tests
- String
- RAG Relevance Scoring Engine
- Navigation Tabs & Views Container
- AppSettings
- TokenBudgetingTests
- Settings Serialization & Coding Keys
- System Date & Time Tool
- Tool Call Transcript Recorder
- DynamicSessionMode
- HTMLSanitizer
- SilicIADynamicInstructions
- Wikipedia Query Normalizer
- View
- .check
- Tool Budgeting & Execution Assembly
- RAG & PDF Chunking Tests
- Search Relevance Match Score Badge
- bug_report.md
- GitHub Development Helper CLI
- pull_request_template.md
- Token Budget Slider Controls
- ChatView.swift
- StreamingLaTeXText
- feature_request.md
- Brand Logo Icon Generation
- Shell Build Automation Script
- Build and Run Shell Script
- TestRAG French Wiki Benchmark
- Offline Chat Mode Concept
- Token Budgeting Engine Concept

## God Nodes (most connected - your core abstractions)
1. `ModelLanguage` - 88 edges
2. `ChatService` - 77 edges
3. `ChatView` - 69 edges
4. `SearchView` - 65 edges
5. `WebSearchService` - 57 edges
6. `RAGContextService` - 53 edges
7. `WebScrapingService` - 42 edges
8. `AIService` - 41 edges
9. `SearchResult` - 38 edges
10. `AppSettings` - 33 edges

## Surprising Connections (you probably didn't know these)
- `Scientific PDF Test Fixtures (PFAS CMC)` --semantically_similar_to--> `DroppedPDFStore`  [INFERRED] [semantically similar]
  SilicIATests/2025.PFAS.CMC.pdf → SilicIA/Services/DroppedPDFStore.swift
- `SilicIATests Suite` --references--> `WebSearchServiceTests`  [INFERRED]
  BUILDING.md → SilicIATests/WebSearchServiceTests.swift
- `SilicIA Brand Identity & Icon Assets` --references--> `SilicIA Assistant`  [INFERRED]
  logo/appicon_big.png → README.md
- `Math & Factorial UI Rendering` --conceptually_related_to--> `SilicIA Assistant`  [INFERRED]
  Screenshots/Factorial.png → README.md
- `Multi-Language UI & Prompts` --implements--> `ModelLanguage`  [EXTRACTED]
  README.md → SilicIA/Models/AppSettings.swift

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Multilingual UI & System Prompt Ecosystem** — readme_multilanguage_support, silicia_services_localizationservice_localizationservice, silicia_models_appsettings_modellanguage, silicia_services_promptloader_promptloader, silicia_prompts_system_prompt_framework [INFERRED 0.95]
- **Privacy-Preserving On-Device Architecture** — privacy_local_processing_guarantee, readme_on_device_llm, silicia_services_aiservice_aiservice, silicia_models_conversation_conversation [INFERRED 0.95]
- **RAG Retrieval Pipeline Components** — readme_rag_pipeline, silicia_services_chatservice_chatservice, silicia_services_ragcontextservice, silicia_services_tokenbudgeting_tokenbudgeting, silicia_services_aiservice_aiservice [INFERRED 0.95]

## Communities (64 total, 15 thin omitted)

### Community 0 - "RAG Retrieval & Chunking"
Cohesion: 0.06
Nodes (16): Accelerate, RAG Retrieval Pipeline, MarkdownSegment, prose, table, RAGChunk, RAGChunker, RAGCitationFormatter (+8 more)

### Community 1 - "SwiftData Conversation Persistence"
Cohesion: 0.07
Nodes (11): SwiftData Chat Persistence, .body, Conversation, Message, Search Tool Calling Definition, ChatMessage, ChatService, Role (+3 more)

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
Cohesion: 0.10
Nodes (9): ImageIO, ArticleRowProjection, ImageAnalysisResult, .isEmpty, ImageAnalysisService, LayoutObservation, PDFPageAnalysisResult, .isEmpty (+1 more)

### Community 7 - "Foundation Model Hardware Availability"
Cohesion: 0.10
Nodes (17): FoundationModelAvailability, Reason, deviceNotEligible, .isUserFixable, modelNotReady, notEnabled, other, .stringValue (+9 more)

### Community 8 - "Search Assist View & Grounding"
Cohesion: 0.09
Nodes (19): Search Prompt Instructions, SearchView, .body, .chatButtonTitle, .defaultScrapingCharactersFromContextTokens, .effectiveContextTokens, .emptyStateView, .exampleQueryChips (+11 more)

### Community 9 - "LaTeX Stream Segmentation"
Cohesion: 0.12
Nodes (5): LaTeXStreamSegmenter, ModelOutputLaTeXSanitizer, .body, LaTeXStreamSegmenterTests, SanitizerTests

### Community 10 - ".loadPrompt"
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
Cohesion: 0.14
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
Cohesion: 0.11
Nodes (14): Combine, Foundation, FoundationModels, HTMLToMarkdown, NaturalLanguage, os, URL Context Extraction, Reeeed (+6 more)

### Community 22 - "SwiftUI"
Cohesion: 0.11
Nodes (11): App Store Short Description, Build & Tooling Configuration, Build Scripts (scripts/build.sh), Contributing Guidelines, LaTeXSwiftUI, SilicIA Brand Identity & Icon Assets, SilicIA Assistant, Math & Factorial UI Rendering (+3 more)

### Community 23 - "App Settings & Tool Test Fixtures"
Cohesion: 0.18
Nodes (3): Observation, SilicIA, XCTest

### Community 24 - "Markdown Rendering & Code Blocks"
Cohesion: 0.15
Nodes (13): MarkdownBlock, code, heading, horizontalRule, .id, orderedList, paragraph, quote (+5 more)

### Community 25 - "DroppedFileStore"
Cohesion: 0.09
Nodes (10): PDF Analysis & Grounding, PDF Context & Citation Showcase, DroppedFileStore, .storageDirectory, DroppedPDFStore, .storageDirectory, ConversationsListView, .body (+2 more)

### Community 26 - "PurchaseManager"
Cohesion: 0.05
Nodes (11): Entitlements, .canAttachDocuments, .canExceedFreeOutputTokens, .canUseMultipleWebSourcesPerProvider, .hasPremiumAccess, FoundingUserStore, PurchaseManager, AppDelegate (+3 more)

### Community 27 - "Model Loading & Inference Engine"
Cohesion: 0.44
Nodes (3): Arguments, RAGSearchTool, RAGSearchToolTests

### Community 29 - ".acquireSession"
Cohesion: 0.20
Nodes (6): DynamicSessionCoordinator, .currentSnapshot, DynamicSessionStateStore, .current, SilicIADynamicProfile, Snapshot

### Community 31 - "ReaderHTMLWebViewRepresentable"
Cohesion: 0.12
Nodes (6): Coordinator, NonScrollingWKWebView, ReaderHTMLWebView, .body, ReaderHTMLWebViewRepresentable, WebKit

### Community 32 - "AIService"
Cohesion: 0.06
Nodes (15): Local Processing Guarantee, SilicIA Privacy Policy, On-Device LLM (Apple Intelligence), Local LLM Chat Showcase, Privacy Feature Showcase, SearchResponse, SearchResult, AIService (+7 more)

### Community 33 - "Web Search Engine Unit Tests"
Cohesion: 0.25
Nodes (3): CitationLink, FeatureRow, .body

### Community 34 - "String"
Cohesion: 0.16
Nodes (8): OutputProfile, .reasoningLevel, OutputProfileKind, concise, detailed, .reasoningLevel, standard, ModelLanguageTests

### Community 35 - "RAG Relevance Scoring Engine"
Cohesion: 0.17
Nodes (4): AppIntents, SilicIAAppShortcuts, .appShortcuts, OpenSilicIASearchIntent

### Community 36 - "Navigation Tabs & Views Container"
Cohesion: 0.15
Nodes (9): AppTab, chat, .id, searchAssist, ContentView, .language, .selectedTab, .selectedTabBinding (+1 more)

### Community 37 - "AppSettings"
Cohesion: 0.11
Nodes (8): AppSettings, .isWebSummariesEnabled, .maxSearchResults, .totalTokensBudget, AppSettingsStore, .settings, .maxAllowedContextTokensForCurrentResponse, AppSettingsStoreTests

### Community 39 - "Settings Serialization & Coding Keys"
Cohesion: 0.12
Nodes (16): CodingKeys, isReaderViewAndSummaryEnabled, isWebSummariesEnabled, language, maxContextTokens, maxDuckDuckGoResults, maxResponseTokens, maxWikipediaResults (+8 more)

### Community 40 - "System Date & Time Tool"
Cohesion: 0.29
Nodes (6): Arguments, DateTimeTool, Mode, both, dateOnly, timeOnly

### Community 42 - "DynamicSessionMode"
Cohesion: 0.22
Nodes (7): DynamicSessionMode, chat, chatFallback, searchQueryGeneration, searchSummary, webPageSummary, PrewarmKey

### Community 44 - "SilicIADynamicInstructions"
Cohesion: 0.25
Nodes (3): SilicIADynamicInstructions, .body, .body

### Community 46 - "View"
Cohesion: 0.12
Nodes (5): MessageBubbleGlass, View, .headerView, SourceToggleButtons, .body

### Community 48 - "Tool Budgeting & Execution Assembly"
Cohesion: 0.24
Nodes (3): ChatServicePDFChunkPolicyTests, ToolKitBudgetTests, ToolTranscriptRecorderTests

### Community 49 - "RAG & PDF Chunking Tests"
Cohesion: 0.36
Nodes (4): AppKit, CoreGraphics, PDFKit, Vision

### Community 51 - "Search Relevance Match Score Badge"
Cohesion: 0.18
Nodes (8): MatchScoreBadge, .body, .clampedPercent, .displayPercent, .progress, SearchResultCard, .body, .isWebSummariesEnabled

### Community 52 - "bug_report.md"
Cohesion: 0.22
Nodes (8): Actual Behavior, Additional Context, Describe the Bug, Environment, Error Logs, Expected Behavior, Screenshots, Steps to Reproduce

### Community 53 - "GitHub Development Helper CLI"
Cohesion: 0.52
Nodes (6): check_build_status(), check_repo_stats(), create_feature_branch(), print_menu(), github-helper.sh script, view_recent_commits()

### Community 54 - "pull_request_template.md"
Cohesion: 0.22
Nodes (8): Additional Notes, Changes Made, Checklist, Description, Related Issues, Screenshots (if applicable), Testing, Type of Change

### Community 55 - "Token Budget Slider Controls"
Cohesion: 0.22
Nodes (7): .chatSettingsPanel, TokenBudgetSliderView, .body, .estimatedContextWords, .estimatedOutputWords, .outputProfile, .profileBadgeColor

### Community 56 - "ChatView.swift"
Cohesion: 0.15
Nodes (9): SafariServices, ChatViewMode, full, pdfTalkme, FilePickerKind, .allowedContentTypes, image, pdf (+1 more)

### Community 57 - "StreamingLaTeXText"
Cohesion: 0.14
Nodes (9): PlatformColors, .controlBackground, .textBackground, Color, .platformWindowBackground, .summaryCard, .webPageSummaryOverlay, StreamingLaTeXText (+1 more)

### Community 58 - "feature_request.md"
Cohesion: 0.40
Nodes (4): Additional Context, Describe Alternatives You've Considered, Describe the Solution You'd Like, Is Your Feature Request Related to a Problem?

## Knowledge Gaps
- **172 isolated node(s):** `searchAssist`, `chat`, `.id`, `.language`, `.selectedTabBinding` (+167 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 438 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **15 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ChatService` connect `SwiftData Conversation Persistence` to `RAG Retrieval & Chunking`, `AIService`, `Dual Web Search & Tests`, `Chat Interface & Streaming`, `Navigation Tabs & Views Container`, `Web Content Scraping & Errors`, `Search Assist View & Grounding`, `System Framework Integrations`, `PurchaseManager`, `ReaderHTMLWebViewRepresentable`?**
  _High betweenness centrality (0.146) - this node is a cross-community bridge._
- **Are the 7 inferred relationships involving `ChatService` (e.g. with `ContentView` and `Search Tool Calling Definition`) actually correct?**
  _`ChatService` has 7 INFERRED edges - model-reasoned connections that need verification._
- **What connects `searchAssist`, `chat`, `.id` to the rest of the system?**
  _172 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `RAG Retrieval & Chunking` be split into smaller, more focused modules?**
  _Cohesion score 0.05836713101745724 - nodes in this community are weakly interconnected._
- **Why does `ModelLanguage` connect `Dual Web Search & Tests` to `AIService`, `SwiftData Conversation Persistence`, `String`, `RAG Retrieval & Chunking`, `Navigation Tabs & Views Container`, `AppSettings`, `Foundation Model Hardware Availability`, `System Date & Time Tool`, `.loadPrompt`, `Multi-Query Search Sources Tool`, `Search Relevance Match Score Badge`, `System Framework Integrations`, `Token Budget Slider Controls`, `DroppedFileStore`, `Model Loading & Inference Engine`, `.acquireSession`?**
  _High betweenness centrality (0.137) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `ChatView` (e.g. with `.body` and `.testMainViewsRenderWithoutCrashing()`) actually correct?**
  _`ChatView` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Should `SwiftData Conversation Persistence` be split into smaller, more focused modules?**
  _Cohesion score 0.06802244039270687 - nodes in this community are weakly interconnected._