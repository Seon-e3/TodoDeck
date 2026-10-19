// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TodoDeck",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "TodoDeck"),
        .testTarget(name: "TodoDeckTests", dependencies: ["TodoDeck"]),
    ],
    swiftLanguageModes: [.v5]
)
