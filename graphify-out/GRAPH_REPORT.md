# Graph Report - SilicIA  (2026-11-11)

## Corpus Check
- 116 files · ~112,995 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 15 file(s) not represented in the graph (top: (none) 5, .entitlements 3, .plist 2)

## Summary
- 1507 nodes · 3740 edges · 78 communities (56 shown, 22 thin omitted)
- Extraction: 94% EXTRACTED · 6% INFERRED · 0% AMBIGUOUS · INFERRED: 224 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `354146bb`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- String
- ChatService
- WikipediaSource
- ReaderHTMLWebViewRepresentable
- ChatView
- WebScrapingService
- Sendable
- ContentView
- SearchView
- ModelOutputLaTeXSanitizer
- MarkdownContentView
- generate_slides_ipad.py
- ShareViewController
- steps
- SourceFunnel
- env
- steps
- Coordinator
- ToolCallGovernor
- steps
- CalculatorTool
- Foundation
- AIService
- SilicIA
- SearchView.swift
- DroppedFileStore
- PurchaseManager
- ContentView
- StreamingLaTeXText
- LocalizationService
- AppSettings
- TokenBudgetingTests
- CodingKeys
- MatchScoreBadge
- OpenSilicIASearchIntent
- MarkdownContentView
- .acquireSession
- ModelAnsweringTests
- WebSearchService
- DateTimeTool
- ToolTranscriptRecorder
- String
- SilicIA Assistant
- MarkdownBlock
- RAGSearchTool
- SharedTopBarView
- SearchError
- Color
- DebugRAGStorage
- ModelLanguage
- WebSearchServiceTests
- bug_report.md
- github-helper.sh
- pull_request_template.md
- AppSettingsStoreTests
- TokenBudgetSliderView
- .loadPrompt
- feature_request.md
- SwiftUI
- WebSearchService.swift
- .testMainViewsRenderWithoutCrashing
- convert.sh
- build.sh
- build-and-run.sh
- run.sh
- Offline Chat Mode
- Token Budgeting Engine
- SourceToggleButtons
- View
- .summaryCard
- ChatViewMode
- Coordinator
- ChatService.swift

## God Nodes (most connected - your core abstractions)
1. `ChatService` - 88 edges
2. `ModelLanguage` - 88 edges
3. `ChatView` - 71 edges
4. `SearchView` - 66 edges
5. `WebSearchService` - 56 edges
6. `RAGContextService` - 51 edges
7. `AppSettings` - 46 edges
8. `WebScrapingService` - 40 edges
9. `AIService` - 39 edges
10. `SearchResult` - 35 edges

## Surprising Connections (you probably didn't know these)
- `Multi-Language UI & Prompts` --implements--> `ModelLanguage`  [EXTRACTED]
  README.md → SilicIA/Models/AppSettings.swift
- `SilicIATests Suite` --references--> `WebSearchServiceTests`  [INFERRED]
  BUILDING.md → SilicIATests/WebSearchServiceTests.swift
- `SilicIA Brand Identity & Icon Assets` --references--> `SilicIA Assistant`  [INFERRED]
  logo/appicon_big.png → README.md
- `Math & Factorial UI Rendering` --conceptually_related_to--> `SilicIA Assistant`  [INFERRED]
  Screenshots/Factorial.png → README.md
- `SwiftData Chat Persistence` --implements--> `Conversation`  [EXTRACTED]
  README.md → SilicIA/Models/Conversation.swift

## Import Cycles
- None detected.

## Communities (78 total, 22 thin omitted)

### Community 0 - "String"
Cohesion: 0.08
Nodes (16): Accelerate, NaturalLanguage, RAG Retrieval Pipeline, MarkdownSegment, prose, table, QueryTermData, RAGChunk (+8 more)

### Community 1 - "ChatService"
Cohesion: 0.07
Nodes (12): SwiftData Chat Persistence, .body, Conversation, Message, Search Tool Calling Definition, ChatMessage, ChatService, PDFPageBatch (+4 more)

### Community 2 - "WikipediaSource"
Cohesion: 0.17
Nodes (10): ContextSourceKind, .displayName, .id, offline, .systemImage, web, wiki, WikipediaSource (+2 more)

