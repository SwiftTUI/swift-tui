// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "gallery-demo",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .executable(
      name: "gallery-demo",
      targets: ["GalleryDemo"]
    )
  ],
  dependencies: [
    .package(path: "../..")
  ],
  targets: [
    .executableTarget(
      name: "GalleryDemo",
      dependencies: [
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
        .product(name: "TerminalUIScenes", package: "swift-terminal-ui"),
        .product(name: "TerminalUICharts", package: "swift-terminal-ui"),
      ]
    ),
  ]
)
