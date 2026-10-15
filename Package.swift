// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mac-cleaner",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MacCleanerCore"),
        .executableTarget(name: "mac-cleaner", dependencies: ["MacCleanerCore"]),
        .testTarget(name: "MacCleanerCoreTests", dependencies: ["MacCleanerCore"]),
    ]
)
