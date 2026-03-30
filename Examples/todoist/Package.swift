// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "todoist-demo",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .executable(
      name: "todoist-demo",
      targets: ["TodoistDemo"]
    )
  ],
  dependencies: [
    .package(path: "../.."),
    .package(path: "Packages/swift-todoist"),
    .package(
      url: "https://github.com/pointfreeco/swift-structured-queries.git",
      from: "0.31.0"
    ),
    .package(
      url: "https://github.com/groue/GRDB.swift.git",
      from: "7.10.0"
    ),
  ],
  targets: [
    .executableTarget(
      name: "TodoistDemo",
      dependencies: [
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
        .product(name: "TerminalUIScenes", package: "swift-terminal-ui"),
        .product(name: "TodoistAPI", package: "swift-todoist"),
        .product(name: "StructuredQueries", package: "swift-structured-queries"),
        .product(name: "StructuredQueriesSQLite", package: "swift-structured-queries"),
        .product(name: "GRDB", package: "GRDB.swift"),
      ]
    ),
    .testTarget(
      name: "TodoistDemoTests",
      dependencies: [
        "TodoistDemo",
        .product(name: "TerminalUI", package: "swift-terminal-ui"),
      ]
    )
  ]
)
