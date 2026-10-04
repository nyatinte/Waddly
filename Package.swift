// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Waddly",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Waddly", targets: ["WaddlyApp"])
    ],
    targets: [
        .target(name: "WaddlyCore", path: "Sources/WaddlyCore"),
        .executableTarget(
            name: "WaddlyApp",
            dependencies: ["WaddlyCore"],
            path: "Sources/WaddlyApp"
        ),
        .testTarget(
            name: "WaddlyCoreTests",
            dependencies: ["WaddlyCore"],
            path: "Tests/WaddlyCoreTests",
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "WaddlyAppTests",
            dependencies: ["WaddlyApp"],
            path: "Tests/WaddlyAppTests"
        )
    ]
)
