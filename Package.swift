// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Motif",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MotifCore", targets: ["MotifCore"]),
        .executable(name: "Motif", targets: ["Motif"])
    ],
    targets: [
        .target(
            name: "MotifCore",
            path: "Sources/MotifCore"
        ),
        .executableTarget(
            name: "Motif",
            dependencies: ["MotifCore"],
            path: "Sources/Motif",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "MotifCoreTests",
            dependencies: ["MotifCore"],
            path: "Tests/MotifCoreTests"
        )
    ]
)
