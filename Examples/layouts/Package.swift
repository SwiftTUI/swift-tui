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
    .package(name: "swift-tui", path: "../.."),
    .package(path: "../../Runners/SwiftTUICLI"),
  ],
  targets: [
    .executableTarget(
      name: "LayoutsApp",
      dependencies: [
        "Layouts",
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUICLI", package: "SwiftTUICLI"),
      ]
    ),
    .target(
      name: "Layouts",
      dependencies: [
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUICharts", package: "swift-tui"),
      ]
    ),
    .testTarget(
      name: "LayoutsTests",
      dependencies: [
        "Layouts",
        .product(name: "SwiftTUI", package: "swift-tui"),
      ]
    ),
  ]
)
