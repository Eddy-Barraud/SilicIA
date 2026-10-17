import Foundation
import SwiftSoup
import HTMLToMarkdown
import Reeeed

@main
struct BenchmarkRunner {
    static func main() async {
        print("==========================================================================================")
        print("  SilicIA Full Webpage HTML to Markdown Benchmark Suite                                  ")
        print("  Evaluating 8 Strategies:                                                               ")
        print("    1. SilicIA Baseline Regex                                                            ")
        print("    2. SwiftSoup Body Extraction + html-to-markdown-swift                                ")
        print("    3. Reeeed (Readability/Mercury JS Extractor) + html-to-markdown-swift                  ")
        print("    4. swift-readability (Mozilla Readability WKWebView) + html-to-markdown-swift          ")
        print("    5. Raw html-to-markdown-swift (Full Document)                                        ")
        print("    6. SilicIA Web Vision (Headless WKWebView PDF Rasterization + Apple Vision OCR)      ")
        print("    7. WKWebView innerText + html-to-markdown-swift                                       ")
        print("    8. neolee/swift-readability (Pure Swift Readability) + html-to-markdown-swift          ")
        print("==========================================================================================")
        
        let basePath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // ReaderLMBenchmark
            .path
        
        let outputDir = URL(fileURLWithPath: basePath).appendingPathComponent("OutputMarkdown")
        let outputPdfDir = URL(fileURLWithPath: basePath).appendingPathComponent("OutputPDF")
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: outputPdfDir, withIntermediateDirectories: true)
        
        let samples: [BenchmarkSample]
        do {
            samples = try CorpusLoader.loadFullWebpageSamples(basePath: basePath)
        } catch {
            print("Failed to load corpus samples: \(error)")
            return
        }
        
        print("Discovered \(samples.count) full-page sample documents.")
        print("Markdown Output directory: \(outputDir.path)")
        print("PDF Output directory:      \(outputPdfDir.path)\n")
        
        // Warm up Reeeed JS runtime
        Reeeed.warmup(extractor: .readability)
        Reeeed.warmup(extractor: .mercury)
        
        // Warm up swift-readability
        _ = try? await SwiftReadabilityExtractor.extractAndConvert(html: "<html><body><article><p>Warmup</p></article></body></html>")
        
        // Warm up WKWebView innerText extractor
        _ = try? await WKWebViewInnerTextExtractor.extractAndConvert(html: "<html><body><p>Warmup</p></body></html>")
        
        // Warm up neolee/swift-readability (Pure Swift)
        _ = try? NeoLeeReadabilityExtractor.extractAndConvert(html: "<html><body><article><p>Warmup</p></article></body></html>")
        
        // Warm up Apple Vision neural models (OCR + Classifier)
        print("Warming up Apple Vision neural engine...")
        WebVisionBenchmarkService.warmup()
        print("Warmup complete.\n")
        
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
            
            // 4. swift-readability + html2md
            let srExtractMs: Double
            let srConvertMs: Double
            let srTotalMs: Double
            let srMarkdownChars: Int
            
            // 5. Raw html-to-markdown-swift
            let rawH2mMs: Double
            let rawH2mChars: Int
            
            // 6. SilicIA Web Vision
            let webVisionPdfMs: Double
            let webVisionOcrMs: Double
            let webVisionTotalMs: Double
            let webVisionPages: Int
            let webVisionChars: Int
            
            // 7. WKWebView innerText + html-to-markdown-swift
            let wkTextExtractMs: Double
            let wkTextConvertMs: Double
            let wkTextTotalMs: Double
            let wkTextChars: Int
            
