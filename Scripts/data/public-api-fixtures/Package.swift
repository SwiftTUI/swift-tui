// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "PublicAPIFixture",
  products: [
    .library(name: "SwiftTUI", targets: ["SwiftTUI"])
  ],
  targets: [
    .target(name: "SwiftTUI")
  ],
)
