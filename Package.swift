// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DeepResearch",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "DeepResearch",
            path: "Sources/DeepResearch"
        ),
        .testTarget(
            name: "DeepResearchTests",
            dependencies: ["DeepResearch"],
            path: "Tests/DeepResearchTests"
        ),
    ]
)
