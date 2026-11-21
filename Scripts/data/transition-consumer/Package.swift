// swift-tools-version: 6.4

import PackageDescription

// An external consumer of the `Transition` surface (STUI-1543, STUI-1546).
//
// `Scripts/check_transition_consumer.sh` copies this package out of the tree,
// builds it against the checkout and runs its tests. The library target
// depends on the `SwiftTUIViews` product alone and uses the Swift settings
// the SwiftTUI library repositories use (the `swift-tui-charts` manifest is
// the model), so it compiles as a third-party transition library would. It
// holds the transition surface (`TransitionSurface.swift`) and six
// demonstration transitions (`Demonstrations/`).
//
// `TransitionConsumerTests` frame-tests the demonstrations through the public
// one-shot renderer, and `TransitionShowcase` is a terminal app that plays
// one of them for a recording. Both depend on the `SwiftTUI` product, as an
// application that uses the library would.
//
// The framework is this checkout, three directories up. The gate script
// copies the package to a directory at the same depth, so the same literal
// path reaches the checkout from the copy.

let consumerSwiftSettings: [SwiftSetting] = [
  .swiftLanguageMode(.v6),
  .strictMemorySafety(),
  .defaultIsolation(.none),
  .enableUpcomingFeature("ExistentialAny"),
  .enableUpcomingFeature("ImmutableWeakCaptures"),
  .enableUpcomingFeature("InternalImportsByDefault"),
  .enableUpcomingFeature("MemberImportVisibility"),
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
  name: "TransitionConsumer",
  platforms: [.macOS(.v15), .iOS(.v18)],
  products: [
    .library(name: "TransitionConsumer", targets: ["TransitionConsumer"]),
    .executable(name: "transition-showcase", targets: ["TransitionShowcase"]),
  ],
  dependencies: [
    .package(name: "swift-tui", path: "../../..")
  ],
  targets: [
    .target(
      name: "TransitionConsumer",
      dependencies: [
        .product(name: "SwiftTUIViews", package: "swift-tui")
      ],
      swiftSettings: consumerSwiftSettings
    ),
    .executableTarget(
      name: "TransitionShowcase",
      dependencies: [
        "TransitionConsumer",
        .product(name: "SwiftTUI", package: "swift-tui"),
      ],
      swiftSettings: consumerSwiftSettings
    ),
    .testTarget(
      name: "TransitionConsumerTests",
      dependencies: [
        "TransitionConsumer",
        .product(name: "SwiftTUI", package: "swift-tui"),
      ],
      swiftSettings: consumerSwiftSettings
    ),
  ]
)
