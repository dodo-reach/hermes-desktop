// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HermesDesktop",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "HermesDesktop",
            targets: ["HermesDesktop"]
        )
    ],
    dependencies: [
        .package(path: "Vendor/SwiftTerm")
    ],
    targets: [
        .executableTarget(
            name: "HermesDesktop",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/HermesDesktop",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "HermesDesktopTests",
            dependencies: ["HermesDesktop"],
            path: "Tests/HermesDesktopTests"
        )
    ]
)
