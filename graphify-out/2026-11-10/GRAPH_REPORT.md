# Graph Report - SilicIA  (2026-11-10)

## Corpus Check
- 127 files · ~122,777 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 17 file(s) not represented in the graph (top: (none) 5, .entitlements 3, .plist 2)

## Summary
- 1644 nodes · 4041 edges · 75 communities (54 shown, 21 thin omitted)
- Extraction: 93% EXTRACTED · 7% INFERRED · 0% AMBIGUOUS · INFERRED: 293 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `a2f099fd`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- RAG Retrieval & Chunking
- SwiftData Conversation Persistence
- AIService
- Coordinator
- Chat Interface & Streaming
- Web Content Scraping & Errors
- Image Analysis & Visual Grounding
- Foundation Model Hardware Availability
- Search Assist View & Grounding
- LaTeX Stream Segmentation
- SearchView.swift
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
- Foundation
- String
- App Settings & Tool Test Fixtures
- MarkdownContentView
- DroppedFileStore
- PurchaseManager
- .persist
- ReaderHTMLWebViewRepresentable
- .loadPrompt
- AppSettings
- .acquireSession
- CodingKeys
- String
- XCTestCase
- RAG Relevance Scoring Engine
- MarkdownBlock
- DynamicSessionCoordinator
- SearchResultCard
- SilicIADynamicInstructions
- System Date & Time Tool
- Tool Call Transcript Recorder
- HTMLSanitizer
- SwiftUI
- ContentView
- RAGSearchTool
- View
- LocalizationService
- DebugRAGStorage
- ModelAnsweringTests
- ModelLanguage
- SearchResultCard
- bug_report.md
- GitHub Development Helper CLI
- pull_request_template.md
- MessageBubbleGlass
- WebSearchService
- Sendable
- feature_request.md
- StreamingLaTeXText
- SearchError
- .testPDFPageSummaryWithBatchingAndSingleParagraph
- SourceToggleButtons
- Brand Logo Icon Generation
- Shell Build Automation Script
- Build and Run Shell Script
- TestRAG French Wiki Benchmark
- Offline Chat Mode Concept
- Token Budgeting Engine Concept
- WikipediaQueryCleaner
- AppKit
- FilePickerKind
- AppSettingsStoreTests
- .summaryCard
- WebScrapingService.swift

## God Nodes (most connected - your core abstractions)
1. `ChatService` - 90 edges
2. `ModelLanguage` - 88 edges
3. `ChatView` - 74 edges
4. `SearchView` - 66 edges
5. `WebSearchService` - 61 edges
6. `RAGContextService` - 58 edges
7. `AIService` - 43 edges
8. `WebScrapingService` - 43 edges
9. `AppSettings` - 40 edges
10. `SearchResult` - 39 edges

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

## Communities (75 total, 21 thin omitted)

### Community 0 - "RAG Retrieval & Chunking"
Cohesion: 0.06
Nodes (16): Accelerate, RAG Retrieval Pipeline, MarkdownSegment, prose, table, QueryTermData, RAGChunk, RAGChunker (+8 more)

### Community 1 - "SwiftData Conversation Persistence"
Cohesion: 0.06
Nodes (13): SwiftData Chat Persistence, Conversation, Message, Search Tool Calling Definition, ChatMessage, ChatService, PDFPageBatch, PriorExchange (+5 more)

### Community 2 - "AIService"
Cohesion: 0.05
Nodes (12): Local Processing Guarantee, SilicIA Privacy Policy, On-Device LLM (Apple Intelligence), Local LLM Chat Showcase, Privacy Feature Showcase, SearchResponse, SearchResult, AIService (+4 more)

### Community 3 - "Coordinator"
Cohesion: 0.15
Nodes (3): Coordinator, ReaderHTMLWebView, .body

### Community 4 - "Chat Interface & Streaming"
Cohesion: 0.08
Nodes (20): ChatView, .attachmentMenu, .body, .chatHeaderView, .chatSettingsPage, .composerView, .effectiveIsWebSearchEnabled, .effectiveUseDuckDuckGo (+12 more)

### Community 5 - "Web Content Scraping & Errors"
Cohesion: 0.10
Nodes (12): HTMLConversionError, conversionFailed, emptyContent, .errorDescription, excessiveDOMDepth, excessiveElementCount, inputTooLarge, ReaderWebPageContent (+4 more)

### Community 6 - "Image Analysis & Visual Grounding"
Cohesion: 0.08
Nodes (10): ImageIO, ArticleRowProjection, ImageAnalysisResult, .isEmpty, ImageAnalysisService, LayoutObservation, PDFPageAnalysisResult, .isEmpty (+2 more)

### Community 7 - "Foundation Model Hardware Availability"
Cohesion: 0.07
Nodes (25): FoundationModelAvailability, Reason, deviceNotEligible, .isUserFixable, modelNotReady, notEnabled, other, .stringValue (+17 more)

