// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "TodoistAPI",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
    ],
    products: [
        .library(
            name: "TodoistAPI",
            targets: ["TodoistAPI"],
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.33.1")
    ],
    targets: [
        .target(
            name: "TodoistAPI",
            dependencies: [
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
            ],
        ),
        .testTarget(
            name: "TodoistAPITests",
            dependencies: ["TodoistAPI"],
        ),
    ],
    swiftLanguageModes: [.v6]
)
