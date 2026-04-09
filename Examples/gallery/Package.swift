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
  ],
  dependencies: [
    .package(path: "../.."),
    .package(path: "../../Runners/TerminalUICLI"),
    .package(url: "https://github.com/apple/swift-algorithms.git", from: "1.2.1"),
  ],
  targets: [
    .executableTarget(
      name: "GalleryDemo",
      dependencies: [
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
        .product(name: "TerminalUICLI", package: "TerminalUICLI"),
        .product(name: "TerminalUICharts", package: "swift-terminal-ui"),
        .product(name: "Algorithms", package: "swift-algorithms"),
      ]
    ),
  ]
)
