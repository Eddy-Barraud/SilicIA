import Foundation
import SwiftSoup
import HTMLToMarkdown
import Reeeed

@main
struct BenchmarkRunner {
    static func main() async {
        print("==========================================================================================")
        print("  SilicIA Full Webpage HTML to Markdown Benchmark Suite                                  ")
        print("  Evaluating 5 Strategies:                                                               ")
        print("    1. SilicIA Baseline Regex                                                            ")
        print("    2. SwiftSoup Body Extraction + html-to-markdown-swift                                ")
        print("    3. Reeeed (Readability/Mercury JS Extractor) + html-to-markdown-swift                  ")
        print("    4. Raw html-to-markdown-swift (Full Document)                                        ")
        print("    5. SilicIA Web Vision (Headless WKWebView PDF Rasterization + Apple Vision OCR)      ")
        print("==========================================================================================")
        
        let basePath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // ReaderLMBenchmark
            .path
        
        let outputDir = URL(fileURLWithPath: basePath).appendingPathComponent("OutputMarkdown")
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        
        let samples: [BenchmarkSample]
        do {
            samples = try CorpusLoader.loadFullWebpageSamples(basePath: basePath)
        } catch {
            print("Failed to load corpus samples: \(error)")
            return
        }
        
        print("Discovered \(samples.count) full-page sample documents.")
        print("Output directory: \(outputDir.path)\n")
        
        // Warm up Reeeed JS runtime
        Reeeed.warmup(extractor: .readability)
        Reeeed.warmup(extractor: .mercury)
        
        struct BenchmarkMetrics {
            let name: String
            let rawBytes: Int
            
            // 1. SilicIA Regex
            let regexTimeMs: Double
            let regexChars: Int
            
            // 2. SwiftSoup Body Extraction + html2md
            let soupExtractMs: Double
            let soupConvertMs: Double
            let soupTotalMs: Double
            let soupMarkdownChars: Int
            
            // 3. Reeeed Article Extraction + html2md
            let reeeedExtractMs: Double
            let reeeedConvertMs: Double
            let reeeedTotalMs: Double
            let reeeedMarkdownChars: Int
            
            // 4. Raw html-to-markdown-swift
            let rawH2mMs: Double
            let rawH2mChars: Int
            
            // 5. SilicIA Web Vision
            let webVisionPdfMs: Double
            let webVisionOcrMs: Double
            let webVisionTotalMs: Double
            let webVisionPages: Int
            let webVisionChars: Int
        }
        
        var results: [BenchmarkMetrics] = []
        
        for (index, sample) in samples.enumerated() {
            let safeDocName = sample.name
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: "_")
                .lowercased()
            
            guard let sampleURL = URL(string: sample.sourceURL) else { continue }
            
            print("------------------------------------------------------------------------------------------")
            print("[\(index + 1)/\(samples.count)] Evaluating Document: [\(sample.name)]")
            print("Raw HTML Size: \(sample.byteSize) bytes (\(String(format: "%.1f", Double(sample.byteSize) / 1024.0)) KB)")
            
            // --- Method 1: SilicIA Regex Baseline ---
            let regexStart = CFAbsoluteTimeGetCurrent()
            let regexMarkdown = RegexBaselineScraper.extractMarkdown(from: sample.rawHTML, maxCharacters: 100_000)
            let regexTimeMs = (CFAbsoluteTimeGetCurrent() - regexStart) * 1000.0
            print("  1. [SilicIA Regex]             Time: \(String(format: "%7.2f", regexTimeMs)) ms | Length: \(regexMarkdown.count) chars")
            let regexOutputFile = outputDir.appendingPathComponent("\(safeDocName)_regex.md")
            try? regexMarkdown.write(to: regexOutputFile, atomically: true, encoding: .utf8)
            
            // --- Method 2: SwiftSoup Body Extraction + html-to-markdown-swift ---
            let soupStart = CFAbsoluteTimeGetCurrent()
            var bodyHTML = ""
            var soupMarkdown = ""
            var soupExtractMs = 0.0
            var soupConvertMs = 0.0
            do {
                bodyHTML = try SwiftSoupExtractor.extractBodyHTML(sample.rawHTML, cleanNonContent: true)
                soupExtractMs = (CFAbsoluteTimeGetCurrent() - soupStart) * 1000.0
                
                let convStart = CFAbsoluteTimeGetCurrent()
                soupMarkdown = try HTMLToMarkdown.convert(bodyHTML, plugins: [
                    BasePlugin(),
                    CommonmarkPlugin(),
                    GFMPlugin()
                ])
                soupConvertMs = (CFAbsoluteTimeGetCurrent() - convStart) * 1000.0
                let soupTotalMs = soupExtractMs + soupConvertMs
                print("  2. [SwiftSoup + html2md]       Time: \(String(format: "%7.2f", soupTotalMs)) ms (Extract: \(String(format: "%.1f", soupExtractMs))ms, Convert: \(String(format: "%.1f", soupConvertMs))ms) | Length: \(soupMarkdown.count) chars")
            } catch {
                print("  2. [SwiftSoup + html2md]       Failed: \(error)")
            }
            let soupOutputFile = outputDir.appendingPathComponent("\(safeDocName)_swiftsoup_html2md.md")
            try? soupMarkdown.write(to: soupOutputFile, atomically: true, encoding: .utf8)
            
            // Direct SwiftSoup text
            if let soupText = try? SwiftSoupExtractor.extractBodyText(sample.rawHTML) {
                let soupTextFile = outputDir.appendingPathComponent("\(safeDocName)_swiftsoup_text.md")
                try? soupText.write(to: soupTextFile, atomically: true, encoding: .utf8)
            }
            
            // --- Method 3: Reeeed Article Extraction + html-to-markdown-swift ---
            var reeeedRes: ReeeedExtractor.ExtractionResult? = nil
            do {
                // Try readability extractor first; fallback to mercury
                do {
                    reeeedRes = try await ReeeedExtractor.extractAndConvert(
                        html: sample.rawHTML,
                        url: sampleURL,
                        extractor: .readability
                    )
                } catch {
                    reeeedRes = try await ReeeedExtractor.extractAndConvert(
                        html: sample.rawHTML,
                        url: sampleURL,
                        extractor: .mercury
                    )
                }
                if let r = reeeedRes {
                    print("  3. [Reeeed + html2md]          Time: \(String(format: "%7.2f", r.totalMs)) ms (Extract: \(String(format: "%.1f", r.extractMs))ms, Convert: \(String(format: "%.1f", r.markdownConvertMs))ms) | Length: \(r.markdown.count) chars")
                    let reeeedOutputFile = outputDir.appendingPathComponent("\(safeDocName)_reeeed.md")
                    try? r.markdown.write(to: reeeedOutputFile, atomically: true, encoding: .utf8)
                }
            } catch {
                print("  3. [Reeeed + html2md]          Failed: \(error)")
            }
            
            // --- Method 4: Direct Raw html-to-markdown-swift (Full Document) ---
            let rawH2mStart = CFAbsoluteTimeGetCurrent()
            var rawH2mMarkdown = ""
            var rawH2mMs = 0.0
            do {
                rawH2mMarkdown = try HTMLToMarkdown.convert(sample.rawHTML, plugins: [
                    BasePlugin(),
                    CommonmarkPlugin(),
                    GFMPlugin()
                ])
                rawH2mMs = (CFAbsoluteTimeGetCurrent() - rawH2mStart) * 1000.0
                print("  4. [Raw html-to-markdown]      Time: \(String(format: "%7.2f", rawH2mMs)) ms | Length: \(rawH2mMarkdown.count) chars")
            } catch {
                print("  4. [Raw html-to-markdown]      Failed: \(error)")
            }
            let rawH2mOutputFile = outputDir.appendingPathComponent("\(safeDocName)_raw_html2md.md")
            try? rawH2mMarkdown.write(to: rawH2mOutputFile, atomically: true, encoding: .utf8)
            
            // --- Method 5: SilicIA Web Vision (WKWebView PDF render + Apple Vision OCR) ---
            var webVisionRes: WebVisionBenchmarkService.WebVisionResult? = nil
            do {
                webVisionRes = try await WebVisionBenchmarkService.shared.process(
                    html: sample.rawHTML,
                    baseURL: sampleURL,
                    maxCharacters: 100_000
                )
                if let wv = webVisionRes {
                    print("  5. [SilicIA Web Vision]        Time: \(String(format: "%7.2f", wv.totalMs)) ms (PDF: \(String(format: "%.1f", wv.renderToPdfMs))ms, OCR: \(String(format: "%.1f", wv.visionOcrMs))ms, \(wv.pageCount) pgs) | Length: \(wv.markdown.count) chars")
                    let webVisionOutputFile = outputDir.appendingPathComponent("\(safeDocName)_webvision.md")
                    try? wv.markdown.write(to: webVisionOutputFile, atomically: true, encoding: .utf8)
                }
            } catch {
                print("  5. [SilicIA Web Vision]        Failed: \(error)")
            }
            
            results.append(BenchmarkMetrics(
                name: sample.name,
                rawBytes: sample.byteSize,
                regexTimeMs: regexTimeMs,
                regexChars: regexMarkdown.count,
                soupExtractMs: soupExtractMs,
                soupConvertMs: soupConvertMs,
                soupTotalMs: soupExtractMs + soupConvertMs,
                soupMarkdownChars: soupMarkdown.count,
                reeeedExtractMs: reeeedRes?.extractMs ?? 0,
                reeeedConvertMs: reeeedRes?.markdownConvertMs ?? 0,
                reeeedTotalMs: reeeedRes?.totalMs ?? 0,
                reeeedMarkdownChars: reeeedRes?.markdown.count ?? 0,
                rawH2mMs: rawH2mMs,
                rawH2mChars: rawH2mMarkdown.count,
                webVisionPdfMs: webVisionRes?.renderToPdfMs ?? 0,
                webVisionOcrMs: webVisionRes?.visionOcrMs ?? 0,
                webVisionTotalMs: webVisionRes?.totalMs ?? 0,
                webVisionPages: webVisionRes?.pageCount ?? 0,
                webVisionChars: webVisionRes?.markdown.count ?? 0
            ))
        }
        
