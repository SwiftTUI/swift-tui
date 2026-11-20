// swift-tools-version: 6.4

import PackageDescription

// An external consumer of the `Transition` surface (STUI-1543).
//
// `Scripts/check_transition_consumer.sh` copies this package out of the tree
// and builds it against the checkout. The library target depends on the
// `SwiftTUIViews` product alone and uses the Swift settings the SwiftTUI
// library repositories use (the `swift-tui-charts` manifest is the model), so
// it compiles as a third-party transition library would.
//
// The framework is found through `SWIFTTUI_PACKAGE_PATH`, which the gate
// script sets to the checkout. The default is the path from this directory.
let swiftTUIPath = Context.environment["SWIFTTUI_PACKAGE_PATH"] ?? "../../.."

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
    .library(name: "TransitionConsumer", targets: ["TransitionConsumer"])
  ],
  dependencies: [
    .package(name: "swift-tui", path: swiftTUIPath)
  ],
  targets: [
    .target(
      name: "TransitionConsumer",
      dependencies: [
        .product(name: "SwiftTUIViews", package: "swift-tui")
      ],
      swiftSettings: consumerSwiftSettings
    )
  ]
)
