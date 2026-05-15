// swift-tools-version: 6.3

import PackageDescription

// SwiftUI port of `Examples/layouts`. The intent is to render the same
// 56 layout-shape examples in real SwiftUI so the BEHAVIOUR_FINDINGS
// observations can be compared side-by-side with the embedded SwiftTUI
// implementation. This package deliberately drops the test target
// from the original — the original tests rasterise via SwiftTUI's
// `DefaultRenderer` / `RasterSurface`, which has no SwiftUI public
// equivalent.
let package = Package(
  name: "layouts-swiftui-demo",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    .executable(
      name: "layouts-swiftui-demo",
      targets: ["SwiftUILayoutsApp"]
    ),
    .library(
      name: "SwiftUILayouts",
      targets: ["SwiftUILayouts"]
    ),
  ],
  dependencies: [
    .package(name: "swift-tui", path: "../.."),
    .package(name: "layouts-demo", path: "../layouts"),
  ],
  targets: [
    .executableTarget(
      name: "SwiftUILayoutsApp",
      dependencies: [
        "SwiftUILayouts",
        .product(name: "Layouts", package: "layouts-demo"),
        .product(name: "SwiftTUIRuntime", package: "swift-tui"),
        .product(name: "SwiftUIHost", package: "swift-tui"),
      ],
      path: "Sources/LayoutsApp"
    ),
    .target(
      name: "SwiftUILayouts",
      dependencies: [],
      path: "Sources/Layouts"
    ),
  ]
)
