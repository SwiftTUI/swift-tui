# AGENTS.md

Guidance for Claude Code and other agentic assistants working in this
repository. Keep this file concise — the detailed design documents in
[`docs/`](docs/README.md) are the source of truth. Update them there, not here.
Use [`active_work.md`](active_work.md) as the live tracker for incomplete work:
keep it current, keep entries concise, link to supporting docs, and remove
items when completed rather than summarizing completed work there.

## Build & Test Commands

```bash
bun run test                                       # Full repo test surface + environment checks
swiftly run swift build                            # Build all root-package targets
swiftly run swift test                             # Run root-package tests
swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests             # One test suite
swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/testName    # One test
swift format format -i --configuration .swift-format.json Sources/ Tests/       # Format
```

Always run `bun run test` after changes that touch shared code, peer packages,
or repo tooling, and confirm it passes before considering work complete.

See [docs/TOOLCHAINS.md](docs/TOOLCHAINS.md) for the canonical toolchain story
(`swiftly`, wasm SDK, Bun, Xcode, Android NDK).

## Architecture (one-page summary)

```
SwiftTUI  ->  SwiftTUIViews  ->  SwiftTUICore
```

- **SwiftTUICore** — pure, terminal-IO-free pipeline
- **SwiftTUIViews** — SwiftUI-shaped authoring surface
- **SwiftTUI** — terminal runtime; re-exports SwiftTUIViews and SwiftTUICore via `@_exported import`
- **SwiftTUICharts** — compact chart/metric track; separate product
- **SwiftTUIAnimatedImage** — finite pre-composed animated image track; GIF codec owner

Every frame flows through seven strict phases:

```
resolve -> measure -> place -> semantics -> draw -> raster -> commit
```

Full detail in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and
[docs/RUNTIME.md](docs/RUNTIME.md). Per-file ownership map in
[docs/SOURCE_LAYOUT.md](docs/SOURCE_LAYOUT.md).

## Development Guidelines

- When a new feature replaces or extends an existing constraint (e.g.
  single-scene → multi-scene), search for and remove **all** old
  guards/assertions that enforce the previous constraint. Don't leave stale
  invariants behind.
- New files should belong to one subsystem. Keep
  [docs/SOURCE_LAYOUT.md](docs/SOURCE_LAYOUT.md) aligned with file moves.
- Treat fixture changes as evidence, not housekeeping. See
  [docs/TESTING_AND_FIXTURE_POLICY.md](docs/TESTING_AND_FIXTURE_POLICY.md).
- For runtime state bugs, distinguish transient flicker from true state loss.
  If state must survive lazy tab, deferred-content, or presentation churn,
  hoist ownership above that seam. Do not over-hoist: tab-local state may be
  intentionally ephemeral across tab switches, but palette open/close should
  be transparent unless the palette itself changes selection. For same view
  instance bugs, distinguish live graph isolation (`RunLoop` / invalidator-
  backed) from no-invalidator `DefaultRenderer` snapshot behavior; do not
  replace graph-scoped imperative state with a last-bound global fallback. See
  [docs/RUNTIME.md](docs/RUNTIME.md) and
  [docs/STATE_KEYING.md](docs/STATE_KEYING.md).
- For wrapper-hosted or scene-hosted regressions, reproduce and test the
  composed runtime path, not just the inner view in isolation.
- For terminal presentation fixes, keep sanitization at the presentation
  boundary and cover both text control scalars and OSC 8 hyperlink
  destinations.

## Code Style

- 2-space indentation, 100-character line length
- `private` (not `fileprivate`) for file-scoped declarations
- Ordered imports, no block comments, no void return on function signatures
- Full config in `.swift-format.json`

## Swift Language Settings

- Swift 6.3 with strict memory safety and Swift 6 language mode
- Upcoming features enabled: `ExistentialAny`, `NonisolatedNonsendingByDefault`,
  `MemberImportVisibility`, `InternalImportsByDefault`, and others
- Platforms: macOS 15+, iOS 18+

## AnyView Policy

- Prefer typed `@ViewBuilder` closures and generic `Content: View` storage
- Treat `AnyView` / `AnyScene` as escape hatches, not default container types
- Do not add public APIs that expose `[AnyView]`, `[AnyScene]`, builder
  closures returning `AnyView`, or node-erasure seams
- If authored content is captured for later evaluation, use
  `scopedAnyView(...)`, not plain `AnyView(...)`
- Add a nearby `AnyView policy:` comment when introducing a new stored
  `AnyView`, `[AnyView]`, or closure-returning-`AnyView` member

Full policy in [docs/PUBLIC_SURFACE_POLICY.md](docs/PUBLIC_SURFACE_POLICY.md).

## Pre-commit Hooks (prek)

- **swift-format** — auto-formats staged `.swift` files
- **no-foundation-in-library-products** — blocks `import Foundation` in the
  Foundation-free `SwiftTUICore`, `SwiftTUIViews`, and `SwiftTUI` library layers
- **public-surface-policies** — enforces the guardrails in
  [docs/PUBLIC_SURFACE_POLICY.md](docs/PUBLIC_SURFACE_POLICY.md)
- **accessibility-guardrails** — pins reviewed raw-glyph, color-state, and
  visual-content source files and requires listening-test docs
- **structured-concurrency-escape-hatches** — blocks `@unchecked Sendable` and
  `nonisolated(unsafe)`. Prefer explicit actor isolation, `Sendable` generic
  constraints, or `Synchronization` primitives instead.

## Tests

Test suites are split by layer:

- `Tests/SwiftTUICoreTests/` — pipeline, layout, raster, focus infrastructure
- `Tests/SwiftTUIViewsTests/` — authoring-surface, environment, actor-isolation
- `Tests/SwiftTUIAnimatedImageTests/` — animated image and GIF import/export behavior
- `Tests/SwiftTUITests/` — runtime, rendering, fixtures, end-to-end behavior
- `Platforms/CLI/Tests/SwiftTUICLITests/` — CLI runner, socket, pty,
  attach, scene-management behavior
- `Platforms/WASI/Tests/SwiftTUIWASITests/` — WASI launcher and
  manifest-mode behavior
- `Platforms/WASI/Tests/WASISurfaceBridgeTests/` — `web-surface`
  encoder, input parser, and transport behavior

Prefer Swift Testing (`import Testing`, `@Test`, `#expect`) for new tests.
Existing XCTest suites may remain.

For runtime and animation tests, prefer real `RunLoop` input-path coverage and
bounded condition-based waits over fixed sleeps. See
[docs/TESTING_AND_FIXTURE_POLICY.md](docs/TESTING_AND_FIXTURE_POLICY.md).

## Documentation

[docs/README.md](docs/README.md) is the canonical index — follow it for
architecture, runtime, API governance, proposals, and background material.
