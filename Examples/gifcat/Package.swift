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
    .package(name: "swift-terminal-ui", path: "../.."),
    .package(path: "../../Runners/TerminalUICLI"),
    .package(path: "../../Vendor/swift-gif"),
  ],
  targets: [
    .target(
      name: "GifCat",
      dependencies: [
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
        .product(name: "GIF", package: "swift-gif"),
      ]
    ),
    .executableTarget(
      name: "GifCatApp",
      dependencies: [
        "GifCat",
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
        .product(name: "TerminalUICLI", package: "TerminalUICLI"),
      ]
    ),
    .testTarget(
      name: "GifCatTests",
      dependencies: [
        "GifCat",
        .product(name: "GIF", package: "swift-gif"),
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
      ]
    ),
  ]
)
