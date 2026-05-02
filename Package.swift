// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

let nativeRuntimePlatforms: [PackageDescription.Platform] = [
  .macOS,
  .linux,
  .android,
  .iOS,
]

let explicitPlatforms = ProcessInfo.processInfo.environment["DISABLE_EXPLICIT_PLATFORMS"] != "1"

let packagePlatforms: [SupportedPlatform]? = {
  if !explicitPlatforms {
    return nil
  }

  return [
    .macOS(.v15),
    .iOS(.v18),
  ]
}()

let packageDependencies: [Package.Dependency] = [
  .package(
    url: "https://github.com/swiftlang/swift-docc-plugin.git",
    from: "1.4.6"
  ),
  .package(
    url: "https://github.com/apple/swift-collections.git",
    from: "1.4.1"
  ),
  .package(
    url: "https://github.com/apple/swift-async-algorithms.git",
    from: "1.1.3"
  ),
  .package(
    path: "Vendor/UnixSignals"
  ),
  .package(
    path: "Vendor/swift-figlet"
  ),
  .package(
    path: "Vendor/swift-gif"
  ),
  .package(
    path: "Vendor/swift-jpeg"
  ),
  .package(
    path: "Vendor/swift-png"
  ),
]

let swiftTUIDependencies: [Target.Dependency] = [
  "Core",
  "View",
  .product(name: "EmbeddedFonts", package: "swift-figlet"),
  .product(
    name: "UnixSignals",
    package: "UnixSignals",
    condition: .when(platforms: nativeRuntimePlatforms),
  ),
  .product(
    name: "GIF",
    package: "swift-gif"
  ),
  .product(
    name: "JPEG",
    package: "swift-jpeg"
  ),
  .product(
    name: "PNG",
    package: "swift-png"
  ),
]

let swiftTUITestDependencies: [Target.Dependency] = [
  "SwiftTUI",
  "Core",
  "View",
  "SwiftTUICharts",
  .product(
    name: "GIF",
    package: "swift-gif"
  ),
  .product(
    name: "JPEG",
    package: "swift-jpeg"
  ),
  .product(
    name: "PNG",
    package: "swift-png"
  ),
]

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
  name: "swift-tui",
  platforms: packagePlatforms,
  products: [
    .library(name: "View", targets: ["View"]),
    .library(name: "SwiftTUICharts", targets: ["SwiftTUICharts"]),
    .library(name: "SwiftTUI", targets: ["SwiftTUI"]),
  ],
  dependencies: packageDependencies,
  targets: [
    .target(
      name: "Core",
      dependencies: [
        .product(name: "DequeModule", package: "swift-collections"),
        .product(name: "OrderedCollections", package: "swift-collections"),
        .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
        .product(name: "SwiftFiglet", package: "swift-figlet"),
        .product(name: "EmbeddedFonts", package: "swift-figlet"),
      ],
      swiftSettings: swiftSettings()
    ),

    .target(
      name: "View",
      dependencies: [
        "Core",
        .product(name: "EmbeddedFonts", package: "swift-figlet"),
      ],
      swiftSettings: swiftSettings()
    ),

    .target(
      name: "SwiftTUICharts",
      dependencies: ["Core", "View"],
      swiftSettings: swiftSettings()
    ),

    .target(
      name: "SwiftTUI",
      dependencies: swiftTUIDependencies,
      resources: [],
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "CoreTests",
      dependencies: [
        "Core"
      ],
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "ViewTests",
      dependencies: [
        "Core",
        "View",
      ],
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "SwiftTUITests",
      dependencies: swiftTUITestDependencies,
      exclude: ["Fixtures"],
      swiftSettings: swiftSettings()
    ),
  ]
)
