// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "WebExampleApp",
  platforms: [
    .macOS(.v15),
  ],
  products: [
    .executable(
      name: "WebExampleApp",
      targets: ["WebExampleApp"]
    ),
  ],
  dependencies: [
    .package(path: "../../.."),
  ],
  targets: [
    .executableTarget(
      name: "WebExampleApp",
      dependencies: [
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
        .product(name: "TerminalUIScenes", package: "swift-terminal-ui"),
      ],
      path: "Sources/TerminalApp"
    ),
  ],
  swiftLanguageModes: [.v6]
)
