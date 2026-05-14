# Architecture

A tour of the package boundaries, the strict frame pipeline, and the data products that flow between phases.

## Overview

SwiftTUI is split into focused targets so that pure pipeline work, authoring
work, runtime work, terminal convenience, platform hosts, and domain products
can each evolve without blurring concerns. This article documents those
boundaries and the seven-phase frame pipeline that connects them.

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

- Release-facing convenience product for terminal-native apps
- Re-exports `SwiftTUIRuntime`, `SwiftTUIArguments`, and `SwiftTUICLI` so
  terminal-native apps can write only `import SwiftTUI`
- Does not depend on WebHost, browser resources, SwiftUI hosting, WASI hosting,
  charts, animated images, or terminal-program embedding

### Platform integration products

- executable runner products `SwiftTUICLI` and `SwiftTUIWASI` build top-level
  execution layers on top of `SwiftTUIRuntime`
- host products and packages retain authored `SwiftTUIRuntime` apps inside
  platform-managed shells: `SwiftUIHost` for native SwiftUI, `SwiftTUIWebHost`
  for localhost-browser launch, and `Platforms/Web` for browser deployment
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

The implementation centers on this strict phase order:

```text
resolve -> measure -> place -> semantics -> draw -> raster -> commit
```

That ordering is visible in ``DefaultRenderer``, `FrameArtifacts`, `Pipeline`, and the regression suites.

## Coordinate Domains

Layout and raster placement use integer terminal cells: `CellPoint`,
`CellSize`, and `CellRect`. Pointer input, gestures, Canvas drawing, and
interpolation use continuous cell-space values: `Point`, `Size`, `Rect`, and
`Vector`. Pixel geometry is host metadata, not the normal authoring unit.

This split lets the same authored app run on cell-only terminals and on native,
web, or terminal-pixel hosts. The semantic snapshot can route against stable
cell regions while the handler receives the most precise point the runtime can
provide.

### Resolve

- Public `View` values are lowered into `ResolvedNode` trees
- Structural views such as `Group`, `ForEach`, and conditionals affect the resolved child set
- Environment and metadata are merged here
- Root presentation entries are declared during normal base resolution. The
  portal root reconciles those entries, then composes active overlays around the
  resolved base tree so the displayed base subtree keeps its authored identity
  space
- Reuse is conservative and keyed by identity, invalidation scope, and compatible context

### Measure

- The layout engine probes resolved nodes under proposals and produces `MeasuredNode` trees
- Measurement is cacheable and side-effect free
- Custom layouts, alignment, spacing, `fixedSize`, and text measurement live here

### Place

- The same layout engine turns measured nodes into `PlacedNode` trees
- Placement is the authoritative geometry source for interaction regions, content bounds, scrolling extents, and later composition

### Semantics

- The semantic extractor walks the placed tree to derive focus regions, interaction regions, action routes, selection routes, and scroll routes
- Disabled state, interaction gates, and hit policy are respected here so
  non-interactive nodes fall out of routing

### Draw

- The draw extractor lowers placed nodes into draw commands
- Styling, text payloads, rules, shapes, collection chrome, table chrome, and indicators are handled here

### Raster

- The rasterizer converts draw commands into a cell surface with styled runs
- Terminal capability adaptation is not part of layout; it happens later during presentation
- Raster cells are data, not terminal bytes. The presentation layer is
  responsible for sanitizing control scalars and hyperlink destinations before
  writing to a terminal stream.

### Commit

- The commit planner packages semantic, lifecycle, and handler-installation work into a `CommitPlan`
- The view graph owns lifecycle state and emits explicit appear, disappear, task-start, and task-cancel operations during frame finalization
- Public `.onAppear`, `.onDisappear`, and `.task` hooks lower into this phase rather than firing during resolve

## Runtime Model

``RunLoop`` wraps the pure frame pipeline in an interactive session, coordinating terminal I/O, input parsing, signal handling, frame scheduling, state invalidation, focus routing, and lifecycle staging around the pure frame products.

The core runtime is intentionally narrow today:

- one terminal host
- one active root scene in `SwiftTUIRuntime`
- one full-canvas ``WindowGroup`` per session
- keyboard-first interaction with optional mouse input when the terminal supports reporting

Platform integration and multi-scene orchestration live in sibling products in
the root package rather than in the `SwiftTUIRuntime` product itself.

Those integration layers serve three execution modes:

- terminal-native executable execution via `TerminalRunner.run(MyApp.self)` or
  the default `App.main()` provided by the `SwiftTUI` convenience product
- WASI executable execution and manifest generation via `WASIRunner` in
  `SwiftTUIWASI`
- host-managed embedding via `SceneManifest(for:)` and
  `HostedRasterSurface` plus `HostedSceneSession(for:sceneID:surface:)`, as used by `SwiftUIHost` and
  `Platforms/Web`
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
- `FrameArtifacts`: the full frame bundle plus diagnostics for testing and inspection

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
- <doc:Vision>
- <doc:Host-Integration>
- [Architecture details](https://github.com/adamz/swift-tui/blob/main/docs/ARCHITECTURE.md)
