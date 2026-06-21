// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CCUsageBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CCUsageBar",
            path: "Sources/CCUsageBar"
        )
    ]
)