### Community 8 - "Search Assist View & Grounding"
Cohesion: 0.09
Nodes (19): Search Prompt Instructions, SearchView, .body, .chatButtonTitle, .effectiveContextTokens, .emptyStateView, .exampleQueryChips, .hasChatMoreContext (+11 more)

### Community 9 - "LaTeX Stream Segmentation"
Cohesion: 0.10
Nodes (5): LaTeXStreamSegmenter, ModelOutputLaTeXSanitizer, .body, LaTeXStreamSegmenterTests, SanitizerTests

### Community 10 - "SearchView.swift"
Cohesion: 0.18
Nodes (8): SafariServices, NetworkConstants, ChatViewMode, full, pdfTalkme, UIKit, UniformTypeIdentifiers, WebKit

### Community 11 - "App Store Screenshot Generation"
Cohesion: 0.10
Nodes (16): draw_text_wrapped(), load_font(), main(), make_phone_mockup(), pill_badge(), radial_glow(), render_slide(), vertical_gradient() (+8 more)

### Community 13 - "GitHub Actions Build CI"
Cohesion: 0.07
Nodes (26): GitHub Automation & CI, env, runs-on, steps, CODE_SIGN_IDENTITY, CODE_SIGNING_ALLOWED, CODE_SIGNING_REQUIRED, DEVELOPMENT_TEAM (+18 more)

### Community 14 - "Multi-Query Search Sources Tool"
Cohesion: 0.10
Nodes (16): Arguments, SearchSourcesTool, SingleQueryArguments, WebOnlyArguments, WebOnlySingleQueryArguments, WebSourcesTool, WikiFastArguments, WikiFastOnlyArguments (+8 more)

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

### Community 21 - "Foundation"
Cohesion: 0.17
Nodes (5): Combine, Foundation, FoundationModels, NaturalLanguage, StoreKit

### Community 22 - "String"
Cohesion: 0.18
Nodes (11): OutputProfile, .reasoningLevel, OutputProfileKind, concise, detailed, .implicitContextCharacters, .implicitContextTokens, .implicitResponseTokens (+3 more)

### Community 23 - "App Settings & Tool Test Fixtures"
Cohesion: 0.17
Nodes (3): Observation, SilicIA, XCTest

### Community 25 - "DroppedFileStore"
Cohesion: 0.06
Nodes (13): PDF Analysis & Grounding, PDF Context & Citation Showcase, DroppedFileStore, .storageDirectory, DroppedPDFStore, .storageDirectory, DroppedTextFileStore, .storageDirectory (+5 more)

### Community 26 - "PurchaseManager"
Cohesion: 0.05
Nodes (11): Entitlements, .canAttachDocuments, .canExceedFreeOutputTokens, .canUseMultipleWebSourcesPerProvider, .hasPremiumAccess, FoundingUserStore, PurchaseManager, AppDelegate (+3 more)

### Community 29 - ".loadPrompt"
Cohesion: 0.21
Nodes (4): System Prompt Framework, BundleToken, PromptLoader, PromptLoaderTests

### Community 30 - "AppSettings"
Cohesion: 0.10
Nodes (9): AppSettings, .isReaderViewAndSummaryEnabled, .isWebSummariesEnabled, .maxSearchResults, .outputProfileKind, .totalTokensBudget, AppSettingsStore, .settings (+1 more)

### Community 31 - ".acquireSession"
Cohesion: 0.25
Nodes (8): DynamicSessionMode, chat, chatFallback, searchQueryGeneration, searchSummary, webPageSummary, PrewarmKey, Snapshot

### Community 32 - "CodingKeys"
Cohesion: 0.11
Nodes (17): CodingKeys, isReaderViewAndSummaryEnabled, isWebSummariesEnabled, language, maxContextTokens, maxDuckDuckGoResults, maxResponseTokens, maxWikipediaResults (+9 more)

### Community 34 - "XCTestCase"
Cohesion: 0.22
Nodes (3): ChatServicePDFChunkPolicyTests, ToolKitBudgetTests, ToolTranscriptRecorderTests

### Community 35 - "RAG Relevance Scoring Engine"
Cohesion: 0.17
Nodes (4): AppIntents, SilicIAAppShortcuts, .appShortcuts, OpenSilicIASearchIntent

### Community 36 - "MarkdownBlock"
Cohesion: 0.18
Nodes (10): MarkdownBlock, code, heading, horizontalRule, .id, orderedList, paragraph, quote (+2 more)

### Community 38 - "SearchResultCard"
Cohesion: 0.31
Nodes (4): SearchResultCard, .body, .isWebSummariesEnabled, .resultsView

### Community 39 - "SilicIADynamicInstructions"
Cohesion: 0.17
Nodes (7): os, DynamicSessionStateStore, .current, SilicIADynamicInstructions, .body, SilicIADynamicProfile, .body

### Community 40 - "System Date & Time Tool"
Cohesion: 0.29
Nodes (6): Arguments, DateTimeTool, Mode, both, dateOnly, timeOnly

