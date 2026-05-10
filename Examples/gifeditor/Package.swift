// swift-tools-version: 6.3

import PackageDescription

// Example app split across four targets:
//
//   * GIFEditorCore — pure value-type model plus bridge to the vendored
//     swift-gif encoder/decoder. Has no SwiftTUI dependency,
//     so a future SwiftUI / UIKit / web port can reuse it verbatim.
//   * GIFEditorUI — SwiftTUI-shaped view tree and view model. The
//     terminal-only authoring surface lives here; a sibling
//     GIFEditorUI_SwiftUI target would slot in alongside.
//   * GIFEditor — composition root. Today it just exposes the root
//     view; tomorrow it can wire alternative UIs to the same core.
//   * gifeditor — the executable. Hosts the App via SwiftTUICLI.
let package = Package(
  name: "gifeditor",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    .executable(
      name: "gifeditor",
      targets: ["GIFEditorApp"]
    ),
    .library(
      name: "GIFEditor",
      targets: ["GIFEditor"]
    ),
    .library(
      name: "GIFEditorUI",
      targets: ["GIFEditorUI"]
    ),
    .library(
      name: "GIFEditorCore",
      targets: ["GIFEditorCore"]
    ),
  ],
  dependencies: [
    .package(name: "swift-tui", path: "../.."),
    .package(name: "SwiftTUICLI", path: "../../Platforms/CLI"),
    .package(name: "SwiftTUIArguments", path: "../../Platforms/Arguments"),
    .package(name: "SwiftTUIWebHost", path: "../../Platforms/WebHost"),
    .package(path: "../../Vendor/swift-gif"),
  ],
  targets: [
    .target(
      name: "GIFEditorCore",
      dependencies: [
        .product(name: "GIF", package: "swift-gif")
      ]
    ),
    .target(
      name: "GIFEditorUI",
      dependencies: [
        "GIFEditorCore",
        .product(name: "SwiftTUI", package: "swift-tui"),
      ]
    ),
    .target(
      name: "GIFEditor",
      dependencies: [
        "GIFEditorUI",
        "GIFEditorCore",
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUIWebHostCLI", package: "SwiftTUIWebHost"),
      ]
    ),
    .executableTarget(
      name: "GIFEditorApp",
      dependencies: [
        "GIFEditor",
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUICLI", package: "SwiftTUICLI"),
        .product(name: "SwiftTUIArguments", package: "SwiftTUIArguments"),
      ]
    ),
    .testTarget(
      name: "GIFEditorCoreTests",
      dependencies: [
        "GIFEditorCore",
        .product(name: "GIF", package: "swift-gif"),
      ]
    ),
    .testTarget(
      name: "GIFEditorUITests",
      dependencies: [
        "GIFEditorUI",
        .product(name: "SwiftTUI", package: "swift-tui"),
      ]
    ),
  ]
)
