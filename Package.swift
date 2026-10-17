// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Glissando",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Glissando"),
        .testTarget(name: "GlissandoTests", dependencies: ["Glissando"])
    ]
)
