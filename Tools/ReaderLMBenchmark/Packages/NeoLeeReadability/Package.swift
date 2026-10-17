// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NeoLeeReadability",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "NeoLeeReadability",
            targets: ["NeoLeeReadability"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.5")
    ],
    targets: [
        .target(
            name: "NeoLeeReadability",
            dependencies: ["SwiftSoup"],
            path: "Sources/Readability"
        )
    ]
)
