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
    .package(name: "swift-tui", path: "../../.."),
    .package(path: "../../gallery"),
  ],
  targets: [
    .target(
      name: "WebExampleScenes",
      dependencies: [
        .product(name: "GalleryDemoViews", package: "gallery"),
        .product(name: "SwiftTUI", package: "swift-tui"),
      ],
      path: "Sources/WebExampleScenes"
    ),
    .executableTarget(
      name: "WebExampleApp",
      dependencies: [
        "WebExampleScenes",
        .product(name: "SwiftTUIWASI", package: "swift-tui"),
      ],
      path: "Sources/TerminalApp"
    ),
  ],
  swiftLanguageModes: [.v6]
)
