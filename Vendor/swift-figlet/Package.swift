// swift-tools-version: 6.3

import PackageDescription

func swiftSettings(_ settings: PackageDescription.SwiftSetting...) -> [PackageDescription
  .SwiftSetting]
{
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
  name: "swift-figlet",
  products: [
    .library(
      name: "SwiftFiglet",
      targets: ["SwiftFiglet"]
    ),
    .library(
      name: "EmbeddedFonts",
      targets: ["EmbeddedFonts"]
    ),
    .executable(
      name: "figlet",
      targets: ["figlet"]
    ),
  ],
  targets: [
    .target(
      name: "SwiftFiglet",
      swiftSettings: swiftSettings()
    ),
    .target(
      name: "EmbeddedFonts",
      dependencies: ["SwiftFiglet"],
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "SwiftFigletTests",
      dependencies: [
        "SwiftFiglet",
        "EmbeddedFonts",
      ],
      exclude: [
        "Fixtures"
      ],
      swiftSettings: swiftSettings()
    ),
    .executableTarget(
      name: "figlet",
      dependencies: [
        "SwiftFiglet",
        "EmbeddedFonts",
      ],
      swiftSettings: swiftSettings()
    ),
  ],
  swiftLanguageModes: [.v6]
)
