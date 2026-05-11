// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "gitviz",
  platforms: [.macOS(.v15)],
  products: [
    .executable(name: "gitviz", targets: ["GitViz"])
  ],
  dependencies: [
    .package(name: "swift-tui", path: "../.."),
    .package(name: "SwiftTUICLI", path: "../../Platforms/CLI"),
    .package(name: "SwiftTUIArguments", path: "../../Platforms/Arguments"),
  ],
  targets: [
    .executableTarget(
      name: "GitViz",
      dependencies: [
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUICharts", package: "swift-tui"),
        .product(name: "SwiftTUICLI", package: "SwiftTUICLI"),
        .product(name: "SwiftTUIArguments", package: "SwiftTUIArguments"),
      ]
    ),
    .testTarget(
      name: "GitVizTests",
      dependencies: ["GitViz"],
      resources: [.copy("Fixtures")]
    ),
  ],
  swiftLanguageModes: [.v6]
)
