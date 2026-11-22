// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LiquidBrew",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "LiquidBrew", targets: ["LiquidBrew"]),
        .executable(name: "liquidbrew", targets: ["LiquidBrew"])
    ],
    targets: [
        .executableTarget(
            name: "LiquidBrew",
            path: "Sources/LiquidBrew",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [.linkedFramework("Metal"), .linkedFramework("CoreGraphics")]
        ),
        .testTarget(name: "LiquidBrewTests", dependencies: ["LiquidBrew"])
    ]
)
