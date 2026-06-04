// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TokenUsageApp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TokenUsageApp",
            path: "Sources/TokenUsageApp"
        ),
        .testTarget(
            name: "TokenUsageAppTests",
            dependencies: ["TokenUsageApp"],
            path: "Tests/TokenUsageAppTests"
        )
    ]
)