            // 8. neolee/swift-readability (Pure Swift) + html-to-markdown-swift
            let neoleeExtractMs: Double
            let neoleeConvertMs: Double
            let neoleeTotalMs: Double
            let neoleeMarkdownChars: Int
        }
        
        var results: [BenchmarkMetrics] = []
        
        for (index, sample) in samples.enumerated() {
            let safeDocName = sample.name
                .precomposedStringWithCanonicalMapping
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: "_")
                .lowercased()
                .precomposedStringWithCanonicalMapping
            
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
            
            // --- Method 4: swift-readability + html-to-markdown-swift ---
            var srRes: SwiftReadabilityExtractor.ExtractionResult? = nil
            do {
                srRes = try await SwiftReadabilityExtractor.extractAndConvert(
                    html: sample.rawHTML,
                    baseURL: sampleURL
                )
                if let sr = srRes {
                    print("  4. [swift-readability+h2md]    Time: \(String(format: "%7.2f", sr.totalMs)) ms (Extract: \(String(format: "%.1f", sr.extractMs))ms, Convert: \(String(format: "%.1f", sr.markdownConvertMs))ms) | Length: \(sr.markdown.count) chars")
                    let srOutputFile = outputDir.appendingPathComponent("\(safeDocName)_swiftreadability.md")
                    try? sr.markdown.write(to: srOutputFile, atomically: true, encoding: .utf8)
                }
            } catch {
                print("  4. [swift-readability+h2md]    Failed: \(error)")
            }
            
            // --- Method 5: Direct Raw html-to-markdown-swift (Full Document) ---
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
                print("  5. [Raw html-to-markdown]      Time: \(String(format: "%7.2f", rawH2mMs)) ms | Length: \(rawH2mMarkdown.count) chars")
            } catch {
                print("  5. [Raw html-to-markdown]      Failed: \(error)")
            }
            let rawH2mOutputFile = outputDir.appendingPathComponent("\(safeDocName)_raw_html2md.md")
            try? rawH2mMarkdown.write(to: rawH2mOutputFile, atomically: true, encoding: .utf8)
            
            // --- Method 6: SilicIA Web Vision (WKWebView PDF render + Apple Vision OCR) ---
            var webVisionRes: WebVisionBenchmarkService.WebVisionResult? = nil
            do {
                webVisionRes = try await WebVisionBenchmarkService.shared.process(
                    html: sample.rawHTML,
                    baseURL: sampleURL,
                    maxCharacters: 100_000
                )
                if let wv = webVisionRes {
                    print("  6. [SilicIA Web Vision]        Time: \(String(format: "%7.2f", wv.totalMs)) ms (PDF: \(String(format: "%.1f", wv.renderToPdfMs))ms, OCR: \(String(format: "%.1f", wv.visionOcrMs))ms, \(wv.pageCount) pg 1080x1920 @ 150DPI No-JS) | Length: \(wv.markdown.count) chars")
                    let webVisionOutputFile = outputDir.appendingPathComponent("\(safeDocName)_webvision.md")
                    try? wv.markdown.write(to: webVisionOutputFile, atomically: true, encoding: .utf8)
                    
                    let webVisionPdfFile = outputPdfDir.appendingPathComponent("\(safeDocName)_rendered_1080x1920.pdf")
                    try? wv.pdfData.write(to: webVisionPdfFile, options: .atomic)
                    print("                                    Saved PDF:      \(webVisionPdfFile.lastPathComponent) (\(wv.pdfByteSize) bytes)")
                }
            } catch {
                print("  6. [SilicIA Web Vision]        Failed: \(error)")
            }
            
            // --- Method 7: WKWebView innerText + html-to-markdown-swift ---
            var wkTextRes: WKWebViewInnerTextExtractor.ExtractionResult? = nil
            do {
                wkTextRes = try await WKWebViewInnerTextExtractor.extractAndConvert(
                    html: sample.rawHTML,
                    baseURL: sampleURL
                )
                if let wk = wkTextRes {
                    print("  7. [WKWebView innerText+h2md]  Time: \(String(format: "%7.2f", wk.totalMs)) ms (Extract: \(String(format: "%.1f", wk.extractMs))ms, Convert: \(String(format: "%.1f", wk.markdownConvertMs))ms) | Length: \(wk.markdown.count) chars")
                    let wkTextOutputFile = outputDir.appendingPathComponent("\(safeDocName)_wkwebview_innertext.md")
                    try? wk.markdown.write(to: wkTextOutputFile, atomically: true, encoding: .utf8)
                }
            } catch {
                print("  7. [WKWebView innerText+h2md]  Failed: \(error)")
            }
            
            // --- Method 8: neolee/swift-readability (Pure Swift) + html-to-markdown-swift ---
            var neoleeRes: NeoLeeReadabilityExtractor.ExtractionResult? = nil
            do {
                neoleeRes = try NeoLeeReadabilityExtractor.extractAndConvert(
                    html: sample.rawHTML,
                    baseURL: sampleURL
                )
                if let nl = neoleeRes {
                    print("  8. [neolee/readability+h2md]   Time: \(String(format: "%7.2f", nl.totalMs)) ms (Extract: \(String(format: "%.1f", nl.extractMs))ms, Convert: \(String(format: "%.1f", nl.markdownConvertMs))ms) | Length: \(nl.markdown.count) chars")
                    let neoleeOutputFile = outputDir.appendingPathComponent("\(safeDocName)_neolee_readability.md")
                    try? nl.markdown.write(to: neoleeOutputFile, atomically: true, encoding: .utf8)
                }
            } catch {
                print("  8. [neolee/readability+h2md]   Failed: \(error)")
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
                srExtractMs: srRes?.extractMs ?? 0,
                srConvertMs: srRes?.markdownConvertMs ?? 0,
                srTotalMs: srRes?.totalMs ?? 0,
                srMarkdownChars: srRes?.markdown.count ?? 0,
                rawH2mMs: rawH2mMs,
                rawH2mChars: rawH2mMarkdown.count,
                webVisionPdfMs: webVisionRes?.renderToPdfMs ?? 0,
                webVisionOcrMs: webVisionRes?.visionOcrMs ?? 0,
                webVisionTotalMs: webVisionRes?.totalMs ?? 0,
                webVisionPages: webVisionRes?.pageCount ?? 0,
                webVisionChars: webVisionRes?.markdown.count ?? 0,
                wkTextExtractMs: wkTextRes?.extractMs ?? 0,
                wkTextConvertMs: wkTextRes?.markdownConvertMs ?? 0,
                wkTextTotalMs: wkTextRes?.totalMs ?? 0,
                wkTextChars: wkTextRes?.markdown.count ?? 0,
                neoleeExtractMs: neoleeRes?.extractMs ?? 0,
                neoleeConvertMs: neoleeRes?.markdownConvertMs ?? 0,
                neoleeTotalMs: neoleeRes?.totalMs ?? 0,
                neoleeMarkdownChars: neoleeRes?.markdown.count ?? 0
            ))
        }
        
        print("\n=================================================================================================================================================================================")
        print("                                                               FULL WEBPAGE BENCHMARK SUMMARY (SPEED)                                                            ")
        print("=================================================================================================================================================================================")
        print(String(format: "%-28@ | %-8@ | %-10@ | %-12@ | %-11@ | %-13@ | %-12@ | %-13@ | %-13@ | %-15@",
                     "Document", "HTML", "Regex(ms)", "SwiftSoup", "Reeeed(ms)", "Ryu0118(ms)", "NeoLee(ms)", "Raw h2md(ms)", "WKinnerText", "WebVision(ms)"))
        print(String(repeating: "-", count: 185))
        
        for r in results {
            let sizeStr = "\(String(format: "%.1f", Double(r.rawBytes) / 1024.0)) KB"
            let regexStr = "\(String(format: "%.1f", r.regexTimeMs))"
            let soupStr = "\(String(format: "%.1f", r.soupTotalMs))"
            let reeeedStr = "\(String(format: "%.1f", r.reeeedTotalMs))"
            let srStr = "\(String(format: "%.1f", r.srTotalMs))"
            let neoleeStr = "\(String(format: "%.1f", r.neoleeTotalMs))"
            let rawH2mStr = "\(String(format: "%.1f", r.rawH2mMs))"
            let wkTextStr = "\(String(format: "%.1f", r.wkTextTotalMs))"
            let wvStr = "\(String(format: "%.1f", r.webVisionTotalMs)) (\(r.webVisionPages)p)"
            
            print(String(format: "%-28@ | %-8@ | %-10@ | %-12@ | %-11@ | %-13@ | %-12@ | %-13@ | %-13@ | %-15@",
                         String(r.name.prefix(28)), sizeStr, regexStr, soupStr, reeeedStr, srStr, neoleeStr, rawH2mStr, wkTextStr, wvStr))
        }
        
        print("\n=================================================================================================================================================================================")
        print("                                                              OUTPUT LENGTH SUMMARY (CHARACTERS)                                                                 ")
        print("=================================================================================================================================================================================")
        print(String(format: "%-28@ | %-10@ | %-12@ | %-11@ | %-13@ | %-12@ | %-13@ | %-13@ | %-15@",
                     "Document", "Regex Ch", "SwiftSoup Ch", "Reeeed Ch", "Ryu0118 Ch", "NeoLee Ch", "Raw h2md", "WKinnerText", "WebVision Chars"))
        print(String(repeating: "-", count: 185))
        for r in results {
            print(String(format: "%-28@ | %-10d | %-12d | %-11d | %-13d | %-12d | %-13d | %-13d | %-15d",
                         String(r.name.prefix(28)), r.regexChars, r.soupMarkdownChars, r.reeeedMarkdownChars, r.srMarkdownChars, r.neoleeMarkdownChars, r.rawH2mChars, r.wkTextChars, r.webVisionChars))
        }
        print("=================================================================================================================================================================================\n")
        
        print("All resulting Markdown (.md) files saved to disk:")
        print("  📂 \(outputDir.path)\n")
        let savedFiles = (try? FileManager.default.contentsOfDirectory(atPath: outputDir.path)) ?? []
        for file in savedFiles.sorted() {
            let path = outputDir.appendingPathComponent(file).path
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
            print("  • \(file) (\(size) bytes)")
        }
        
        print("\nAll rendered A4 PDF (.pdf) files saved to disk:")
        print("  📄 \(outputPdfDir.path)\n")
        let savedPdfs = (try? FileManager.default.contentsOfDirectory(atPath: outputPdfDir.path)) ?? []
        for file in savedPdfs.sorted() {
            let path = outputPdfDir.appendingPathComponent(file).path
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
            print("  • \(file) (\(size) bytes)")
        }
        print("\nBenchmark completed successfully!")
    }
}
