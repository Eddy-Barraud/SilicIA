import Foundation

public struct BenchmarkSample: Sendable {
    public let name: String
    public let sourceURL: String
    public let rawHTML: String
    public let byteSize: Int
    
    public init(name: String, sourceURL: String, rawHTML: String) {
        self.name = name
        self.sourceURL = sourceURL
        self.rawHTML = rawHTML
        self.byteSize = rawHTML.utf8.count
    }
}

public enum CorpusLoader {
    public static func loadFullWebpageSamples(basePath: String) throws -> [BenchmarkSample] {
        var samples: [BenchmarkSample] = []
        
        let fileManager = FileManager.default
        let samplesDir = URL(fileURLWithPath: basePath).appendingPathComponent("Samples")
        
        let fullPageFiles = [
            ("Wikipedia Polyéthylène (Full page ~325KB)", "https://fr.wikipedia.org/wiki/Polyéthylène", "polyethylene.html"),
            ("Allrecipes Marble Cake (Full page ~511KB)", "https://www.allrecipes.com/recipe/7891/marble-cake-i/", "marble_cake.html"),
            ("Radio France Paradoxe de la tolérance (Full page ~345KB)", "https://www.radiofrance.fr/franceculture/le-paradoxe-de-la-tolerance-ou-les-limites-de-la-democratie-selon-karl-popper-6482256", "radiofrance_popper.html")
        ]
        
        for (name, url, filename) in fullPageFiles {
            let fileURL = samplesDir.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: fileURL.path),
               let content = try? String(contentsOf: fileURL, encoding: .utf8),
               !content.isEmpty {
                samples.append(BenchmarkSample(name: name, sourceURL: url, rawHTML: content))
            }
        }
        
        return samples
    }
}
