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
    .package(name: "swift-tui", path: "../..")
  ],
  targets: [
    .executableTarget(
      name: "WebHostExample",
      dependencies: [
        .product(name: "SwiftTUIWebHostCLI", package: "swift-tui")
      ]
    ),
    .testTarget(
      name: "WebHostExampleTests",
      dependencies: []
    ),
  ],
  swiftLanguageModes: [.v6]
)
