// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let nativeRuntimePlatforms: [PackageDescription.Platform] = [
  .macOS,
  .linux,
  .android,
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
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    .library(name: "View", targets: ["View"]),
    .library(name: "TerminalUICharts", targets: ["TerminalUICharts"]),
    .library(name: "TerminalUI", targets: ["TerminalUI"]),
    .library(name: "TerminalUIScenes", targets: ["TerminalUIScenes"]),
  ],
  dependencies: [
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
      url: "https://github.com/apple/swift-atomics.git",
      from: "1.3.0"
    ),
    .package(
      url: "https://github.com/tayloraswift/swift-png.git",
      exact: "4.4.9"
    ),
  ],
  targets: [
    .target(
      name: "UnixSignals",
      dependencies: [
        .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
      ],
      path: "Sources/Vendor/UnixSignals",
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "UnixSignalsTests",
      dependencies: [
        "UnixSignals",
        .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
      ],
      path: "Sources/Vendor/UnixSignalsTests",
      swiftSettings: swiftSettings()
    ),
    .target(
      name: "Core",
      dependencies: [
        .product(name: "Atomics", package: "swift-atomics"),
        .product(name: "DequeModule", package: "swift-collections"),
        .product(name: "OrderedCollections", package: "swift-collections"),
        .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
      ],
      swiftSettings: swiftSettings()
    ),

    .target(
      name: "View",
      dependencies: ["Core"],
      swiftSettings: swiftSettings()
    ),

    .target(
      name: "PrototypeUIComponents",
      dependencies: ["View"],
      swiftSettings: swiftSettings()
    ),

    .target(
      name: "TerminalUICharts",
      dependencies: ["Core", "View"],
      swiftSettings: swiftSettings()
    ),

    .target(
      name: "TerminalUI",
      dependencies: [
        "Core",
        "View",
        .target(
          name: "UnixSignals",
          condition: .when(platforms: nativeRuntimePlatforms)
        ),
        .product(name: "PNG", package: "swift-png"),
      ],
      resources: [],
      swiftSettings: swiftSettings()
    ),
    .target(
      name: "TerminalUIScenes",
      dependencies: [
        "TerminalUI",
        .target(
          name: "UnixSignals",
          condition: .when(platforms: nativeRuntimePlatforms)
        ),
      ],
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
        "TerminalUI",
      ],
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "PrototypeUIComponentsTests",
      dependencies: [
        "PrototypeUIComponents",
        "TerminalUI",
      ],
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "TerminalUITests",
      dependencies: [
        "TerminalUI",
        "Core",
        "View",
        "TerminalUIScenes",
        "TerminalUICharts",
        .product(name: "PNG", package: "swift-png"),
      ],
      exclude: ["Fixtures"],
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "TerminalUIScenesTests",
      dependencies: [
        "TerminalUIScenes",
        "TerminalUI",
        "Core",
        "View",
      ],
      swiftSettings: swiftSettings()
    ),
  ]
)
