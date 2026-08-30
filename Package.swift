// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FloatingNotes",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.2")
    ],
    targets: [
        .executableTarget(
            name: "FloatingNotes",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/FloatingNotes",
            resources: [.process("Resources")],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        )
    ]
)
