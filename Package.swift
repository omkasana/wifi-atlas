// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WiFiAtlas", platforms: [.macOS(.v14)],
    products: [.library(name: "AtlasCore", targets: ["AtlasCore"]), .executable(name: "WiFiAtlas", targets: ["WiFiAtlas"])],
    targets: [
        .target(name: "AtlasCore"),
        .executableTarget(name: "WiFiAtlas", dependencies: ["AtlasCore"]),
        .testTarget(name: "AtlasCoreTests", dependencies: ["AtlasCore", "WiFiAtlas"])
    ]
)
