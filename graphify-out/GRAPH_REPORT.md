# Graph Report - SilicIA  (2026-11-11)

## Corpus Check
- 116 files · ~112,879 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 15 file(s) not represented in the graph (top: (none) 5, .entitlements 3, .plist 2)

## Summary
- 1503 nodes · 3732 edges · 74 communities (56 shown, 18 thin omitted)
- Extraction: 94% EXTRACTED · 6% INFERRED · 0% AMBIGUOUS · INFERRED: 224 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `42424906`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- RAG Retrieval & Chunking
- SwiftData Conversation Persistence
- WikipediaSource
- ReaderHTMLWebViewRepresentable
- Chat Interface & Streaming
- Web Content Scraping & Errors
- Image Analysis & Visual Grounding
- ContentView
- Search Assist View & Grounding
- ModelOutputLaTeXSanitizer
- ToolError
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
- AIService
- SilicIA
- String
- DroppedFileStore
- PurchaseManager
- ContentView
- StreamingLaTeXText
- LocalizationService
- AppSettings
- TokenBudgetingTests
- CodingKeys
- MatchScoreBadge
- .executeWikipediaSearch
- RAG Relevance Scoring Engine
- MarkdownContentView
- .acquireSession
- SwiftData
- WebSearchService
- System Date & Time Tool
- Tool Call Transcript Recorder
- SearchResult
- SilicIA Assistant
- MarkdownBlock
- RAGSearchTool
- SharedTopBarView
- NetworkConstants.swift
- SearchView.swift
- DebugRAGStorage
- test.swift
- TokenBudgetSliderView
- bug_report.md
- GitHub Development Helper CLI
- pull_request_template.md
- AppSettingsStoreTests
- TokenBudgetSliderView
- .loadPrompt
- feature_request.md
- XCTestCase
- .persist
- DynamicSessionMode
- .testMainViewsRenderWithoutCrashing
- Brand Logo Icon Generation
- Shell Build Automation Script
- Build and Run Shell Script
- TestRAG French Wiki Benchmark
- Offline Chat Mode Concept
- Token Budgeting Engine Concept
- View
- SwiftUI
- Coordinator
- ChatService.swift

## God Nodes (most connected - your core abstractions)
1. `ModelLanguage` - 88 edges
2. `ChatService` - 88 edges
3. `ChatView` - 71 edges
4. `SearchView` - 66 edges
5. `WebSearchService` - 56 edges
6. `RAGContextService` - 51 edges
7. `AppSettings` - 46 edges
8. `WebScrapingService` - 40 edges
9. `AIService` - 39 edges
10. `SearchResult` - 35 edges

## Surprising Connections (you probably didn't know these)
- `SilicIATests Suite` --references--> `WebSearchServiceTests`  [INFERRED]
  BUILDING.md → SilicIATests/WebSearchServiceTests.swift
- `SilicIA Brand Identity & Icon Assets` --references--> `SilicIA Assistant`  [INFERRED]
  logo/appicon_big.png → README.md
- `Math & Factorial UI Rendering` --conceptually_related_to--> `SilicIA Assistant`  [INFERRED]
  Screenshots/Factorial.png → README.md
- `Multi-Language UI & Prompts` --implements--> `ModelLanguage`  [EXTRACTED]
  README.md → SilicIA/Models/AppSettings.swift
- `SwiftData Chat Persistence` --implements--> `Conversation`  [EXTRACTED]
  README.md → SilicIA/Models/Conversation.swift

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Multilingual UI & System Prompt Ecosystem** — readme_multilanguage_support, silicia_services_localizationservice_localizationservice, silicia_models_appsettings_modellanguage, silicia_services_promptloader_promptloader, silicia_prompts_system_prompt_framework [INFERRED 0.95]
- **Privacy-Preserving On-Device Architecture** — privacy_local_processing_guarantee, readme_on_device_llm, silicia_services_aiservice_aiservice, silicia_models_conversation_conversation [INFERRED 0.95]
- **RAG Retrieval Pipeline Components** — readme_rag_pipeline, silicia_services_chatservice_chatservice, silicia_services_ragcontextservice, silicia_services_tokenbudgeting_tokenbudgeting, silicia_services_aiservice_aiservice [INFERRED 0.95]

## Communities (74 total, 18 thin omitted)

### Community 0 - "RAG Retrieval & Chunking"
Cohesion: 0.09
Nodes (14): Accelerate, MarkdownSegment, prose, table, QueryTermData, RAGChunk, RAGChunker, RAGCitationFormatter (+6 more)

