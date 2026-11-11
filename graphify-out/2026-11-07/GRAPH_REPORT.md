# Graph Report - SilicIA  (2026-11-03)

## Corpus Check
- 121 files · ~107,371 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 15 file(s) not represented in the graph (top: (none) 5, .entitlements 3, .plist 2)

## Summary
- 1535 nodes · 3676 edges · 67 communities (49 shown, 18 thin omitted)
- Extraction: 93% EXTRACTED · 7% INFERRED · 0% AMBIGUOUS · INFERRED: 269 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `540a10ee`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- RAG Retrieval & Chunking
- SwiftData Conversation Persistence
- AIService
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
- ReaderHTMLWebViewRepresentable
- String
- DynamicSessionCoordinator
- ReaderHTMLWebViewRepresentable
- .check
- String
- DynamicSessionCoordinator
- RAG Relevance Scoring Engine
- SilicIAApp.swift
- AppSettings
- DebugRAGStorage
- Color
- System Date & Time Tool
- Tool Call Transcript Recorder
- XCTestCase
- WebScrapingService.swift
- SilicIADynamicProfile
- NetworkConstants.swift
- View
- Tool Budgeting & Execution Assembly
- RAG & PDF Chunking Tests
- Search Relevance Match Score Badge
- bug_report.md
- GitHub Development Helper CLI
- pull_request_template.md
- TokenBudgetSliderView
- StreamingLaTeXText
- feature_request.md
- FilePickerKind
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
7. `AIService` - 42 edges
8. `WebScrapingService` - 42 edges
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

## Communities (67 total, 18 thin omitted)

### Community 0 - "RAG Retrieval & Chunking"
Cohesion: 0.06
Nodes (16): Accelerate, RAG Retrieval Pipeline, HTMLSanitizer, MarkdownSegment, prose, table, RAGChunk, RAGChunker (+8 more)

### Community 1 - "SwiftData Conversation Persistence"
Cohesion: 0.06
Nodes (17): SwiftData Chat Persistence, .body, ModelLanguage, .code, english, french, .nlLanguage, spanish (+9 more)

### Community 2 - "AIService"
Cohesion: 0.07
Nodes (11): Local Processing Guarantee, SilicIA Privacy Policy, On-Device LLM (Apple Intelligence), Local LLM Chat Showcase, Privacy Feature Showcase, SearchResponse, SearchResult, AIService (+3 more)

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
Cohesion: 0.10
Nodes (17): FoundationModelAvailability, Reason, deviceNotEligible, .isUserFixable, modelNotReady, notEnabled, other, .stringValue (+9 more)

### Community 8 - "Search Assist View & Grounding"
Cohesion: 0.09
Nodes (18): Search Prompt Instructions, SearchView, .body, .chatButtonTitle, .effectiveContextTokens, .emptyStateView, .exampleQueryChips, .hasChatMoreContext (+10 more)

### Community 9 - "LaTeX Stream Segmentation"
Cohesion: 0.12
Nodes (5): LaTeXStreamSegmenter, ModelOutputLaTeXSanitizer, .body, LaTeXStreamSegmenterTests, SanitizerTests

### Community 10 - ".loadPrompt"
Cohesion: 0.13
Nodes (9): System Prompt Framework, BundleToken, PromptLoader, Configuration, ToolCallingTone, chat, search, ToolKit (+1 more)

### Community 11 - "App Store Screenshot Generation"
Cohesion: 0.10
Nodes (16): draw_text_wrapped(), load_font(), main(), make_phone_mockup(), pill_badge(), radial_glow(), render_slide(), vertical_gradient() (+8 more)

### Community 13 - "GitHub Actions Build CI"
Cohesion: 0.07
Nodes (26): GitHub Automation & CI, env, runs-on, steps, CODE_SIGN_IDENTITY, CODE_SIGNING_ALLOWED, CODE_SIGNING_REQUIRED, DEVELOPMENT_TEAM (+18 more)

