//
//  BenchmarkSearchPipeline.swift
//  Benchmarks Foundation Model timings, TTFT vs prompt length, streaming efficiency,
//  and verifies answer quality across queries.
//

import Foundation
import FoundationModels

print("══════════════════════════════════════════════════════════════════════")
print("🚀 BENCHMARK: Foundation Model Timings, TTFT Scaling & Answer Quality")
print("══════════════════════════════════════════════════════════════════════")

let systemModel = SystemLanguageModel.default
print("Device Foundation Model Status: \(systemModel.availability)")

// PART 1: Session Prewarm vs Cold Session TTFT
print("\n──────────────────────────────────────────────────────────────────────")
print("📊 1. TIMING INVESTIGATION: Cold Session vs Prewarmed Session")
print("──────────────────────────────────────────────────────────────────────")

let promptCold = "Give a concise 1-sentence definition of Euclidean distance."
let sessionCold = LanguageModelSession()
let tColdStart = Date()
var ttftCold: Double? = nil
for try await _ in sessionCold.streamResponse(to: promptCold) {
    if ttftCold == nil {
        ttftCold = Date().timeIntervalSince(tColdStart)
    }
}
let totalCold = Date().timeIntervalSince(tColdStart)
print(String(format: "❄️  Cold Session:      TTFT = %.3f s | Total = %.3f s", ttftCold ?? 0, totalCold))

let sessionWarm = LanguageModelSession()
sessionWarm.prewarm()
// Give the background prewarm a moment to settle
try await Task.sleep(nanoseconds: 100_000_000)

let tWarmStart = Date()
var ttftWarm: Double? = nil
for try await _ in sessionWarm.streamResponse(to: promptCold) {
    if ttftWarm == nil {
        ttftWarm = Date().timeIntervalSince(tWarmStart)
    }
}
let totalWarm = Date().timeIntervalSince(tWarmStart)
print(String(format: "🔥 Prewarmed Session:  TTFT = %.3f s | Total = %.3f s", ttftWarm ?? 0, totalWarm))
let prewarmDiff = (ttftCold ?? 0) - (ttftWarm ?? 0)
print(String(format: "⚡ Prewarming advantage: %.3f s faster TTFT (%.1f%% improvement)", max(0, prewarmDiff), max(0, prewarmDiff) / max(0.001, ttftCold ?? 1) * 100))

// PART 2: Prompt Length (Chunk Capping) vs Time to First Token (TTFT)
print("\n──────────────────────────────────────────────────────────────────────")
print("📊 2. TIMING INVESTIGATION: TTFT Scaling vs RAG Context / Prompt Size")
print("──────────────────────────────────────────────────────────────────────")

let wikiSampleChunk = """
Source: Euclidean distance (Wikipedia)
In mathematics, the Euclidean distance between two points in Euclidean space is the length of a line segment between the two points. It can be calculated from the Cartesian coordinates of the points using the Pythagorean theorem, therefore occasionally being called the Pythagorean distance. These names come from the ancient Greek mathematicians Euclid and Pythagoras, although Euclid did not represent distances as numbers.
"""

let configurations: [(chunks: Int, label: String, profile: String)] = [
    (1, "1 chunk  (~450 chars)",  "Minimal single-fact"),
    (3, "3 chunks (~1350 chars)", "Concise profile (NEW capped limit)"),
    (4, "4 chunks (~1800 chars)", "Standard profile (NEW capped limit)"),
    (6, "6 chunks (~2700 chars)", "Detailed profile (NEW capped limit)"),
    (12, "12 chunks (~5400 chars)", "Uncapped prior baseline (context over-stuffing)")
]

for config in configurations {
    var contextText = ""
    for i in 1...config.chunks {
        contextText += "[\(i)] " + wikiSampleChunk + "\n\n"
    }
    let queryPrompt = """
    Instructions:
    Answer concisely based on the reference context.

    Sujet ou question : distance euclidienne

    Contexte web de référence (support factuel) :
    \(contextText)
    Sujet ou question : distance euclidienne
    """

    let tStart = Date()
    var firstTokenSec: Double? = nil
    var snapshots = 0
    var fullOutput = ""

    for try await snapshot in sessionWarm.streamResponse(to: queryPrompt) {
        if firstTokenSec == nil {
            firstTokenSec = Date().timeIntervalSince(tStart)
        }
        snapshots += 1
        fullOutput = snapshot.content
    }
    let elapsed = Date().timeIntervalSince(tStart)
    print(String(format: "• %-18@ [prompt: %5d chars] -> TTFT: %.3f s | Total: %.3f s | %2d chunks | Profile: %@",
                 config.label, queryPrompt.count, firstTokenSec ?? 0, elapsed, config.chunks, config.profile))
}

// PART 3: Quality Comparison on Concrete Queries
print("\n──────────────────────────────────────────────────────────────────────")
print("📊 3. QUALITY COMPARISON: Query Results Before & After Optimization")
print("──────────────────────────────────────────────────────────────────────")

let qualityQueries = [
    (
        query: "distance euclidienne",
        context: """
        Source: Distance euclidienne (Wikipédia)
        En mathématiques, la distance euclidienne est la distance classique entre deux points dans l'espace euclidien. Elle s'obtient à l'aide du théorème de Pythagore à partir des coordonnées cartésiennes des points. Pour deux points p = (p1, ..., pn) et q = (q1, ..., qn), la formule est d(p, q) = sqrt(sum((pi - qi)^2)).
        """,
        check: "Pythagore"
    ),
    (
        query: "Who proposed the theory of general relativity?",
        context: """
        Source: General relativity (Wikipedia)
        General relativity is the geometric theory of gravitation published by Albert Einstein in 1915 and is the current description of gravitation in modern physics. It generalizes special relativity and refines Newton's law of universal gravitation.
        """,
        check: "Einstein"
    ),
    (
        query: "Quelle est la capitale de l'Australie ?",
        context: """
        Source: Canberra (Wikipédia)
        Canberra est la capitale de l'Australie. Avec 456 652 habitants, c'est la huitième ville la plus peuplée du pays. Contrairement à une idée répandue, ni Sydney ni Melbourne n'est la capitale de l'Australie.
        """,
        check: "Canberra"
    )
]

for item in qualityQueries {
    print("\n❓ Query: \"\(item.query)\"")
    let prompt = """
    Instructions:
    Donne une réponse claire, directe et concise basée sur le contexte.

    Sujet ou question : \(item.query)

    Contexte web de référence :
    \(item.context)

    Sujet ou question : \(item.query)
    """

    let qStart = Date()
    var qTTFT: Double? = nil
    var qText = ""
    for try await snapshot in sessionWarm.streamResponse(to: prompt) {
        if qTTFT == nil {
            qTTFT = Date().timeIntervalSince(qStart)
        }
        qText = snapshot.content
    }
    let qTotal = Date().timeIntervalSince(qStart)
    let cleaned = qText.trimmingCharacters(in: .whitespacesAndNewlines)
    let hasFact = cleaned.localizedCaseInsensitiveContains(item.check)
    print(String(format: "   ⏱️  TTFT: %.3f s | Total: %.3f s | Contains factual key ('%@'): %@", qTTFT ?? 0, qTotal, item.check, hasFact ? "✅ YES" : "❌ NO"))
    print("   📝 Answer: \"\(cleaned.replacingOccurrences(of: "\n", with: " "))\"")
}

print("\n══════════════════════════════════════════════════════════════════════")
print("✅ Benchmark completed successfully!")
print("══════════════════════════════════════════════════════════════════════")
