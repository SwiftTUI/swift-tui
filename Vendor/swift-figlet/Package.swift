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
            name: "swift-figlet",
            targets: ["swift-figlet"]
        ),
        .library(
            name: "swift-figlet-embedded-fonts",
            targets: ["swift-figlet-embedded-fonts"]
        ),
        .executable(
            name: "figlet",
            targets: ["figlet"]
        ),
        .executable(
            name: "figlet-embedded",
            targets: ["figlet-embedded"]
        )
    ],
    targets: [
        .target(
            name: "swift-figlet",
            exclude: [
                "Resources",
            ],
            swiftSettings: swiftSettings()
        ),
        .target(
            name: "swift-figlet-embedded-fonts",
            dependencies: ["swift-figlet"],
            swiftSettings: swiftSettings()
        ),
        .target(
            name: "figlet-cli",
            dependencies: ["swift-figlet"],
            swiftSettings: swiftSettings()
        ),
        .testTarget(
            name: "swift-figletTests",
            dependencies: [
                "swift-figlet",
                "swift-figlet-embedded-fonts",
            ],
            exclude: [
                "Fixtures",
            ],
            swiftSettings: swiftSettings()
        ),
        .executableTarget(
            name: "figlet",
            dependencies: ["figlet-cli"],
            swiftSettings: swiftSettings()
        ),
        .executableTarget(
            name: "figlet-embedded",
            dependencies: [
                "figlet-cli",
                "swift-figlet-embedded-fonts",
            ],
            swiftSettings: swiftSettings()
        ),
    ],
    swiftLanguageModes: [.v6]
)
