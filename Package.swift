// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MiniCap",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "MiniCap",
            path: "Sources/MiniCap",
            swiftSettings: [.unsafeFlags(["-Osize"])]
        )
    ],
    swiftLanguageModes: [.v5]
)
