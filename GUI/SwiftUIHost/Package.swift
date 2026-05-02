// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "SwiftUIHost",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    .library(
      name: "SwiftUIHost",
      targets: ["SwiftUIHost"]
    )
  ],
  dependencies: [
    .package(name: "swift-tui", path: "../..")
  ],
  targets: [
    .target(
      name: "SwiftUIHost",
      dependencies: [
        .product(name: "SwiftTUI", package: "swift-tui")
      ],
      resources: [
        .process("Resources")
      ]
    ),
    .testTarget(
      name: "SwiftUIHostTests",
      dependencies: [
        "SwiftUIHost",
        .product(name: "SwiftTUI", package: "swift-tui"),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