### Community 14 - "Multi-Query Search Sources Tool"
Cohesion: 0.15
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
Cohesion: 0.13
Nodes (14): Decision, allow, .description, duplicate, .refusalMessage, toolBudgetReached, totalBudgetReached, ToolCallGovernor (+6 more)

### Community 19 - "Web Search Scraper Verification CI"
Cohesion: 0.08
Nodes (23): env, runs-on, steps, CODE_SIGN_IDENTITY, CODE_SIGNING_ALLOWED, CODE_SIGNING_REQUIRED, DEVELOPMENT_TEAM, jobs (+15 more)

### Community 20 - "On-Device Calculator Tool"
Cohesion: 0.17
Nodes (3): Arguments, CalculatorTool, CalculatorToolTests

### Community 21 - "System Framework Integrations"
Cohesion: 0.19
Nodes (6): Combine, Foundation, FoundationModels, NaturalLanguage, os, StoreKit

### Community 22 - "SwiftUI"
Cohesion: 0.14
Nodes (10): LaTeXSwiftUI, SafariServices, ChatViewMode, full, pdfTalkme, SwiftData, SwiftUI, UIKit (+2 more)

### Community 23 - "App Settings & Tool Test Fixtures"
Cohesion: 0.16
Nodes (3): Observation, SilicIA, XCTest

### Community 24 - "Markdown Rendering & Code Blocks"
Cohesion: 0.15
Nodes (13): MarkdownBlock, code, heading, horizontalRule, .id, orderedList, paragraph, quote (+5 more)

### Community 25 - "DroppedFileStore"
Cohesion: 0.07
Nodes (12): PDF Analysis & Grounding, PDF Context & Citation Showcase, DroppedFileStore, .storageDirectory, DroppedImageStore, .storageDirectory, DroppedPDFStore, .storageDirectory (+4 more)

### Community 26 - "PurchaseManager"
Cohesion: 0.05
Nodes (11): Entitlements, .canAttachDocuments, .canExceedFreeOutputTokens, .canUseMultipleWebSourcesPerProvider, .hasPremiumAccess, FoundingUserStore, PurchaseManager, AppDelegate (+3 more)

### Community 27 - "Model Loading & Inference Engine"
Cohesion: 0.35
Nodes (4): Arguments, RAGSearchTool, .defaultScrapingCharactersFromContextTokens, RAGSearchToolTests

### Community 28 - "ReaderHTMLWebViewRepresentable"
Cohesion: 0.22
Nodes (3): NonScrollingWKWebView, .body, ReaderHTMLWebViewRepresentable

### Community 29 - "String"
Cohesion: 0.05
Nodes (32): AppTab, chat, .id, searchAssist, ContentView, .language, .selectedTab, .selectedTabBinding (+24 more)

### Community 30 - "DynamicSessionCoordinator"
Cohesion: 0.16
Nodes (10): DynamicSessionMode, chat, chatFallback, searchQueryGeneration, searchSummary, webPageSummary, DynamicSessionStateStore, .current (+2 more)

### Community 35 - "RAG Relevance Scoring Engine"
Cohesion: 0.17
Nodes (4): AppIntents, SilicIAAppShortcuts, .appShortcuts, OpenSilicIASearchIntent

### Community 36 - "SilicIAApp.swift"
Cohesion: 0.25
Nodes (7): App Store Short Description, Build & Tooling Configuration, Build Scripts (scripts/build.sh), Contributing Guidelines, SilicIA Brand Identity & Icon Assets, SilicIA Assistant, Math & Factorial UI Rendering

### Community 37 - "AppSettings"
Cohesion: 0.10
Nodes (9): AppSettings, .isWebSummariesEnabled, .maxSearchResults, .totalTokensBudget, AppSettingsStore, .settings, .maxAllowedContextTokensForCurrentResponse, .body (+1 more)

### Community 38 - "DebugRAGStorage"
Cohesion: 0.20
Nodes (5): DebugRAGStorage, .debugRootDirectory, .promptsDirectory, .rankedChunksDirectory, .webpagesDirectory

