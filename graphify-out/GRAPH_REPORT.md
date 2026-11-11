# Graph Report - SilicIA  (2026-11-11)

## Corpus Check
<<<<<<< HEAD
- 116 files · ~112,879 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 15 file(s) not represented in the graph (top: (none) 5, .entitlements 3, .plist 2)

## Summary
- 1503 nodes · 3732 edges · 74 communities (56 shown, 18 thin omitted)
- Extraction: 94% EXTRACTED · 6% INFERRED · 0% AMBIGUOUS · INFERRED: 224 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `42424906`
=======
- 120 files · ~104,183 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 18 file(s) not represented in the graph (top: (none) 8, .entitlements 3, .plist 2)

## Summary
- 1471 nodes · 3480 edges · 66 communities (50 shown, 16 thin omitted)
- Extraction: 92% EXTRACTED · 8% INFERRED · 0% AMBIGUOUS · INFERRED: 261 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `7dada8b8`
>>>>>>> 6a7e116 (graph update)
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- RAG Retrieval & Chunking
- SwiftData Conversation Persistence
<<<<<<< HEAD
- WikipediaSource
- ReaderHTMLWebViewRepresentable
=======
- .clampedToolResponseTokens
- Dual Web Search & Tests
>>>>>>> 6a7e116 (graph update)
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
<<<<<<< HEAD
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
=======
- System Framework Integrations
- Network Constants & App Navigation
- App Settings & Tool Test Fixtures
- .loadPrompt
- Dropped File Context Store
- PurchaseManager
- Model Loading & Inference Engine
- StreamingLaTeXText
- URL Attachment Input Row
- UI Localization String Resolution
- Color
- Tool Calling Prompt Unit Tests
- SearchResultCard
- WikipediaQueryCleaner
- RAG Relevance Scoring Engine
- SearchResponse
- FilePickerKind
- .setTotalTokensBudget
- Settings Serialization & Coding Keys
- System Date & Time Tool
- Tool Call Transcript Recorder
- App Entry Point & Lifecycle
- Glassmorphic Message Bubble Styling
- Search Result Cards & Safari View
- XCTestCase
- .assemble
- RAG & PDF Chunking Tests
- TokenBudgetSliderView
- SwiftUI View Rendering Test Suite
- GitHub Development Helper CLI
- AppSettings Store Persistence
- Streaming LaTeX Math Display
- Legacy Settings Migration Keys
- SwiftUI
>>>>>>> 6a7e116 (graph update)
- Brand Logo Icon Generation
- Shell Build Automation Script
- Build and Run Shell Script
- TestRAG French Wiki Benchmark
- Offline Chat Mode Concept
- Token Budgeting Engine Concept
<<<<<<< HEAD
- View
- SwiftUI
- Coordinator
- ChatService.swift
=======
- Local Processing Guarantee
- View
- ChatService.swift
- Coordinator
- WebScrapingService.swift
>>>>>>> 6a7e116 (graph update)

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
<<<<<<< HEAD
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
=======
- `Scientific PDF Test Fixtures (PFAS CMC)` --semantically_similar_to--> `DroppedPDFStore`  [INFERRED] [semantically similar]
  SilicIATests/2025.PFAS.CMC.pdf → SilicIA/Services/DroppedPDFStore.swift
- `Multi-Language UI & Prompts` --implements--> `ModelLanguage`  [EXTRACTED]
  README.md → SilicIA/Models/AppSettings.swift
- `Local Processing Guarantee` --rationale_for--> `AIService`  [INFERRED]
  Privacy.md → SilicIA/Services/AIService.swift
- `SilicIATests Suite` --references--> `WebSearchServiceTests`  [INFERRED]
  BUILDING.md → SilicIATests/WebSearchServiceTests.swift
- `SilicIA Brand Identity & Icon Assets` --references--> `SilicIA Assistant`  [INFERRED]
  logo/appicon_big.png → README.md
>>>>>>> 6a7e116 (graph update)

## Import Cycles
- None detected.

