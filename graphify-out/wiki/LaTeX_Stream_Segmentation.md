# LaTeX Stream Segmentation

> 34 nodes · cohesion 0.12

## Key Concepts

- **ModelOutputLaTeXSanitizer** (13 connections) — `SilicIA/Services/Sanitizer.swift`
- **String** (11 connections)
- **.sanitizeLaTeXDocumentWrappers()** (10 connections) — `SilicIA/Services/Sanitizer.swift`
- **.finalizeSanitizedText()** (9 connections) — `SilicIA/Services/Sanitizer.swift`
- **.escapeCurrencyDollars()** (8 connections) — `SilicIA/Services/Sanitizer.swift`
- **SanitizerTests** (8 connections) — `SilicIATests/SanitizerTests.swift`
- **.safeBoundaries()** (6 connections) — `SilicIA/Services/LaTeXStreamSegmenter.swift`
- **LaTeXStreamSegmenterTests** (6 connections) — `SilicIATests/LaTeXStreamSegmenterTests.swift`
- **.replacingRegex()** (5 connections) — `SilicIA/Services/Sanitizer.swift`
- **.unwrapProseArrayEnvironments()** (5 connections) — `SilicIA/Services/Sanitizer.swift`
- **.paragraphBlocks()** (4 connections) — `SilicIA/Services/LaTeXStreamSegmenter.swift`
- **.applyRegex()** (4 connections) — `SilicIA/Services/Sanitizer.swift`
- **.insertBoundarySpacesForKnownCommands()** (4 connections) — `SilicIA/Services/Sanitizer.swift`
- **.replacingDigitPowers()** (4 connections) — `SilicIA/Services/Sanitizer.swift`
- **.replacingMarkdownTitles()** (4 connections) — `SilicIA/Services/Sanitizer.swift`
- **LaTeXStreamSegmenter** (3 connections) — `SilicIA/Services/LaTeXStreamSegmenter.swift`
- **.replacingDigitPowerMatches()** (3 connections) — `SilicIA/Services/Sanitizer.swift`
- **.unwrapTextCommands()** (3 connections) — `SilicIA/Services/Sanitizer.swift`
- **NSRegularExpression** (3 connections)
- **.body** (3 connections) — `SilicIA/Views/StreamingLaTeXText.swift`
- **.testCurrencyAndMathCoexistenceAndFullPipeline()** (3 connections) — `SilicIATests/SanitizerTests.swift`
- **LaTeXStreamSegmenter.swift** (2 connections) — `SilicIA/Services/LaTeXStreamSegmenter.swift`
- **String** (2 connections)
- **Sanitizer.swift** (2 connections) — `SilicIA/Services/Sanitizer.swift`
- **.testCurrencyDollarIsNotMath()** (2 connections) — `SilicIATests/LaTeXStreamSegmenterTests.swift`
- *... and 9 more nodes in this community*

## Relationships

- [SwiftData Conversation Persistence](SwiftData_Conversation_Persistence.md) (3 shared connections)
- [System Framework Integrations](System_Framework_Integrations.md) (2 shared connections)
- [On-Device LLM & Privacy Policy](On-Device_LLM_&_Privacy_Policy.md) (2 shared connections)
- [App Settings & Tool Test Fixtures](App_Settings_&_Tool_Test_Fixtures.md) (2 shared connections)
- [Model Loading & Inference Engine](Model_Loading_&_Inference_Engine.md) (2 shared connections)
- [Streaming LaTeX Math Display](Streaming_LaTeX_Math_Display.md) (1 shared connections)

## Source Files

- `SilicIA/Services/LaTeXStreamSegmenter.swift`
- `SilicIA/Services/Sanitizer.swift`
- `SilicIA/Views/StreamingLaTeXText.swift`
- `SilicIATests/LaTeXStreamSegmenterTests.swift`
- `SilicIATests/SanitizerTests.swift`

## Audit Trail

- EXTRACTED: 78 (100%)
- INFERRED: 0 (0%)
- AMBIGUOUS: 0 (0%)

---

*Part of the graphify knowledge wiki. See [index](index.md) to navigate.*