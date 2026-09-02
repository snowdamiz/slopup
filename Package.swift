// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Slopup",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Slopup", targets: ["Slopup"])
    ],
    targets: [
        .executableTarget(
            name: "Slopup",
            path: "Sources/Slopup",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "SlopupTests",
            dependencies: ["Slopup"],
            path: "Tests/SlopupTests"
        )
    ]
)
