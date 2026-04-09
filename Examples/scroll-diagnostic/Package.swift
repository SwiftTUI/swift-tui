// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "scroll-diagnostic",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    .executable(
      name: "scroll-diagnostic",
      targets: ["ScrollDiagnostic"]
    )
  ],
  dependencies: [
    .package(path: "../.."),
    .package(path: "../../Runners/TerminalUICLI"),
  ],
  targets: [
    .executableTarget(
      name: "ScrollDiagnostic",
      dependencies: [
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
        .product(name: "TerminalUICLI", package: "TerminalUICLI"),
        .product(name: "TerminalUICharts", package: "swift-terminal-ui"),
      ]
    )
  ]
)
