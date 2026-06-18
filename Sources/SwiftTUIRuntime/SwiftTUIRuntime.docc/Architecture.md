# Architecture

A tour of the package boundaries, the composed runtime pipeline, and the data products that flow between phases.

## Overview

SwiftTUI is split into focused targets so that pure pipeline work, authoring
work, runtime work, terminal convenience, platform hosts, and domain products
can each evolve without blurring concerns. This article documents those
boundaries, the runtime pipeline, and the phase products that connect them.

## Target Boundaries

### `SwiftTUICore`

- Defines the shared geometry, styling, semantic, raster, and commit data types
- Implements layout, semantic extraction, draw extraction, rasterization, diagnostics, scheduling, and commit planning
- Stays pure with respect to terminal I/O

### `SwiftTUIViews`

- Exposes the SwiftUI-shaped authoring surface
- Resolves authored views into core nodes
- Provides property wrappers, environment plumbing, focus APIs, layouts, and controls

### `SwiftTUICharts`

- Builds compact chart and metric views on top of `SwiftTUIViews`
- Reuses the same layout, semantic, draw, and raster pipeline
- Remains a separate track so charting does not distort the core library surface

### `SwiftTUIAnimatedImage`

- Builds finite pre-composed animated image views on top of `SwiftTUIViews`
- Owns GIF import and export through the vendored `swift-gif` package
- Keeps animated media concerns out of the core `SwiftTUI` runtime surface

### `SwiftTUIRuntime`

- Re-exports the public authoring and core surface that matters for shared runtime work
- Adds terminal host integration, alternate-screen ownership, input parsing,
  capability-aware presentation, ``RunLoop``, and rendering entry points
- Provides host-facing runtime seams such as scene manifests, retained hosted-scene sessions, shared terminal control-message parsing, injected input streams, and streaming terminal output sinks for non-terminal hosts

### `SwiftTUI`

- Release-facing convenience product for batteries-included apps
- Re-exports the combined terminal/WebHost CLI surface and
  `SwiftTUIAnimatedImage` so apps can write only `import SwiftTUI`
- Includes terminal launch, standard arguments, `--web` localhost launch, and
  animated GIF/image support by default
- Does not depend on SwiftUI hosting, WASI hosting, charts, or
  terminal-program embedding

### Platform integration products

- executable runner products `SwiftTUICLI` and `SwiftTUIWASI` build top-level
  execution layers on top of `SwiftTUIRuntime`
- host products and packages retain authored `SwiftTUIRuntime` apps inside
  platform-managed shells: `SwiftTUIWebHost` for localhost-browser launch and
  `@swifttui/web` for browser deployment. The native SwiftUI host (for embedding
  a SwiftTUI app in a SwiftUI view on macOS/iOS) now lives in the separate
  `swift-tui-swiftui` package: https://github.com/SwiftTUI/swift-tui-swiftui
- `SwiftTUIWebHost` is compound: its runner starts a localhost browser host and
  `SwiftTUIWebHostCLI` composes terminal and WebHost launch routing
- terminal-program embedding lives in `SwiftTUITerminal` and
  `SwiftTUIPTYPrimitives`; tabbed and split-pane terminal workspaces live in
  `SwiftTUITerminalWorkspace`

The conceptual model is:

```text
authored app surface -> SwiftTUIRuntime -> platform integration product -> platform shell
```

That last integration layer comes in two forms:

- executable runner products own top-level execution and default `App.main()` stories
- host products retain `HostedSceneSession` values inside another app or runtime lifecycle
- compound products must say which side is in scope: runner, host bridge, or
  presentation surface

For a deeper look at how those pieces fit together at the host boundary, see <doc:Host-Integration>.

## Frame Pipeline

``DefaultRenderer`` executes one composed runtime pipeline:

```text
head -> animation injection -> late-preference reconciliation -> fused frame tail -> commit
```

Sync, async, and cancellable rendering are execution strategies over that one
composition. The fused frame tail is the performance node that runs measure,
place, semantics, draw, and raster.

