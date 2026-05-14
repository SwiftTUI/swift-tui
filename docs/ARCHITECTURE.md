# Architecture

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
- Owns GIF encoding and decoding through the vendored `swift-gif` package
- Keeps animated media concerns out of the core `SwiftTUI` runtime surface

### `SwiftTUIRuntime`

- Re-exports the public authoring and core surface that matters for shared runtime work
- Adds terminal host integration, alternate-screen ownership, input parsing,
  capability-aware presentation, `RunLoop`, and rendering entry points
- Provides host-facing runtime seams such as scene manifests, retained hosted-scene sessions, shared terminal control-message parsing, injected input streams, and streaming terminal output sinks for non-terminal hosts

### `SwiftTUI`

- Release-facing convenience product for terminal-native apps
- Re-exports `SwiftTUIRuntime`, `SwiftTUIArguments`, and `SwiftTUICLI` so
  terminal-native apps can write only `import SwiftTUI`
- Does not depend on WebHost, FlyingFox, browser resources, SwiftUI hosting,
  WASI hosting, charts, animated images, or terminal-program embedding

### Platform integration products

- executable runner products `SwiftTUICLI` and `SwiftTUIWASI` build top-level
  execution layers on top of `SwiftTUIRuntime`
- host products and packages retain authored `SwiftTUIRuntime` apps inside
  platform-managed shells: `SwiftUIHost` for native SwiftUI, `SwiftTUIWebHost`
  for localhost-browser launch, and `Platforms/Web` for browser deployment
- `SwiftTUIWebHost` is compound: its runner starts a localhost browser host and
  `SwiftTUIWebHostCLI` composes terminal and WebHost launch routing
- terminal-program embedding lives in `SwiftTUITerminal` and
  `SwiftTUIPTYPrimitives`; first-class terminal workspaces live in
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

Detailed terminology lives in [TERMINOLOGY.md](TERMINOLOGY.md). Detailed
per-file ownership lives in [SOURCE_LAYOUT.md](SOURCE_LAYOUT.md).

## Frame Pipeline

The implementation centers on this strict phase order:

```text
resolve -> measure -> place -> semantics -> draw -> raster -> commit
```

That ordering is visible in `DefaultRenderer`, `FrameArtifacts`, `Pipeline`, and the regression suites.

## Coordinate Domains

SwiftTUI keeps layout and raster placement integer-cell based while pointer,
drawing, and interpolation APIs use continuous cell-space geometry.

- `CellPoint`, `CellSize`, and `CellRect` describe integer terminal cells.
  They are the units for layout placement, semantic bounds, raster surfaces,
  terminal output, and compatibility hit regions.
- `Point`, `Size`, `Rect`, and `Vector` describe continuous positions in the
  same terminal cell coordinate space. A `Point(x: 2.25, y: 1.5)` is inside
  cell `(2, 1)`, not in device pixels.
- `PixelPoint`, `PixelSize`, and `CellPixelMetrics` are provenance and host
  metadata. They explain how a host or terminal mapped device pixels into
  cell-space input, but they do not change layout units.

The semantics phase still routes through cell-denominated regions so controls
remain stable on cell-only terminals. Pointer handlers receive the original
continuous `PointerLocation` after routing, and authored gesture values expose
continuous `Point` values even when the runtime had to synthesize the center of
an integer cell as a fallback.

### Resolve

- Public `View` values are lowered into `ResolvedNode` trees through package-only lowering helpers
- Structural views such as `Group`, `ForEach`, and conditionals affect the resolved child set
- Environment and metadata are merged here
- Root presentations are declared during normal base resolution as portal
  entries. The graph-owned portal root reconciles those declarations, then
  composes active entries through `OverlayStack` so hosted content has ordinary
  view-graph ownership under the portal destination.
- The render pipeline exposes the authored root directly when no overlay is
  active. When overlays are active, the composed overlay stack becomes the
  downstream resolved root for measure, place, semantics, draw, raster, and
  commit.
- Reuse is conservative and keyed by identity, invalidation scope, and compatible context

### Measure

- `LayoutEngine` probes resolved nodes under proposals and produces `MeasuredNode` trees
- Measurement is cacheable and side-effect free
- Custom layouts, alignment, spacing, `fixedSize`, and text measurement live here

### Place

- The same layout engine turns measured nodes into `PlacedNode` trees
- Placement is the authoritative geometry source for interaction regions, content bounds, scrolling extents, and later composition

### Semantics

- `SemanticExtractor` walks the placed tree to derive focus regions, interaction regions, action routes, selection routes, and scroll routes
- Disabled state, interaction gates, and hit policy are respected here so
  non-interactive nodes fall out of routing without being unmounted

### Draw

- `DrawExtractor` lowers placed nodes into draw commands
- Styling, text payloads, rules, shapes, collection chrome, table chrome, and indicators are handled here

### Raster

- `Rasterizer` converts draw commands into a cell surface with styled runs
- Terminal capability adaptation is not part of layout; it happens later during presentation
- Raster cells are data, not terminal bytes. The presentation layer is
  responsible for sanitizing control scalars and hyperlink destinations before
  writing to a terminal stream.

### Commit

