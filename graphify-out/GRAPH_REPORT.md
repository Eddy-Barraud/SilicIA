# Graph Report - SilicIA  (2026-11-03)

## Corpus Check
- 121 files · ~106,896 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 15 file(s) not represented in the graph (top: (none) 5, .entitlements 3, .plist 2)

## Summary
- 1529 nodes · 3664 edges · 68 communities (55 shown, 13 thin omitted)
- Extraction: 93% EXTRACTED · 7% INFERRED · 0% AMBIGUOUS · INFERRED: 272 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `7dada8b8`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- RAG Retrieval & Chunking
- SwiftData Conversation Persistence
- .loadPrompt
- Dual Web Search & Tests
- Chat Interface & Streaming
- Web Content Scraping & Errors
- Image Analysis & Visual Grounding
- Foundation Model Hardware Availability
- Search Assist View & Grounding
- LaTeX Stream Segmentation
- ModelLanguage
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
- .loadIfNeeded
- .acquireSession
- LocalizationService
- ReaderHTMLWebViewRepresentable
- AIService
- Web Search Engine Unit Tests
- String
- RAG Relevance Scoring Engine
- Navigation Tabs & Views Container
- AppSettings
- DebugRAGStorage
- Settings Serialization & Coding Keys
- System Date & Time Tool
- Tool Call Transcript Recorder
- ModelAnsweringTests
- HTMLSanitizer
- SilicIADynamicInstructions
- Wikipedia Query Normalizer
- View
- SearchView.swift
- Tool Budgeting & Execution Assembly
- RAG & PDF Chunking Tests
- SilicIAApp.swift
- Search Relevance Match Score Badge
- bug_report.md
- GitHub Development Helper CLI
- pull_request_template.md
- Token Budget Slider Controls
- ChatView.swift
- StreamingLaTeXText
- feature_request.md
- FilePickerKind
- ModelAvailabilityNotice
- WebScrapingService.swift
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
10. `AppSettings` - 34 edges

## Surprising Connections (you probably didn't know these)
- `Scientific PDF Test Fixtures (PFAS CMC)` --semantically_similar_to--> `DroppedPDFStore`  [INFERRED] [semantically similar]
  SilicIATests/2025.PFAS.CMC.pdf → SilicIA/Services/DroppedPDFStore.swift
- `Multi-Language UI & Prompts` --implements--> `ModelLanguage`  [EXTRACTED]
  README.md → SilicIA/Models/AppSettings.swift
- `SilicIATests Suite` --references--> `WebSearchServiceTests`  [INFERRED]
  BUILDING.md → SilicIATests/WebSearchServiceTests.swift
- `SilicIA Brand Identity & Icon Assets` --references--> `SilicIA Assistant`  [INFERRED]
  logo/appicon_big.png → README.md
- `Math & Factorial UI Rendering` --conceptually_related_to--> `SilicIA Assistant`  [INFERRED]
  Screenshots/Factorial.png → README.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Multilingual UI & System Prompt Ecosystem** — readme_multilanguage_support, silicia_services_localizationservice_localizationservice, silicia_models_appsettings_modellanguage, silicia_services_promptloader_promptloader, silicia_prompts_system_prompt_framework [INFERRED 0.95]
- **Privacy-Preserving On-Device Architecture** — privacy_local_processing_guarantee, readme_on_device_llm, silicia_services_aiservice_aiservice, silicia_models_conversation_conversation [INFERRED 0.95]
- **RAG Retrieval Pipeline Components** — readme_rag_pipeline, silicia_services_chatservice_chatservice, silicia_services_ragcontextservice, silicia_services_tokenbudgeting_tokenbudgeting, silicia_services_aiservice_aiservice [INFERRED 0.95]

## Communities (68 total, 13 thin omitted)

### Community 0 - "RAG Retrieval & Chunking"
Cohesion: 0.06
Nodes (15): Accelerate, MarkdownSegment, prose, table, RAGChunk, RAGChunker, RAGCitationFormatter, RAGContextService (+7 more)

### Community 1 - "SwiftData Conversation Persistence"
Cohesion: 0.07
Nodes (11): SwiftData Chat Persistence, .body, Conversation, Message, Search Tool Calling Definition, ChatMessage, ChatService, Role (+3 more)

