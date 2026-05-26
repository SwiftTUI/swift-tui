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
    url: "https://github.com/apple/swift-argument-parser.git",
    from: "1.5.0"
  ),
  .package(
    url: "https://github.com/migueldeicaza/SwiftTerm.git",
    from: "1.2.0"
  ),
  .package(
    url: "https://github.com/swhitty/FlyingFox.git",
    from: "0.26.0"
  ),
]

let swiftTUIRuntimeDependencies: [Target.Dependency] = [
  "SwiftTUICore",
  "SwiftTUIViews",
  "EmbeddedFonts",
  "JPEG",
  "PNG",
]

let swiftTUITestDependencies: [Target.Dependency] = [
  "SwiftTUI",
  "SwiftTUIRuntime",
  "SwiftTUICore",
  "SwiftTUIViews",
  "SwiftTUITestSupport",
  "SwiftTUIAnimatedImage",
  "SwiftTUICharts",
  "JPEG",
  "PNG",
]

#if os(Linux)
  let includeSwiftUIHost = false
#else
  let includeSwiftUIHost = true
#endif

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

let packageProducts: [Product] =
  [
    .library(name: "SwiftTUIViews", targets: ["SwiftTUIViews"]),
    .library(name: "SwiftTUIRuntime", targets: ["SwiftTUIRuntime"]),
    .library(name: "SwiftTUIAnimatedImage", targets: ["SwiftTUIAnimatedImage"]),
    .library(name: "SwiftTUICharts", targets: ["SwiftTUICharts"]),
    .library(name: "SwiftTUI", targets: ["SwiftTUI"]),
    .library(name: "SwiftTUIArguments", targets: ["SwiftTUIArguments"]),
    .library(name: "SwiftTUIPTYPrimitives", targets: ["SwiftTUIPTYPrimitives"]),
    .library(name: "SwiftTUITerminal", targets: ["SwiftTUITerminal"]),
    .library(name: "SwiftTUITerminalWorkspace", targets: ["SwiftTUITerminalWorkspace"]),
    .library(name: "SwiftTUICLI", targets: ["SwiftTUICLI"]),
    .library(name: "SwiftTUIWASI", targets: ["SwiftTUIWASI"]),
    .library(name: "SwiftTUIWebHost", targets: ["SwiftTUIWebHost"]),
    .library(name: "SwiftTUIWebHostCLI", targets: ["SwiftTUIWebHostCLI"]),
    // Exported so example packages can synchronise their tests on
    // the shared poll-free signals instead of timeout-based waiting.
    .library(name: "SwiftTUITestSupport", targets: ["SwiftTUITestSupport"]),
  ]
  + (includeSwiftUIHost
    ? [
      .library(name: "SwiftUIHost", targets: ["SwiftUIHost"])
    ]
    : [])

