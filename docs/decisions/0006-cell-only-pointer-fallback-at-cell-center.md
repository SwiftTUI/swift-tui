---
adr: "0006"
title: "Cell-only pointer fallback synthesizes location at cell center"
status: accepted
date: 2026-04-29
sources:
  - docs/RUNTIME.md
  - docs/CELL_PIXEL_GEOMETRY_RESEARCH.md
  - docs/proposals/CELL_PIXEL_METRICS.md
---

# ADR-0006: Cell-only pointer fallback synthesizes location at cell center

## Context

TerminalUI keeps layout integer-cell-based but exposes continuous
cell-space geometry to gesture handlers, hover, drawing, and
interpolation APIs. A `Point(x: 2.25, y: 1.5)` is inside cell `(2, 1)`,
not in device pixels.

Pointer input quality varies enormously by terminal:

- **Cell-only terminals** (the documented compatibility matrix:
  xterm, xterm.js, foot, and various multiplexers in default mode)
  report mouse events at integer-cell granularity.
- **Sub-cell-capable terminals** (Kitty, WezTerm, iTerm2, foot in some
  modes) can report pixel coordinates via DEC private mode 1016
  (SGR-Pixels).
- **Native and web hosts** (`GUI/SwiftUITUIGUI`,
  `GUI/WebTUIGUI`) can deliver true pixel coordinates derived from
  device input.

Authored gesture code shouldn't have to branch on host capability. A
`DragGesture` should produce continuous `Point` values whether the
underlying terminal reports pixels or only cells.

## Decision

The runtime normalizes every pointer event into `PointerLocation`
with two fields:

- `cell: CellPoint` — the containing integer terminal cell, used for
  routing through the semantic snapshot.
- `location: Point` — the continuous cell-space point delivered to
  gestures, hover handlers, spatial taps, drags, and drop contexts.

When the underlying transport reports only cells, the runtime
**synthesizes `location` at the geometric center of the reported
cell**. Authored gesture handlers receive a continuous `Point` value
in every case; cell-only fallback is invisible at the API.

Hosts that *can* report sub-cell locations supply `location` directly
from their pixel coordinates divided by `CellPixelMetrics`. Authored
views that need to render precision-aware affordances can read
`PointerInputCapabilities` and `CellPixelMetrics` from the
environment without changing layout.

## Status

Accepted. The cell-only fallback is documented in the public
[Pointer-And-Canvas.md](../../Sources/View/View.docc/Pointer-And-Canvas.md)
authoring guide and pinned by `Tests/TerminalUITests` pointer
coordinate fixtures. Mouse precision resolution is settled before
the run loop's event pump starts; see
[RUNTIME.md](../RUNTIME.md) for the trust-policy and probe-order
rules.

## Consequences

**Enabled:**

- Authored gesture code is identical across terminal capabilities.
  No `if pointerInputCapabilities.hasSubCellPrecision` branches in
  ordinary view code.
- Snapshot tests of gesture behavior stay deterministic across
  capability profiles, because cell-only fallback always produces
  the same `(x + 0.5, y + 0.5)` synthesized point.
- Drag thresholds and hit regions can use continuous-cell math
  (e.g. "12 cells of drag activation distance") without knowing
  the host's reporting precision.

**Foreclosed:**

- Authored gestures cannot rely on sub-cell precision for
  correctness. A drag that requires precise pixel-level input
  should declare the requirement and degrade gracefully on
  cell-only terminals.
- The runtime cannot pretend cell-only events are pixel-precise
  for routing. Routing always uses `cell`; only the post-routing
  delivery uses `location`.

**Discipline imposed:**

- New pointer-facing public APIs must work meaningfully on
  cell-only terminals. "We can ship this once SGR-Pixels lands
  everywhere" is not an acceptable design plan.
- Hosts that supply sub-cell locations are responsible for
  consistent rounding so that `cell` and `location` agree about
  which cell contains the event.

The bet: terminal apps look the same at the API regardless of
where they run, and authoring gesture code does not require knowing
which terminal multiplexer the user happens to favor.
