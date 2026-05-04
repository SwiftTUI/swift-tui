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
  name: "SwiftTUIWASI",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(name: "SwiftTUIWASI", targets: ["SwiftTUIWASI"]),
    .library(name: "WASISurfaceBridge", targets: ["WASISurfaceBridge"]),
  ],
  dependencies: [
    .package(name: "swift-tui", path: "../..")
  ],
  targets: [
    .target(
      name: "WASISurfaceBridge",
      dependencies: [
        .product(name: "SwiftTUI", package: "swift-tui")
      ],
      swiftSettings: swiftSettings()
    ),
    .target(
      name: "SwiftTUIWASI",
      dependencies: [
        "WASISurfaceBridge",
        .product(name: "SwiftTUI", package: "swift-tui"),
      ],
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "WASISurfaceBridgeTests",
      dependencies: [
        "WASISurfaceBridge",
        .product(name: "SwiftTUI", package: "swift-tui"),
      ],
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "SwiftTUIWASITests",
      dependencies: [
        "SwiftTUIWASI",
        .product(name: "SwiftTUI", package: "swift-tui"),
      ],
      swiftSettings: swiftSettings()
    ),
  ],
  swiftLanguageModes: [.v6]
)
