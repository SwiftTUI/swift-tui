// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "WebExampleApp",
  platforms: [
    .macOS(.v15),
  ],
  products: [
    .library(
      name: "WebExampleScenes",
      targets: ["WebExampleScenes"]
    ),
    .executable(
      name: "WebExampleApp",
      targets: ["WebExampleApp"]
    ),
  ],
  dependencies: [
    .package(path: "../../.."),
    .package(path: "../../gallery"),
  ],
  targets: [
    .target(
      name: "WebExampleScenes",
      dependencies: [
        .product(name: "GalleryDemoViews", package: "gallery"),
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
        .product(name: "TerminalUICharts", package: "swift-terminal-ui"),
        .product(name: "TerminalUIScenes", package: "swift-terminal-ui"),
      ],
      path: "Sources/WebExampleScenes"
    ),
    .executableTarget(
      name: "WebExampleApp",
      dependencies: [
        "WebExampleScenes",
        .product(name: "TerminalUIScenes", package: "swift-terminal-ui"),
      ],
      path: "Sources/TerminalApp"
    ),
  ],
  swiftLanguageModes: [.v6]
)
