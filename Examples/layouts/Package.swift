// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "layouts-demo",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    .executable(
      name: "layouts-demo",
      targets: ["LayoutsApp"]
    ),
    .library(
      name: "Layouts",
      targets: ["Layouts"]
    ),
  ],
  dependencies: [
    .package(name: "swift-terminal-ui", path: "../.."),
    .package(path: "../../Runners/TerminalUICLI"),
  ],
  targets: [
    .executableTarget(
      name: "LayoutsApp",
      dependencies: [
        "Layouts",
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
        .product(name: "TerminalUICLI", package: "TerminalUICLI"),
      ]
    ),
    .target(
      name: "Layouts",
      dependencies: [
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
        .product(name: "TerminalUICharts", package: "swift-terminal-ui"),
      ]
    ),
    .testTarget(
      name: "LayoutsTests",
      dependencies: [
        "Layouts",
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
      ]
    ),
  ]
)
