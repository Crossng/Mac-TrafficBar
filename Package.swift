// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TrafficBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "TrafficBarCore", targets: ["TrafficBarCore"]),
        .executable(name: "TrafficBar", targets: ["TrafficBar"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.1")
    ],
    targets: [
        .target(
            name: "TrafficBarCore",
            linkerSettings: [
                .linkedFramework("SystemConfiguration")
            ]
        ),
        .executableTarget(
            name: "TrafficBar",
            dependencies: [
                "TrafficBarCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "TrafficBarCoreTests",
            dependencies: ["TrafficBarCore"]
        )
    ]
)