### Community 39 - "Color"
Cohesion: 0.29
Nodes (5): PlatformColors, .controlBackground, .textBackground, Color, .platformWindowBackground

### Community 40 - "System Date & Time Tool"
Cohesion: 0.29
Nodes (6): Arguments, DateTimeTool, Mode, both, dateOnly, timeOnly

### Community 42 - "XCTestCase"
Cohesion: 0.05
Nodes (11): Multi-Language UI & Prompts, LocalizationService, WikipediaQueryCleaner, ChatServicePDFChunkPolicyTests, LocalizationTests, .service, ModelAnsweringTests, ModelLanguageTests (+3 more)

### Community 43 - "WebScrapingService.swift"
Cohesion: 0.40
Nodes (4): HTMLToMarkdown, URL Context Extraction, Reeeed, Multi-Context Chat Showcase

### Community 44 - "SilicIADynamicProfile"
Cohesion: 0.22
Nodes (4): SilicIADynamicInstructions, .body, SilicIADynamicProfile, .body

### Community 46 - "View"
Cohesion: 0.13
Nodes (6): View, FeatureRow, .body, .headerView, SourceToggleButtons, .body

### Community 49 - "RAG & PDF Chunking Tests"
Cohesion: 0.43
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

### Community 55 - "TokenBudgetSliderView"
Cohesion: 0.25
Nodes (6): .chatSettingsPanel, TokenBudgetSliderView, .estimatedContextWords, .estimatedOutputWords, .outputProfile, .profileBadgeColor

### Community 57 - "StreamingLaTeXText"
Cohesion: 0.20
Nodes (5): PlatformClipboard, .summaryCard, .webPageSummaryOverlay, StreamingLaTeXText, .foreground

### Community 58 - "feature_request.md"
Cohesion: 0.40
Nodes (4): Additional Context, Describe Alternatives You've Considered, Describe the Solution You'd Like, Is Your Feature Request Related to a Problem?

### Community 59 - "FilePickerKind"
Cohesion: 0.33
Nodes (4): FilePickerKind, .allowedContentTypes, image, pdf

## Knowledge Gaps
- **172 isolated node(s):** `Accelerate`, `prose`, `table`, `assistant`, `user` (+167 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 443 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **18 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ModelLanguage` connect `SwiftData Conversation Persistence` to `RAG Retrieval & Chunking`, `.check`, `AIService`, `Dual Web Search & Tests`, `AppSettings`, `Foundation Model Hardware Availability`, `System Date & Time Tool`, `XCTestCase`, `.loadPrompt`, `Multi-Query Search Sources Tool`, `Search Relevance Match Score Badge`, `System Framework Integrations`, `TokenBudgetSliderView`, `DroppedFileStore`, `Model Loading & Inference Engine`, `String`, `DynamicSessionCoordinator`?**
  _High betweenness centrality (0.138) - this node is a cross-community bridge._
- **Are the 7 inferred relationships involving `ChatService` (e.g. with `ContentView` and `Search Tool Calling Definition`) actually correct?**
  _`ChatService` has 7 INFERRED edges - model-reasoned connections that need verification._
- **What connects `Accelerate`, `prose`, `table` to the rest of the system?**
  _172 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `RAG Retrieval & Chunking` be split into smaller, more focused modules?**
  _Cohesion score 0.057805469020422294 - nodes in this community are weakly interconnected._
- **Why does `ChatService` connect `SwiftData Conversation Persistence` to `RAG Retrieval & Chunking`, `String`, `Dual Web Search & Tests`, `Chat Interface & Streaming`, `Web Content Scraping & Errors`, `Search Assist View & Grounding`, `XCTestCase`, `RAG & PDF Chunking Tests`, `PurchaseManager`, `String`?**
  _High betweenness centrality (0.126) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `ChatView` (e.g. with `.body` and `.testMainViewsRenderWithoutCrashing()`) actually correct?**
  _`ChatView` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Should `SwiftData Conversation Persistence` be split into smaller, more focused modules?**
  _Cohesion score 0.06282828282828283 - nodes in this community are weakly interconnected._