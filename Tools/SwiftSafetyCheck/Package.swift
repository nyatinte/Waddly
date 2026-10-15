// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftSafetyCheck",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "600.0.1")
    ],
    targets: [
        .executableTarget(
            name: "swift-safety-check",
            dependencies: [
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax")
            ]
        )
    ]
)
