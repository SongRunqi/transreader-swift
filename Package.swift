// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TransReaderSwift",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "TransReaderSwift",
            path: "Sources/TransReaderSwift",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
