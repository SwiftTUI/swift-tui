// swift-tools-version:6.0
import PackageDescription

let package:Package = .init(
    name: "swift-hash",
    platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6)],
    products: [
        .library(name: "Base16", targets: ["Base16"]),
        .library(name: "Base64", targets: ["Base64"]),
        .library(name: "CRC", targets: ["CRC"]),
        .library(name: "InlineBuffer", targets: ["InlineBuffer"]),
        .library(name: "MD5", targets: ["MD5"]),
        .library(name: "MessageAuthentication", targets: ["MessageAuthentication"]),
        .library(name: "SHA1", targets: ["SHA1"]),
        .library(name: "SHA2", targets: ["SHA2"]),
        .library(name: "UUID", targets: ["UUID"]),
    ],
    targets: [
        .target(name: "BaseDigits"),

        .target(name: "Base16",
            dependencies: [
                .target(name: "BaseDigits"),
            ]),

        .target(name: "Base64",
            dependencies: [
                .target(name: "BaseDigits"),
            ]),

        .target(name: "CRC",
            dependencies: [
                .target(name: "Base16"),
            ]),

        .target(name: "InlineBuffer"),

        .target(name: "MD5",
            dependencies: [
                .target(name: "InlineBuffer"),
            ]),

        .target(name: "MessageAuthentication"),

        .target(name: "SHA1",
            dependencies: [
                .target(name: "InlineBuffer"),
            ]),

        .target(name: "SHA2",
            dependencies: [
                .target(name: "Base16"),
                .target(name: "MessageAuthentication"),
            ]),

        .target(name: "UUID",
            dependencies: [
                .target(name: "Base16"),
            ]),

        .testTarget(name: "Base64Tests",
            dependencies: [
                .target(name: "Base64"),
            ]),

        .testTarget(name: "CRCTests",
            dependencies: [
                .target(name: "CRC"),
            ]),

        .testTarget(name: "MD5Tests",
            dependencies: [
                .target(name: "MD5"),
            ]),

        .testTarget(name: "SHA2Tests",
            dependencies: [
                .target(name: "SHA2"),
            ]),
    ]
)

for target:PackageDescription.Target in package.targets
{
    {
        var settings:[PackageDescription.SwiftSetting] = $0 ?? []

        settings.append(.enableUpcomingFeature("ExistentialAny"))
        settings.append(.enableExperimentalFeature("StrictConcurrency"))

        settings.append(.define("DEBUG", .when(configuration: .debug)))

        $0 = settings
    } (&target.swiftSettings)
}
