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
  .package(path: "Vendor/UnixSignals"),
  .package(path: "Vendor/swift-figlet"),
  .package(url: "https://github.com/swiftlang/swift-docc-plugin.git", from: "1.4.6"),
  .package(
    url: "https://github.com/apple/swift-collections.git",
    from: "1.4.1"
  ),
  .package(
    url: "https://github.com/apple/swift-async-algorithms.git",
    from: "1.1.3"
  ),
  .package(
    path: "Vendor/swift-jpeg"
  ),
  .package(
    path: "Vendor/swift-gif"
  ),
]

let terminalUIDependencies: [Target.Dependency] = [
  "Core",
  "View",
  .product(name: "EmbeddedFonts", package: "swift-figlet"),
  .product(
    name: "UnixSignals",
    package: "UnixSignals",
    condition: .when(platforms: nativeRuntimePlatforms),
  ),
  .product(
    name: "JPEG",
    package: "swift-jpeg"
  ),
  .product(
    name: "GIF",
    package: "swift-gif"
  ),
]

let terminalUITestDependencies: [Target.Dependency] = [
  "TerminalUI",
  "Core",
  "View",
  "TerminalUICharts",
  .product(
    name: "JPEG",
    package: "swift-jpeg"
  ),
  .product(
    name: "GIF",
    package: "swift-gif"
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
  name: "swift-terminal-ui",
  platforms: packagePlatforms,
  products: [
    .library(name: "View", targets: ["View"]),
    .library(name: "TerminalUICharts", targets: ["TerminalUICharts"]),
    .library(name: "TerminalUI", targets: ["TerminalUI"]),
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
      name: "TerminalUICharts",
      dependencies: ["Core", "View"],
      swiftSettings: swiftSettings()
    ),

    .target(
      name: "TerminalUI",
      dependencies: terminalUIDependencies,
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
      name: "TerminalUITests",
      dependencies: terminalUITestDependencies,
      exclude: ["Fixtures"],
      swiftSettings: swiftSettings()
    ),
  ]
)
