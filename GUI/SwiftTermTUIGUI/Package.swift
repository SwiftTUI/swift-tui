// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "SwiftTermTUIGUI",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    .library(
      name: "SwiftTermTUIGUI",
      targets: ["SwiftTermTUIGUI"]
    )
  ],
  dependencies: [
    .package(path: "../.."),
    .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.13.0"),
  ],
  targets: [
    .target(
      name: "SwiftTermTUIGUI",
      dependencies: [
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
        .product(name: "SwiftTerm", package: "SwiftTerm"),
      ]
    ),
    .testTarget(
      name: "SwiftTermTUIGUITests",
      dependencies: [
        "SwiftTermTUIGUI",
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
        .product(name: "SwiftTerm", package: "SwiftTerm"),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
