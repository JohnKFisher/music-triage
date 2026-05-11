// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MusicTriageCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MusicTriageCore",
            targets: ["MusicTriageCore"]
        )
    ],
    targets: [
        .target(
            name: "MusicTriageCore",
            path: "Sources/MusicTriageCore"
        ),
        .testTarget(
            name: "MusicTriageCoreTests",
            dependencies: ["MusicTriageCore"],
            path: "Tests/MusicTriageCoreTests"
        )
    ]
)
