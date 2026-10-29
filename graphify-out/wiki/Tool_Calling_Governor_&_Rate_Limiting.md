# Tool Calling Governor & Rate Limiting

> 24 nodes · cohesion 0.14

## Key Concepts

- **ToolCallGovernor** (18 connections) — `SilicIA/Services/Tools/ToolCallGovernor.swift`
- **ToolError** (13 connections) — `SilicIA/Services/Tools/ToolCallGovernor.swift`
- **Decision** (12 connections) — `SilicIA/Services/Tools/ToolCallGovernor.swift`
- **.evaluate()** (10 connections) — `SilicIA/Services/Tools/ToolCallGovernor.swift`
- **String** (6 connections)
- **ToolCallGovernorTests** (5 connections) — `SilicIATests/ToolCallGovernorTests.swift`
- **Int** (4 connections)
- **ToolCallGovernor.swift** (3 connections) — `SilicIA/Services/Tools/ToolCallGovernor.swift`
- **.init()** (3 connections) — `SilicIA/Services/Tools/ToolCallGovernor.swift`
- **.normalize()** (3 connections) — `SilicIA/Services/Tools/ToolCallGovernor.swift`
- **.testAllowanceAndDuplicateRefusal()** (3 connections) — `SilicIATests/ToolCallGovernorTests.swift`
- **.testToolBudgetCaps()** (3 connections) — `SilicIATests/ToolCallGovernorTests.swift`
- **.testTotalBudgetCeilingStopsCallsAndRepeatedDuplicates()** (3 connections) — `SilicIATests/ToolCallGovernorTests.swift`
- **CustomStringConvertible** (1 connections)
- **allow** (1 connections) — `SilicIA/Services/Tools/ToolCallGovernor.swift`
- **.description** (1 connections) — `SilicIA/Services/Tools/ToolCallGovernor.swift`
- **duplicate** (1 connections) — `SilicIA/Services/Tools/ToolCallGovernor.swift`
- **.refusalMessage** (1 connections) — `SilicIA/Services/Tools/ToolCallGovernor.swift`
- **toolBudgetReached** (1 connections) — `SilicIA/Services/Tools/ToolCallGovernor.swift`
- **totalBudgetReached** (1 connections) — `SilicIA/Services/Tools/ToolCallGovernor.swift`
- **duplicate** (1 connections) — `SilicIA/Services/Tools/ToolCallGovernor.swift`
- **.errorDescription** (1 connections) — `SilicIA/Services/Tools/ToolCallGovernor.swift`
- **toolBudgetReached** (1 connections) — `SilicIA/Services/Tools/ToolCallGovernor.swift`
- **totalBudgetReached** (1 connections) — `SilicIA/Services/Tools/ToolCallGovernor.swift`

## Relationships

- [Model Loading & Inference Engine](Model_Loading_&_Inference_Engine.md) (6 shared connections)
- [On-Device Calculator Tool](On-Device_Calculator_Tool.md) (3 shared connections)
- [System Date & Time Tool](System_Date_&_Time_Tool.md) (3 shared connections)
- [Multi-Query Search Sources Tool](Multi-Query_Search_Sources_Tool.md) (3 shared connections)
- [Web Content Scraping & Errors](Web_Content_Scraping_&_Errors.md) (2 shared connections)
- [System Framework Integrations](System_Framework_Integrations.md) (1 shared connections)
- [System Prompt Template Loader](System_Prompt_Template_Loader.md) (1 shared connections)
- [Tool Budgeting & Execution Assembly](Tool_Budgeting_&_Execution_Assembly.md) (1 shared connections)
- [App Settings & Tool Test Fixtures](App_Settings_&_Tool_Test_Fixtures.md) (1 shared connections)

## Source Files

- `SilicIA/Services/Tools/ToolCallGovernor.swift`
- `SilicIATests/ToolCallGovernorTests.swift`

## Audit Trail

- EXTRACTED: 46 (78%)
- INFERRED: 13 (22%)
- AMBIGUOUS: 0 (0%)

---

*Part of the graphify knowledge wiki. See [index](index.md) to navigate.*