let package = Package(
  name: "swift-tui",
  platforms: packagePlatforms,
  products: packageProducts,
  dependencies: packageDependencies,
  targets: [
    .target(
      name: "SwiftTUICore",
      dependencies: [
        .product(name: "DequeModule", package: "swift-collections"),
        .product(name: "OrderedCollections", package: "swift-collections"),
        .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
        "SwiftFiglet",
        "EmbeddedFonts",
      ],
      swiftSettings: swiftSettings()
    ),

    .target(
      name: "SwiftTUIViews",
      dependencies: [
        "SwiftTUICore",
        "EmbeddedFonts",
      ],
      swiftSettings: swiftSettings()
    ),

    .target(
      name: "SwiftTUICharts",
      dependencies: ["SwiftTUICore", "SwiftTUIViews"],
      swiftSettings: swiftSettings()
    ),

    .target(
      name: "SwiftTUIAnimatedImage",
      dependencies: [
        "SwiftTUICore",
        "SwiftTUIViews",
        "GIF",
      ],
      swiftSettings: swiftSettings()
    ),

    .target(
      name: "SwiftTUIRuntime",
      dependencies: swiftTUIRuntimeDependencies,
      path: "Sources/SwiftTUIRuntime",
      resources: [],
      swiftSettings: swiftSettings()
    ),
    .target(
      name: "SwiftTUI",
      dependencies: [
        "SwiftTUIAnimatedImage",
        "SwiftTUIWebHostCLI",
      ],
      path: "Sources/SwiftTUI",
      swiftSettings: swiftSettings()
    ),
    .target(
      name: "SwiftTUIArguments",
      dependencies: [
        "SwiftTUIRuntime",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Platforms/Arguments/Sources/SwiftTUIArguments",
      swiftSettings: swiftSettings()
    ),
    .target(
      name: "SwiftTUIPTYCPrimitives",
      path: "Platforms/Embedding/Sources/SwiftTUIPTYCPrimitives"
    ),
    .target(
      name: "SwiftTUIPTYPrimitives",
      dependencies: [
        "SwiftTUICore"
      ],
      path: "Platforms/Embedding/Sources/SwiftTUIPTYPrimitives",
      swiftSettings: swiftSettings()
    ),
    .target(
      name: "SwiftTUITerminal",
      dependencies: [
        "SwiftTUIRuntime",
        "SwiftTUIPTYPrimitives",
        "SwiftTUIPTYCPrimitives",
        .product(name: "SwiftTerm", package: "SwiftTerm"),
      ],
      path: "Platforms/Embedding/Sources/SwiftTUITerminal",
      swiftSettings: swiftSettings()
    ),
    .target(
      name: "SwiftTUITerminalWorkspace",
      dependencies: [
        "SwiftTUIRuntime",
        "SwiftTUITerminal",
      ],
      path: "Platforms/Embedding/Sources/SwiftTUITerminalWorkspace",
      swiftSettings: swiftSettings()
    ),
    .target(
      name: "SwiftTUICLI",
      dependencies: [
        "SwiftTUIRuntime",
        "SwiftTUIArguments",
        "SwiftTUIPTYPrimitives",
        "UnixSignals",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Platforms/CLI/Sources/SwiftTUICLI",
      swiftSettings: swiftSettings()
    ),
    .target(
      name: "WASISurfaceBridge",
      dependencies: [
        "SwiftTUIRuntime"
      ],
      path: "Platforms/WASI/Sources/WASISurfaceBridge",
      swiftSettings: swiftSettings()
    ),
    .target(
      name: "SwiftTUIWASI",
      dependencies: [
        "SwiftTUIRuntime",
        "WASISurfaceBridge",
      ],
      path: "Platforms/WASI/Sources/SwiftTUIWASI",
      swiftSettings: swiftSettings()
    ),
    .target(
      name: "SwiftTUIWebHost",
      dependencies: [
        "SwiftTUIRuntime",
        "WASISurfaceBridge",
        .product(name: "FlyingFox", package: "FlyingFox"),
        .product(name: "FlyingSocks", package: "FlyingFox"),
      ],
      path: "Platforms/WebHost/Sources/SwiftTUIWebHost",
      resources: [
        .copy("Resources/browser")
      ],
      swiftSettings: swiftSettings()
    ),
    .target(
      name: "SwiftTUIWebHostCLI",
      dependencies: [
        "SwiftTUIRuntime",
        "SwiftTUICLI",
        "SwiftTUIArguments",
        "SwiftTUIWebHost",
      ],
      path: "Platforms/WebHost/Sources/SwiftTUIWebHostCLI",
      swiftSettings: swiftSettings()
    ),
    .target(
      name: "SwiftTUITestSupport",
      path: "Tests/Support",
      swiftSettings: swiftSettings()
    ),

    // -- Absorbed Vendor targets --
    // Sources remain under Vendor/<pkg>/ on disk; the per-Vendor Package.swift
    // files have been deleted. swift-tui now owns these modules as first-class
    // targets, so the package has no local-path subpackage dependencies and
    // can be consumed by external SwiftPM clients.
    .target(
      name: "UnixSignals",
      dependencies: [
        .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
      ],
      path: "Vendor/UnixSignals/Sources/UnixSignals",
      swiftSettings: swiftSettings()
    ),
    .target(
      name: "SwiftFiglet",
      path: "Vendor/swift-figlet/Sources/SwiftFiglet",
      swiftSettings: swiftSettings()
    ),
    .target(
      name: "EmbeddedFonts",
      dependencies: ["SwiftFiglet"],
      path: "Vendor/swift-figlet/Sources/EmbeddedFonts",
      swiftSettings: swiftSettings()
    ),
    .executableTarget(
      name: "figlet",
      dependencies: ["SwiftFiglet", "EmbeddedFonts"],
      path: "Vendor/swift-figlet/Sources/figlet",
      swiftSettings: swiftSettings()
    ),
    .target(
      name: "GIF",
      path: "Vendor/swift-gif/Sources/GIF",
      swiftSettings: swiftSettings()
    ),
    .target(
      name: "JPEG",
      path: "Vendor/swift-jpeg/Sources/JPEG",
      swiftSettings: swiftSettings()
    ),
    .target(
      name: "PNG",
      path: "Vendor/swift-png/Sources/PNG",
      swiftSettings: swiftSettings()
    ),

    .testTarget(
      name: "SwiftTUICoreTests",
      dependencies: [
        "SwiftTUICore"
      ],
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "SwiftTUIViewsTests",
      dependencies: [
        "SwiftTUICore",
        "SwiftTUIViews",
      ],
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "SwiftTUITests",
      dependencies: swiftTUITestDependencies,
      exclude: [
        "Accessibility/README.md",
        "Fixtures",
      ],
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "SwiftTUIArgumentsTests",
      dependencies: [
        "SwiftTUI",
        "SwiftTUIArguments",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Platforms/Arguments/Tests/SwiftTUIArgumentsTests",
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "SwiftTUICLITests",
      dependencies: [
        "SwiftTUI",
        "SwiftTUIArguments",
        "SwiftTUICLI",
        "SwiftTUIPTYPrimitives",
        "SwiftTUITestSupport",
      ],
      path: "Platforms/CLI/Tests/SwiftTUICLITests",
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "SwiftTUIPTYPrimitivesTests",
      dependencies: [
        "SwiftTUI",
        "SwiftTUIPTYPrimitives",
      ],
      path: "Platforms/Embedding/Tests/SwiftTUIPTYPrimitivesTests",
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "SwiftTUITerminalTests",
      dependencies: [
        "SwiftTUI",
        "SwiftTUICore",
        "SwiftTUITestSupport",
        "SwiftTUIPTYPrimitives",
        "SwiftTUITerminal",
      ],
      path: "Platforms/Embedding/Tests/SwiftTUITerminalTests",
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "SwiftTUITerminalWorkspaceTests",
      dependencies: [
        "SwiftTUI",
        "SwiftTUICore",
        "SwiftTUITerminal",
        "SwiftTUITerminalWorkspace",
      ],
      path: "Platforms/Embedding/Tests/SwiftTUITerminalWorkspaceTests",
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "WASISurfaceBridgeTests",
      dependencies: [
        "SwiftTUI",
        "WASISurfaceBridge",
      ],
      path: "Platforms/WASI/Tests/WASISurfaceBridgeTests",
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "SwiftTUIWASITests",
      dependencies: [
        "SwiftTUI",
        "SwiftTUIWASI",
      ],
      path: "Platforms/WASI/Tests/SwiftTUIWASITests",
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "SwiftTUIWebHostTests",
      dependencies: [
        "SwiftTUI",
        "SwiftTUICLI",
        "SwiftTUIWebHost",
        "SwiftTUIWebHostCLI",
        "SwiftTUITestSupport",
      ],
      path: "Platforms/WebHost/Tests/SwiftTUIWebHostTests",
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "SwiftTUIAnimatedImageTests",
      dependencies: [
        "SwiftTUIAnimatedImage",
        "SwiftTUI",
        "SwiftTUITestSupport",
      ],
      swiftSettings: swiftSettings()
    ),

    // -- Absorbed Vendor test targets --
    .testTarget(
      name: "UnixSignalsTests",
      dependencies: [
        "UnixSignals",
        .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
      ],
      path: "Vendor/UnixSignals/Tests/UnixSignalsTests",
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "SwiftFigletTests",
      dependencies: ["SwiftFiglet", "EmbeddedFonts"],
      path: "Vendor/swift-figlet/Tests/SwiftFigletTests",
      exclude: ["Fixtures"],
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "GIFTests",
      dependencies: ["GIF"],
      path: "Vendor/swift-gif/Sources/GIFTests",
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "JPEGTests",
      dependencies: ["JPEG"],
      path: "Vendor/swift-jpeg/Sources/JPEGTests",
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "PNGTests",
      dependencies: ["PNG"],
      path: "Vendor/swift-png/Sources/PNGTests",
      swiftSettings: swiftSettings()
    ),
  ]
    + (includeSwiftUIHost
      ? [
        .target(
          name: "SwiftUIHost",
          dependencies: [
            "SwiftTUIRuntime"
          ],
          path: "Platforms/SwiftUI/Sources/SwiftUIHost",
          resources: [
            .process("Resources")
          ],
          swiftSettings: swiftSettings()
        ),
        .testTarget(
          name: "SwiftUIHostTests",
          dependencies: [
            "SwiftTUI",
            "SwiftTUITestSupport",
            "SwiftUIHost",
          ],
          path: "Platforms/SwiftUI/Tests/SwiftUIHostTests",
          swiftSettings: swiftSettings()
        ),
      ]
      : [])
)
