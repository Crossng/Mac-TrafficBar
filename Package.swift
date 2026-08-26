// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BandwidthDesk",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TrafficBar", targets: ["TrafficBar"]),
        .executable(name: "BandwidthEngineVerifier", targets: ["BandwidthEngineVerifier"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.1")
    ],
    targets: [
        .target(
            name: "BandwidthEngine",
            linkerSettings: [
                .linkedFramework("SystemConfiguration")
            ]
        ),
        .executableTarget(
            name: "TrafficBar",
            dependencies: [
                "BandwidthEngine",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(
            name: "BandwidthEngineVerifier",
            dependencies: ["BandwidthEngine"]
        )
    ]
)
