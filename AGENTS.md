# AGENTS.md

Guidance for Claude Code and other agentic assistants working in this
repository. Keep this file concise. The architecture documentation in
[`docs/`](docs/README.md) holds internal project notes. Developer-facing guides
live in the DocC catalogs under `Sources/`.

## Build & Test Commands

```bash
bun run test                                       # Repo gate: shared suite + policy checks
bun run test:all                                   # Exhaustive checked-in primary-repo test surface
swiftly run swift build                            # Build all root-package targets
swiftly run swift test                             # Run root-package tests
swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests             # One test suite
swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/testName    # One test
swift format format -i --configuration .swift-format.json Sources/ Tests/     # Format
```

Always run `bun run test` after changes that touch shared code, platform
products, or repository tooling. Make sure that it passes before you complete
the work. Example-package coverage lives in `SwiftTUI/swift-tui-examples`.
Do not run repo-local builds or tests with bare `swift` or `xcrun swift` — use
`swiftly run swift ...` so runs match the pinned toolchain. See
[DEVELOPMENT.md](https://github.com/SwiftTUI/swift-tui-org/blob/main/docs/swift-tui/DEVELOPMENT.md)
in the `swift-tui-org` coordination repository for the full toolchain, gate, and
release story.

## Architecture (one-page summary)

```
SwiftTUIPrimitives -> SwiftTUIGraph -> SwiftTUICore -> SwiftTUIViews -> SwiftTUIRuntime
```

- **SwiftTUIPrimitives** — leaf vocabulary: inert value types only (geometry,
  identity, style/color values, draw/layout metadata, the `Animatable` math). No
  engine, no render algorithms. Builds independently. Foundation-free.
- **SwiftTUIGraph** — the reconciliation engine (the AttributeGraph analog).
  It owns `ViewGraph`/`ResolvedNode`, state slots, dependency tracking,
  invalidation planning, reuse gates, checkpoints, and entity routing. It also
  owns the runtime registries, the scheduler, and animation intent. Depends on
  `SwiftTUIPrimitives` **only** —
  the compiler enforces that graph code names no render type. Foundation-free.
- **SwiftTUICore** — the render engine: measure/place/draw/raster/commit phases
  and their typed products, extractors, style resolution, content engine. Consumes
  the graph's `ResolvedNode` snapshots. It `@_exported`-imports Graph and
  Primitives, so
  `import SwiftTUICore` is unchanged. Terminal-IO-free.
- **SwiftTUIViews** — the SwiftUI-shaped authoring surface (`View`, controls,
  layout, state, focus, gestures). `@_exported`-imports Core so the published
  `SwiftTUIViews` product is a self-sufficient authoring surface for external
  view libraries (SwiftTUICharts consumes exactly this).
- **SwiftTUIRuntime** — the run loop, renderer, scenes, and host integration.
- **SwiftTUI** — the batteries-included convenience product. It re-exports the
  combined terminal/WebHost runner and `SwiftTUIAnimatedImage`.
- **SwiftTUICharts** — chart and graph views. It ships from the peer repository
  [`SwiftTUI/swift-tui-charts`](https://github.com/SwiftTUI/swift-tui-charts),
  composed on the public `SwiftTUIViews` surface.

`DefaultRenderer` runs one composed runtime stage pipeline:

```
head -> animation injection -> late-preference reconciliation -> fused frame tail -> commit
```

The fused tail produces the seven typed phase products in order:

```
resolve -> measure -> place -> semantics -> draw -> raster -> commit
```

Full developer-facing detail lives in
[Runtime-Render-Pipeline.md](Sources/SwiftTUIRuntime/SwiftTUIRuntime.docc/Runtime-Render-Pipeline.md).
Internal source-layout context lives in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Development Guidelines

- When a new feature replaces an existing constraint, search for and remove
  **all** old guards and assertions that enforce the previous constraint. Do
  not leave stale invariants behind.
- Put each new file in one subsystem. Keep the source layout in
  [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) aligned with file moves.
- New files that touch C stdio/POSIX (`open`/`write`/`getenv`/`FILE`, …) must
  stay **WASI-safe and strict-memory-safety clean**. Import each libc:
  `Darwin`, `Glibc`, `Android`, and `Musl`. Exclude path-based POSIX code with
  `#if !canImport(WASILibc)`. Use `DebugLogRouter` and
  `TerminalPOSIXController` as models. Mark each unsafe call `unsafe`.
  A WASI-only break in 0.0.19 passed the Linux-only gate. The
  `EnvFrameTraceSink` break in 0.0.26 also passed it. The repository gate now has a
  `wasm32-wasi cross-compile` lane for
  `SwiftTUIWASI`. Before you push a WASI-related change, run `swiftly run swift
  build --swift-sdk swift-6.3.3-RELEASE_wasm --target SwiftTUIWASI`. Use
  `--target`, not `--product`. A library-product build includes non-WASI PTY
  targets.
- Treat fixture changes as evidence, not housekeeping — see
  [DEVELOPMENT.md](https://github.com/SwiftTUI/swift-tui-org/blob/main/docs/swift-tui/DEVELOPMENT.md#rendered-text-fixtures).
- For runtime state bugs, distinguish transient flicker from true state loss.
  If state must survive lazy-tab, deferred-content, or presentation churn,
  hoist ownership above that seam. Do not hoist unrelated state. Distinguish
  live graph isolation from no-invalidator `DefaultRenderer` snapshots. A live
  graph uses `RunLoop` or an invalidator. Do not replace graph-scoped imperative
  state with a last-bound global fallback. See
  [Runtime-Render-Pipeline.md](Sources/SwiftTUIRuntime/SwiftTUIRuntime.docc/Runtime-Render-Pipeline.md).
- For wrapper-hosted or scene-hosted regressions, reproduce against the
  composed runtime path, not just the inner view in isolation.
- Keep terminal-output sanitization at the presentation boundary, covering both
  text control scalars and OSC 8 hyperlink destinations.

## Code Style

- 2-space indentation, 100-character line length.
- `private` (not `fileprivate`) for file-scoped declarations.
- Ordered imports, no block comments, no void return on function signatures.
- The complete configuration is in `.swift-format.json`.

## Swift Language Configuration

- Swift 6.3.3, Swift 6 language mode, strict memory safety,
  `.defaultIsolation(.none)`.
- Upcoming features enabled include `ExistentialAny`,
  `NonisolatedNonsendingByDefault`, `MemberImportVisibility`, and
  `InternalImportsByDefault`.
- SwiftPM package platforms: macOS 15+, iOS 18+. macOS CI floor: `macos-26`.

## AnyView Policy

- Prefer typed `@ViewBuilder` closures and generic `Content: View` storage.
- Use `AnyView` and `AnyScene` only as escape hatches, not default container
  types.
- Do not add public APIs that expose `[AnyView]`, `[AnyScene]`, builder
  closures returning `AnyView`, or node-erasure seams.
- If authored content is captured for later evaluation, use
  `scopedAnyView(...)`, not plain `AnyView(...)`.
- Add a nearby `AnyView policy:` comment when introducing a new stored
  `AnyView`, `[AnyView]`, or closure-returning-`AnyView` member.

Full policy in [docs/PUBLIC-API.md](docs/PUBLIC-API.md#anyview-policy).

## Pre-commit Hooks (prek)

- **swift-format** — auto-formats staged `.swift` files.
- **no-foundation-in-library-products** — blocks `import Foundation` (including
  `@_implementationOnly` / `@_exported` / `@preconcurrency` and `Foundation.*`
  submodule forms) in the Foundation-free `SwiftTUICore`, `SwiftTUIViews`, and
  `SwiftTUI` layers and the vendored `SwiftTUIVendorFiglet` /
  `SwiftTUIVendorFigletEmbeddedFonts` runtime that they re-export. The
  repository gate also runs `Scripts/check_foundation_free_layers.sh`. This
  script uses `-emit-loaded-module-trace` to follow package resolution. It finds
  transitive Foundation dependencies in `SwiftTUICore` and `SwiftTUIViews`.
- **public-surface-policies** — enforces the guardrails documented in
  [docs/PUBLIC-API.md](docs/PUBLIC-API.md).
- **structured-concurrency-escape-hatches** — blocks `@unchecked Sendable` and
  `nonisolated(unsafe)`. Prefer explicit isolation, `Sendable` constraints, or
  `Synchronization` primitives.
- **main-thread-usage** — forbids bare `Thread.isMainThread` without
  justification.
- **no-ai-coauthors** — uses
  `https://github.com/GoodHatsLLC/no-ai-coauthors` to reject commit messages
  with AI attribution trailers.

## Tests

Test suites are split by layer:

- `Tests/SwiftTUICoreTests/` — pipeline, layout, raster, focus infrastructure.
- `Tests/SwiftTUIViewsTests/` — authoring surface, environment, actor isolation.
- `Tests/SwiftTUIAnimatedImageTests/` — animated image and GIF behavior.
- `Tests/SwiftTUITests/` — runtime, rendering, fixtures, end-to-end behavior.
- `Platforms/CLI/Tests/` and `Platforms/WASI/Tests/` — runner and transport
  behavior.

Use Swift Testing (`import Testing`, `@Test`, `#expect`) for tests. For runtime
and animation tests, use real `RunLoop` input-path coverage. Use bounded
condition-based waits instead of fixed sleeps. See
[DEVELOPMENT.md](https://github.com/SwiftTUI/swift-tui-org/blob/main/docs/swift-tui/DEVELOPMENT.md).

## Documentation

[docs/README.md](docs/README.md) indexes the `HEAD`-state architecture and
contract documentation. Developer-facing guides and per-symbol API reference
live in the `*.docc` catalogs under `Sources/`. Maintainer development docs
(codebase guide, build/test/release process, flake register) live in the
`swift-tui-org` coordination repository under `docs/swift-tui/`.