        print("\n=================================================================================================================================")
        print("                                            FULL WEBPAGE BENCHMARK SUMMARY (SPEED)                                               ")
        print("=================================================================================================================================")
        print(String(format: "%-30@ | %-8@ | %-12@ | %-15@ | %-15@ | %-13@ | %-15@",
                     "Document", "HTML", "Regex (ms)", "SwiftSoup (ms)", "Reeeed (ms)", "Raw h2md (ms)", "WebVision (ms)"))
        print(String(repeating: "-", count: 125))
        
        for r in results {
            let sizeStr = "\(String(format: "%.1f", Double(r.rawBytes) / 1024.0)) KB"
            let regexStr = "\(String(format: "%.1f", r.regexTimeMs))"
            let soupStr = "\(String(format: "%.1f", r.soupTotalMs))"
            let reeeedStr = "\(String(format: "%.1f", r.reeeedTotalMs))"
            let rawH2mStr = "\(String(format: "%.1f", r.rawH2mMs))"
            let wvStr = "\(String(format: "%.1f", r.webVisionTotalMs)) (\(r.webVisionPages)p)"
            
            print(String(format: "%-30@ | %-8@ | %-12@ | %-15@ | %-15@ | %-13@ | %-15@",
                         String(r.name.prefix(30)), sizeStr, regexStr, soupStr, reeeedStr, rawH2mStr, wvStr))
        }
        
        print("\n=================================================================================================================================")
        print("                                           OUTPUT LENGTH SUMMARY (CHARACTERS)                                                    ")
        print("=================================================================================================================================")
        print(String(format: "%-30@ | %-12@ | %-15@ | %-15@ | %-13@ | %-15@",
                     "Document", "Regex Chars", "SwiftSoup Chars", "Reeeed Chars", "Raw h2md", "WebVision Chars"))
        print(String(repeating: "-", count: 110))
        for r in results {
            print(String(format: "%-30@ | %-12d | %-15d | %-15d | %-13d | %-15d",
                         String(r.name.prefix(30)), r.regexChars, r.soupMarkdownChars, r.reeeedMarkdownChars, r.rawH2mChars, r.webVisionChars))
        }
        print("=================================================================================================================================\n")
        
        print("All resulting Markdown (.md) files saved to disk:")
        print("  📂 \(outputDir.path)\n")
        let savedFiles = (try? FileManager.default.contentsOfDirectory(atPath: outputDir.path)) ?? []
        for file in savedFiles.sorted() {
            let path = outputDir.appendingPathComponent(file).path
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
            print("  • \(file) (\(size) bytes)")
        }
        print("\nBenchmark completed successfully!")
    }
}