<<<<<<< HEAD
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
=======
## Communities (66 total, 16 thin omitted)

### Community 0 - "RAG Retrieval & Chunking"
Cohesion: 0.06
Nodes (14): Accelerate, MarkdownSegment, prose, table, RAGChunk, RAGChunker, RAGContextService, RAGSelectionOptions (+6 more)

### Community 1 - "SwiftData Conversation Persistence"
Cohesion: 0.07
Nodes (11): SwiftData Chat Persistence, .body, Conversation, Message, Search Tool Calling Definition, ChatMessage, ChatService, Role (+3 more)

### Community 3 - "Dual Web Search & Tests"
>>>>>>> 6a7e116 (graph update)
Cohesion: 0.22
Nodes (3): NonScrollingWKWebView, .body, ReaderHTMLWebViewRepresentable

### Community 4 - "Chat Interface & Streaming"
Cohesion: 0.08
Nodes (19): ChatView, .attachmentMenu, .body, .chatHeaderView, .composerView, .effectiveIsWebSearchEnabled, .effectiveUseDuckDuckGo, .effectiveUseWikipedia (+11 more)

### Community 5 - "Web Content Scraping & Errors"
Cohesion: 0.08
<<<<<<< HEAD
Nodes (13): HTMLSanitizer, HTMLConversionError, conversionFailed, emptyContent, .errorDescription, excessiveDOMDepth, excessiveElementCount, inputTooLarge (+5 more)

### Community 6 - "Image Analysis & Visual Grounding"
Cohesion: 0.09
Nodes (10): ImageIO, ArticleRowProjection, ImageAnalysisResult, .isEmpty, ImageAnalysisService, LayoutObservation, PDFPageAnalysisResult, .isEmpty (+2 more)

### Community 7 - "ContentView"
Cohesion: 0.10
Nodes (17): FoundationModelAvailability, Reason, deviceNotEligible, .isUserFixable, modelNotReady, notEnabled, other, .stringValue (+9 more)
=======
Nodes (15): SilicIATests Suite, HTMLSanitizer, HTMLConversionError, conversionFailed, emptyContent, .errorDescription, excessiveDOMDepth, excessiveElementCount (+7 more)

### Community 6 - "Image Analysis & Visual Grounding"
Cohesion: 0.10
Nodes (9): ImageIO, ArticleRowProjection, ImageAnalysisResult, .isEmpty, ImageAnalysisService, LayoutObservation, PDFPageAnalysisResult, .isEmpty (+1 more)

### Community 7 - "Foundation Model Hardware Availability"
Cohesion: 0.07
Nodes (20): .isReaderViewAndSummaryEnabled, FoundationModelAvailability, Reason, deviceNotEligible, .isUserFixable, modelNotReady, notEnabled, other (+12 more)
>>>>>>> 6a7e116 (graph update)

### Community 8 - "Search Assist View & Grounding"
Cohesion: 0.09
Nodes (19): Search Prompt Instructions, SearchView, .body, .chatButtonTitle, .defaultScrapingCharactersFromContextTokens, .effectiveContextTokens, .emptyStateView, .exampleQueryChips (+11 more)

### Community 9 - "ModelOutputLaTeXSanitizer"
Cohesion: 0.20
Nodes (3): LaTeXStreamSegmenter, ModelOutputLaTeXSanitizer, .body

<<<<<<< HEAD
### Community 10 - "ToolError"
Cohesion: 0.25
Nodes (7): SearchError, botChallengeDetected, .errorDescription, invalidResponse, invalidURL, networkError, parsingFailed
=======
### Community 10 - "System Prompt Template Loader"
Cohesion: 0.19
Nodes (3): SearchResult, AIService, TimingMetric
>>>>>>> 6a7e116 (graph update)

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
<<<<<<< HEAD
Cohesion: 0.15
Nodes (13): Decision, allow, .description, duplicate, .refusalMessage, toolBudgetReached, totalBudgetReached, ToolCallGovernor (+5 more)
=======
Cohesion: 0.13
Nodes (14): Decision, allow, .description, duplicate, .refusalMessage, toolBudgetReached, totalBudgetReached, ToolCallGovernor (+6 more)
>>>>>>> 6a7e116 (graph update)

