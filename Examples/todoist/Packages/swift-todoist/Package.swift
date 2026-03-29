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
    dependencies: [],
    targets: [
        .target(
            name: "TodoistAPI",
            dependencies: [],
        ),
        .testTarget(
            name: "TodoistAPITests",
            dependencies: ["TodoistAPI"],
        ),
    ],
    swiftLanguageModes: [.v6]
)
