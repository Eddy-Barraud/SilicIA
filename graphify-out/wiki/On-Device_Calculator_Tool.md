# On-Device Calculator Tool

> 24 nodes · cohesion 0.17

## Key Concepts

- **CalculatorTool** (21 connections) — `SilicIA/Services/Tools/CalculatorTool.swift`
- **.call()** (16 connections) — `SilicIA/Services/Tools/CalculatorTool.swift`
- **CalculatorToolTests** (10 connections) — `SilicIATests/CalculatorToolTests.swift`
- **String** (8 connections)
- **.testGovernorIntegration()** (5 connections) — `SilicIATests/CalculatorToolTests.swift`
- **.evaluate()** (4 connections) — `SilicIA/Services/Tools/CalculatorTool.swift`
- **.format()** (4 connections) — `SilicIA/Services/Tools/CalculatorTool.swift`
- **.registerCallAndCheckLoop()** (4 connections) — `SilicIA/Services/Tools/CalculatorTool.swift`
- **Arguments** (3 connections) — `SilicIA/Services/Tools/CalculatorTool.swift`
- **.expandFactorials()** (3 connections) — `SilicIA/Services/Tools/CalculatorTool.swift`
- **.promoteIntegersToDoubles()** (3 connections) — `SilicIA/Services/Tools/CalculatorTool.swift`
- **.resetLoopGuardForTesting()** (3 connections) — `SilicIA/Services/Tools/CalculatorTool.swift`
- **.testLoopGuard()** (3 connections) — `SilicIATests/CalculatorToolTests.swift`
- **Double** (2 connections)
- **Int** (2 connections)
- **.setUp()** (2 connections) — `SilicIATests/CalculatorToolTests.swift`
- **.testBasicArithmetic()** (2 connections) — `SilicIATests/CalculatorToolTests.swift`
- **.testDecimalAndCommaFormatting()** (2 connections) — `SilicIATests/CalculatorToolTests.swift`
- **.testFactorialEvaluationAndPrecisionCap()** (2 connections) — `SilicIATests/CalculatorToolTests.swift`
- **.testRejectsInvalidSyntax()** (2 connections) — `SilicIATests/CalculatorToolTests.swift`
- **CharacterSet** (1 connections)
- **Date** (1 connections)
- **NSRegularExpression** (1 connections)
- **TimeInterval** (1 connections)

## Relationships

- [Tool Calling Governor & Rate Limiting](Tool_Calling_Governor_&_Rate_Limiting.md) (3 shared connections)
- [Tool Call Transcript Recorder](Tool_Call_Transcript_Recorder.md) (3 shared connections)
- [System Framework Integrations](System_Framework_Integrations.md) (1 shared connections)
- [Multi-Query Search Sources Tool](Multi-Query_Search_Sources_Tool.md) (1 shared connections)
- [Tool Budgeting & Execution Assembly](Tool_Budgeting_&_Execution_Assembly.md) (1 shared connections)
- [App Settings & Tool Test Fixtures](App_Settings_&_Tool_Test_Fixtures.md) (1 shared connections)
- [Model Loading & Inference Engine](Model_Loading_&_Inference_Engine.md) (1 shared connections)

## Source Files

- `SilicIA/Services/Tools/CalculatorTool.swift`
- `SilicIATests/CalculatorToolTests.swift`

## Audit Trail

- EXTRACTED: 46 (79%)
- INFERRED: 12 (21%)
- AMBIGUOUS: 0 (0%)

---

*Part of the graphify knowledge wiki. See [index](index.md) to navigate.*