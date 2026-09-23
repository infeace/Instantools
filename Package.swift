// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "InstantTab",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "InstantTab",
            dependencies: ["InstantTabCore", "SkyLightShim"]
        ),
        .target(name: "InstantTabCore"),
        .target(name: "SkyLightShim"),
        .testTarget(
            name: "InstantTabCoreTests",
            dependencies: ["InstantTabCore"]
        ),
    ]
)
