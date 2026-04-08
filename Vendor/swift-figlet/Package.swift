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
        .executable(
            name: "figlet",
            targets: ["figlet"]
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
        .testTarget(
            name: "swift-figletTests",
            dependencies: ["swift-figlet"],
            exclude: [
                "Fixtures",
            ],
            swiftSettings: swiftSettings()
        ),
        .executableTarget(
            name: "figlet",
            dependencies: ["swift-figlet"],
            swiftSettings: swiftSettings()
        ),
    ],
    swiftLanguageModes: [.v6]
)
