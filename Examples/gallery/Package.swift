// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "gallery-demo",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    .executable(
      name: "gallery-demo",
      targets: ["GalleryDemo"]
    ),
    .library(
      name: "GalleryDemoViews",
      targets: ["GalleryDemoViews"]
    ),
  ],
  dependencies: [
    .package(path: "../.."),
    .package(path: "../../Runners/TerminalUICLI"),
  ],
  targets: [
    .executableTarget(
      name: "GalleryDemo",
      dependencies: [
        "GalleryDemoViews",
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
        .product(name: "TerminalUICLI", package: "TerminalUICLI"),
      ]
    ),
    .target(
      name: "GalleryDemoViews",
      dependencies: [
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
        .product(name: "TerminalUICharts", package: "swift-terminal-ui"),
      ]
    ),
    .testTarget(
      name: "GalleryDemoViewsTests",
      dependencies: [
        "GalleryDemoViews",
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
      ]
    ),
  ]
)
