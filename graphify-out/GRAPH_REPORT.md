# Graph Report - SilicIA  (2026-11-11)

## Corpus Check
- 116 files · ~112,998 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 15 file(s) not represented in the graph (top: (none) 5, .entitlements 3, .plist 2)

## Summary
- 1517 nodes · 3740 edges · 88 communities (51 shown, 37 thin omitted)
- Extraction: 94% EXTRACTED · 6% INFERRED · 0% AMBIGUOUS · INFERRED: 224 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `bbf2515f`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- String
- ChatService
- DynamicSessionCoordinator
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
- MonetizationTests
- Entitlements
- LocalizationService
- AppSettings
- SilicIADynamicProfile
- CodingKeys
- MatchScoreBadge
- .check
- OpenSilicIASearchIntent
- SourceFunnel
- .acquireSession
- XCTestCase
- WebSearchService
- DateTimeTool
- ToolTranscriptRecorder
- String
- SilicIA Assistant
- MarkdownBlock
- RAGSearchTool
- SharedTopBarView
- SilicIAApp
- StreamingLaTeXText
- DebugRAGStorage
- URL
- AppDelegate
- bug_report.md
- github-helper.sh
- pull_request_template.md
- AppSettingsStoreTests
- SwiftUI
- .assemble
- feature_request.md
- ChatService.swift
- TokenBudgetSliderView
- .testMainViewsRenderWithoutCrashing
- convert.sh
- build.sh
- build-and-run.sh
- run.sh
- Offline Chat Mode
- Token Budgeting Engine
- ModelAvailabilityNotice
- View
- SwiftData
- Coordinator
- WebScrapingService.swift

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

## Communities (88 total, 37 thin omitted)

### Community 0 - "String"
Cohesion: 0.09
Nodes (15): Accelerate, RAG Retrieval Pipeline, MarkdownSegment, prose, table, QueryTermData, RAGChunk, RAGChunker (+7 more)

### Community 1 - "ChatService"
Cohesion: 0.07
Nodes (12): SwiftData Chat Persistence, .body, Conversation, Message, Search Tool Calling Definition, ChatMessage, ChatService, PDFPageBatch (+4 more)

### Community 2 - "DynamicSessionCoordinator"
Cohesion: 0.16
Nodes (8): DynamicSessionCoordinator, .currentSnapshot, DynamicSessionMode, chat, chatFallback, searchQueryGeneration, searchSummary, webPageSummary

### Community 4 - "ChatView"
Cohesion: 0.05
Nodes (37): AppTab, chat, .id, searchAssist, ContextSourceKind, .displayName, .id, offline (+29 more)

### Community 5 - "WebScrapingService"
Cohesion: 0.08
Nodes (13): HTMLSanitizer, HTMLConversionError, conversionFailed, emptyContent, .errorDescription, excessiveDOMDepth, excessiveElementCount, inputTooLarge (+5 more)

### Community 6 - "Sendable"
Cohesion: 0.09
Nodes (10): ImageIO, ArticleRowProjection, ImageAnalysisResult, .isEmpty, ImageAnalysisService, LayoutObservation, PDFPageAnalysisResult, .isEmpty (+2 more)

### Community 7 - "ContentView"
Cohesion: 0.13
Nodes (14): FoundationModelAvailability, Reason, deviceNotEligible, .isUserFixable, modelNotReady, notEnabled, other, .stringValue (+6 more)

### Community 8 - "SearchView"
Cohesion: 0.09
Nodes (19): Search Prompt Instructions, SearchView, .body, .chatButtonTitle, .defaultScrapingCharactersFromContextTokens, .effectiveContextTokens, .emptyStateView, .exampleQueryChips (+11 more)

### Community 9 - "ModelOutputLaTeXSanitizer"
Cohesion: 0.21
Nodes (3): LaTeXStreamSegmenter, ModelOutputLaTeXSanitizer, .body

### Community 11 - "generate_slides_ipad.py"
Cohesion: 0.10
Nodes (16): draw_text_wrapped(), load_font(), main(), make_phone_mockup(), pill_badge(), radial_glow(), render_slide(), vertical_gradient() (+8 more)

### Community 13 - "steps"
Cohesion: 0.07
Nodes (26): GitHub Automation & CI, env, runs-on, steps, CODE_SIGN_IDENTITY, CODE_SIGNING_ALLOWED, CODE_SIGNING_REQUIRED, DEVELOPMENT_TEAM (+18 more)

### Community 14 - "SourceFunnel"
Cohesion: 0.17
Nodes (13): Arguments, SearchSourcesTool, SingleQueryArguments, WebOnlyArguments, WebOnlySingleQueryArguments, WebSourcesTool, WikiFastArguments, WikiFastOnlyArguments (+5 more)

### Community 15 - "env"
Cohesion: 0.08
Nodes (25): APPLE_APP_SPECIFIC_PASSWORD, APPLE_ID, APPLE_TEAM_ID, BUILD_CERTIFICATE_BASE64, GITHUB_TOKEN, P12_PASSWORD, jobs, release (+17 more)