### Community 2 - ".loadPrompt"
Cohesion: 0.21
Nodes (4): System Prompt Framework, BundleToken, PromptLoader, PromptLoaderTests

### Community 3 - "Dual Web Search & Tests"
Cohesion: 0.09
Nodes (9): SilicIATests Suite, Dual Web Search Architecture, Dual Web Search Showcase, WebSearchService, .userAgent, WikipediaSearchFallbackPage, WikipediaSearchFallbackResponse, WikipediaWithHTMLResponse (+1 more)

### Community 4 - "Chat Interface & Streaming"
Cohesion: 0.07
Nodes (20): ChatView, .attachmentMenu, .body, .chatHeaderView, .chatSettingsPage, .composerView, .effectiveIsWebSearchEnabled, .effectiveUseDuckDuckGo (+12 more)

### Community 5 - "Web Content Scraping & Errors"
Cohesion: 0.08
Nodes (19): HTMLConversionError, conversionFailed, emptyContent, .errorDescription, excessiveDOMDepth, excessiveElementCount, inputTooLarge, ReaderWebPageContent (+11 more)

### Community 6 - "Image Analysis & Visual Grounding"
Cohesion: 0.10
Nodes (9): ImageIO, ArticleRowProjection, ImageAnalysisResult, .isEmpty, ImageAnalysisService, LayoutObservation, PDFPageAnalysisResult, .isEmpty (+1 more)

### Community 7 - "Foundation Model Hardware Availability"
Cohesion: 0.11
Nodes (16): .isReaderViewAndSummaryEnabled, FoundationModelAvailability, Reason, deviceNotEligible, .isUserFixable, modelNotReady, notEnabled, other (+8 more)

### Community 8 - "Search Assist View & Grounding"
Cohesion: 0.09
Nodes (19): Search Prompt Instructions, SearchView, .body, .chatButtonTitle, .defaultScrapingCharactersFromContextTokens, .effectiveContextTokens, .emptyStateView, .exampleQueryChips (+11 more)

### Community 9 - "LaTeX Stream Segmentation"
Cohesion: 0.12
Nodes (5): LaTeXStreamSegmenter, ModelOutputLaTeXSanitizer, .body, LaTeXStreamSegmenterTests, SanitizerTests

### Community 10 - "ModelLanguage"
Cohesion: 0.18
Nodes (11): ModelLanguage, .code, english, french, .nlLanguage, spanish, Configuration, ToolCallingTone (+3 more)

### Community 11 - "App Store Screenshot Generation"
Cohesion: 0.10
Nodes (16): draw_text_wrapped(), load_font(), main(), make_phone_mockup(), pill_badge(), radial_glow(), render_slide(), vertical_gradient() (+8 more)

### Community 13 - "GitHub Actions Build CI"
Cohesion: 0.07
Nodes (26): GitHub Automation & CI, env, runs-on, steps, CODE_SIGN_IDENTITY, CODE_SIGNING_ALLOWED, CODE_SIGNING_REQUIRED, DEVELOPMENT_TEAM (+18 more)

### Community 14 - "Multi-Query Search Sources Tool"
Cohesion: 0.12
Nodes (8): Arguments, SearchSourcesTool, SingleQueryArguments, WebSourcesTool, WikiSourcesTool, SourceFunnel, CapturedResultsBox, TestRAGMain

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
Cohesion: 0.18
Nodes (6): Combine, Foundation, FoundationModels, NaturalLanguage, os, StoreKit

### Community 22 - "SwiftUI"
Cohesion: 0.13
Nodes (8): LaTeXSwiftUI, PlatformColors, .controlBackground, .textBackground, Color, .platformWindowBackground, SwiftData, SwiftUI

### Community 23 - "App Settings & Tool Test Fixtures"
Cohesion: 0.17
Nodes (3): Observation, SilicIA, XCTest

### Community 24 - "Markdown Rendering & Code Blocks"
Cohesion: 0.15
Nodes (13): MarkdownBlock, code, heading, horizontalRule, .id, orderedList, paragraph, quote (+5 more)

