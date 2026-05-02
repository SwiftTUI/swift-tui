// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "minimal",
  platforms: [
    .macOS(.v15)
  ],
  dependencies: [
    .package(name: "swift-tui", path: "../..")
  ],
  targets: [
    .executableTarget(
      name: "minimal",
      dependencies: [.product(name: "SwiftTUI", package: "swift-tui")]
    )
  ],
  swiftLanguageModes: [.v6]
)
