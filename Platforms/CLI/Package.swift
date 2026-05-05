// swift-tools-version: 6.3

import PackageDescription

func swiftSettings(_ settings: SwiftSetting...) -> [SwiftSetting] {
  [
    .swiftLanguageMode(.v6),
    .strictMemorySafety(),
    .defaultIsolation(.none),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("ImmutableWeakCaptures"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  ] + settings
}

let package = Package(
  name: "SwiftTUICLI",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(name: "SwiftTUICLI", targets: ["SwiftTUICLI"])
  ],
  dependencies: [
    .package(name: "swift-tui", path: "../.."),
    .package(path: "../Embedding"),
    .package(path: "../../Vendor/UnixSignals"),
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
  ],
  targets: [
    .target(
      name: "SwiftTUICLI",
      dependencies: [
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUIPTYPrimitives", package: "Embedding"),
        .product(name: "UnixSignals", package: "UnixSignals"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "SwiftTUICLITests",
      dependencies: [
        "SwiftTUICLI",
        .product(name: "SwiftTUIPTYPrimitives", package: "Embedding"),
        .product(name: "SwiftTUI", package: "swift-tui"),
      ],
      swiftSettings: swiftSettings()
    ),
  ],
  swiftLanguageModes: [.v6]
)
