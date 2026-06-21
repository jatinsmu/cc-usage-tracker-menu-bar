// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CCUsageBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CCUsageBar",
            path: "Sources/CCUsageBar"
        ),
        .testTarget(
            name: "CCUsageBarTests",
            dependencies: ["CCUsageBar"],
            path: "Tests/CCUsageBarTests"
        ),
    ]
)
