// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "live-engine",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "LiveEngine",
            dependencies: [],
            path: "Sources"
        )
    ]
)
