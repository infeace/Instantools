// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Instantools",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Instantools",
            dependencies: ["InstantoolsCore", "InstantoolsKit", "AppSwitcherCore", "AppSwitcherKit", "SkyLightShim"]
        ),
        .executableTarget(
            name: "AppSwitcher",
            dependencies: ["InstantoolsCore", "InstantoolsKit", "AppSwitcherCore", "AppSwitcherKit", "SkyLightShim"]
        ),
        .executableTarget(
            name: "LayoutSwitcher",
            dependencies: ["InstantoolsCore", "InstantoolsKit", "LayoutSwitcherCore"]
        ),
        .target(name: "InstantoolsCore"),
        .target(name: "InstantoolsKit", dependencies: ["InstantoolsCore"]),
        .target(name: "AppSwitcherCore"),
        .target(name: "AppSwitcherKit", dependencies: ["AppSwitcherCore", "InstantoolsKit", "SkyLightShim"]),
        .target(name: "LayoutSwitcherCore"),
        .target(name: "SkyLightShim"),
        .testTarget(
            name: "InstantoolsCoreTests",
            dependencies: ["InstantoolsCore"]
        ),
        .testTarget(
            name: "AppSwitcherCoreTests",
            dependencies: ["AppSwitcherCore"]
        ),
        .testTarget(
            name: "LayoutSwitcherCoreTests",
            dependencies: ["LayoutSwitcherCore"]
        ),
        .testTarget(
            name: "AppSwitcherKitTests",
            dependencies: ["AppSwitcherKit", "AppSwitcherCore"]
        ),
        .testTarget(
            name: "InstantoolsTests",
            dependencies: ["Instantools", "InstantoolsCore"]
        ),
    ]
)