### Community 1 - "SwiftData Conversation Persistence"
Cohesion: 0.07
Nodes (12): SwiftData Chat Persistence, .body, Conversation, Message, Search Tool Calling Definition, ChatMessage, ChatService, PDFPageBatch (+4 more)

### Community 2 - "WikipediaSource"
Cohesion: 0.16
Nodes (11): NaturalLanguage, ContextSourceKind, .displayName, .id, offline, .systemImage, web, wiki (+3 more)

### Community 3 - "ReaderHTMLWebViewRepresentable"
Cohesion: 0.22
Nodes (3): NonScrollingWKWebView, .body, ReaderHTMLWebViewRepresentable

### Community 4 - "Chat Interface & Streaming"
Cohesion: 0.08
Nodes (19): ChatView, .attachmentMenu, .body, .chatHeaderView, .composerView, .effectiveIsWebSearchEnabled, .effectiveUseDuckDuckGo, .effectiveUseWikipedia (+11 more)

### Community 5 - "Web Content Scraping & Errors"
Cohesion: 0.08
Nodes (13): HTMLSanitizer, HTMLConversionError, conversionFailed, emptyContent, .errorDescription, excessiveDOMDepth, excessiveElementCount, inputTooLarge (+5 more)

### Community 6 - "Image Analysis & Visual Grounding"
Cohesion: 0.09
Nodes (10): ImageIO, ArticleRowProjection, ImageAnalysisResult, .isEmpty, ImageAnalysisService, LayoutObservation, PDFPageAnalysisResult, .isEmpty (+2 more)

### Community 7 - "ContentView"
Cohesion: 0.10
Nodes (17): FoundationModelAvailability, Reason, deviceNotEligible, .isUserFixable, modelNotReady, notEnabled, other, .stringValue (+9 more)

### Community 8 - "Search Assist View & Grounding"
Cohesion: 0.09
Nodes (19): Search Prompt Instructions, SearchView, .body, .chatButtonTitle, .defaultScrapingCharactersFromContextTokens, .effectiveContextTokens, .emptyStateView, .exampleQueryChips (+11 more)

### Community 9 - "ModelOutputLaTeXSanitizer"
Cohesion: 0.20
Nodes (3): LaTeXStreamSegmenter, ModelOutputLaTeXSanitizer, .body

### Community 10 - "ToolError"
Cohesion: 0.25
Nodes (7): SearchError, botChallengeDetected, .errorDescription, invalidResponse, invalidURL, networkError, parsingFailed

### Community 11 - "App Store Screenshot Generation"
Cohesion: 0.10
Nodes (16): draw_text_wrapped(), load_font(), main(), make_phone_mockup(), pill_badge(), radial_glow(), render_slide(), vertical_gradient() (+8 more)

### Community 13 - "GitHub Actions Build CI"
Cohesion: 0.07
Nodes (26): GitHub Automation & CI, env, runs-on, steps, CODE_SIGN_IDENTITY, CODE_SIGNING_ALLOWED, CODE_SIGNING_REQUIRED, DEVELOPMENT_TEAM (+18 more)

### Community 14 - "Multi-Query Search Sources Tool"
Cohesion: 0.12
Nodes (14): Arguments, SearchSourcesTool, SingleQueryArguments, WebOnlyArguments, WebOnlySingleQueryArguments, WebSourcesTool, WikiFastArguments, WikiFastOnlyArguments (+6 more)

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
Cohesion: 0.15
Nodes (13): Decision, allow, .description, duplicate, .refusalMessage, toolBudgetReached, totalBudgetReached, ToolCallGovernor (+5 more)

### Community 19 - "Web Search Scraper Verification CI"
Cohesion: 0.08
Nodes (23): env, runs-on, steps, CODE_SIGN_IDENTITY, CODE_SIGNING_ALLOWED, CODE_SIGNING_REQUIRED, DEVELOPMENT_TEAM, jobs (+15 more)

### Community 21 - "Foundation"
Cohesion: 0.26
Nodes (3): Foundation, FoundationModels, StoreKit

### Community 22 - "AIService"
Cohesion: 0.07
Nodes (20): Local Processing Guarantee, SilicIA Privacy Policy, On-Device LLM (Apple Intelligence), RAG Retrieval Pipeline, Local LLM Chat Showcase, Privacy Feature Showcase, AIService, TimingMetric (+12 more)

### Community 24 - "String"
Cohesion: 0.13
Nodes (5): .isReaderViewAndSummaryEnabled, PlatformClipboard, CitationLink, .searchBarView, .summaryCard

### Community 25 - "DroppedFileStore"
Cohesion: 0.07
Nodes (9): DroppedFileStore, .storageDirectory, DroppedImageStore, .storageDirectory, DroppedTextFileStore, .storageDirectory, ConversationsListView, .body (+1 more)

