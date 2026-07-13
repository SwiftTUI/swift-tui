// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

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
  "SwiftTUIVendorFigletEmbeddedFonts",
  "SwiftTUIVendorJPEG",
  "SwiftTUIVendorPNG",
]

let swiftTUITestDependencies: [Target.Dependency] = [
  "SwiftTUI",
  "SwiftTUIRuntime",
  "SwiftTUIProfiling",
  "SwiftTUICore",
  "SwiftTUIViews",
  "SwiftTUITestSupport",
  "SwiftTUIAnimatedImage",
  "SwiftTUIVendorJPEG",
  "SwiftTUIVendorPNG",
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

let packageProducts: [Product] =
  [
    .library(name: "SwiftTUIViews", targets: ["SwiftTUIViews"]),
    .library(name: "SwiftTUIRuntime", targets: ["SwiftTUIRuntime"]),
    .library(name: "SwiftTUIProfiling", targets: ["SwiftTUIProfiling"]),
    .library(name: "SwiftTUIAnimatedImage", targets: ["SwiftTUIAnimatedImage"]),
    .library(name: "SwiftTUI", targets: ["SwiftTUI"]),
    .library(name: "SwiftTUIArguments", targets: ["SwiftTUIArguments"]),
    .library(name: "SwiftTUIPTYPrimitives", targets: ["SwiftTUIPTYPrimitives"]),
    .library(name: "SwiftTUITerminal", targets: ["SwiftTUITerminal"]),
    .library(name: "SwiftTUITerminalWorkspace", targets: ["SwiftTUITerminalWorkspace"]),
    .library(name: "SwiftTUICLI", targets: ["SwiftTUICLI"]),
    .library(name: "SwiftTUIWASI", targets: ["SwiftTUIWASI"]),
    .library(name: "SwiftTUIWebHost", targets: ["SwiftTUIWebHost"]),
    .library(name: "SwiftTUIWebHostCLI", targets: ["SwiftTUIWebHostCLI"]),
    .library(name: "SwiftTUIAndroidHost", targets: ["SwiftTUIAndroidHost"]),
    // Exported so example packages can synchronize their tests on
    // the shared poll-free signals instead of timeout-based waiting.
    .library(name: "SwiftTUITestSupport", targets: ["SwiftTUITestSupport"]),
  ]

let package = Package(
  name: "swift-tui",
  platforms: packagePlatforms,
  products: packageProducts,
  dependencies: packageDependencies,
  targets: [
    .target(
      name: "SwiftTUIPrimitives",
      dependencies: [
        "SwiftTUIVendorFigletEmbeddedFonts"
      ],
      swiftSettings: swiftSettings()
    ),

    .target(
      name: "SwiftTUIGraph",
      dependencies: [
        "SwiftTUIPrimitives"
      ],
      swiftSettings: swiftSettings()
    ),

    .target(
      name: "SwiftTUICore",
      dependencies: [
        "SwiftTUIPrimitives",
        "SwiftTUIGraph",
        .product(name: "DequeModule", package: "swift-collections"),
        "SwiftTUIVendorFiglet",
        "SwiftTUIVendorFigletEmbeddedFonts",
      ],
      swiftSettings: swiftSettings()
    ),

    .target(
      name: "SwiftTUIViews",
      dependencies: [
        "SwiftTUICore",
        "SwiftTUIVendorFigletEmbeddedFonts",
      ],
      swiftSettings: swiftSettings()
    ),

    .target(
      name: "SwiftTUIAnimatedImage",
      dependencies: [
        "SwiftTUICore",
        "SwiftTUIViews",
        "SwiftTUIVendorGIF",
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
        "SwiftTUIArguments",
        "SwiftTUIRuntime",
        "SwiftTUIWebHostCLI",
      ],
      path: "Sources/SwiftTUI",
      swiftSettings: swiftSettings()
    ),
    .target(
      name: "SwiftTUIProfiling",
      dependencies: [
        "SwiftTUICore",
        "SwiftTUIRuntime",
      ],
      path: "Sources/SwiftTUIProfiling",
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
    // C shim that exposes `dladdr` to `EntryPointLaunchTests` so the suite can
    // resolve the loaded test-bundle path and locate sibling fixture
    // executables. `dladdr`/`Dl_info` are GNU extensions Swift's `Glibc`
    // overlay does not surface on Linux; the C side defines `_GNU_SOURCE` and
    // links `dl` so the symbol resolves on every platform.
    .target(
      name: "CEntryPointImageLocator",
      path: "Tests/CEntryPointImageLocator",
      linkerSettings: [
        .linkedLibrary("dl", .when(platforms: [.linux]))
      ]
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
        "SwiftTUIVendorUnixSignals",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Platforms/CLI/Sources/SwiftTUICLI",
      swiftSettings: swiftSettings()
    ),
    .target(
      name: "SwiftTUIWASISurfaceBridge",
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
        "SwiftTUIWASISurfaceBridge",
      ],
      path: "Platforms/WASI/Sources/SwiftTUIWASI",
      swiftSettings: swiftSettings()
    ),
    .target(
      name: "SwiftTUIWebHost",
      dependencies: [
        "SwiftTUIRuntime",
        "SwiftTUIWASISurfaceBridge",
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
      name: "SwiftTUIAndroidHost",
      dependencies: [
        "SwiftTUIRuntime"
      ],
      path: "Platforms/Android/Sources/SwiftTUIAndroidHost",
      swiftSettings: swiftSettings()
    ),
    .target(
      name: "SwiftTUITestSupport",
      dependencies: [
        // Lets the shared poll-free harness (recording surface + keep-open
        // input readers) drive a real RunLoop via the public/@_spi(Testing)
        // runtime surface instead of each test target re-declaring private
        // doubles. Runtime transitively pulls Core+Views; Core is named
        // directly for its public IR types (RasterSurface, CellSize, KeyPress…).
        "SwiftTUICore",
        "SwiftTUIRuntime",
      ],
      path: "Tests/Support",
      swiftSettings: swiftSettings()
    ),

    // -- Absorbed Vendor targets --
    // Sources remain under Vendor/<pkg>/ on disk; the per-Vendor Package.swift
    // files have been deleted. swift-tui now owns these modules as first-class
    // targets, so the package has no local-path subpackage dependencies and
    // can be consumed by external SwiftPM clients.
    //
    // Every absorbed target is named `SwiftTUIVendor<Upstream>`. SwiftPM
    // requires target names to be unique across the *whole* package graph, and
    // any target reachable from one of our products enters every consumer's
    // graph. Under their upstream names these modules are landmines: a consumer
    // that also depends on swift-service-lifecycle (which ships `UnixSignals`)
    // fails resolution outright with
    //
    //   error: multiple packages ('swift-service-lifecycle', 'swift-tui')
    //   declare targets with a conflicting name: 'UnixSignals'
    //
    // — and `GIF` / `JPEG` / `PNG` / `SwiftFiglet` are no safer. The prefix
    // makes a collision essentially impossible and makes the vendoring
    // decision legible at every use site: an `import SwiftTUIVendorPNG` is
    // self-evidently our copy, not upstream swift-png.
    //
    // Consequence for use sites: only the `import` line carries the vendored
    // name. `GIF`/`JPEG`/`PNG` each declare a `public enum` matching their old
    // module name, so `PNG.Image` and friends keep resolving to the enum.
    .target(
      name: "SwiftTUIVendorUnixSignals",
      dependencies: [
        .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
      ],
      path: "Vendor/UnixSignals/Sources/UnixSignals",
      swiftSettings: swiftSettings()
    ),
    .target(
      name: "SwiftTUIVendorFiglet",
      path: "Vendor/swift-figlet/Sources/SwiftFiglet",
      swiftSettings: swiftSettings()
    ),
    .target(
      name: "SwiftTUIVendorFigletEmbeddedFonts",
      dependencies: ["SwiftTUIVendorFiglet"],
      path: "Vendor/swift-figlet/Sources/EmbeddedFonts",
      swiftSettings: swiftSettings()
    ),
    .executableTarget(
      name: "SwiftTUIVendorFigletCLI",
      dependencies: ["SwiftTUIVendorFiglet", "SwiftTUIVendorFigletEmbeddedFonts"],
      path: "Vendor/swift-figlet/Sources/figlet",
      swiftSettings: swiftSettings()
    ),
    .target(
      name: "SwiftTUIVendorGIF",
      path: "Vendor/swift-gif/Sources/GIF",
      swiftSettings: swiftSettings()
    ),
    .target(
      name: "SwiftTUIVendorJPEG",
      path: "Vendor/swift-jpeg/Sources/JPEG",
      swiftSettings: swiftSettings()
    ),
    .target(
      name: "SwiftTUIVendorPNG",
      path: "Vendor/swift-png/Sources/PNG",
      swiftSettings: swiftSettings()
    ),

    // Launch-entry-point regression fixtures. Tiny executables that
    // `EntryPointLaunchTests` runs under a PTY to prove `@main` starts the
    // runtime and a bare `MyApp.main()` is rejected with a diagnostic. They are
    // build-order dependencies of that test target, not importable modules.
    .executableTarget(
      name: "EntryPointFixtureAtMain",
      dependencies: ["SwiftTUI"],
      path: "Tests/EntryPointLaunchFixtures/EntryPointFixtureAtMain",
      swiftSettings: swiftSettings()
    ),
    .executableTarget(
      name: "EntryPointFixtureBare",
      dependencies: ["SwiftTUI"],
      path: "Tests/EntryPointLaunchFixtures/EntryPointFixtureBare",
      swiftSettings: swiftSettings()
    ),
    .executableTarget(
      name: "EntryPointFixtureCLIBare",
      dependencies: ["SwiftTUICLI", "SwiftTUIArguments"],
      path: "Tests/EntryPointLaunchFixtures/EntryPointFixtureCLIBare",
      swiftSettings: swiftSettings()
    ),
    .executableTarget(
      name: "EntryPointFixtureWebHostCLIBare",
      dependencies: ["SwiftTUIWebHostCLI", "SwiftTUIArguments"],
      path: "Tests/EntryPointLaunchFixtures/EntryPointFixtureWebHostCLIBare",
      swiftSettings: swiftSettings()
    ),

    .testTarget(
      // The reconciliation-engine unit suites (F108): depends on
      // SwiftTUIGraph ONLY, so the engine's tests build and run without the
      // render stack — the compiler-enforced proof that the Phase 2b
      // boundary holds. Graph tests that need render types belong in
      // SwiftTUICoreTests (e.g. RetainedFrameStructuralIndexTests).
      name: "SwiftTUIGraphTests",
      dependencies: [
        "SwiftTUIGraph"
      ],
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "SwiftTUICoreTests",
      dependencies: [
        "SwiftTUICore",
        // A few Core suites still exercise graph-engine internals alongside
        // render types (RetainedFrameStructuralIndexTests, the legacy
        // source-parsing suites); depend on the module so
        // `@testable import SwiftTUIGraph` stays available. Engine-only
        // suites live in SwiftTUIGraphTests.
        "SwiftTUIGraph",
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
      name: "SwiftTUIProfilingTests",
      dependencies: [
        "SwiftTUIProfiling",
        "SwiftTUIRuntime",
        "SwiftTUICore",
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
      name: "SwiftTUIWASISurfaceBridgeTests",
      dependencies: [
        "SwiftTUI",
        "SwiftTUIWASISurfaceBridge",
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
      name: "SwiftTUIAndroidHostTests",
      dependencies: [
        "SwiftTUIAndroidHost",
        "SwiftTUIRuntime",
      ],
      path: "Platforms/Android/Tests/SwiftTUIAndroidHostTests",
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
    .testTarget(
      name: "EntryPointLaunchTests",
      dependencies: [
        "SwiftTUIArguments",
        "SwiftTUICore",
        "SwiftTUIPTYPrimitives",
        "SwiftTUITerminal",
        "CEntryPointImageLocator",
        // The EntryPointFixture* executables are deliberately NOT
        // dependencies. Depending on an executable target links its `main`
        // into the package test runner, and under `-c release` a fixture's
        // entry point wins the binary's `_main` — every
        // `swift test -c release` then launches the fixture CLI instead of
        // the test runner (found by the release soundness lane, F05). The
        // suite locates the fixture binaries on disk; the gate builds them
        // explicitly first (Scripts/test_all.sh, "Build entry-point launch
        // fixtures").
      ],
      path: "Tests/EntryPointLaunchTests",
      swiftSettings: swiftSettings()
    ),

    // -- Absorbed Vendor test targets --
    .testTarget(
      name: "SwiftTUIVendorUnixSignalsTests",
      dependencies: [
        "SwiftTUIVendorUnixSignals",
        .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
      ],
      path: "Vendor/UnixSignals/Tests/UnixSignalsTests",
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "SwiftTUIVendorFigletTests",
      dependencies: ["SwiftTUIVendorFiglet", "SwiftTUIVendorFigletEmbeddedFonts"],
      path: "Vendor/swift-figlet/Tests/SwiftFigletTests",
      exclude: ["Fixtures"],
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "SwiftTUIVendorGIFTests",
      dependencies: ["SwiftTUIVendorGIF"],
      path: "Vendor/swift-gif/Sources/GIFTests",
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "SwiftTUIVendorJPEGTests",
      dependencies: ["SwiftTUIVendorJPEG"],
      path: "Vendor/swift-jpeg/Sources/JPEGTests",
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "SwiftTUIVendorPNGTests",
      dependencies: ["SwiftTUIVendorPNG"],
      path: "Vendor/swift-png/Sources/PNGTests",
      swiftSettings: swiftSettings()
    ),
  ]
)
