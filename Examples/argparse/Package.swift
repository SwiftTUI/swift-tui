// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "argparse-demo",
  platforms: [.macOS(.v15)],
  products: [
    .executable(name: "argparse-demo", targets: ["ArgParseDemo"])
  ],
  dependencies: [
    .package(name: "swift-tui", path: "../.."),
    .package(name: "SwiftTUICLI", path: "../../Platforms/CLI"),
    .package(name: "SwiftTUIArguments", path: "../../Platforms/Arguments"),
  ],
  targets: [
    .executableTarget(
      name: "ArgParseDemo",
      dependencies: [
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUICLI", package: "SwiftTUICLI"),
        .product(name: "SwiftTUIArguments", package: "SwiftTUIArguments"),
      ]
    )
  ]
)