### Community 4 - "ChatView"
Cohesion: 0.08
Nodes (19): ChatView, .attachmentMenu, .body, .chatHeaderView, .composerView, .effectiveIsWebSearchEnabled, .effectiveUseDuckDuckGo, .effectiveUseWikipedia (+11 more)

### Community 5 - "WebScrapingService"
Cohesion: 0.08
Nodes (13): HTMLSanitizer, HTMLConversionError, conversionFailed, emptyContent, .errorDescription, excessiveDOMDepth, excessiveElementCount, inputTooLarge (+5 more)

### Community 6 - "Sendable"
Cohesion: 0.09
Nodes (10): ImageIO, ArticleRowProjection, ImageAnalysisResult, .isEmpty, ImageAnalysisService, LayoutObservation, PDFPageAnalysisResult, .isEmpty (+2 more)

### Community 7 - "ContentView"
Cohesion: 0.09
Nodes (19): .isReaderViewAndSummaryEnabled, FoundationModelAvailability, Reason, deviceNotEligible, .isUserFixable, modelNotReady, notEnabled, other (+11 more)

### Community 8 - "SearchView"
Cohesion: 0.09
Nodes (18): Search Prompt Instructions, SearchView, .body, .chatButtonTitle, .defaultScrapingCharactersFromContextTokens, .effectiveContextTokens, .emptyStateView, .exampleQueryChips (+10 more)

### Community 9 - "ModelOutputLaTeXSanitizer"
Cohesion: 0.21
Nodes (3): LaTeXStreamSegmenter, ModelOutputLaTeXSanitizer, .body

### Community 10 - "MarkdownContentView"
Cohesion: 0.29
Nodes (3): MarkdownBlockParser, MarkdownContentView, .body

### Community 11 - "generate_slides_ipad.py"
Cohesion: 0.10
Nodes (16): draw_text_wrapped(), load_font(), main(), make_phone_mockup(), pill_badge(), radial_glow(), render_slide(), vertical_gradient() (+8 more)

### Community 13 - "steps"
Cohesion: 0.07
Nodes (26): GitHub Automation & CI, env, runs-on, steps, CODE_SIGN_IDENTITY, CODE_SIGNING_ALLOWED, CODE_SIGNING_REQUIRED, DEVELOPMENT_TEAM (+18 more)

### Community 14 - "SourceFunnel"
Cohesion: 0.10
Nodes (16): Arguments, SearchSourcesTool, SingleQueryArguments, WebOnlyArguments, WebOnlySingleQueryArguments, WebSourcesTool, WikiFastArguments, WikiFastOnlyArguments (+8 more)

### Community 15 - "env"
Cohesion: 0.08
Nodes (25): APPLE_APP_SPECIFIC_PASSWORD, APPLE_ID, APPLE_TEAM_ID, BUILD_CERTIFICATE_BASE64, GITHUB_TOKEN, P12_PASSWORD, jobs, release (+17 more)

### Community 16 - "steps"
Cohesion: 0.08
Nodes (25): CODE_SIGN_IDENTITY, CODE_SIGNING_ALLOWED, CODE_SIGNING_REQUIRED, DEVELOPMENT_TEAM, jobs, test, name, on (+17 more)

### Community 17 - "Coordinator"
Cohesion: 0.15
Nodes (3): Coordinator, KeyboardDismissTapOverlay, WindowTrackingView

### Community 18 - "ToolCallGovernor"
Cohesion: 0.23
Nodes (8): Decision, allow, .description, duplicate, .refusalMessage, toolBudgetReached, totalBudgetReached, ToolCallGovernor

### Community 19 - "steps"
Cohesion: 0.08
Nodes (23): env, runs-on, steps, CODE_SIGN_IDENTITY, CODE_SIGNING_ALLOWED, CODE_SIGNING_REQUIRED, DEVELOPMENT_TEAM, jobs (+15 more)

### Community 21 - "Foundation"
Cohesion: 0.22
Nodes (3): Foundation, FoundationModels, NetworkConstants

### Community 22 - "AIService"
Cohesion: 0.06
Nodes (26): Local Processing Guarantee, SilicIA Privacy Policy, On-Device LLM (Apple Intelligence), Local LLM Chat Showcase, Privacy Feature Showcase, AIService, TimingMetric, OutputProfile (+18 more)

