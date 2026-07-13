# Changelog

All notable changes to SwiftTUI are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

SwiftTUI is pre-1.0: while the public surface is being proven, minor releases
may make source-breaking API adjustments. Pin with `.upToNextMinor`.

## [Unreleased]

### Removed

- **BREAKING: the `SwiftTUICharts` product moved to its own repository,
  [`SwiftTUI/swift-tui-charts`](https://github.com/SwiftTUI/swift-tui-charts).**
  `swift-tui` no longer declares a `SwiftTUICharts` product or target. Keep
  your `import SwiftTUICharts` lines as they are, add the new package
  dependency, and change the product's `package:` identity:

  ```swift
  dependencies: [
    .package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "<version>"),
    .package(url: "https://github.com/SwiftTUI/swift-tui-charts.git", exact: "<version>"),
  ],
  // in the target:
  .product(name: "SwiftTUICharts", package: "swift-tui-charts"),
  ```

### Added

- `AccessibilityVisualContent` is now public, and the public
  `SemanticMetadata` initializer accepts `accessibilityVisualContent:`, so
  external view libraries can participate in the missing-label accessibility
  diagnostics contract.
- The published `SwiftTUIViews` product re-exports `SwiftTUICore` (which
  re-exports `SwiftTUIGraph` and `SwiftTUIPrimitives`), making
  `import SwiftTUIViews` a self-sufficient authoring surface for external
  view libraries — the same re-export shape `SwiftTUIRuntime` already had.

### Changed

- Documented that `DefaultRenderer.render(_:)` is a one-shot snapshot/preview
  entry point and is **not** focus/press-reuse-safe across successive calls
  (focus/press state is excluded from the reuse snapshot and protected by the
  run loop's suppression scope, which the one-shot path does not compute) — drive
  interactive rendering through the run loop. Clarified the `EquatableView`
  documentation: it wraps an already-`Equatable` `Content` and relocates the
  reuse boundary onto its own node; prefer conforming the boundary view to
  `Equatable` directly unless a distinct boundary node is needed.
- Added a DEBUG memoization diagnostic (`SWIFTTUI_MEMO_TRACE` → `inert_equatable`)
  that flags an `Equatable` / `.equatable()` boundary which is never memo-reused
  because it reads `@State`/`@Observable`/focus state — surfacing a silently inert
  opt-in. The reflective comparator path is now DEBUG-only (the production gate is
  `Equatable`-only); no public API change.

## [0.0.21] - 2026-06-17

### Added

- **`EquatableView` and `View.equatable()`** (SwiftUI parity). Wrapping a
  read-free boundary view (or conforming it to `Equatable`) lets the renderer
  reuse its whole committed subtree via a single `==` when the value is
  unchanged, instead of re-evaluating it under an invalidated ancestor. `==` is
  a correctness contract — see the `EquatableView` docs.

### Changed

- **Memoized-body reuse is on by default.** When a node reached under an
  invalidated ancestor is `Equatable`-equal to its previous value, reads no
  `@State`/`@Observable`/focus state, and passes the retained-reuse guards, its
  committed subtree is reused instead of recomputed. The gate is `Equatable`-only
  (a true opt-in): inert on views that do not conform to `Equatable` (measured
  within noise on non-opt-in trees), a large `resolve` win on those that do. Set
  `SWIFTTUI_MEMO_REUSE=0` to disable.

## [0.0.19] - 2026-06-10

Lockstep release across the SwiftTUI org. Headline: a first preview of the
host-managed Android surface.

### Added

- **Android host (early preview).** A new `SwiftTUIAndroidHost` library
  product and target under `Platforms/Android`: hosts SwiftTUI scenes behind
  a `swift_tui_android_*` C ABI for JNI/Compose embedders, publishing
  semantic host frames — styled cells, terminal colors,
  underline/strikethrough decorations, image attachment records and
  payloads, accessibility nodes and announcements, focus presentation, and
  preferred layout size — as versioned JSON snapshots. Verified rendering
  the gallery example on an arm64-v8a emulator. IME composition, clipboard,
  link opening, and precise drag/scroll gestures remain follow-up work.
- A platform-neutral `HostedSurfaceSizeNegotiator` in `SwiftTUIRuntime`,
  shared by the SwiftUI and Android hosts for hosted-surface size
  negotiation.
- Ordered raster presentation layers.
- GIF blend-behavior test coverage.
- A complete copy-pasteable `Package.swift` example in the README.
- README disclosure of the `#12` run-loop memory-corruption known issue.

### Changed

- Broad Android compatibility across core, runtime, profiling, and terminal
  I/O (`canImport(Android)` paths); the package cross-builds for
  `aarch64-unknown-linux-android28` with the official Swift Android SDK.
- Presentation sheets render with single-line full-bleed chrome.
- `perf(termui)`: sheet-open-latency benchmark plus gated additive-overlay
  raster reuse.
- README: the web packages are now installed from npm
  (`npm install @swifttui/web @swifttui/build`); the GitHub-release tarball URLs
  are documented as a secondary, pin-a-release-asset option.
- `docs/VISION-GAP.md` restored at `HEAD` (five docs link to it) and brought
  current: npm publishing and still-`Image` blend-mode precomposition are now
  recorded as shipped.

## [0.0.18] - 2026-06-07

Lockstep release across the SwiftTUI org, reconciling a prior version skew (a
solo `0.0.17` tag carrying the breaking `Canvas`/`CanvasContext` redesign that
the rest of the org had not followed). Includes the image-blend-mode
precomposition work (still images), cache hardening, and glyph-aware backdrops.

See the GitHub releases for the full per-tag history:
<https://github.com/SwiftTUI/swift-tui/releases>.

[Unreleased]: https://github.com/SwiftTUI/swift-tui/compare/0.0.18...HEAD
[0.0.18]: https://github.com/SwiftTUI/swift-tui/releases/tag/0.0.18
