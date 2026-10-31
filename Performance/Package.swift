// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WaddlyPerformance",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(name: "Waddly", path: ".."),
        // Vendored so MemoryAllocation uses one canonical URL. Release
        // 0.3.1 still depends on the pre-move coenttb URL, and SwiftPM
        // will reject two URLs for one package identity.
        .package(name: "swift-testing-performance", path: "Vendor/swift-testing-performance"),
        // Commit afe7e86 is the deleted 0.2.0 tag. Upstream main no longer
        // publishes the MemoryAllocation product this suite imports.
        .package(
            url: "https://github.com/swift-molecules/swift-memory-allocation",
            revision: "afe7e86f16981007b841470d5ea79f0026868bc3"
        )
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