### Community 19 - "Web Search Scraper Verification CI"
Cohesion: 0.08
Nodes (23): env, runs-on, steps, CODE_SIGN_IDENTITY, CODE_SIGNING_ALLOWED, CODE_SIGNING_REQUIRED, DEVELOPMENT_TEAM, jobs (+15 more)

### Community 21 - "Foundation"
Cohesion: 0.26
Nodes (3): Foundation, FoundationModels, StoreKit

<<<<<<< HEAD
### Community 22 - "AIService"
Cohesion: 0.07
Nodes (20): Local Processing Guarantee, SilicIA Privacy Policy, On-Device LLM (Apple Intelligence), RAG Retrieval Pipeline, Local LLM Chat Showcase, Privacy Feature Showcase, AIService, TimingMetric (+12 more)

### Community 24 - "String"
Cohesion: 0.13
Nodes (5): .isReaderViewAndSummaryEnabled, PlatformClipboard, CitationLink, .searchBarView, .summaryCard
=======
### Community 21 - "System Framework Integrations"
Cohesion: 0.18
Nodes (6): Combine, Foundation, FoundationModels, NaturalLanguage, NetworkConstants, StoreKit
>>>>>>> 6a7e116 (graph update)

### Community 25 - "DroppedFileStore"
Cohesion: 0.07
Nodes (9): DroppedFileStore, .storageDirectory, DroppedImageStore, .storageDirectory, DroppedTextFileStore, .storageDirectory, ConversationsListView, .body (+1 more)

<<<<<<< HEAD
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
=======
### Community 24 - ".loadPrompt"
Cohesion: 0.21
Nodes (4): System Prompt Framework, BundleToken, PromptLoader, PromptLoaderTests

### Community 25 - "Dropped File Context Store"
Cohesion: 0.06
Nodes (13): PDF Analysis & Grounding, PDF Context & Citation Showcase, DroppedFileStore, .storageDirectory, DroppedImageStore, .storageDirectory, DroppedPDFStore, .storageDirectory (+5 more)

### Community 26 - "PurchaseManager"
Cohesion: 0.05
Nodes (11): Entitlements, .canAttachDocuments, .canExceedFreeOutputTokens, .canUseMultipleWebSourcesPerProvider, .hasPremiumAccess, FoundingUserStore, PurchaseManager, AppDelegate (+3 more)

### Community 27 - "Model Loading & Inference Engine"
Cohesion: 0.09
Nodes (21): AppTab, chat, .id, searchAssist, ContentView, .language, .selectedTab, .selectedTabBinding (+13 more)

### Community 28 - "StreamingLaTeXText"
Cohesion: 0.20
Nodes (5): PlatformClipboard, .summaryCard, .webPageSummaryOverlay, StreamingLaTeXText, .foreground

### Community 29 - "URL Attachment Input Row"
Cohesion: 0.20
Nodes (4): Multi-Language UI & Prompts, LocalizationService, LocalizationTests, .service

### Community 30 - "UI Localization String Resolution"
Cohesion: 0.12
Nodes (7): AppSettings, .isWebSummariesEnabled, .maxSearchResults, .totalTokensBudget, AppSettingsStore, .settings, AppSettingsStoreTests

### Community 31 - "Color"
Cohesion: 0.17
Nodes (6): MessageBubbleGlass, PlatformColors, .controlBackground, .textBackground, Color, .platformWindowBackground

### Community 32 - "Tool Calling Prompt Unit Tests"
Cohesion: 0.12
Nodes (16): CodingKeys, isReaderViewAndSummaryEnabled, isWebSummariesEnabled, language, maxContextTokens, maxDuckDuckGoResults, maxResponseTokens, maxWikipediaResults (+8 more)

