// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ChatGPTUsage",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ChatGPTUsage", targets: ["ChatGPTUsage"])],
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(name: "ChatGPTUsage", dependencies: ["UsageCore"]),
        .executableTarget(name: "UsageVerifier", dependencies: ["UsageCore"], path: "Tests/UsageVerifier")
    ]
)
