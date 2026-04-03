// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "TerminalApp",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
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
    .package(path: "../../../Runners/TerminalUIWASI"),
    .package(path: "../../gallery"),
  ],
  targets: [
    .target(
      name: "WebExampleScenes",
      dependencies: [
        .product(name: "GalleryDemoViews", package: "gallery"),
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
        .product(name: "TerminalUICharts", package: "swift-terminal-ui"),
      ],
      path: "Sources/WebExampleScenes"
    ),
    .executableTarget(
      name: "WebExampleApp",
      dependencies: [
        "WebExampleScenes",
        .product(name: "TerminalUIWASI", package: "TerminalUIWASI"),
      ],
      path: "Sources/TerminalApp"
    ),
  ],
  swiftLanguageModes: [.v6]
)
