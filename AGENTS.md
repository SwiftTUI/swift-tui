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
products, or repo tooling, and confirm it passes before considering work
complete. Example-package coverage lives in `SwiftTUI/swift-tui-examples`.
Do not run repo-local builds or tests with bare `swift` or `xcrun swift` — use
`swiftly run swift ...` so runs match the pinned toolchain. See
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for the full toolchain, gate, and
release story.

## Architecture (one-page summary)

```
SwiftTUICore  ->  SwiftTUIViews  ->  SwiftTUIRuntime
```

- **SwiftTUICore** — the engine: geometry, the frame pipeline, and the typed
  phase products. Terminal-IO-free.
- **SwiftTUIViews** — the SwiftUI-shaped authoring surface (`View`, controls,
  layout, state, focus, gestures).
- **SwiftTUIRuntime** — the run loop, renderer, scenes, and host integration.
- **SwiftTUI** — the batteries-included convenience product; re-exports the
  combined terminal/WebHost runner and `SwiftTUIAnimatedImage`.
- **SwiftTUICharts** — peer product for charting/graph views.

`DefaultRenderer` runs one composed runtime stage pipeline:

```
head -> animation injection -> late-preference reconciliation -> fused frame tail -> commit
```

The fused tail produces the seven typed phase products in order:

```
resolve -> measure -> place -> semantics -> draw -> raster -> commit
```

Full developer-facing detail lives in
[Runtime-Render-Pipeline.md](Sources/SwiftTUIRuntime/SwiftTUIRuntime.docc/Runtime-Render-Pipeline.md);
internal source-layout context lives in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Development Guidelines

- When a new feature replaces an existing constraint, search for and remove
  **all** old guards and assertions that enforced the previous constraint. Do
  not leave stale invariants behind.
- New files should belong to one subsystem; keep the source layout in
  [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) aligned with file moves.
- Treat fixture changes as evidence, not housekeeping — see
  [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md#rendered-text-fixtures).
- For runtime state bugs, distinguish transient flicker from true state loss.
  If state must survive lazy-tab, deferred-content, or presentation churn,
  hoist ownership above that seam — but do not over-hoist. Distinguish live
  graph isolation (`RunLoop` / invalidator-backed) from no-invalidator
  `DefaultRenderer` snapshot behavior; do not replace graph-scoped imperative
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
- Full config in `.swift-format.json`.

## Swift Language Settings

- Swift 6.3.1, Swift 6 language mode, strict memory safety,
  `.defaultIsolation(.none)`.
- Upcoming features enabled include `ExistentialAny`,
  `NonisolatedNonsendingByDefault`, `MemberImportVisibility`, and
  `InternalImportsByDefault`.
- SwiftPM package platforms: macOS 15+, iOS 18+. macOS CI floor: `macos-26`.

## AnyView Policy

- Prefer typed `@ViewBuilder` closures and generic `Content: View` storage.
- Treat `AnyView` / `AnyScene` as escape hatches, not default container types.
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
  `SwiftTUI` layers and the vendored `EmbeddedFonts`/`SwiftFiglet` runtime they
  re-export. The repo gate additionally runs `Scripts/check_foundation_free_layers.sh`,
  which follows package resolution (via `-emit-loaded-module-trace`) to catch
  Foundation reaching `SwiftTUICore`/`SwiftTUIViews` through any transitive
  dependency.
- **public-surface-policies** — enforces the guardrails documented in
  [docs/PUBLIC-API.md](docs/PUBLIC-API.md).
- **structured-concurrency-escape-hatches** — blocks `@unchecked Sendable` and
  `nonisolated(unsafe)`; prefer explicit isolation, `Sendable` constraints, or
  `Synchronization` primitives.
- **main-thread-usage** — forbids bare `Thread.isMainThread` without
  justification.

## Tests

Test suites are split by layer:

- `Tests/SwiftTUICoreTests/` — pipeline, layout, raster, focus infrastructure.
- `Tests/SwiftTUIViewsTests/` — authoring surface, environment, actor isolation.
- `Tests/SwiftTUIAnimatedImageTests/` — animated image and GIF behavior.
- `Tests/SwiftTUITests/` — runtime, rendering, fixtures, end-to-end behavior.
- `Platforms/CLI/Tests/` and `Platforms/WASI/Tests/` — runner and transport
  behavior.

Use Swift Testing (`import Testing`, `@Test`, `#expect`) for tests. For runtime
and animation tests, prefer real `RunLoop` input-path coverage and bounded
condition-based waits over fixed sleeps. See
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Documentation

[docs/README.md](docs/README.md) indexes internal project documentation.
Developer-facing guides and per-symbol API reference live in the `*.docc`
catalogs under `Sources/`.
