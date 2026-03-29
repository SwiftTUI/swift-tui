# Architecture

Last updated: March 26, 2026

## Target Boundaries

### `Core`

- Defines the shared geometry, styling, semantic, raster, and commit data types
- Implements layout, semantic extraction, draw extraction, rasterization, diagnostics, scheduling, and commit planning
- Stays pure with respect to terminal I/O

### `View`

- Exposes the SwiftUI-shaped authoring surface
- Resolves authored views into core nodes
- Hosts property wrappers, environment plumbing, focus APIs, layouts, and controls

### `TerminalUICharts`

- Builds compact chart and metric views on top of `View`
- Reuses the same layout, semantic, draw, and raster pipeline
- Remains a separate track so charting does not distort the core library surface

### `TerminalUI`

- Re-exports the public package surface that matters for single-session runtime work
- Adds terminal host integration, alternate-screen ownership, input parsing, signal handling, capability-aware presentation, `RunLoop`, and rendering entry points

### `TerminalUIScenes`

- Builds the optional scene-runtime layer on top of `TerminalUI`
- Adds pty-backed secondary scene sessions, socket discovery, attachment, and multi-scene orchestration
- Currently carries the public scene-launch path, including the single-window case

Detailed per-file ownership lives in [SOURCE_LAYOUT.md](SOURCE_LAYOUT.md).

## Frame Pipeline

The implementation centers on this strict phase order:

```text
resolve -> measure -> place -> semantics -> draw -> raster -> commit
```

That ordering is visible in `DefaultRenderer`, `FrameArtifacts`, `Pipeline`, and the regression suites.

### Resolve

- Public `View` values are lowered into `ResolvedNode` trees through package-only lowering helpers
- Structural views such as `Group`, `ForEach`, and conditionals affect the resolved child set
- Environment and metadata are merged here
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
- Lifecycle ownership is flattened into `CommittedLifecycleState`, diffed against the previous committed frame, and emitted as explicit appear, disappear, task-start, and task-cancel operations
- Public `.onAppear`, `.onDisappear`, and `.task` hooks lower into this phase rather than firing during resolve

## Runtime Model

`RunLoop` wraps the pure frame pipeline in an interactive terminal session.

It coordinates:

- `TerminalHost` for raw mode, alternate-screen ownership, surface sizing, and writes
- input readers and signal readers for event streams
- `FrameScheduler` for invalidations, deadlines, signals, and wakeups
- `StateContainer` plus dynamic state storage for local state changes
- focus, action, key, lifecycle, task, pointer, and focused-value registries
- `LifecycleCoordinator` and `TaskRunner` for post-present lifecycle reconciliation
- a package-private window host that makes each `WindowGroup` fill and clip to the terminal canvas

The core runtime is intentionally narrow today:

- one terminal host
- one active root scene in `TerminalUI`
- one full-canvas `WindowGroup` per session
- keyboard-first interaction with optional mouse input when the terminal supports reporting

Multi-scene orchestration is packaged separately in `TerminalUIScenes`.

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

- The public styling story is semantic and appearance-derived first, not token-theme first
- Terminal appearance can be inferred heuristically or queried actively from the host
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