### Community 43 - "SwiftUI"
Cohesion: 0.11
Nodes (14): App Store Short Description, Build & Tooling Configuration, Build Scripts (scripts/build.sh), Contributing Guidelines, SilicIA Brand Identity & Icon Assets, SilicIA Assistant, Math & Factorial UI Rendering, PlatformColors (+6 more)

### Community 44 - "ContentView"
Cohesion: 0.20
Nodes (9): AppTab, chat, .id, searchAssist, ContentView, .body, .language, .selectedTab (+1 more)

### Community 45 - "RAGSearchTool"
Cohesion: 0.35
Nodes (4): Arguments, RAGSearchTool, .defaultScrapingCharactersFromContextTokens, RAGSearchToolTests

### Community 46 - "View"
Cohesion: 0.27
Nodes (3): View, FeatureRow, .body

### Community 47 - "LocalizationService"
Cohesion: 0.20
Nodes (4): Multi-Language UI & Prompts, LocalizationService, LocalizationTests, .service

### Community 48 - "DebugRAGStorage"
Cohesion: 0.20
Nodes (5): DebugRAGStorage, .debugRootDirectory, .promptsDirectory, .rankedChunksDirectory, .webpagesDirectory

### Community 50 - "ModelLanguage"
Cohesion: 0.20
Nodes (7): ModelLanguage, .code, english, french, .nlLanguage, spanish, ModelLanguageTests

### Community 51 - "SearchResultCard"
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

### Community 56 - "WebSearchService"
Cohesion: 0.07
Nodes (13): SilicIATests Suite, Dual Web Search Architecture, Dual Web Search Showcase, WikipediaSource, online, wikiFast, WebSearchService, .userAgent (+5 more)

### Community 57 - "Sendable"
Cohesion: 0.26
Nodes (5): Configuration, ToolCallingTone, chat, search, ToolKit

### Community 58 - "feature_request.md"
Cohesion: 0.40
Nodes (4): Additional Context, Describe Alternatives You've Considered, Describe the Solution You'd Like, Is Your Feature Request Related to a Problem?

### Community 59 - "StreamingLaTeXText"
Cohesion: 0.25
Nodes (4): LaTeXSwiftUI, MarkdownBlockParser, StreamingLaTeXText, .foreground

### Community 60 - "SearchError"
Cohesion: 0.25
Nodes (7): SearchError, botChallengeDetected, .errorDescription, invalidResponse, invalidURL, networkError, parsingFailed

### Community 70 - "AppKit"
Cohesion: 0.36
Nodes (4): AppKit, CoreGraphics, PDFKit, Vision

### Community 71 - "FilePickerKind"
Cohesion: 0.33
Nodes (4): FilePickerKind, .allowedContentTypes, image, pdf

### Community 74 - "WebScrapingService.swift"
Cohesion: 0.40
Nodes (4): HTMLToMarkdown, URL Context Extraction, Reeeed, Multi-Context Chat Showcase

## Knowledge Gaps
- **180 isolated node(s):** `searchAssist`, `chat`, `.id`, `.language`, `.selectedTabBinding` (+175 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 454 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **21 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ModelLanguage` connect `ModelLanguage` to `RAG Retrieval & Chunking`, `SwiftData Conversation Persistence`, `AIService`, `SearchResultCard`, `Foundation Model Hardware Availability`, `System Date & Time Tool`, `ContentView`, `RAGSearchTool`, `Multi-Query Search Sources Tool`, `LocalizationService`, `SearchResultCard`, `Foundation`, `String`, `DroppedFileStore`, `WebSearchService`, `Sendable`, `.loadPrompt`, `AppSettings`?**
  _High betweenness centrality (0.157) - this node is a cross-community bridge._
- **Are the 9 inferred relationships involving `ChatService` (e.g. with `ContentView` and `Search Tool Calling Definition`) actually correct?**
  _`ChatService` has 9 INFERRED edges - model-reasoned connections that need verification._
- **What connects `searchAssist`, `chat`, `.id` to the rest of the system?**
  _180 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `RAG Retrieval & Chunking` be split into smaller, more focused modules?**
  _Cohesion score 0.05884179475236764 - nodes in this community are weakly interconnected._
- **Why does `ChatService` connect `SwiftData Conversation Persistence` to `RAG Retrieval & Chunking`, `AIService`, `Coordinator`, `Chat Interface & Streaming`, `Web Content Scraping & Errors`, `AppKit`, `Search Assist View & Grounding`, `ContentView`, `ModelAnsweringTests`, `WebSearchService`, `DroppedFileStore`, `PurchaseManager`?**
  _High betweenness centrality (0.124) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `ChatView` (e.g. with `.body` and `.testMainViewsRenderWithoutCrashing()`) actually correct?**
  _`ChatView` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Should `SwiftData Conversation Persistence` be split into smaller, more focused modules?**
  _Cohesion score 0.056744818212708124 - nodes in this community are weakly interconnected._