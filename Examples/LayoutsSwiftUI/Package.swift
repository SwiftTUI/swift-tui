// swift-tools-version: 6.3

import PackageDescription

// SwiftUI port of `Examples/layouts`. The intent is to render the same
// 56 layout-shape examples in real SwiftUI so the BEHAVIOUR_FINDINGS
// observations can be compared side-by-side against an authoritative
// SwiftUI reference. This package deliberately drops the test target
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
      targets: ["LayoutsApp"]
    ),
    .library(
      name: "Layouts",
      targets: ["Layouts"]
    ),
  ],
  dependencies: [],
  targets: [
    .executableTarget(
      name: "LayoutsApp",
      dependencies: ["Layouts"]
    ),
    .target(
      name: "Layouts",
      dependencies: []
    ),
  ]
)
