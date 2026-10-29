# AppSettings Store Persistence

> 7 nodes · cohesion 0.33

## Key Concepts

- **AppSettingsStore** (7 connections) — `SilicIA/Models/AppSettingsStore.swift`
- **.load()** (4 connections) — `SilicIA/Models/AppSettings.swift`
- **.save()** (4 connections) — `SilicIA/Models/AppSettings.swift`
- **.normalized()** (3 connections) — `SilicIA/Models/AppSettings.swift`
- **.init()** (2 connections) — `SilicIA/Models/AppSettingsStore.swift`
- **.settings** (2 connections) — `SilicIA/Models/AppSettingsStore.swift`
- **.testMutationsPersistAutomatically()** (2 connections) — `SilicIATests/AppSettingsStoreTests.swift`

## Relationships

- [App Configuration & Token Budgets](App_Configuration_&_Token_Budgets.md) (4 shared connections)
- [AppSettings JSON Encoding](AppSettings_JSON_Encoding.md) (1 shared connections)
- [Search Source Toggle Controls](Search_Source_Toggle_Controls.md) (1 shared connections)
- [App Settings & Tool Test Fixtures](App_Settings_&_Tool_Test_Fixtures.md) (1 shared connections)
- [AppSettings Store Unit Tests](AppSettings_Store_Unit_Tests.md) (1 shared connections)

## Source Files

- `SilicIA/Models/AppSettings.swift`
- `SilicIA/Models/AppSettingsStore.swift`
- `SilicIATests/AppSettingsStoreTests.swift`

## Audit Trail

- EXTRACTED: 15 (94%)
- INFERRED: 1 (6%)
- AMBIGUOUS: 0 (0%)

---

*Part of the graphify knowledge wiki. See [index](index.md) to navigate.*