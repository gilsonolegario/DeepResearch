// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DeepResearch",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/nodes-app/swift-markdown-engine", from: "0.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "DeepResearch",
            dependencies: [
                .product(name: "MarkdownEngine", package: "swift-markdown-engine"),
            ],
            path: "Sources/DeepResearch",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "DeepResearchTests",
            dependencies: ["DeepResearch"],
            path: "Tests/DeepResearchTests"
        ),
    ]
)
