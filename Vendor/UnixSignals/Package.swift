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
  name: "UnixSignals",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    .library(name: "UnixSignals", targets: ["UnixSignals"])
  ],
  dependencies: [
    .package(
      url: "https://github.com/apple/swift-async-algorithms.git",
      from: "1.1.3"
    )
  ],
  targets: [
    .target(
      name: "UnixSignals",
      dependencies: [
        .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
      ],
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "UnixSignalsTests",
      dependencies: [
        "UnixSignals",
        .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
      ],
      swiftSettings: swiftSettings()
    ),
  ],
  swiftLanguageModes: [.v6]
)
