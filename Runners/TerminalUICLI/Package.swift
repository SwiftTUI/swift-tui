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
  name: "TerminalUICLI",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(name: "TerminalUICLI", targets: ["TerminalUICLI"])
  ],
  dependencies: [
    .package(path: "../.."),
    .package(path: "../../Vendor/UnixSignals"),
  ],
  targets: [
    .target(
      name: "TerminalUICLI",
      dependencies: [
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
        .product(name: "UnixSignals", package: "UnixSignals"),
      ],
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "TerminalUICLITests",
      dependencies: [
        "TerminalUICLI",
        .product(name: "TerminalUI", package: "swift-terminal-ui")
      ],
      swiftSettings: swiftSettings()
    ),
  ],
  swiftLanguageModes: [.v6]
)
