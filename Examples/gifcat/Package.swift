// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "gifcat",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    .executable(
      name: "gifcat",
      targets: ["GifCatApp"]
    ),
    .library(
      name: "GifCat",
      targets: ["GifCat"]
    ),
  ],
  dependencies: [
    .package(name: "swift-tui", path: "../.."),
    .package(path: "../../Runners/SwiftTUICLI"),
  ],
  targets: [
    .target(
      name: "GifCat",
      dependencies: [
        .product(name: "AnimatedImage", package: "swift-tui"),
        .product(name: "SwiftTUI", package: "swift-tui"),
      ]
    ),
    .executableTarget(
      name: "GifCatApp",
      dependencies: [
        "GifCat",
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUICLI", package: "SwiftTUICLI"),
      ]
    ),
    .testTarget(
      name: "GifCatTests",
      dependencies: [
        "GifCat",
        .product(name: "AnimatedImage", package: "swift-tui"),
        .product(name: "SwiftTUI", package: "swift-tui"),
      ]
    ),
  ]
)
