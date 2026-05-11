# SilicIA

[![Build SilicIA](https://github.com/Eddy-Barraud/SilicIA/actions/workflows/build.yml/badge.svg)](https://github.com/Eddy-Barraud/SilicIA/actions/workflows/build.yml)
[![Check Web Search Sources](https://github.com/Eddy-Barraud/SilicIA/actions/workflows/checkwebscrap.yml/badge.svg)](https://github.com/Eddy-Barraud/SilicIA/actions/workflows/checkwebscrap.yml)

A privacy-focused AI assistant for macOS and iOS, powered by Apple Intelligence (on-device LLM). Search the web via DuckDuckGo and Wikipedia, chat without any web source, or analyse PDF documents — all processed entirely on your device.

![Example usage asking the Factorial function](Screenshots/Factorial.png)

## Features

- 🔍 **Dual Web Search**: DuckDuckGo + Wikipedia, each independently toggleable with a per-source result count slider
- 🤖 **On-Device LLM**: Powered by Apple's Foundation Models framework — no data ever leaves your device
- 💬 **Offline Chat Mode**: Disable all sources and chat directly with the model — no network traffic at all
- 📄 **PDF Analysis**: Drag and drop any PDF; the app chunks and indexes it for retrieval-augmented answers with page-level citations
- 📎 **URL Context**: Paste any URL into the chat to scrape and use its content as context
- 🔗 **Search Assist**: Web search with AI-generated summaries and direct links to sources
- 💾 **Persistent Chat History**: Conversations saved locally with SwiftData; auto-generated titles
- 🌍 **Multi-language UI**: English, French, and Spanish — driven by an in-app setting, not the OS locale
- 📤 **Share Extension**: Share any webpage from Safari directly into SilicIA as context
- 🔒 **Privacy-First**: No tracking, no analytics, no cloud AI — everything runs on your Apple Silicon chip

## Overview

SilicIA is a native macOS and iOS application that brings a [Perplexica](https://github.com/ItzCrazyKns/Perplexica)-style AI search experience to Apple Silicon devices with Apple Intelligence. It combines privacy-respecting web search with Apple's on-device LLM to deliver accurate, cited answers without sending your queries to any third-party AI service.

### How It Works

1. **Query** — Type your question naturally
2. **Search** — DuckDuckGo and/or Wikipedia are queried (or skipped entirely in offline mode)
3. **Scrape** — Full page content is fetched and chunked into a retrieval index
4. **Rank** — Chunks are scored for relevance against your query using cosine similarity
5. **Generate** — The highest-ranked context is injected into a prompt and streamed through the on-device model
6. **Cite** — Sources (URLs or PDF pages) are listed beneath the answer

## Architecture

```
SilicIA/
├── Models/
│   ├── AppSettings.swift           # Settings: language, token limits, source toggles, result counts
│   ├── Conversation.swift          # SwiftData model for chat conversations
│   ├── Message.swift               # SwiftData model for individual messages with citations
│   └── SearchResult.swift          # Data model for web search results
├── Services/
│   ├── WebSearchService.swift      # DuckDuckGo + Wikipedia search orchestration
│   ├── WebScrapingService.swift    # Web page content extraction and HTML cleaning
│   ├── AIService.swift             # On-device LLM via Apple Foundation Models
│   ├── ChatService.swift           # RAG orchestration: search → chunk → rank → generate
│   ├── RAGContextService.swift     # Chunking, relevance scoring, context selection
│   ├── PromptLoader.swift          # Loads language-specific prompt templates from disk
│   ├── LocalizationService.swift   # JSON-based UI string resolution (EN/FR/ES)
│   ├── DroppedPDFStore.swift       # Manages PDF drag-and-drop state across views
│   ├── TokenBudgeting.swift        # Context window budget calculations
│   └── Sanitizer.swift             # Text and LaTeX sanitization helpers
├── Views/
│   ├── SearchView.swift            # Search interface: query bar, results, AI summary
│   ├── ChatView.swift              # Conversational interface with PDF/URL context support
│   └── ConversationsListView.swift # Chat history browser with load/delete
├── Resources/
│   └── Localization/               # JSON string tables: common, searchView, chatView, …
├── prompts/                        # Language-specific prompt templates (.en/.fr/.es .txt)
├── ContentView.swift               # Root tab container (Search / Chat)
├── SilicIAApp.swift                # App entry point and SwiftData container setup
├── SilicIA.entitlements            # macOS sandbox and capability permissions
└── SilicIA-iOS.entitlements        # iOS entitlements (includes com.apple.security.web)
```

### Data Flow

```
User Query
    ↓
WebSearchService  ──────────────────────────────┐
  ├── DuckDuckGo (privacy search, toggleable)   │
  └── Wikipedia  (encyclopedic, toggleable)     │
    ↓                                           │
WebScrapingService (extract full page text)     │  ← skipped in offline mode
    ↓                                           │
RAGContextService                               │
  ├── RAGChunker (split into overlapping chunks)│
  └── relevance scoring (cosine similarity TF) ─┘
    ↓
AIService (Apple Foundation Models — on-device)
    ↓
Streamed answer with citations
```

## Technical Details

### Frameworks & Technologies

- **SwiftUI** — Declarative UI for macOS and iOS
- **FoundationModels** — Apple Intelligence on-device LLM (requires Apple Silicon)
- **SwiftData** — Local persistence for chat history and conversations
- **PDFKit** — PDF loading, page rendering, and text extraction
- **Foundation / URLSession** — Networking with caching and timeout configuration
- **NaturalLanguage** — Tokenization for relevance scoring (not the primary LLM)
- **LaTeXSwiftUI** — Renders LaTeX expressions in AI answers

### Search Sources

| Source | API | Privacy | Default results |
|--------|-----|---------|-----------------|
| DuckDuckGo | Instant Answer API | No tracking | 6 (1–20) |
| Wikipedia | Wikipedia REST API | No tracking | 2 (1–20) |

Both sources are independently toggleable in Settings. When both are off, queries go directly to the on-device model with no network requests (**offline chat mode**).

### PDF Analysis

- Drag a PDF onto the chat panel or use the file picker
- The PDF is parsed page-by-page using PDFKit
- Text is chunked with configurable size and overlap
- Chunks are ranked by cosine similarity at query time
- Answers include **page-number citations** that link back to the source page

### RAG Pipeline

1. **Chunking** (`RAGChunker`) — Splits scraped text into overlapping windows to preserve sentence context
2. **Scoring** (`RAGContextService`) — Scores each chunk by cosine TF similarity against the query (or a set of derived queries for deep search)
3. **Budget** (`TokenBudgeting`) — Calculates the maximum context characters that fit the model's context window
4. **Selection** — Picks the highest-scoring chunks within budget; falls back to the top chunk if nothing fits
5. **Prompt injection** — Selected context is inserted into the appropriate prompt template before generation

### Chat History

Conversations are stored locally with **SwiftData**:

- **Conversation** — Metadata (title, dates) with cascade-delete over its messages
- **Message** — Role, content, citations, timestamp
- **Auto-titles** — Generated from the first user message (50-character truncation)
- **History view** — Browse, reload, and delete past conversations

### Multi-language Support

The UI language is controlled by the in-app **ModelLanguage** setting (independent of OS locale). Supported languages: **English**, **French**, **Spanish**.

The same setting drives the language of AI prompts, so summaries and answers are generated in your chosen language.

**Adding a new language** is a three-step process:
1. Add a `case` to `ModelLanguage` in `AppSettings.swift` with a `code` mapping (e.g. `"de"`)
2. Add `*.de.json` string files under `SilicIA/Resources/Localization/`
3. Add `prompt.*.de.txt` prompt templates under `SilicIA/prompts/`

The `LocalizationTests` target verifies that every English key exists in all other languages at build time.

### Privacy & Security

- All AI inference runs **on-device** via Apple's Foundation Models — no query or answer is sent to any cloud AI
- Web searches use **DuckDuckGo** (no user tracking) and **Wikipedia** (open API)
- No analytics, no crash reporting, no data collection
- Chat history is stored **locally only** — never synced or uploaded
- Scraping happens client-side; only the URLs you explicitly search are contacted

## Requirements

- **macOS 26** or later on any Apple Silicon Mac
- **iOS 26** or later on iPhone 15 Pro / iPhone 15 Pro Max or newer, or any iPad with an M-series chip
- Apple Intelligence must be enabled in System Settings / Settings
- Internet connection for web searches (not required in offline chat mode)

## Building

1. **Clone the repository**
   ```bash
   git clone https://github.com/eddybarraud/SilicIA.git
   cd SilicIA
   ```

2. **Open in Xcode**
   ```bash
   open SilicIA.xcodeproj
   ```

3. **Configure signing**
   - Select the **SilicIA** target → **Signing & Capabilities**
   - Enable **Automatically manage signing** and select your Apple Developer Team

4. **Build and run** — `⌘R` in Xcode, or:
   ```bash
   ./scripts/build.sh Debug
   ```

## Usage Tips

- **Search Assist** tab — type any question; results appear with an AI summary above the source links
- **Chat** tab — conversational interface; attach a PDF or URL with the paperclip button for context-aware answers
- Toggle sources in Settings to switch between web-grounded and fully offline responses
- Click any citation in a chat answer to jump to the source URL or PDF page
- All previous conversations are accessible from the History panel in the Chat tab

## License

This project is licensed under the **SilicIA Non-Commercial License v1.0**.

**Non-Commercial Use Only**: Personal projects, academic research, evaluation, and non-profit use are permitted at no charge.

**For Commercial Use**: Contact the licensor to obtain a commercial license.

See [LICENSE](LICENSE) for full terms and conditions.

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on setting up the development environment, coding conventions, and submitting pull requests.

```bash
git clone https://github.com/eddybarraud/SilicIA.git
./scripts/build.sh Debug
```

## Credits

- Created by Eddy Barraud
- Uses [LaTeXSwiftUI](https://github.com/colinc86/LaTeXSwiftUI)
- Chat history implementation inspired by [FoundationChat](https://github.com/Dimillian/FoundationChat)
