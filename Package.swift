// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FloatingNotes",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FloatingNotes",
            path: "Sources/FloatingNotes",
            resources: [.process("Resources")]
        )
    ]
)
