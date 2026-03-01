// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AsyncGuardKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(
            name: "AsyncGuardKit",
            targets: ["AsyncGuardKit"]
        )
    ],
    targets: [
        .target(
            name: "AsyncGuardKit",
            path: "Sources/AsyncGuardKit",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "AsyncGuardKitTests",
            dependencies: ["AsyncGuardKit"],
            path: "Tests/AsyncGuardKitTests",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
