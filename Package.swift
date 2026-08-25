// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DeepResearch",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "DeepResearch",
            dependencies: [],
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