### Community 26 - "PurchaseManager"
Cohesion: 0.05
Nodes (11): Entitlements, .canAttachDocuments, .canExceedFreeOutputTokens, .canUseMultipleWebSourcesPerProvider, .hasPremiumAccess, FoundingUserStore, PurchaseManager, AppDelegate (+3 more)

### Community 27 - "ContentView"
Cohesion: 0.20
Nodes (8): AppTab, chat, .id, searchAssist, ContentView, .language, .selectedTab, .selectedTabBinding

### Community 28 - "StreamingLaTeXText"
Cohesion: 0.18
Nodes (8): LaTeXSwiftUI, PlatformColors, .controlBackground, .textBackground, Color, .platformWindowBackground, StreamingLaTeXText, .foreground

### Community 29 - "LocalizationService"
Cohesion: 0.13
Nodes (10): Multi-Language UI & Prompts, ModelLanguage, .code, english, french, .nlLanguage, spanish, LocalizationService (+2 more)

### Community 30 - "AppSettings"
Cohesion: 0.09
Nodes (14): AppSettings, .contextSourceKind, .isWebSummariesEnabled, .maxDuckDuckGoResults, .maxSearchResults, .maxWikipediaResults, .outputProfileKind, .temperature (+6 more)

### Community 31 - "TokenBudgetingTests"
Cohesion: 0.22
Nodes (6): os, SilicIADynamicInstructions, .body, SilicIADynamicProfile, .body, TokenBudgetingTests

### Community 32 - "CodingKeys"
Cohesion: 0.11
Nodes (17): CodingKeys, isReaderViewAndSummaryEnabled, isWebSummariesEnabled, language, maxContextTokens, maxDuckDuckGoResults, maxResponseTokens, maxWikipediaResults (+9 more)

### Community 33 - "MatchScoreBadge"
Cohesion: 0.25
Nodes (5): MatchScoreBadge, .body, .clampedPercent, .displayPercent, .progress

### Community 34 - ".executeWikipediaSearch"
Cohesion: 0.33
Nodes (3): WikipediaSource, online, wikiFast

### Community 35 - "RAG Relevance Scoring Engine"
Cohesion: 0.17
Nodes (4): AppIntents, SilicIAAppShortcuts, .appShortcuts, OpenSilicIASearchIntent

### Community 36 - "MarkdownContentView"
Cohesion: 0.29
Nodes (3): MarkdownBlockParser, MarkdownContentView, .body

### Community 37 - ".acquireSession"
Cohesion: 0.17
Nodes (6): DynamicSessionCoordinator, .currentSnapshot, DynamicSessionStateStore, .current, PrewarmKey, Snapshot

### Community 39 - "WebSearchService"
Cohesion: 0.11
Nodes (6): SilicIATests Suite, Dual Web Search Architecture, Dual Web Search Showcase, WebSearchService, .userAgent, WebSearchServiceTests

### Community 40 - "System Date & Time Tool"
Cohesion: 0.29
Nodes (6): Arguments, DateTimeTool, Mode, both, dateOnly, timeOnly

### Community 42 - "SearchResult"
Cohesion: 0.26
Nodes (3): SearchResponse, SearchResult, WikiFastArticle

### Community 43 - "SilicIA Assistant"
Cohesion: 0.25
Nodes (7): App Store Short Description, Build & Tooling Configuration, Build Scripts (scripts/build.sh), Contributing Guidelines, SilicIA Brand Identity & Icon Assets, SilicIA Assistant, Math & Factorial UI Rendering

### Community 44 - "MarkdownBlock"
Cohesion: 0.12
Nodes (14): FilePickerKind, .allowedContentTypes, image, pdf, MarkdownBlock, code, heading, horizontalRule (+6 more)

### Community 45 - "RAGSearchTool"
Cohesion: 0.28
Nodes (3): Arguments, RAGSearchTool, ToolKitTests

### Community 46 - "SharedTopBarView"
Cohesion: 0.22
Nodes (5): SharedTopBarView, .body, .settings, SourceToggleButtons, .body

### Community 48 - "SearchView.swift"
Cohesion: 0.21
Nodes (7): SafariServices, FeatureRow, .body, SearchResultCard, .body, .isWebSummariesEnabled, WebKit

### Community 49 - "DebugRAGStorage"
Cohesion: 0.20
Nodes (5): DebugRAGStorage, .debugRootDirectory, .promptsDirectory, .rankedChunksDirectory, .webpagesDirectory

