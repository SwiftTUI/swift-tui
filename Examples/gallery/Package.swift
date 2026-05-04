// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "gallery-demo",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    .executable(
      name: "gallery-demo",
      targets: ["GalleryDemo"]
    ),
    .library(
      name: "GalleryDemoViews",
      targets: ["GalleryDemoViews"]
    ),
  ],
  dependencies: [
    .package(name: "swift-tui", path: "../.."),
    .package(name: "SwiftTUICLI", path: "../../Platforms/CLI"),
  ],
  targets: [
    .executableTarget(
      name: "GalleryDemo",
      dependencies: [
        "GalleryDemoViews",
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUICLI", package: "SwiftTUICLI"),
      ]
    ),
    .target(
      name: "GalleryDemoViews",
      dependencies: [
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUICharts", package: "swift-tui"),
      ]
    ),
    .testTarget(
      name: "GalleryDemoViewsTests",
      dependencies: [
        "GalleryDemoViews",
        .product(name: "SwiftTUI", package: "swift-tui"),
      ]
    ),
  ]
)