Within that composition, the typed phase products still flow in this order:

```text
resolve -> measure -> place -> semantics -> draw -> raster -> commit
```

The product model is documented in the Rendering Pipeline article in
`SwiftTUICore`. The runtime scheduling, cancellation, commit policy,
diagnostics, and host handoff are documented in
<doc:Runtime-Render-Pipeline>.

## Coordinate Domains

Layout and raster placement use integer terminal cells: `CellPoint`,
`CellSize`, and `CellRect`. Pointer input, gestures, Canvas drawing, and
interpolation use continuous cell-space values: `Point`, `Size`, `Rect`, and
`Vector`. Pixel geometry is host metadata, not the normal authoring unit.

This split lets the same authored app run on cell-only terminals and on native,
web, or terminal-pixel hosts. The semantic snapshot can route against stable
cell regions while the handler receives the most precise point the runtime can
provide.

## Runtime Model

``RunLoop`` wraps the pure frame pipeline in an interactive session, coordinating terminal I/O, input parsing, signal handling, frame scheduling, state invalidation, focus routing, and lifecycle staging around the pure frame products.

The core runtime is intentionally narrow today:

- one terminal host
- one active root scene in `SwiftTUIRuntime`
- one full-canvas ``WindowGroup`` per session
- keyboard-first interaction with optional mouse input when the terminal supports reporting

Platform integration and multi-scene orchestration live in sibling products in
the root package rather than in the `SwiftTUIRuntime` product itself.

Those integration layers serve four execution modes:

- terminal-native executable execution via `TerminalRunner.run(MyApp.self)` or
  the default `App.main()` provided by the `SwiftTUI` convenience product
- WASI executable execution and manifest generation via `WASIRunner` in
  `SwiftTUIWASI`
- host-managed embedding via `SceneManifest(for:)` and
  `HostedRasterSurface` plus `HostedSceneSession(for:sceneID:surface:)`, as used by
  `@swifttui/web`
- localhost-browser WebHost execution via `WebHostRunner` and the WebHost
  browser bridge in `SwiftTUIWebHost`

CLI scene management is executable-runner policy rather than an authored-scene
rule. One-window and multi-window apps share the same runner story; composed
hosts depend on `SwiftTUIRuntime` instead of the `SwiftTUI` terminal
convenience product.

## Important Data Products

- `ResolvedNode`: resolved structure plus merged environment and metadata
- `MeasuredNode`: size decisions under a proposal, including child measurements
- `PlacedNode`: final geometry, content bounds, and semantic role
- `SemanticSnapshot`: focus, interaction, action, selection, and scroll routing
- `SemanticHostFrame`: committed host handoff containing raster output,
  semantics, focused identity, optional raster damage, and a producer sequence
- `DrawNode`: draw commands for text, shapes, rules, lists, tables, and indicators
- `RasterSurface`: final cell grid plus style runs
- `CommitPlan`: runtime-facing semantic, lifecycle, and handler work
- `FrameArtifacts`: the full current-frame inspection bundle plus diagnostics.
  Prefer phase-specific products or `SemanticHostFrame` for host contracts.

## Styling And Presentation

- The public styling story is semantic-token-first: TUI views author against `.foreground`, `.background`, `.warning`, `.tint`, and related roles
- The active host integration chooses the active theme; the inner TUI app does not branch on host style variants or inspect theme choice directly
- Terminal appearance can be inferred heuristically or queried actively from the host and can synthesize the default semantic theme when no explicit host theme is provided
- Presentation lowers raster surfaces into ASCII, ANSI16, ANSI256, or true-color output
- Presentation sanitizes authored text and OSC 8 hyperlink destinations before
  emitting terminal bytes; layout, semantics, and raster artifacts never need to
  encode terminal-control safety rules themselves
- Terminal capability affects presentation, not layout semantics

## See Also

- <doc:Runtime>
- <doc:Runtime-Render-Pipeline>
- <doc:Vision>
- <doc:Host-Integration>
