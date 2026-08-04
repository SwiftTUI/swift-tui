# Hosts and Platforms (internal notes)

The canonical, consumer-facing host matrix, per-host engine profiles,
host-frame contract, platform support matrix, and embedding overview live in
the published DocC article
[Hosts And Platforms](../Sources/SwiftTUIRuntime/SwiftTUIRuntime.docc/Hosts-And-Platforms.md)
(`SwiftTUIRuntime` catalog). Keep that article authoritative; this file holds
only the maintainer-facing context that does not belong on the documentation
site.

## Where host code lives

The in-package integration code lives under `Platforms/`: terminal launch,
WASI, localhost WebHost, Android, and shared embedding contracts are SwiftPM
targets here. Hosts are partitioned across repositories by **distribution
contract**, not by backend. A host in another package ecosystem keeps that half
in a dedicated sibling repository. These repositories are
`SwiftTUI/swift-tui-web` (Bun/npm) and `SwiftTUI/swift-tui-android`
(Gradle/Maven AAR + plugin). Tagged releases or released artifacts couple them
back to this package. The Apple-SDK-gated `SwiftUIHost` product is
wholly external, in
[`SwiftTUI/swift-tui-swiftui`](https://github.com/SwiftTUI/swift-tui-swiftui).
These boundaries keep foreign package managers and Apple-only framework
imports out of this core SwiftPM package. Repository ownership and release
boundaries are recorded in [REPOSITORY-SPLIT.md](REPOSITORY-SPLIT.md).

## Maintainer notes

- **Wire contract.** The normative converged host-wire record, state,
  capability, delivery, and consumer contract is
  [HOST-WIRE-CONTRACT.md](HOST-WIRE-CONTRACT.md). The `SwiftTUIAndroidHost`
  and `swift-tui-web`/`swift-tui-swiftui` implementations must track it; the
  fixture corpus is byte-synced across those repositories (see
  [DEVELOPMENT.md](DEVELOPMENT.md)).
- **Platform declarations.** The package declares `macOS 15` and `iOS 18`
  platforms unless the build sets `DISABLE_EXPLICIT_PLATFORMS=1` (Linux CI
  does, to skip the Apple platform restriction).
- **Android packaging state.** The current `AndroidGallery` example packages
  arm64 only, although the Swift host cross-compiles for arm64 and x86_64.
  Android host behavior gaps are tracked in
  [VISION-GAP.md](VISION-GAP.md#android-host).
- **Embedding gaps.** Sixel/Kitty graphics inside embedded panes, the Kitty
  keyboard protocol, OSC 99 notification namespacing, and process
  reattachment after an app restart are not implemented. See
  [VISION-GAP.md](VISION-GAP.md).
- **CI floors.** GitHub `macos-26` is the macOS CI floor. iOS CI builds
  host-compatible products but does not run tests.
