# Architecture

A guide to the package boundaries, composed runtime pipeline, and phase data
products.

## Overview

SwiftTUI uses focused targets. Pure pipeline work, authoring work, runtime work,
terminal convenience, platform hosts, and domain products can evolve without
blurring their concerns. This article documents those
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

### `SwiftTUICharts` (external)

- Ships from the peer repository
  [`SwiftTUI/swift-tui-charts`](https://github.com/SwiftTUI/swift-tui-charts)
- Builds compact chart and metric views on the public `SwiftTUIViews` surface
- Remains a separate package so charting does not distort the core library surface

### `SwiftTUIAnimatedImage`

- Builds finite pre-composed animated image views on top of `SwiftTUIViews`
- Owns GIF import and export through the vendored `swift-gif` package
- Keeps animated media concerns out of the core `SwiftTUI` runtime surface

### `SwiftTUIRuntime`

- Re-exports the public authoring and core surface that matters for shared runtime work
- Adds terminal host integration, alternate-screen ownership, input parsing,
  capability-aware presentation, ``RunLoop``, and rendering entry points
- Provides scene manifests and retained hosted-scene sessions for hosts
- Provides shared terminal control-message parsing and injected input streams
- Provides streaming terminal output sinks for non-terminal hosts

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
  platform-managed shells: `SwiftTUIWebHost` for localhost-browser launch,
  `SwiftTUIAndroidHost` for Android embedding, and `@swifttui/web` for browser
  deployment. The Apple-SDK-gated `SwiftUIHost` product lives in the separate
  `swift-tui-swiftui` package: https://github.com/SwiftTUI/swift-tui-swiftui
- `SwiftTUIWebHost` is compound: its runner starts a localhost browser host and
  `SwiftTUIWebHostCLI` composes terminal and WebHost launch routing
- terminal-program embedding lives in `SwiftTUITerminal` and
  `SwiftTUIPTYPrimitives`. The tabbed/split-pane workspace layer lives in the
  `terminal-workspace` example app in `SwiftTUI/swift-tui-examples`

The conceptual model is:

```text
authored app surface -> SwiftTUIRuntime -> platform integration product -> platform shell
```

That last integration layer comes in two forms:

- executable runner products own top-level execution and default `App.main()` stories
- host products retain `HostedSceneSession` values inside another app or runtime lifecycle
- compound products must say which side is in scope: runner, host bridge, or
  presentation surface

For more information about the host boundary, see <doc:Host-Integration>.

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

``RunLoop`` wraps the pure frame pipeline in an interactive session. It
coordinates terminal I/O, input parsing, signals, frames, state, focus, and
lifecycle staging.

The core runtime is intentionally narrow today:

- one terminal host
- one active root scene in `SwiftTUIRuntime`
- one full-canvas ``WindowGroup`` per session
- keyboard-first interaction with optional mouse input when the terminal supports reporting

Platform integration and multi-scene orchestration live in sibling products in
the root package rather than in the `SwiftTUIRuntime` product itself.

The canonical execution-mode matrix, cross-package ownership, and resolve
engine profiles live in
<doc:Hosts-And-Platforms>.
For the public
runtime seams used by executable and retained-session integrations, see
<doc:Host-Integration>.

CLI scene management is executable-runner policy rather than an authored-scene
rule. One-window and multi-window apps share the same runner story. Composed
hosts depend on `SwiftTUIRuntime` instead of the `SwiftTUI` terminal
convenience product.

## Important Data Products

- `RenderSnapshot`: public one-shot renderer output containing committed raster,
  semantics, presentation damage, and diagnostics.
- `RasterSurface`: final cell grid plus style runs.
- `SemanticSnapshot`: focus, interaction, action, selection, and scroll routing.
- `SemanticHostFrame`: committed host handoff containing raster output,
  semantics, focused identity, optional raster damage, and a producer sequence.
- `FrameDiagnostics`: public frame counts, work metrics, timing, runtime, and
  drop diagnostics.
- Package-only phase IR: `ResolvedNode`, `MeasuredNode`, `PlacedNode`,
  `DrawNode`, `CommitPlan`, and `FrameArtifacts`. These keep the implementation
  explicit without becoming host or app contracts.

## Styling And Presentation

- The public styling model uses semantic tokens. TUI views author against
  `.foreground`, `.background`, `.warning`, `.tint`, and related roles.
- The active host integration selects the active theme. The inner TUI app does
  not select or inspect host style variants.
- The runtime can infer the terminal appearance or query it from the host.
- If the host provides no theme, the runtime creates the default semantic
  theme.
- Presentation lowers raster surfaces into ASCII, ANSI16, ANSI256, or
  true-color output.
- Presentation sanitizes authored text and OSC 8 hyperlink destinations before
  it emits terminal bytes. Layout, semantics, and raster artifacts do not
  encode terminal-control safety rules.
- Terminal capability affects presentation, not layout semantics.

## See Also

- <doc:Runtime>
- <doc:Runtime-Render-Pipeline>
- <doc:Vision>
- <doc:Host-Integration>
