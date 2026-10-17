// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReaderLMBenchmark",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/jaredhowland/html-to-markdown-swift.git", from: "0.9.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.5"),
        .package(url: "https://github.com/nate-parrott/reeeed.git", branch: "main"),
        .package(url: "https://github.com/Ryu0118/swift-readability.git", exact: "0.4.0"),
        .package(path: "Packages/NeoLeeReadability"),
    ],
    targets: [
        .executableTarget(
            name: "ReaderLMBenchmark",
            dependencies: [
                .product(name: "HTMLToMarkdown", package: "html-to-markdown-swift"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
                .product(name: "Reeeed", package: "reeeed"),
                .product(name: "Readability", package: "swift-readability"),
                .product(name: "NeoLeeReadability", package: "NeoLeeReadability"),
            ],
            path: "Sources"
        )
    ]
)