- `CommitPlanner` packages semantic, lifecycle, and handler-installation work into `CommitPlan`
- `ViewGraph` owns lifecycle state and emits explicit appear, disappear, task-start, and task-cancel operations during frame finalization
- Portal teardown flows through ordinary structural child removal, so dismissed
  overlay subtrees cancel tasks, fire disappear handlers, and prune runtime
  registrations through the same committed-frame path as other UI.
- Public `.onAppear`, `.onDisappear`, and `.task` hooks lower into this phase rather than firing during resolve

## Presentation Primitives

Root-level UI is composed from package-internal primitives rather than a
presentation-only host path:

- `Portal` carries root-overlay declarations from arbitrary source subtrees to
  the nearest portal root while resolving hosted content under destination-owned
  identities.
- `OverlayStack` draws the base and active overlays in deterministic
  `(zIndex, activationOrdinal, stableID)` order and bridges the scene focus
  scope onto overlay content.
- `InteractionGate` marks a subtree as visible but unavailable for input.
  Semantics omit gated focus, command, pointer, gesture, drop, text-input, and
  focused-value routes while lifecycle and tasks remain mounted.
- `DismissStack` stores topmost-dismiss actions with the same ordering model as
  drawing, so Escape routing is not coupled to presentation family names.

The built-in sheet, alert, confirmation-dialog, menu, and toast APIs are
adapters over those primitives.

## Why The Phase Split Matters

Keeping the phases explicit gives the project a few durable advantages:

- tests can pin exact behavior at the right abstraction boundary
- layout and semantics do not need terminal escape-sequence knowledge
- runtime presentation can evolve without rewriting layout
- diagnostics can report where work was computed versus reused

The first and last bullets are what motivates the strict phase order in code. Collapsing two phases would force regression tests to overspecify (asserting on combined output instead of one phase) and would blur the diagnostic signal that distinguishes "we reused this" from "we recomputed this." Both costs accrue silently and only show up when a regression resists localization. The split is the cheaper path.

## Runtime Model

`RunLoop` wraps the pure frame pipeline in an interactive session.

It coordinates:

- `TerminalHost` for raw mode, alternate-screen ownership, surface sizing, and writes
- `HostedRasterSurface` for native hosts that consume `RasterSurface` and `SemanticSnapshot` directly
- `HostedSceneSession` retained scene execution for embedded SwiftUI hosts
- input readers and signal readers for event streams
- `InjectedTerminalInputReader` for wrapper-managed byte or event delivery that still shares the terminal control-message contract
- `FrameScheduler` for invalidations, deadlines, signals, and wakeups
- `StateContainer` plus dynamic state storage for local state changes
- focus, action, key, lifecycle, task, pointer, and focused-value registries
- `LifecycleCoordinator` and `TaskRunner` for post-present lifecycle reconciliation
- a package-private window host that makes each `WindowGroup` fill and clip to the terminal canvas

The core runtime is intentionally narrow today:

- one terminal host
- one active root scene in `SwiftTUIRuntime`
- one full-canvas `WindowGroup` per session
- keyboard-first interaction with optional pointer input when the host or
  terminal supports reporting

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
- `DrawNode`: draw commands for text, shapes, rules, lists, tables, and indicators
- `RasterSurface`: final cell grid plus style runs
- `CommitPlan`: runtime-facing semantic, lifecycle, and handler work
- `FrameArtifacts`: the full frame bundle plus diagnostics for testing and inspection

## Styling And Presentation

- The public styling story is semantic-token-first: TUI views author against
  `.foreground`, `.background`, `.warning`, `.tint`, and related roles
- The active host integration chooses the active theme; the inner TUI app does
  not branch on host style variants or inspect theme choice directly
- Terminal appearance can be inferred heuristically or queried actively from the
  host and can synthesize the default semantic theme when no explicit host theme
  is provided
- Presentation lowers raster surfaces into ASCII, ANSI16, ANSI256, or true-color output
- Presentation sanitizes authored text and OSC 8 hyperlink destinations before
  emitting terminal bytes; layout, semantics, and raster artifacts never need to
  encode terminal-control safety rules themselves
- Terminal capability affects presentation, not layout semantics

## Transitional Seams

The repository still carries a few package-only seams:

- lowerer protocols such as `ViewNode` and `ResolvableView`
- internal resolver and lifecycle seams used by tests and runtime plumbing

Those seams should remain adapters. They are not part of the public authoring story and should not leak back into the supported surface.

## Related Docs

- [STATUS.md](STATUS.md): current implementation status and remaining constraints
- [RUNTIME.md](RUNTIME.md): runtime behavior, lifecycle semantics, and incremental cost model
- [SOURCE_LAYOUT.md](SOURCE_LAYOUT.md): source ownership map
- [PUBLIC_API_INVENTORY.md](PUBLIC_API_INVENTORY.md): canonical public and package-only surface areas
- [PUBLIC_SURFACE_POLICY.md](PUBLIC_SURFACE_POLICY.md): review policy for future public API additions
- [TESTING_AND_FIXTURE_POLICY.md](TESTING_AND_FIXTURE_POLICY.md): fixture, performance, and architecture regression policy
- [VISION.md](VISION.md): philosophy, scope, and deferred items