### Community 23 - "SilicIA"
Cohesion: 0.13
Nodes (8): Observation, SilicIA, DocumentContextTests, LocalizationTests, .service, SanitizerTests, ToolCallingPromptTests, XCTest

### Community 24 - "SearchView.swift"
Cohesion: 0.31
Nodes (4): SearchResultCard, .body, .isWebSummariesEnabled, .resultsView

### Community 25 - "DroppedFileStore"
Cohesion: 0.06
Nodes (13): PDF Analysis & Grounding, PDF Context & Citation Showcase, DroppedFileStore, .storageDirectory, DroppedImageStore, .storageDirectory, DroppedPDFStore, .storageDirectory (+5 more)

### Community 26 - "PurchaseManager"
Cohesion: 0.05
Nodes (11): Entitlements, .canAttachDocuments, .canExceedFreeOutputTokens, .canUseMultipleWebSourcesPerProvider, .hasPremiumAccess, FoundingUserStore, PurchaseManager, AppDelegate (+3 more)

### Community 27 - "ContentView"
Cohesion: 0.20
Nodes (8): AppTab, chat, .id, searchAssist, ContentView, .language, .selectedTab, .selectedTabBinding

### Community 28 - "StreamingLaTeXText"
Cohesion: 0.33
Nodes (3): LaTeXSwiftUI, StreamingLaTeXText, .foreground

### Community 30 - "AppSettings"
Cohesion: 0.09
Nodes (14): AppSettings, .contextSourceKind, .isWebSummariesEnabled, .maxDuckDuckGoResults, .maxSearchResults, .maxWikipediaResults, .outputProfileKind, .temperature (+6 more)

### Community 31 - "TokenBudgetingTests"
Cohesion: 0.15
Nodes (11): os, DynamicSessionMode, chat, chatFallback, searchQueryGeneration, searchSummary, webPageSummary, SilicIADynamicInstructions (+3 more)

### Community 32 - "CodingKeys"
Cohesion: 0.11
Nodes (17): CodingKeys, isReaderViewAndSummaryEnabled, isWebSummariesEnabled, language, maxContextTokens, maxDuckDuckGoResults, maxResponseTokens, maxWikipediaResults (+9 more)

### Community 33 - "MatchScoreBadge"
Cohesion: 0.25
Nodes (5): MatchScoreBadge, .body, .clampedPercent, .displayPercent, .progress

### Community 35 - "OpenSilicIASearchIntent"
Cohesion: 0.17
Nodes (4): AppIntents, SilicIAAppShortcuts, .appShortcuts, OpenSilicIASearchIntent

### Community 36 - "MarkdownContentView"
Cohesion: 0.26
Nodes (3): SearchResponse, SearchResult, WikiFastArticle

### Community 37 - ".acquireSession"
Cohesion: 0.16
Nodes (6): DynamicSessionCoordinator, .currentSnapshot, DynamicSessionStateStore, .current, PrewarmKey, Snapshot

### Community 39 - "WebSearchService"
Cohesion: 0.13
Nodes (4): Dual Web Search Architecture, Dual Web Search Showcase, WebSearchService, .userAgent

### Community 40 - "DateTimeTool"
Cohesion: 0.29
Nodes (6): Arguments, DateTimeTool, Mode, both, dateOnly, timeOnly

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
Cohesion: 0.38
Nodes (3): SharedTopBarView, .body, .settings

### Community 47 - "SearchError"
Cohesion: 0.14
Nodes (12): ToolError, duplicate, .errorDescription, toolBudgetReached, totalBudgetReached, SearchError, botChallengeDetected, .errorDescription (+4 more)

### Community 48 - "Color"
Cohesion: 0.18
Nodes (6): MessageBubbleGlass, PlatformColors, .controlBackground, .textBackground, Color, .platformWindowBackground

### Community 49 - "DebugRAGStorage"
Cohesion: 0.20
Nodes (5): DebugRAGStorage, .debugRootDirectory, .promptsDirectory, .rankedChunksDirectory, .webpagesDirectory

### Community 50 - "ModelLanguage"
Cohesion: 0.22
Nodes (6): ModelLanguage, .code, english, french, .nlLanguage, spanish

