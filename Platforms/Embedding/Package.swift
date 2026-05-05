// swift-tools-version: 6.3

import PackageDescription

func swiftSettings(_ settings: SwiftSetting...) -> [SwiftSetting] {
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
  name: "swift-tui-embedding",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(name: "SwiftTUIPTYPrimitives", targets: ["SwiftTUIPTYPrimitives"]),
    .library(name: "SwiftTUITerminal", targets: ["SwiftTUITerminal"]),
  ],
  dependencies: [
    .package(name: "swift-tui", path: "../.."),
    .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
  ],
  targets: [
    .target(
      name: "SwiftTUIPTYPrimitives",
      dependencies: [
        .product(name: "SwiftTUI", package: "swift-tui")
      ],
      swiftSettings: swiftSettings()
    ),
    .target(
      name: "SwiftTUITerminal",
      dependencies: [
        "SwiftTUIPTYPrimitives",
        .product(name: "SwiftTUI", package: "swift-tui"),
        .product(name: "SwiftTerm", package: "SwiftTerm"),
      ],
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "SwiftTUITerminalTests",
      dependencies: ["SwiftTUITerminal"],
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "SwiftTUIPTYPrimitivesTests",
      dependencies: [
        "SwiftTUIPTYPrimitives",
        .product(name: "SwiftTUI", package: "swift-tui"),
      ],
      swiftSettings: swiftSettings()
    ),
  ],
  swiftLanguageModes: [.v6]
)