### Community 51 - "TokenBudgetSliderView"
Cohesion: 0.29
Nodes (6): TokenBudgetSliderView, .body, .estimatedContextWords, .estimatedOutputWords, .outputProfile, .profileBadgeColor

### Community 52 - "bug_report.md"
Cohesion: 0.22
Nodes (8): Actual Behavior, Additional Context, Describe the Bug, Environment, Error Logs, Expected Behavior, Screenshots, Steps to Reproduce

### Community 53 - "GitHub Development Helper CLI"
Cohesion: 0.52
Nodes (6): check_build_status(), check_repo_stats(), create_feature_branch(), print_menu(), github-helper.sh script, view_recent_commits()

### Community 54 - "pull_request_template.md"
Cohesion: 0.22
Nodes (8): Additional Notes, Changes Made, Checklist, Description, Related Issues, Screenshots (if applicable), Testing, Type of Change

### Community 56 - "TokenBudgetSliderView"
Cohesion: 0.22
Nodes (7): ChatViewMode, full, pdfTalkme, SharedSettingsView, .body, .settings, .settingsPanel

### Community 57 - ".loadPrompt"
Cohesion: 0.14
Nodes (9): System Prompt Framework, BundleToken, PromptLoader, Configuration, ToolCallingTone, chat, search, ToolKit (+1 more)

### Community 58 - "feature_request.md"
Cohesion: 0.40
Nodes (4): Additional Context, Describe Alternatives You've Considered, Describe the Solution You'd Like, Is Your Feature Request Related to a Problem?

### Community 59 - "XCTestCase"
Cohesion: 0.20
Nodes (4): DocumentContextTests, ModelAnsweringTests, SanitizerTests, ToolCallingPromptTests

### Community 60 - ".persist"
Cohesion: 0.21
Nodes (4): PDF Analysis & Grounding, PDF Context & Citation Showcase, DroppedPDFStore, .storageDirectory

### Community 61 - "DynamicSessionMode"
Cohesion: 0.29
Nodes (6): DynamicSessionMode, chat, chatFallback, searchQueryGeneration, searchSummary, webPageSummary

### Community 71 - "SwiftUI"
Cohesion: 0.24
Nodes (7): AppKit, Combine, PDFKit, SwiftUI, UIKit, UniformTypeIdentifiers, Vision

### Community 78 - "ChatService.swift"
Cohesion: 0.33
Nodes (5): CoreGraphics, HTMLToMarkdown, URL Context Extraction, Reeeed, Multi-Context Chat Showcase

## Knowledge Gaps
- **193 isolated node(s):** `searchAssist`, `chat`, `.id`, `.language`, `.selectedTabBinding` (+188 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 457 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **18 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ModelLanguage` connect `LocalizationService` to `RAG Retrieval & Chunking`, `SwiftData Conversation Persistence`, `WikipediaSource`, `Image Analysis & Visual Grounding`, `ContentView`, `Multi-Query Search Sources Tool`, `AIService`, `DroppedFileStore`, `ContentView`, `AppSettings`, `MatchScoreBadge`, `.executeWikipediaSearch`, `WebSearchService`, `System Date & Time Tool`, `SearchResult`, `RAGSearchTool`, `SearchView.swift`, `TokenBudgetSliderView`, `.loadPrompt`, `.fetchWikipediaPageDetails`?**
  _High betweenness centrality (0.156) - this node is a cross-community bridge._
- **Are the 9 inferred relationships involving `ChatService` (e.g. with `ContentView` and `Search Tool Calling Definition`) actually correct?**
  _`ChatService` has 9 INFERRED edges - model-reasoned connections that need verification._
- **What connects `searchAssist`, `chat`, `.id` to the rest of the system?**
  _193 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `RAG Retrieval & Chunking` be split into smaller, more focused modules?**
  _Cohesion score 0.08563611491108071 - nodes in this community are weakly interconnected._
- **Why does `ChatService` connect `SwiftData Conversation Persistence` to `RAG Retrieval & Chunking`, `Chat Interface & Streaming`, `Web Content Scraping & Errors`, `SwiftUI`, `WebSearchService`, `Search Assist View & Grounding`, `XCTestCase`, `Coordinator`, `AIService`, `PurchaseManager`, `ContentView`, `.testMainViewsRenderWithoutCrashing`?**
  _High betweenness centrality (0.126) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `ChatView` (e.g. with `.body` and `.testMainViewsRenderWithoutCrashing()`) actually correct?**
  _`ChatView` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Should `SwiftData Conversation Persistence` be split into smaller, more focused modules?**
  _Cohesion score 0.07333970377448638 - nodes in this community are weakly interconnected._