### Community 25 - "DroppedFileStore"
Cohesion: 0.06
Nodes (13): PDF Analysis & Grounding, PDF Context & Citation Showcase, DroppedFileStore, .storageDirectory, DroppedImageStore, .storageDirectory, DroppedPDFStore, .storageDirectory (+5 more)

### Community 26 - "PurchaseManager"
Cohesion: 0.05
Nodes (11): Entitlements, .canAttachDocuments, .canExceedFreeOutputTokens, .canUseMultipleWebSourcesPerProvider, .hasPremiumAccess, FoundingUserStore, PurchaseManager, AppDelegate (+3 more)

### Community 27 - "Model Loading & Inference Engine"
Cohesion: 0.44
Nodes (3): Arguments, RAGSearchTool, RAGSearchToolTests

### Community 29 - ".acquireSession"
Cohesion: 0.13
Nodes (12): DynamicSessionCoordinator, .currentSnapshot, DynamicSessionMode, chat, chatFallback, searchQueryGeneration, searchSummary, webPageSummary (+4 more)

### Community 30 - "LocalizationService"
Cohesion: 0.20
Nodes (4): Multi-Language UI & Prompts, LocalizationService, LocalizationTests, .service

### Community 31 - "ReaderHTMLWebViewRepresentable"
Cohesion: 0.13
Nodes (4): Coordinator, ReaderHTMLWebView, .body, ReaderHTMLWebViewRepresentable

### Community 32 - "AIService"
Cohesion: 0.07
Nodes (12): Local Processing Guarantee, SilicIA Privacy Policy, On-Device LLM (Apple Intelligence), RAG Retrieval Pipeline, Local LLM Chat Showcase, Privacy Feature Showcase, SearchResponse, SearchResult (+4 more)

### Community 34 - "String"
Cohesion: 0.18
Nodes (8): OutputProfile, .reasoningLevel, OutputProfileKind, concise, detailed, .reasoningLevel, standard, ModelLanguageTests

### Community 35 - "RAG Relevance Scoring Engine"
Cohesion: 0.17
Nodes (4): AppIntents, SilicIAAppShortcuts, .appShortcuts, OpenSilicIASearchIntent

### Community 36 - "Navigation Tabs & Views Container"
Cohesion: 0.18
Nodes (8): AppTab, chat, .id, searchAssist, ContentView, .language, .selectedTab, .selectedTabBinding

### Community 37 - "AppSettings"
Cohesion: 0.10
Nodes (9): AppSettings, .isWebSummariesEnabled, .maxSearchResults, .totalTokensBudget, AppSettingsStore, .settings, .maxAllowedContextTokensForCurrentResponse, .body (+1 more)

### Community 38 - "DebugRAGStorage"
Cohesion: 0.20
Nodes (5): DebugRAGStorage, .debugRootDirectory, .promptsDirectory, .rankedChunksDirectory, .webpagesDirectory

### Community 39 - "Settings Serialization & Coding Keys"
Cohesion: 0.12
Nodes (16): CodingKeys, isReaderViewAndSummaryEnabled, isWebSummariesEnabled, language, maxContextTokens, maxDuckDuckGoResults, maxResponseTokens, maxWikipediaResults (+8 more)

### Community 40 - "System Date & Time Tool"
Cohesion: 0.29
Nodes (6): Arguments, DateTimeTool, Mode, both, dateOnly, timeOnly

### Community 44 - "SilicIADynamicInstructions"
Cohesion: 0.24
Nodes (4): SilicIADynamicInstructions, .body, SilicIADynamicProfile, .body

### Community 46 - "View"
Cohesion: 0.15
Nodes (4): View, .headerView, SourceToggleButtons, .body

### Community 47 - "SearchView.swift"
Cohesion: 0.27
Nodes (6): FeatureRow, .body, SearchResultCard, .body, .isWebSummariesEnabled, WebKit

### Community 48 - "Tool Budgeting & Execution Assembly"
Cohesion: 0.22
Nodes (3): ChatServicePDFChunkPolicyTests, ToolKitBudgetTests, ToolTranscriptRecorderTests

