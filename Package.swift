// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AsyncGuardKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
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
            path: "Sources/AsyncGuardKit"
        ),
        .testTarget(
            name: "AsyncGuardKitTests",
            dependencies: ["AsyncGuardKit"],
            path: "Tests/AsyncGuardKitTests"
        )
    ]
)
