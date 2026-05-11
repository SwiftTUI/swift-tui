// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "file-previewer",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .executable(
      name: "FilePreviewerApp",
      targets: ["FilePreviewerAppRunner"]
    )
  ],
  dependencies: [
    .package(name: "swift-tui", path: "../.."),
  ],
  targets: [
    .target(
      name: "FilePreviewerApp",
      dependencies: [
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUITerminal", package: "swift-tui"),
      ]
    ),
    .executableTarget(
      name: "FilePreviewerAppRunner",
      dependencies: [
        "FilePreviewerApp",
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUICLI", package: "swift-tui"),
      ]
    ),
    .testTarget(
      name: "FilePreviewerAppTests",
      dependencies: [
        "FilePreviewerApp",
        .product(name: "SwiftTUI", package: "swift-tui"),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