### Community 49 - "RAG & PDF Chunking Tests"
Cohesion: 0.43
Nodes (4): AppKit, CoreGraphics, PDFKit, Vision

### Community 50 - "SilicIAApp.swift"
Cohesion: 0.25
Nodes (7): App Store Short Description, Build & Tooling Configuration, Build Scripts (scripts/build.sh), Contributing Guidelines, SilicIA Brand Identity & Icon Assets, SilicIA Assistant, Math & Factorial UI Rendering

### Community 51 - "Search Relevance Match Score Badge"
Cohesion: 0.25
Nodes (5): MatchScoreBadge, .body, .clampedPercent, .displayPercent, .progress

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
Cohesion: 0.29
Nodes (6): .chatSettingsPanel, TokenBudgetSliderView, .estimatedContextWords, .estimatedOutputWords, .outputProfile, .profileBadgeColor

### Community 56 - "ChatView.swift"
Cohesion: 0.18
Nodes (7): SafariServices, NetworkConstants, ChatViewMode, full, pdfTalkme, UIKit, UniformTypeIdentifiers

### Community 57 - "StreamingLaTeXText"
Cohesion: 0.20
Nodes (5): PlatformClipboard, .summaryCard, .webPageSummaryOverlay, StreamingLaTeXText, .foreground

### Community 58 - "feature_request.md"
Cohesion: 0.40
Nodes (4): Additional Context, Describe Alternatives You've Considered, Describe the Solution You'd Like, Is Your Feature Request Related to a Problem?

### Community 59 - "FilePickerKind"
Cohesion: 0.33
Nodes (4): FilePickerKind, .allowedContentTypes, image, pdf

### Community 60 - "ModelAvailabilityNotice"
Cohesion: 0.33
Nodes (3): ModelAvailabilityNotice, .body, .iconName

### Community 61 - "WebScrapingService.swift"
Cohesion: 0.40
Nodes (4): HTMLToMarkdown, URL Context Extraction, Reeeed, Multi-Context Chat Showcase

## Knowledge Gaps
- **172 isolated node(s):** `searchAssist`, `chat`, `.id`, `.language`, `.selectedTabBinding` (+167 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 439 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **13 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ChatService` connect `SwiftData Conversation Persistence` to `AIService`, `RAG Retrieval & Chunking`, `Dual Web Search & Tests`, `Navigation Tabs & Views Container`, `Chat Interface & Streaming`, `Web Content Scraping & Errors`, `Search Assist View & Grounding`, `ModelAnsweringTests`, `RAG & PDF Chunking Tests`, `DroppedFileStore`, `PurchaseManager`, `ReaderHTMLWebViewRepresentable`?**
  _High betweenness centrality (0.144) - this node is a cross-community bridge._
- **Are the 7 inferred relationships involving `ChatService` (e.g. with `ContentView` and `Search Tool Calling Definition`) actually correct?**
  _`ChatService` has 7 INFERRED edges - model-reasoned connections that need verification._
- **What connects `searchAssist`, `chat`, `.id` to the rest of the system?**
  _172 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `RAG Retrieval & Chunking` be split into smaller, more focused modules?**
  _Cohesion score 0.05929919137466307 - nodes in this community are weakly interconnected._
- **Why does `ModelLanguage` connect `ModelLanguage` to `RAG Retrieval & Chunking`, `SwiftData Conversation Persistence`, `.loadPrompt`, `Dual Web Search & Tests`, `Foundation Model Hardware Availability`, `Multi-Query Search Sources Tool`, `System Framework Integrations`, `DroppedFileStore`, `Model Loading & Inference Engine`, `LocalizationService`, `AIService`, `String`, `Navigation Tabs & Views Container`, `AppSettings`, `System Date & Time Tool`, `SearchView.swift`, `Search Relevance Match Score Badge`, `Token Budget Slider Controls`, `ModelAvailabilityNotice`?**
  _High betweenness centrality (0.143) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `ChatView` (e.g. with `.body` and `.testMainViewsRenderWithoutCrashing()`) actually correct?**
  _`ChatView` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Should `SwiftData Conversation Persistence` be split into smaller, more focused modules?**
  _Cohesion score 0.07032967032967033 - nodes in this community are weakly interconnected._