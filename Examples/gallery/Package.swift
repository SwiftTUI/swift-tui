// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "gallery-demo",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    .library(
      name: "GalleryDemoViews",
      targets: ["GalleryDemoViews"]
    ),
    .executable(
      name: "gallery-demo",
      targets: ["GalleryDemo"]
    ),
  ],
  dependencies: [
    .package(path: "../..")
  ],
  targets: [
    .target(
      name: "GalleryDemoViews",
      dependencies: [
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
        .product(name: "TerminalUICharts", package: "swift-terminal-ui"),
      ]
    ),
    .executableTarget(
      name: "GalleryDemo",
      dependencies: [
        "GalleryDemoViews",
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
        .product(name: "TerminalUIScenes", package: "swift-terminal-ui"),
        .product(name: "TerminalUICharts", package: "swift-terminal-ui"),
      ]
    ),
  ]
)
