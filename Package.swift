// swift-tools-version: 6.0
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
            path: "Sources/AsyncGuardKit"
        ),
        .testTarget(
            name: "AsyncGuardKitTests",
            dependencies: ["AsyncGuardKit"],
            path: "Tests/AsyncGuardKitTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
