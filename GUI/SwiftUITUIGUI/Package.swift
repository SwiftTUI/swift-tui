// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "SwiftUITUIGUI",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    .library(
      name: "SwiftUITUIGUI",
      targets: ["SwiftUITUIGUI"]
    )
  ],
  dependencies: [
    .package(name: "swift-terminal-ui", path: "../..")
  ],
  targets: [
    .target(
      name: "SwiftUITUIGUI",
      dependencies: [
        .product(name: "TerminalUI", package: "swift-terminal-ui")
      ]
    ),
    .testTarget(
      name: "SwiftUITUIGUITests",
      dependencies: [
        "SwiftUITUIGUI",
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
