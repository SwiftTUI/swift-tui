// swift-tools-version: 6.3
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

func swiftSettings(_ settings: PackageDescription.SwiftSetting...)
  -> [PackageDescription.SwiftSetting]
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
  name: "swift-jpeg",
  platforms: packagePlatforms,
  products: [
    .library(name: "JPEG", targets: ["JPEG"])
  ],
  targets: [
    .target(
      name: "JPEG",
      path: "Sources/JPEG",
      swiftSettings: swiftSettings()
    ),
    .testTarget(
      name: "JPEGTests",
      dependencies: ["JPEG"],
      path: "Sources/JPEGTests",
      swiftSettings: swiftSettings()
    ),
  ]
)
