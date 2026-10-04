// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WaddlyPerformance",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(name: "Waddly", path: ".."),
        .package(url: "https://github.com/swift-compositions/swift-testing-performance", exact: "0.3.1"),
        .package(url: "https://github.com/coenttb/swift-memory-allocation", exact: "0.2.0")
    ],
    targets: [
        .testTarget(
            name: "WaddlyMemoryTests",
            dependencies: [
                .product(name: "WaddlyCore", package: "Waddly"),
                .product(name: "TestingPerformance", package: "swift-testing-performance"),
                .product(name: "MemoryAllocation", package: "swift-memory-allocation")
            ]
        )
    ]
)
