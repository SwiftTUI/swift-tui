// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "ExampleApp",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    .library(
      name: "ExampleScenes",
      targets: ["ExampleScenes"]
    )
  ],
  dependencies: [
    .package(path: "../../.."),
    .package(path: "../../gallery"),
  ],
  targets: [
    .target(
      name: "ExampleScenes",
      dependencies: [
        .product(name: "GalleryDemoViews", package: "gallery"),
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
        .product(name: "TerminalUICharts", package: "swift-terminal-ui"),
      ],
      path: "Sources/ExampleScenes"
    )
  ],
  swiftLanguageModes: [.v6]
)
