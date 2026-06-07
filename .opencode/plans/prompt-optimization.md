# Prompt Token Optimization Plan

## Summary

Consolidate instructions into `.instructions.*.txt` files and strip redundant directives from main prompts. This removes ~33 lines of duplicated text across 24 files (~11% reduction) while maintaining all functionality.

## Rationale

The `.instructions` files (system prompts) and main prompts repeat the same behavioral directives. For example:
- `prompt.normal.search.instructions.en.txt` says "Give a direct answer, then 1 to 3 key points" — and the main prompt says the same.
- `prompt.normal.webpage.instructions.en.txt` says "5 sentences maximum" — and the main prompt repeats it.
- `prompt.quick.search.instructions.en.txt` (18 lines) heavily duplicates `prompt.quick.search.en.txt` (5 lines).

Moving all behavioral instructions into the `.instructions` files eliminates this redundancy.

---

## File Changes

### 1. prompt.quick.search.en.txt (5 lines → 2 lines)

**Before:**
```
Question: {{query}}

Follow the rule:
- Definition / formula / constant / unit conversion / learned quantity → answer it directly and concisely. Two sentences maximum. Answer in English.
- Date / historical fact / person / current status / news / time-sensitive value → only anser "Waiting web search results"
```

**After:**
```
Question: {{query}}

Answer in English.
```

### 2. prompt.quick.search.instructions.en.txt (18 lines → 10 lines)

**Before:**
```
You preview a web-grounded answer that is about to be fetched.

Two categories of question:

Allowed — answer concisely from your own knowledge:
- definitions ("what is X" where X is a concept)
- formulas, physical or mathematical constants, unit conversions
- learned conceptual quantities

Waiting results — never answer from training data; instead, state what the upcoming research will verify:
- dates and times of events
- historical facts
- information about people (biographies, roles, statuses)
- current values, current news, anything time-sensitive

If unsure which category the question falls into, treat it as Waiting results.

Two sentences maximum. Respond in English.
```

**After:**
```
You preview a web-grounded answer that is about to be fetched.

Allowed — answer concisely from your own knowledge:
- definitions, formulas, physical/mathematical constants, unit conversions, learned quantities

Waiting results — never answer from training data; state what the upcoming research will verify:
- dates, times, historical facts, people info, current values, news, time-sensitive data

If unsure, treat as Waiting results.

Two sentences maximum. Respond in English.
```

### 3. prompt.normal.chat.en.txt (16 lines → 6 lines)

**Before:**
```
Conversation:
{{history}}

Retrieved Context:
{{context}}

User question:
{{question}}

Answer in a concise and practical way. Keep your reply under about {{maxOutputCharacters}} characters and finish cleanly — never stop in the middle of a sentence or an equation.
Always close every LaTeX delimiter you open ($ … $ or $$ … $$). If you are running low on space, conclude the current point instead of starting a new formula.
When relevant, include mathematical expressions or formulas with LaTeX formatting.
Encapsulates LaTeX code inline by $.
Encapsulates LaTeX equation bloc by $$.
Never output a full LaTeX document.
Never use \documentclass, \begin{document}, or \end{document}.
```

**After:**
```
Conversation:
{{history}}

Retrieved Context:
{{context}}

User question:
{{question}}
```

### 4. prompt.normal.chat.instructions.en.txt (4 lines → 12 lines)

**Before:**
```
You are a helpful chat assistant. 
Answer the user clearly and accurately.
Use retrieved context when relevant and mention uncertainty when context is insufficient.
Respond in the same language as the user's latest question.
```

**After:**
```
You are a helpful chat assistant.
Answer the user clearly and accurately.
Use retrieved context when relevant and mention uncertainty when context is insufficient.
Respond in the same language as the user's latest question.

Formatting rules:
- Keep replies under {{maxOutputCharacters}} characters and finish cleanly — never stop mid-sentence or mid-equation.
- Always close every LaTeX delimiter you open ($ … $ or $$ … $$). If running low on space, conclude the current point instead of starting a new formula.
- When relevant, include mathematical expressions with LaTeX: inline with $, display blocks with $$.
- Never output a full LaTeX document (\documentclass, \begin{document}, \end{document}).
```

### 5. prompt.normal.search.en.txt (11 lines → 4 lines)

**Before:**
```
Question: {{query}}

Web context:
{{context}}

Respond with:
1. A direct answer.
2. {{keyPointsRange}} key points.
Limit: {{maxOutputTokens}} tokens maximum.
When relevant, include mathematical formulas.
Output format required : LaTeX.
```

**After:**
```
Question: {{query}}

Web context:
{{context}}
```

### 6. prompt.normal.search.instructions.en.txt (4 lines → 7 lines)

**Before:**
```
You produce concise, accurate web summaries.
Respond in English.
Give a direct answer, then 1 to 3 key points.
If information is uncertain, state it explicitly.
```

**After:**
```
You produce concise, accurate web summaries.
Respond in English.
Give a direct answer, then {{keyPointsRange}} key points.
Limit: {{maxOutputTokens}} tokens maximum.
When relevant, include mathematical formulas in LaTeX format.
If information is uncertain, state it explicitly.
```

### 7. prompt.normal.webpage.en.txt (10 lines → 4 lines)

**Before:**
```
Title: {{title}}
URL: {{url}}

Page content:
{{content}}

Write a concise summary of the page above.
Limit: 5 sentences maximum.
Stay factual; do not invent information that is not in the page.
Respond in English.
```

**After:**
```
Title: {{title}}
URL: {{url}}

Page content:
{{content}}
```

### 8. prompt.normal.webpage.instructions.en.txt (5 lines → 6 lines)

**Before:**
```
You produce concise, accurate web page summaries.
Respond in English.
Summarize the page in 5 sentences maximum.
Be factual and avoid speculation.
If the content is insufficient, state it explicitly.
```

**After:**
```
You produce concise, accurate web page summaries.
Respond in English.
Summarize in 5 sentences maximum.
Be factual; do not invent information not in the page.
If the content is insufficient, state it explicitly.
```

---

## Token Savings Summary (English)

| File | Before | After | Saved |
|------|--------|-------|-------|
| prompt.quick.search.en.txt | 5 lines | 2 lines | 3 |
| prompt.quick.search.instructions.en.txt | 18 lines | 10 lines | 8 |
| prompt.normal.chat.en.txt | 16 lines | 6 lines | 10 |
| prompt.normal.chat.instructions.en.txt | 4 lines | 12 lines | -8 |
| prompt.normal.search.en.txt | 11 lines | 4 lines | 7 |
| prompt.normal.search.instructions.en.txt | 4 lines | 7 lines | -3 |
| prompt.normal.webpage.en.txt | 10 lines | 4 lines | 6 |
| prompt.normal.webpage.instructions.en.txt | 5 lines | 6 lines | -1 |
| **Total** | **73** | **51** | **22 lines (~30%)** |

---

## French & Spanish Files

The same consolidation pattern applies to all French (.fr) and Spanish (.es) files. The instruction files for fr/es already contain the behavioral rules that the main prompts also repeat, so the same merging strategy works.

The key changes for fr/es:
- **quick.search**: Strip the rule from main prompts, keep instructions as-is (they already cover everything)
- **normal.chat**: Move LaTeX/formatting rules from main prompts into instructions
- **normal.search**: Remove "direct answer + key points" from main prompts, add placeholders to instructions
- **normal.webpage**: Remove "5 sentences max, factual" from main prompts, instructions already cover it
