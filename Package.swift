// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Kiritori",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Kiritori",
            path: "Sources/Kiritori"
        )
    ]
)
