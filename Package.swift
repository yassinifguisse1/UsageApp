// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UsageCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "UsageCore", targets: ["UsageCore"]),
        .executable(name: "usageapp-claude-status", targets: ["ClaudeStatus"]),
    ],
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(name: "ClaudeStatus", dependencies: ["UsageCore"]),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"]),
    ]
)
