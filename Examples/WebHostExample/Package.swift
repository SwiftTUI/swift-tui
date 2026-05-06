// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "WebHostExample",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .executable(
      name: "WebHostExample",
      targets: ["WebHostExample"]
    )
  ],
  dependencies: [
    .package(name: "swift-tui", path: "../.."),
    .package(name: "SwiftTUIWebHost", path: "../../Platforms/WebHost"),
  ],
  targets: [
    .executableTarget(
      name: "WebHostExample",
      dependencies: [
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUIWebHostCLI", package: "SwiftTUIWebHost"),
      ]
    ),
    .testTarget(
      name: "WebHostExampleTests",
      dependencies: []
    ),
  ],
  swiftLanguageModes: [.v6]
)