### Community 16 - "steps"
Cohesion: 0.08
Nodes (25): CODE_SIGN_IDENTITY, CODE_SIGNING_ALLOWED, CODE_SIGNING_REQUIRED, DEVELOPMENT_TEAM, jobs, test, name, on (+17 more)

### Community 17 - "Coordinator"
Cohesion: 0.14
Nodes (3): Coordinator, KeyboardDismissTapOverlay, WindowTrackingView

### Community 18 - "ToolCallGovernor"
Cohesion: 0.15
Nodes (13): Decision, allow, .description, duplicate, .refusalMessage, toolBudgetReached, totalBudgetReached, ToolCallGovernor (+5 more)

### Community 19 - "steps"
Cohesion: 0.08
Nodes (23): env, runs-on, steps, CODE_SIGN_IDENTITY, CODE_SIGNING_ALLOWED, CODE_SIGNING_REQUIRED, DEVELOPMENT_TEAM, jobs (+15 more)

### Community 21 - "Foundation"
Cohesion: 0.19
Nodes (5): Combine, Foundation, FoundationModels, os, StoreKit

### Community 22 - "AIService"
Cohesion: 0.05
Nodes (33): Local Processing Guarantee, SilicIA Privacy Policy, On-Device LLM (Apple Intelligence), Local LLM Chat Showcase, Privacy Feature Showcase, ModelLanguage, .code, english (+25 more)

### Community 23 - "SilicIA"
Cohesion: 0.21
Nodes (3): Observation, SilicIA, XCTest

### Community 24 - "SearchView.swift"
Cohesion: 0.21
Nodes (7): SafariServices, FeatureRow, .body, SearchResultCard, .body, .isWebSummariesEnabled, WebKit

### Community 25 - "DroppedFileStore"
Cohesion: 0.06
Nodes (13): PDF Analysis & Grounding, PDF Context & Citation Showcase, DroppedFileStore, .storageDirectory, DroppedImageStore, .storageDirectory, DroppedPDFStore, .storageDirectory (+5 more)

### Community 28 - "Entitlements"
Cohesion: 0.21
Nodes (5): Entitlements, .canAttachDocuments, .canExceedFreeOutputTokens, .canUseMultipleWebSourcesPerProvider, .hasPremiumAccess

### Community 29 - "LocalizationService"
Cohesion: 0.18
Nodes (4): Multi-Language UI & Prompts, LocalizationService, LocalizationTests, .service

### Community 30 - "AppSettings"
Cohesion: 0.12
Nodes (12): AppSettings, .contextSourceKind, .isWebSummariesEnabled, .maxDuckDuckGoResults, .maxSearchResults, .maxWikipediaResults, .outputProfileKind, .temperature (+4 more)

### Community 31 - "SilicIADynamicProfile"
Cohesion: 0.28
Nodes (4): SilicIADynamicInstructions, .body, SilicIADynamicProfile, .body

### Community 32 - "CodingKeys"
Cohesion: 0.11
Nodes (17): CodingKeys, isReaderViewAndSummaryEnabled, isWebSummariesEnabled, language, maxContextTokens, maxDuckDuckGoResults, maxResponseTokens, maxWikipediaResults (+9 more)

### Community 33 - "MatchScoreBadge"
Cohesion: 0.25
Nodes (5): MatchScoreBadge, .body, .clampedPercent, .displayPercent, .progress

### Community 34 - ".check"
Cohesion: 0.17
Nodes (3): .isReaderViewAndSummaryEnabled, AppSettingsStore, .settings

### Community 35 - "OpenSilicIASearchIntent"
Cohesion: 0.17
Nodes (4): AppIntents, SilicIAAppShortcuts, .appShortcuts, OpenSilicIASearchIntent

### Community 36 - "SourceFunnel"
Cohesion: 0.18
Nodes (3): SourceFunnel, CapturedResultsBox, TestRAGMain

### Community 37 - ".acquireSession"
Cohesion: 0.30
Nodes (4): DynamicSessionStateStore, .current, PrewarmKey, Snapshot

### Community 38 - "XCTestCase"
Cohesion: 0.17
Nodes (5): DocumentContextTests, ModelAnsweringTests, PromptLoaderTests, SanitizerTests, ToolCallingPromptTests

### Community 39 - "WebSearchService"
Cohesion: 0.06
Nodes (22): SilicIATests Suite, Dual Web Search Architecture, Dual Web Search Showcase, WikipediaSource, online, wikiFast, SearchResponse, SearchResult (+14 more)

### Community 40 - "DateTimeTool"
Cohesion: 0.29
Nodes (6): Arguments, DateTimeTool, Mode, both, dateOnly, timeOnly

### Community 43 - "SilicIA Assistant"
Cohesion: 0.25
Nodes (7): App Store Short Description, Build & Tooling Configuration, Build Scripts (scripts/build.sh), Contributing Guidelines, SilicIA Brand Identity & Icon Assets, SilicIA Assistant, Math & Factorial UI Rendering

