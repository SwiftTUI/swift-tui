// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "PublicAPIFixture",
  products: [
    .library(name: "SwiftTUI", targets: ["SwiftTUI"]),
    .library(name: "MissingProduct", targets: ["MissingProduct"]),
  ],
  targets: [
    .target(name: "SwiftTUI"),
    .target(name: "MissingProduct"),
  ],
)
