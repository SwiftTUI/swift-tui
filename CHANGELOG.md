# Changelog

All notable changes to SwiftTUI are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

SwiftTUI is pre-1.0: while the public surface is being proven, minor releases
may make source-breaking API adjustments. Pin with `.upToNextMinor`.

## [Unreleased]

### Added

- **Presented-Progress Guard** (opt-in via
  `SWIFTTUI_PRESENTED_PROGRESS_GUARD`): with the guard on, a completed
  frame whose presentation diff against the last presented surface is
  non-empty is never drop-eligible
  (`FrameDropBlocker.undeliveredPresentationDamage`) — the bounded
  completed-frame starvation backstop becomes the invariant "undelivered
  pixels are never droppable", uniformly for every host. Value-identical
  rasters (all-zero damage) stay droppable, and the pre-start cancel arm
  is deliberately out of scope. Default off; the default flip is gated on
  a drop-heavy-host rusage A/B (docs/plans/2026-07-20-001, Stage 5).

## [0.1.12] - 2026-07-21

### Changed

- **WebHost browser bundle re-vendored at `swift-tui-web` 0.1.12.** No
  Swift source changes. The bundle exits the stack-lean hold on confirmed
  V8 workers (`SWIFTTUI_STACK_LEAN_PROFILE: "0"` by default; JSC and
  Gecko stay lean — Gecko by live measurement), riding 0.1.11's
  `async-no-cancel` disposal default. Live non-lean Chromium measures the
  same distinct-generation coverage as lean at roughly half the per-frame
  pipeline cost, with 100% damage-scoped delta frames in the steady
  window.

## [0.1.11] - 2026-07-20

### Added

- **`PerTickPresentCadenceTests`**: composed-runtime per-tick present
  cadence coverage for completed-frame disposal — an autonomous
  Life-shaped tick with deterministic held-tail supersession proves
  `async-no-cancel` presents every completed frame, with a non-lean
  `dropped_completed` red-proof naming the disposal layer, re-run under
  the stack-lean and chunked-resolve WASI-shaped profiles.

### Changed

- **WebHost browser bundle re-vendored at `swift-tui-web` 0.1.11.** No
  Swift source changes. The bundle's `BrowserWASIBridge` now defaults
  browser sessions to `TERMUI_RENDER_MODE=async-no-cancel` (engine-blind,
  both execution modes): completed-frame disposal under supersession —
  not transport publication — was the 0.1.9 live coalescing, and
  ordered commits lift deployed Life distinct-generation coverage
  0.22 → 0.86 with per-frame cost unchanged. The `?renderMode=` page
  seam and caller environments still override.

## [0.1.10] - 2026-07-20

### Changed

- **WebHost browser bundle re-vendored at `swift-tui-web` 0.1.10.** No Swift
  source changes. The bundle brings the JSPI main-thread wasm execution mode
  (opt-in), holds the stack-lean profile as the default on every engine, and
  raises the packaged wasm linear-memory stack from 1 MiB to 16 MiB. Together
  these heal two live 0.1.9 Chromium regressions (an Animations-scene
  shadow-stack overflow, and Life frame-emission coalescing under the
  non-lean profile).

## [0.1.9] - 2026-07-20

### Changed

- **WebHost browser bundle re-vendored at `swift-tui-web` 0.1.9.** No Swift
  source changes. The bundle adds engine-family detection with an
  engine-differentiated stack-lean default (later reverted in 0.1.10) and
  JSPI capability detection.

## [0.1.8] - 2026-07-20

### Added

- **WASI stack-lean resolve profile** (`SWIFTTUI_STACK_LEAN_PROFILE`):
  default-on for WASI builds, opt-in natively. Swaps per-level task-local
  ambient binds for MainActor save/restore slots and disables retained-reuse,
  memoized reuse, and selective evaluation, bounding the resolve descent's
  stack cost for JavaScriptCore's worker thread-stack budget.
- **Depth-capped chunked resolve** (`DeferredResolveDriver`): a
  drain-and-rerun fixpoint that cuts the resolve descent at structural child
  edges past a depth limit (default K=6 under the lean profile;
  `SWIFTTUI_RESOLVE_DEPTH_LIMIT` tunes or force-enables it) and re-resolves
  deferred subtrees from a fresh shallow stack. This fixes the Safari/WebKit
  stack overflow that broke the browser demo on JavaScriptCore.

### Fixed

- **Lean-profile async ambient reads.** Under the stack-lean profile,
  ambient-context reads now fall back to the task-local slot
  (`leanCurrent ?? taskLocalCurrent`), restoring `.task`-closure visibility of
  authoring/environment context. Previously state writes from async tasks
  degraded to detached boxes and produced no frames (the frozen Game of
  Life).

## [0.1.7] - 2026-07-18

### Added

- **Gesture composition**: inter-tap timeout for multi-tap counts, exclusive
  gesture hand-off with replay, and `SimultaneousGesture`/`SequenceGesture`.
- **Typed navigation data paths** and **data-driven dismissal**;
  presentation surfaces now stack.
- **Node-hosted collection rows** and windowed lazy-stack realization:
  lazy stacks realize and measure only the scroll viewport's window, with
  drift correction pinned by tests.
- SwiftUI-parity wiring: object environment values, `withTransaction`,
  spring `initialVelocity`; off-main `@Observable` writes are marshaled
  instead of trapping.

### Changed

- Teardown reachability unified behind a single barrier entrypoint with
  census-adjudicated spares; legacy lifetime ledgers retired.
- Performance program: reuse-gate invalidation queries inverted to the
  invalidated set, unchanged-commit effect republication scoped to an owner
  index, animation deadline work scoped, collection baseline scenarios
  (`lazy-list-1k`, `table-1kx4`) added.

### Fixed

- A large fix batch from the gallery fuzz campaign, including: toolbar chrome
  proposal fill, adopted-slot conditional transitions, location-free drop
  dispatch fallback, node-backed style bodies with adopted authoring owners,
  superseded task starts in merged lifecycle plans, paired pointer-route
  release with departed gesture recognizers, and pass-stable `onChange`
  previous-value reads.

## [0.1.6] - 2026-07-13

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

- The absorbed Vendor targets are renamed with a `SwiftTUIVendor` prefix
  (`UnixSignals` → `SwiftTUIVendorUnixSignals`, `SwiftFiglet` →
  `SwiftTUIVendorFiglet`, `EmbeddedFonts` → `SwiftTUIVendorFigletEmbeddedFonts`,
  `GIF`/`JPEG`/`PNG` → `SwiftTUIVendor{GIF,JPEG,PNG}`, the `figlet` executable →
  `SwiftTUIVendorFigletCLI`). SwiftPM requires target names to be unique across
  the whole package graph, so under their upstream names these targets collided
  with packages that ship the originals (e.g. swift-service-lifecycle's
  `UnixSignals`). No public product changes name; the vendored modules were
  never importable by consumers.
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
