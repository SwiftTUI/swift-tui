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
    .package(name: "swift-tui", path: "../..")
  ],
  targets: [
    .executableTarget(
      name: "TermUIPerf",
      dependencies: [
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUIProfiling", package: "swift-tui"),
        .product(name: "SwiftTUIRuntime", package: "swift-tui"),
      ]
    ),
    .testTarget(
      name: "TermUIPerfTests",
      dependencies: [
        "TermUIPerf",
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUIRuntime", package: "swift-tui"),
      ]
    ),
  ]
)
