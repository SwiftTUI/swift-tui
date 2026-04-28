// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "canvas-demo",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    .executable(
      name: "canvas-demo",
      targets: ["CanvasDemo"]
    ),
    .library(
      name: "CanvasDemoViews",
      targets: ["CanvasDemoViews"]
    ),
  ],
  dependencies: [
    .package(name: "swift-terminal-ui", path: "../.."),
    .package(path: "../../Runners/TerminalUICLI"),
  ],
  targets: [
    .executableTarget(
      name: "CanvasDemo",
      dependencies: [
        "CanvasDemoViews",
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
        .product(name: "TerminalUICLI", package: "TerminalUICLI"),
      ]
    ),
    .target(
      name: "CanvasDemoViews",
      dependencies: [
        .product(name: "TerminalUI", package: "swift-terminal-ui")
      ]
    ),
    .testTarget(
      name: "CanvasDemoViewsTests",
      dependencies: [
        "CanvasDemoViews",
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
      ]
    ),
  ]
)