### Community 33 - "SearchResultCard"
Cohesion: 0.18
Nodes (8): MatchScoreBadge, .body, .clampedPercent, .displayPercent, .progress, SearchResultCard, .body, .isWebSummariesEnabled
>>>>>>> 6a7e116 (graph update)

### Community 35 - "RAG Relevance Scoring Engine"
Cohesion: 0.17
Nodes (4): AppIntents, SilicIAAppShortcuts, .appShortcuts, OpenSilicIASearchIntent

<<<<<<< HEAD
### Community 36 - "MarkdownContentView"
Cohesion: 0.29
Nodes (3): MarkdownBlockParser, MarkdownContentView, .body

### Community 37 - ".acquireSession"
Cohesion: 0.17
Nodes (6): DynamicSessionCoordinator, .currentSnapshot, DynamicSessionStateStore, .current, PrewarmKey, Snapshot

### Community 39 - "WebSearchService"
Cohesion: 0.11
Nodes (6): SilicIATests Suite, Dual Web Search Architecture, Dual Web Search Showcase, WebSearchService, .userAgent, WebSearchServiceTests
=======
### Community 37 - "FilePickerKind"
Cohesion: 0.33
Nodes (4): FilePickerKind, .allowedContentTypes, image, pdf

### Community 39 - "Settings Serialization & Coding Keys"
Cohesion: 0.07
Nodes (14): Dual Web Search Architecture, Dual Web Search Showcase, SearchError, botChallengeDetected, .errorDescription, invalidResponse, invalidURL, networkError (+6 more)
>>>>>>> 6a7e116 (graph update)

### Community 40 - "System Date & Time Tool"
Cohesion: 0.29
Nodes (6): Arguments, DateTimeTool, Mode, both, dateOnly, timeOnly

<<<<<<< HEAD
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
=======
### Community 43 - "Glassmorphic Message Bubble Styling"
Cohesion: 0.25
Nodes (7): App Store Short Description, Build & Tooling Configuration, Build Scripts (scripts/build.sh), Contributing Guidelines, SilicIA Brand Identity & Icon Assets, SilicIA Assistant, Math & Factorial UI Rendering

### Community 44 - "Search Result Cards & Safari View"
Cohesion: 0.15
Nodes (13): MarkdownBlock, code, heading, horizontalRule, .id, orderedList, paragraph, quote (+5 more)

### Community 45 - "XCTestCase"
Cohesion: 0.26
Nodes (5): Arguments, RAGSearchTool, ChatServicePDFChunkPolicyTests, RAGSearchToolTests, ToolTranscriptRecorderTests

### Community 49 - "RAG & PDF Chunking Tests"
>>>>>>> 6a7e116 (graph update)
Cohesion: 0.20
Nodes (5): DebugRAGStorage, .debugRootDirectory, .promptsDirectory, .rankedChunksDirectory, .webpagesDirectory

### Community 51 - "TokenBudgetSliderView"
<<<<<<< HEAD
Cohesion: 0.29
Nodes (6): TokenBudgetSliderView, .body, .estimatedContextWords, .estimatedOutputWords, .outputProfile, .profileBadgeColor

### Community 52 - "bug_report.md"
=======
Cohesion: 0.25
Nodes (6): .chatSettingsPanel, TokenBudgetSliderView, .estimatedContextWords, .estimatedOutputWords, .outputProfile, .profileBadgeColor

### Community 52 - "SwiftUI View Rendering Test Suite"
>>>>>>> 6a7e116 (graph update)
Cohesion: 0.22
Nodes (8): Actual Behavior, Additional Context, Describe the Bug, Environment, Error Logs, Expected Behavior, Screenshots, Steps to Reproduce

### Community 53 - "GitHub Development Helper CLI"
Cohesion: 0.52
Nodes (6): check_build_status(), check_repo_stats(), create_feature_branch(), print_menu(), github-helper.sh script, view_recent_commits()

