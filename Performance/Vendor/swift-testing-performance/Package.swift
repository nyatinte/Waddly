// swift-tools-version: 6.2
// Modified from swift-compositions/swift-testing-performance 0.3.1
// (1a1967f7acfcb081e57122db463817c142cc7186).
// MemoryAllocation is pinned to afe7e86 on
// https://github.com/swift-molecules/swift-memory-allocation, the same
// requirement as Performance/Package.swift. The 0.2.0 tag was deleted.
// Tests and DocC from the upstream package are omitted.

import PackageDescription

let package = Package(
    name: "swift-testing-performance",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26),
    ],
    products: [
        .library(
            name: "TestingPerformance",
            targets: ["TestingPerformance"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-numerics", from: "1.0.0"),
        .package(
            url: "https://github.com/swift-molecules/swift-memory-allocation",
            revision: "afe7e86f16981007b841470d5ea79f0026868bc3"
        )
    ],
    targets: [
        .target(
            name: "TestingPerformance",
            dependencies: [
                .product(name: "Numerics", package: "swift-numerics"),
                .product(name: "MemoryAllocation", package: "swift-memory-allocation")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin].contains(target.type) {
    let existing = target.swiftSettings ?? []
    target.swiftSettings = existing + [
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility")
    ]
}
