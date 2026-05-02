# Architecture

## Target Boundaries

### `Core`

- Defines the shared geometry, styling, semantic, raster, and commit data types
- Implements layout, semantic extraction, draw extraction, rasterization, diagnostics, scheduling, and commit planning
- Stays pure with respect to terminal I/O

### `View`

- Exposes the SwiftUI-shaped authoring surface
- Resolves authored views into core nodes
- Hosts property wrappers, environment plumbing, focus APIs, layouts, and controls

### `SwiftTUICharts`

- Builds compact chart and metric views on top of `View`
- Reuses the same layout, semantic, draw, and raster pipeline
- Remains a separate track so charting does not distort the core library surface

### `SwiftTUI`

- Re-exports the public package surface that matters for single-session runtime work
- Adds terminal host integration, alternate-screen ownership, input parsing, signal handling, capability-aware presentation, `RunLoop`, and rendering entry points
- Hosts host-facing runtime seams such as scene manifests, retained hosted-scene sessions, shared terminal control-message parsing, injected input streams, and streaming terminal output sinks for non-terminal hosts

### Platform integration packages

- executable runner packages `Runners/SwiftTUICLI` and `Runners/SwiftTUIWASI` build top-level execution layers on top of `SwiftTUI`
- embedded host packages `GUI/SwiftUIHost` and `GUI/WebHost` host the same authored `SwiftTUI` apps inside platform-managed shells

The conceptual model is:

```text
authored app surface -> shared SwiftTUI runtime -> platform integration package -> platform shell
```

That last integration layer comes in two forms:

- executable runner packages own top-level execution and default `App.main()` stories
- embedded host packages retain `HostedSceneSession` values inside another app or runtime lifecycle

Detailed per-file ownership lives in [SOURCE_LAYOUT.md](SOURCE_LAYOUT.md).

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
- Root-hoisted presentations are declared during normal base resolution, then
  composed around the resolved base tree afterward so the displayed base
  subtree keeps its authored identity space
- Presentation hosts reconcile any host-owned mirrored presentation state
  from the current resolved base tree before choosing overlay entries;
  selective dirty evaluation can re-resolve only the declaring subtree,
  especially under wrapper and scene hosts
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
- Disabled state and hit policy are respected here so non-interactive nodes fall out of routing

### Draw

- `DrawExtractor` lowers placed nodes into draw commands
- Styling, text payloads, rules, shapes, collection chrome, table chrome, and indicators are handled here

### Raster

- `Rasterizer` converts draw commands into a cell surface with styled runs
- Terminal capability adaptation is not part of layout; it happens later during presentation

### Commit

- `CommitPlanner` packages semantic, lifecycle, and handler-installation work into `CommitPlan`
- `ViewGraph` owns lifecycle state and emits explicit appear, disappear, task-start, and task-cancel operations during frame finalization
- Presentation dismissal cleanup must stay scoped to the dismissed overlay
  subtree identities instead of broad stale-subtree sweeps that can tear down
  unrelated retained content
- Public `.onAppear`, `.onDisappear`, and `.task` hooks lower into this phase rather than firing during resolve

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
- `StreamingTerminalHost` for embedded hosts that need the same presentation contract without owning a file descriptor
- `HostedSceneSession` native surface hosting for embedded SwiftUI hosts that consume `RasterSurface` directly
- input readers and signal readers for event streams
- `InjectedTerminalInputReader` for wrapper-managed byte or event delivery that still shares the terminal control-message contract
- `FrameScheduler` for invalidations, deadlines, signals, and wakeups
- `StateContainer` plus dynamic state storage for local state changes
- focus, action, key, lifecycle, task, pointer, and focused-value registries
- `LifecycleCoordinator` and `TaskRunner` for post-present lifecycle reconciliation
- a package-private window host that makes each `WindowGroup` fill and clip to the terminal canvas

The core runtime is intentionally narrow today:

- one terminal host
- one active root scene in `SwiftTUI`
- one full-canvas `WindowGroup` per session
- keyboard-first interaction with optional pointer input when the host or
  terminal supports reporting

Platform integration and multi-scene orchestration are packaged separately in
peer platform integration packages rather than in the root `SwiftTUI`
library.

Those integration layers serve three execution modes:

- terminal-native executable execution via `TerminalRunner.run(MyApp.self)` or the default `App.main()` provided by `Runners/SwiftTUICLI`
- WASI executable execution and manifest generation via `WASIRunner` in `Runners/SwiftTUIWASI`
- host-managed embedding via `SceneManifest(for:)` and `HostedSceneSession(for:sceneID:...)`, as used by `GUI/SwiftUIHost` and `GUI/WebHost`

CLI scene management is executable-runner policy rather than an authored-scene
rule. One-window and multi-window apps share the same runner story; `SwiftTUI`
itself remains library-only.

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
- Hosts and embedded host packages choose the active theme; the inner TUI app does not
  branch on host style variants or inspect theme choice directly
- Terminal appearance can be inferred heuristically or queried actively from the
  host and can synthesize the default semantic theme when no explicit host theme
  is provided
- Presentation lowers raster surfaces into ASCII, ANSI16, ANSI256, or true-color output
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
