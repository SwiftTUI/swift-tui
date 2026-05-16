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

let swiftTUIRuntimeDependencies: [Target.Dependency] = [
  "SwiftTUICore",
  "SwiftTUIViews",
  .product(name: "EmbeddedFonts", package: "swift-figlet"),
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
  "SwiftTUIRuntime",
  "SwiftTUICore",
  "SwiftTUIViews",
  "SwiftTUIAnimatedImage",
  "SwiftTUICharts",
  .product(
    name: "JPEG",
    package: "swift-jpeg"
  ),
  .product(
    name: "PNG",
    package: "swift-png"
  ),
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
        .product(name: "SwiftFiglet", package: "swift-figlet"),
        .product(name: "EmbeddedFonts", package: "swift-figlet"),
      ],
      swiftSettings: swiftSettings()
    ),

    .target(
      name: "SwiftTUIViews",
      dependencies: [
        "SwiftTUICore",
        .product(name: "EmbeddedFonts", package: "swift-figlet"),
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
        .product(name: "GIF", package: "swift-gif"),
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
        "SwiftTUIRuntime",
        "SwiftTUIArguments",
        "SwiftTUICLI",
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
        .product(name: "UnixSignals", package: "UnixSignals"),
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
      ],
      path: "Platforms/WebHost/Tests/SwiftTUIWebHostTests",
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "SwiftTUIAnimatedImageTests",
      dependencies: [
        "SwiftTUIAnimatedImage",
        "SwiftTUI",
      ],
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
            "SwiftUIHost",
          ],
          path: "Platforms/SwiftUI/Tests/SwiftUIHostTests",
          swiftSettings: swiftSettings()
        ),
      ]
      : [])
)
