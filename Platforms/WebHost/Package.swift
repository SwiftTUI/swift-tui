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
  name: "SwiftTUIWebHost",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(name: "SwiftTUIWebHost", targets: ["SwiftTUIWebHost"]),
    .library(name: "SwiftTUIWebHostCLI", targets: ["SwiftTUIWebHostCLI"]),
  ],
  dependencies: [
    .package(name: "swift-tui", path: "../.."),
    .package(name: "SwiftTUIWASI", path: "../WASI"),
    .package(name: "SwiftTUICLI", path: "../CLI"),
    .package(name: "SwiftTUIArguments", path: "../Arguments"),
    .package(url: "https://github.com/swhitty/FlyingFox.git", from: "0.26.0"),
  ],
  targets: [
    .target(
      name: "SwiftTUIWebHost",
      dependencies: [
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "WASISurfaceBridge", package: "SwiftTUIWASI"),
        .product(name: "FlyingFox", package: "FlyingFox"),
        .product(name: "FlyingSocks", package: "FlyingFox"),
      ],
      resources: [
        .copy("Resources/browser")
      ],
      swiftSettings: swiftSettings()
    ),
    .target(
      name: "SwiftTUIWebHostCLI",
      dependencies: [
        "SwiftTUIWebHost",
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTUICLI", package: "SwiftTUICLI"),
        .product(name: "SwiftTUIArguments", package: "SwiftTUIArguments"),
      ],
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "SwiftTUIWebHostTests",
      dependencies: [
        "SwiftTUIWebHost",
        "SwiftTUIWebHostCLI",
        .product(name: "SwiftTUICLI", package: "SwiftTUICLI"),
      ],
      swiftSettings: swiftSettings()
    ),
  ],
  swiftLanguageModes: [.v6]
)
