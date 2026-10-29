# App Configuration & Token Budgets

> 13 nodes · cohesion 0.18

## Key Concepts

- **AppSettings** (28 connections) — `SilicIA/Models/AppSettings.swift`
- **.setTotalTokensBudget()** (4 connections) — `SilicIA/Models/AppSettings.swift`
- **.init()** (3 connections) — `SilicIA/Models/AppSettings.swift`
- **.maxAllowedContextTokens()** (3 connections) — `SilicIA/Models/AppSettings.swift`
- **Int** (3 connections)
- **.body** (3 connections) — `SilicIA/Views/TokenBudgetSliderView.swift`
- **.maxAllowedContextTokensForCurrentResponse** (2 connections) — `SilicIA/Views/SearchView.swift`
- **Decoder** (1 connections)
- **.isWebSummariesEnabled** (1 connections) — `SilicIA/Models/AppSettings.swift`
- **.maxSearchResults** (1 connections) — `SilicIA/Models/AppSettings.swift`
- **.totalTokensBudget** (1 connections) — `SilicIA/Models/AppSettings.swift`
- **Bool** (1 connections)
- **Double** (1 connections)

## Relationships

- [On-Device LLM & Privacy Policy](On-Device_LLM_&_Privacy_Policy.md) (5 shared connections)
- [AppSettings Store Persistence](AppSettings_Store_Persistence.md) (4 shared connections)
- [Search Assist View & Grounding](Search_Assist_View_&_Grounding.md) (2 shared connections)
- [Token Budget Slider Controls](Token_Budget_Slider_Controls.md) (2 shared connections)
- [Dual Web Search & Tests](Dual_Web_Search_&_Tests.md) (1 shared connections)
- [Chat Interface & Streaming](Chat_Interface_&_Streaming.md) (1 shared connections)
- [AppSettings Store Unit Tests](AppSettings_Store_Unit_Tests.md) (1 shared connections)
- [System Framework Integrations](System_Framework_Integrations.md) (1 shared connections)
- [Settings Serialization & Coding Keys](Settings_Serialization_&_Coding_Keys.md) (1 shared connections)
- [Legacy Settings Migration Keys](Legacy_Settings_Migration_Keys.md) (1 shared connections)
- [System Prompt Template Loader](System_Prompt_Template_Loader.md) (1 shared connections)
- [AppSettings JSON Encoding](AppSettings_JSON_Encoding.md) (1 shared connections)

## Source Files

- `SilicIA/Models/AppSettings.swift`
- `SilicIA/Views/SearchView.swift`
- `SilicIA/Views/TokenBudgetSliderView.swift`

## Audit Trail

- EXTRACTED: 33 (89%)
- INFERRED: 4 (11%)
- AMBIGUOUS: 0 (0%)

---

*Part of the graphify knowledge wiki. See [index](index.md) to navigate.*