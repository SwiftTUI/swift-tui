# Architecture

A tour of the package boundaries, the strict frame pipeline, and the data products that flow between phases.

## Overview

TerminalUI is split into four targets so that pure pipeline work, authoring work, runtime work, and chart work can each evolve at their own pace without blurring concerns. This article documents those boundaries and the seven-phase frame pipeline that connects them.

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
- Adds terminal host integration, alternate-screen ownership, input parsing, signal handling, capability-aware presentation, ``RunLoop``, and rendering entry points
- Hosts host-facing runtime seams such as scene manifests, retained hosted-scene sessions, shared terminal control-message parsing, injected input streams, and streaming terminal output sinks for non-terminal hosts

### Platform integration packages

- executable runner packages `Runners/TerminalUICLI` and `Runners/TerminalUIWASI` build top-level execution layers on top of `TerminalUI`
- embedded host packages `GUI/SwiftUITUIGUI` and `GUI/WebTUIGUI` host the same authored `TerminalUI` apps inside platform-managed shells

The conceptual model is:

```text
authored app surface -> shared TerminalUI runtime -> platform integration package -> platform shell
```

That last integration layer comes in two forms:

- executable runner packages own top-level execution and default `App.main()` stories
- embedded host packages retain `HostedSceneSession` values inside another app or runtime lifecycle

For a deeper look at how those pieces fit together at the host boundary, see <doc:Host-Integration>.

## Frame Pipeline

The implementation centers on this strict phase order:

```text
resolve -> measure -> place -> semantics -> draw -> raster -> commit
```

That ordering is visible in ``DefaultRenderer``, `FrameArtifacts`, `Pipeline`, and the regression suites.

### Resolve

- Public `View` values are lowered into `ResolvedNode` trees
- Structural views such as `Group`, `ForEach`, and conditionals affect the resolved child set
- Environment and metadata are merged here
- Root-hoisted presentations are declared during normal base resolution, then composed around the resolved base tree afterward so the displayed base subtree keeps its authored identity space
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
- Disabled state and hit policy are respected here so non-interactive nodes fall out of routing

### Draw

- The draw extractor lowers placed nodes into draw commands
- Styling, text payloads, rules, shapes, collection chrome, table chrome, and indicators are handled here

### Raster

- The rasterizer converts draw commands into a cell surface with styled runs
- Terminal capability adaptation is not part of layout; it happens later during presentation

### Commit

- The commit planner packages semantic, lifecycle, and handler-installation work into a `CommitPlan`
- The view graph owns lifecycle state and emits explicit appear, disappear, task-start, and task-cancel operations during frame finalization
- Public `.onAppear`, `.onDisappear`, and `.task` hooks lower into this phase rather than firing during resolve

## Runtime Model

``RunLoop`` wraps the pure frame pipeline in an interactive session, coordinating terminal I/O, input parsing, signal handling, frame scheduling, state invalidation, focus routing, and lifecycle staging around the pure frame products.

The core runtime is intentionally narrow today:

- one terminal host
- one active root scene in `TerminalUI`
- one full-canvas ``WindowGroup`` per session
- keyboard-first interaction with optional mouse input when the terminal supports reporting

Platform integration and multi-scene orchestration are packaged separately in peer platform integration packages rather than in the root `TerminalUI` library.

Those integration layers serve three execution modes:

- terminal-native executable execution via `TerminalCLIAppRunner.run(MyApp.self)` or the default `App.main()` provided by `Runners/TerminalUICLI`
- WASI executable execution and manifest generation via `TerminalWASIAppRunner` in `Runners/TerminalUIWASI`
- host-managed embedding via `TerminalUISceneManifest(for:)` and `HostedSceneSession(for:sceneID:...)`, as used by `GUI/SwiftUITUIGUI` and `GUI/WebTUIGUI`

CLI scene management is executable-runner policy rather than an authored-scene rule. One-window and multi-window apps share the same runner story; `TerminalUI` itself remains library-only.

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

- The public styling story is semantic-token-first: TUI views author against `.foreground`, `.background`, `.warning`, `.tint`, and related roles
- Hosts and embedded host packages choose the active theme; the inner TUI app does not branch on host style variants or inspect theme choice directly
- Terminal appearance can be inferred heuristically or queried actively from the host and can synthesize the default semantic theme when no explicit host theme is provided
- Presentation lowers raster surfaces into ASCII, ANSI16, ANSI256, or true-color output
- Terminal capability affects presentation, not layout semantics

## See Also

- <doc:Runtime>
- <doc:Vision>
- <doc:Host-Integration>
- [Architecture details](https://github.com/adamz/swift-terminal-ui/blob/main/docs/ARCHITECTURE.md)
