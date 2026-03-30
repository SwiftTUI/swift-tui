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
    ),
  ],
  dependencies: [
    .package(path: "../.."),
    .package(url: "https://github.com/Lakr233/libghostty-spm.git", from: "1.0.1773686495"),
  ],
  targets: [
    .target(
      name: "SwiftUITUIGUI",
      dependencies: [
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
        .product(name: "TerminalUIScenes", package: "swift-terminal-ui"),
        .product(name: "GhosttyTerminal", package: "libghostty-spm"),
      ]
    ),
    .testTarget(
      name: "SwiftUITUIGUITests",
      dependencies: [
        "SwiftUITUIGUI",
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
        .product(name: "TerminalUIScenes", package: "swift-terminal-ui"),
        .product(name: "GhosttyTerminal", package: "libghostty-spm"),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