### Community 44 - "MarkdownBlock"
Cohesion: 0.18
Nodes (10): MarkdownBlock, code, heading, horizontalRule, .id, orderedList, paragraph, quote (+2 more)

### Community 46 - "SharedTopBarView"
Cohesion: 0.23
Nodes (6): SharedTopBarView, .body, .settings, SourceToggleButtons, .body, .isCompact

### Community 48 - "StreamingLaTeXText"
Cohesion: 0.15
Nodes (9): PlatformColors, .controlBackground, .textBackground, Color, .platformWindowBackground, PlatformClipboard, .summaryCard, StreamingLaTeXText (+1 more)

### Community 49 - "DebugRAGStorage"
Cohesion: 0.20
Nodes (5): DebugRAGStorage, .debugRootDirectory, .promptsDirectory, .rankedChunksDirectory, .webpagesDirectory

### Community 52 - "bug_report.md"
Cohesion: 0.22
Nodes (8): Actual Behavior, Additional Context, Describe the Bug, Environment, Error Logs, Expected Behavior, Screenshots, Steps to Reproduce

### Community 53 - "github-helper.sh"
Cohesion: 0.52
Nodes (6): check_build_status(), check_repo_stats(), create_feature_branch(), print_menu(), github-helper.sh script, view_recent_commits()

### Community 54 - "pull_request_template.md"
Cohesion: 0.22
Nodes (8): Additional Notes, Changes Made, Checklist, Description, Related Issues, Screenshots (if applicable), Testing, Type of Change

### Community 56 - "SwiftUI"
Cohesion: 0.20
Nodes (7): LaTeXSwiftUI, MarkdownBlockParser, SharedSettingsView, .body, .settings, .settingsPanel, SwiftUI

### Community 58 - "feature_request.md"
Cohesion: 0.40
Nodes (4): Additional Context, Describe Alternatives You've Considered, Describe the Solution You'd Like, Is Your Feature Request Related to a Problem?

### Community 59 - "ChatService.swift"
Cohesion: 0.16
Nodes (8): AppKit, CoreGraphics, NaturalLanguage, PDFKit, NetworkConstants, UIKit, UniformTypeIdentifiers, Vision

### Community 61 - "TokenBudgetSliderView"
Cohesion: 0.29
Nodes (6): TokenBudgetSliderView, .body, .estimatedContextWords, .estimatedOutputWords, .outputProfile, .profileBadgeColor

### Community 62 - ".testMainViewsRenderWithoutCrashing"
Cohesion: 0.20
Nodes (5): ContentView, .language, .selectedTab, .selectedTabBinding, ViewRenderingTests

### Community 69 - "ModelAvailabilityNotice"
Cohesion: 0.33
Nodes (3): ModelAvailabilityNotice, .body, .iconName

### Community 77 - "Coordinator"
Cohesion: 0.14
Nodes (3): Coordinator, ReaderHTMLWebView, .body

### Community 78 - "WebScrapingService.swift"
Cohesion: 0.40
Nodes (4): HTMLToMarkdown, URL Context Extraction, Reeeed, Multi-Context Chat Showcase

## Knowledge Gaps
- **193 isolated node(s):** `full`, `pdfTalkme`, `pdf`, `image`, `.allowedContentTypes` (+188 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 469 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **37 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ModelLanguage` connect `AIService` to `String`, `ChatService`, `ChatView`, `Sendable`, `ContentView`, `SourceFunnel`, `SearchView.swift`, `DroppedFileStore`, `LocalizationService`, `AppSettings`, `MatchScoreBadge`, `SourceFunnel`, `WebSearchService`, `DateTimeTool`, `RAGSearchTool`, `.assemble`, `ChatService.swift`, `TokenBudgetSliderView`, `.testMainViewsRenderWithoutCrashing`, `ModelAvailabilityNotice`?**
  _High betweenness centrality (0.132) - this node is a cross-community bridge._
- **Are the 9 inferred relationships involving `ChatService` (e.g. with `ContentView` and `Search Tool Calling Definition`) actually correct?**
  _`ChatService` has 9 INFERRED edges - model-reasoned connections that need verification._
- **What connects `full`, `pdfTalkme`, `pdf` to the rest of the system?**
  _193 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `String` be split into smaller, more focused modules?**
  _Cohesion score 0.08508891928864569 - nodes in this community are weakly interconnected._
- **Why does `ChatService` connect `ChatService` to `String`, `ChatView`, `WebScrapingService`, `XCTestCase`, `WebSearchService`, `SearchView`, `Coordinator`, `ChatService.swift`, `Entitlements`, `.testMainViewsRenderWithoutCrashing`?**
  _High betweenness centrality (0.118) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `ChatView` (e.g. with `.body` and `.testMainViewsRenderWithoutCrashing()`) actually correct?**
  _`ChatView` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Should `ChatService` be split into smaller, more focused modules?**
  _Cohesion score 0.07333970377448638 - nodes in this community are weakly interconnected._