<<<<<<< HEAD
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
=======
### Community 54 - "AppSettings Store Persistence"
Cohesion: 0.22
Nodes (8): Additional Notes, Changes Made, Checklist, Description, Related Issues, Screenshots (if applicable), Testing, Type of Change

### Community 57 - "Streaming LaTeX Math Display"
Cohesion: 0.24
Nodes (5): Configuration, ToolCallingTone, chat, search, ToolKit

### Community 58 - "Legacy Settings Migration Keys"
Cohesion: 0.40
Nodes (4): Additional Context, Describe Alternatives You've Considered, Describe the Solution You'd Like, Is Your Feature Request Related to a Problem?

### Community 59 - "SwiftUI"
Cohesion: 0.14
Nodes (10): LaTeXSwiftUI, SafariServices, ChatViewMode, full, pdfTalkme, SwiftData, SwiftUI, UIKit (+2 more)

### Community 69 - "Local Processing Guarantee"
Cohesion: 0.40
Nodes (5): Local Processing Guarantee, SilicIA Privacy Policy, On-Device LLM (Apple Intelligence), Local LLM Chat Showcase, Privacy Feature Showcase

### Community 70 - "View"
Cohesion: 0.13
Nodes (6): View, FeatureRow, .body, .headerView, SourceToggleButtons, .body

### Community 71 - "ChatService.swift"
Cohesion: 0.36
Nodes (4): AppKit, CoreGraphics, PDFKit, Vision

### Community 78 - "WebScrapingService.swift"
Cohesion: 0.40
Nodes (4): HTMLToMarkdown, URL Context Extraction, Reeeed, Multi-Context Chat Showcase

## Knowledge Gaps
- **161 isolated node(s):** `searchAssist`, `chat`, `.id`, `.language`, `.selectedTabBinding` (+156 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 420 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **16 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.
>>>>>>> 6a7e116 (graph update)

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

<<<<<<< HEAD
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
=======
- **Why does `ModelLanguage` connect `Model Loading & Inference Engine` to `RAG Retrieval & Chunking`, `SwiftData Conversation Persistence`, `SearchResultCard`, `SearchResponse`, `Foundation Model Hardware Availability`, `System Date & Time Tool`, `Settings Serialization & Coding Keys`, `System Prompt Template Loader`, `XCTestCase`, `Multi-Query Search Sources Tool`, `TokenBudgetSliderView`, `System Framework Integrations`, `Dropped File Context Store`, `.loadPrompt`, `Streaming LaTeX Math Display`, `URL Attachment Input Row`, `UI Localization String Resolution`?**
  _High betweenness centrality (0.152) - this node is a cross-community bridge._
- **Are the 7 inferred relationships involving `ChatService` (e.g. with `ContentView` and `Search Tool Calling Definition`) actually correct?**
  _`ChatService` has 7 INFERRED edges - model-reasoned connections that need verification._
- **What connects `searchAssist`, `chat`, `.id` to the rest of the system?**
  _161 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `RAG Retrieval & Chunking` be split into smaller, more focused modules?**
  _Cohesion score 0.060866318147871544 - nodes in this community are weakly interconnected._
- **Why does `ChatService` connect `SwiftData Conversation Persistence` to `RAG Retrieval & Chunking`, `Chat Interface & Streaming`, `Web Content Scraping & Errors`, `Settings Serialization & Coding Keys`, `Search Assist View & Grounding`, `Foundation Model Hardware Availability`, `App Entry Point & Lifecycle`, `System Framework Integrations`, `Network Constants & App Navigation`, `Dropped File Context Store`, `PurchaseManager`, `Model Loading & Inference Engine`?**
  _High betweenness centrality (0.130) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `ChatView` (e.g. with `.body` and `.testMainViewsRenderWithoutCrashing()`) actually correct?**
  _`ChatView` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Should `SwiftData Conversation Persistence` be split into smaller, more focused modules?**
  _Cohesion score 0.07066167290886392 - nodes in this community are weakly interconnected._
>>>>>>> 6a7e116 (graph update)
