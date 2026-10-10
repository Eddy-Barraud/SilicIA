// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReaderLMBenchmark",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/jaredhowland/html-to-markdown-swift.git", from: "0.9.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.5"),
        .package(url: "https://github.com/nate-parrott/reeeed.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "ReaderLMBenchmark",
            dependencies: [
                .product(name: "HTMLToMarkdown", package: "html-to-markdown-swift"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
                .product(name: "Reeeed", package: "reeeed"),
            ],
            path: "Sources"
        )
    ]
)