### Community 52 - "bug_report.md"
Cohesion: 0.22
Nodes (8): Actual Behavior, Additional Context, Describe the Bug, Environment, Error Logs, Expected Behavior, Screenshots, Steps to Reproduce

### Community 53 - "github-helper.sh"
Cohesion: 0.52
Nodes (6): check_build_status(), check_repo_stats(), create_feature_branch(), print_menu(), github-helper.sh script, view_recent_commits()

### Community 54 - "pull_request_template.md"
Cohesion: 0.22
Nodes (8): Additional Notes, Changes Made, Checklist, Description, Related Issues, Screenshots (if applicable), Testing, Type of Change

### Community 56 - "TokenBudgetSliderView"
Cohesion: 0.40
Nodes (3): SharedSettingsView, .body, .settings

### Community 57 - ".loadPrompt"
Cohesion: 0.14
Nodes (9): System Prompt Framework, BundleToken, PromptLoader, Configuration, ToolCallingTone, chat, search, ToolKit (+1 more)

### Community 58 - "feature_request.md"
Cohesion: 0.40
Nodes (4): Additional Context, Describe Alternatives You've Considered, Describe the Solution You'd Like, Is Your Feature Request Related to a Problem?

### Community 59 - "SwiftUI"
Cohesion: 0.23
Nodes (7): AppKit, SafariServices, SwiftData, SwiftUI, UIKit, UniformTypeIdentifiers, WebKit

### Community 61 - "WebSearchService.swift"
Cohesion: 0.70
Nodes (3): WikipediaSearchFallbackPage, WikipediaSearchFallbackResponse, WikipediaWithHTMLResponse

### Community 69 - "SourceToggleButtons"
Cohesion: 0.60
Nodes (3): SourceToggleButtons, .body, .isCompact

### Community 70 - "View"
Cohesion: 0.27
Nodes (3): View, FeatureRow, .body

### Community 72 - "ChatViewMode"
Cohesion: 0.67
Nodes (3): ChatViewMode, full, pdfTalkme

### Community 77 - "Coordinator"
Cohesion: 0.16
Nodes (4): Coordinator, ReaderHTMLWebView, .body, ReaderHTMLWebViewRepresentable

### Community 78 - "ChatService.swift"
Cohesion: 0.18
Nodes (9): Combine, CoreGraphics, HTMLToMarkdown, PDFKit, URL Context Extraction, Reeeed, Multi-Context Chat Showcase, StoreKit (+1 more)

## Knowledge Gaps
- **193 isolated node(s):** `.settings`, `.isCompact`, `Accelerate`, `prose`, `table` (+188 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 458 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **22 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ModelLanguage` connect `ModelLanguage` to `String`, `ChatService`, `WikipediaSource`, `Sendable`, `ContentView`, `SourceFunnel`, `AIService`, `SilicIA`, `SearchView.swift`, `DroppedFileStore`, `ContentView`, `LocalizationService`, `AppSettings`, `MatchScoreBadge`, `.executeWikipediaSearch`, `MarkdownContentView`, `WebSearchService`, `DateTimeTool`, `RAGSearchTool`, `WebSearchServiceTests`, `.loadPrompt`?**
  _High betweenness centrality (0.146) - this node is a cross-community bridge._
- **Are the 9 inferred relationships involving `ChatService` (e.g. with `ContentView` and `Search Tool Calling Definition`) actually correct?**
  _`ChatService` has 9 INFERRED edges - model-reasoned connections that need verification._
- **What connects `.settings`, `.isCompact`, `Accelerate` to the rest of the system?**
  _193 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `String` be split into smaller, more focused modules?**
  _Cohesion score 0.08340016038492382 - nodes in this community are weakly interconnected._
- **Why does `ChatService` connect `ChatService` to `String`, `ChatView`, `WebScrapingService`, `ModelAnsweringTests`, `WebSearchService`, `SearchView`, `Coordinator`, `ChatService.swift`, `DroppedFileStore`, `PurchaseManager`, `ContentView`, `.testMainViewsRenderWithoutCrashing`?**
  _High betweenness centrality (0.126) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `ChatView` (e.g. with `.body` and `.testMainViewsRenderWithoutCrashing()`) actually correct?**
  _`ChatView` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Should `ChatService` be split into smaller, more focused modules?**
  _Cohesion score 0.07286192068800765 - nodes in this community are weakly interconnected._