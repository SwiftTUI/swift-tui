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
  name: "TerminalUIWASI",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(name: "TerminalUIWASI", targets: ["TerminalUIWASI"])
  ],
  dependencies: [
    .package(name: "swift-terminal-ui", path: "../..")
  ],
  targets: [
    .target(
      name: "TerminalUIWASI",
      dependencies: [
        .product(name: "TerminalUI", package: "swift-terminal-ui")
      ],
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "TerminalUIWASITests",
      dependencies: [
        "TerminalUIWASI",
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
      ],
      swiftSettings: swiftSettings()
    ),
  ],
  swiftLanguageModes: [.v6]
)
