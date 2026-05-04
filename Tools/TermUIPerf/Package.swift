// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "termui-perf",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    .executable(
      name: "termui-perf",
      targets: ["TermUIPerf"]
    )
  ],
  dependencies: [
    .package(name: "swift-tui", path: "../.."),
    .package(name: "gallery-demo", path: "../../Examples/gallery"),
    .package(name: "layouts-demo", path: "../../Examples/layouts"),
  ],
  targets: [
    .executableTarget(
      name: "TermUIPerf",
      dependencies: [
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "GalleryDemoViews", package: "gallery-demo"),
        .product(name: "Layouts", package: "layouts-demo"),
      ]
    ),
    .testTarget(
      name: "TermUIPerfTests",
      dependencies: ["TermUIPerf"]
    ),
  ]
)
