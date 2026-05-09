---
title: "feature: extend Canvas for pixel-grid rendering"
type: feature
status: shipped
date: 2026-04-28
---

# feature: extend Canvas for pixel-grid rendering

> **Status:** Shipped for Canvas rendering and the gifeditor migration. The
> pixel-grid, direct-cell, styled-Braille, half-block, example, and documentation
> phases are implemented. Pointer precision remains explicitly deferred to the
> fractional-coordinate and Canvas/pointer active work.

> **Current repo note (2026-05-08):** the standalone `Examples/canvas` package
> named by this historical record is not present in the current checkout. Use
> root Canvas tests and `Examples/gifeditor` as the maintained verification
> surfaces unless a new standalone Canvas example is explicitly prioritized.

## Overview

Extend `Canvas` into the framework primitive used for dense editable pixel
surfaces. This replaces the earlier "add a separate PixelMap" direction: the
new work should grow the existing Canvas family while preserving today's
Braille-subpixel drawing behavior.

The immediate downstream customer is `Examples/gifeditor`, whose current
pixel grid is implemented as thousands of `Rectangle().fill(...).frame(1x1)`
nodes. The desired framework shape is a Canvas-backed pixel grid that can
render:

- one logical pixel per terminal cell,
- two vertical logical pixels per terminal cell using near-square half-blocks,
- Braille-subpixel drawings with per-cell style where possible.

Pointer precision should improve when terminals support pixel mouse reporting,
but the Canvas rendering work must not depend on that support.

## Implementation Progress

- 2026-04-28: Phase 1 is implemented as `Examples/canvas`. The package
  contains a `canvas-demo` executable, a testable `CanvasDemoViews` library,
  model/rendering tests, README coverage, and repo script wiring.
- 2026-04-28: Phases 2-7 are implemented in the framework. `CanvasContext`
  now supports direct terminal-cell writes, full-cell pixel grids, vertical
  half-block pixel grids, and styled Braille cells with last-writer-wins
  conflict handling inside one terminal cell.
- 2026-04-28: Phase 9 is implemented for `Examples/gifeditor`. The editor
  canvas now renders through Canvas-backed pixel-grid layers with a sparse
  Canvas overlay layer for cursor, anchors, and selection marks. A new
  `GIFEditorUITests` target covers full-cell and half-block rendering.
- 2026-04-28: Phase 10 documentation updates are recorded. Public API
  inventory, example index, and GIF editor README describe the Canvas-backed
  pixel-grid path.
- 2026-04-28: Phase 8 pointer precision remains deferred to the structural
  input/gesture workstream. This worktree intentionally did not change
  `MouseEvent`, terminal mouse protocol negotiation, or pointer dispatch.

## Current Constraints

Today `Canvas` is a Braille-only drawing surface:

- `CanvasDrawing.draw(into:)` receives a `CanvasContext` in Braille subpixel
  coordinates.
- Each terminal cell contains a 2x4 Braille mask.
- The rasterizer applies one final foreground/background style to every lit
  Braille cell in the drawing.
- Empty cells are not written.

That is useful for sparklines, curves, masks, and compact vector-like drawing.
It is not sufficient for GIF-editor-style indexed pixels because each terminal
cell needs its own color.

## Design Decisions

- Extend `Canvas`; do not add a separate `PixelMap` primitive.
- Preserve `Canvas(Drawing)` and existing `CanvasDrawing` semantics.
- Keep terminal geometry cell-denominated. Do not change `Point`, `Size`, or
  `Rect` to fractional coordinates.
- Add richer Canvas output internally before exposing broad public API.
- Treat multi-color Braille as per-terminal-cell style, not per-Braille-dot
  style. A terminal Braille glyph can carry only one foreground and one
  background color.
- For same-cell Braille color conflicts, use a deterministic documented rule.
  Last writer wins is the preferred default because it is simple and matches
  imperative drawing expectations.
- Treat half-block rendering as a Canvas pixel-grid mode. It is a rendering
  density feature first and an editing feature only when input precision allows
  it.
- Keep pointer precision tiered:
  - cell mouse works everywhere current mouse reporting works,
  - pixel mouse via SGR-Pixels `?1016` enables sub-cell editing where supported,
  - hosted web/GUI transports can provide direct pixel offsets separately.

## Non-goals

- No structural keyboard shortcut work in this branch.
- No termination-signal or save-before-quit lifecycle work in this branch.
- No broad gesture-system redesign in this branch.
- No pixel-denominated layout system.
- No promise that half-block mouse editing is precise inside tmux or terminals
  that only report cell coordinates.
- No per-Braille-dot true-color model; terminal cells do not support that.

## Phase 1: Canvas Verification Example

Create `Examples/canvas` as the executable verification surface for this work.
This must happen before framework changes so behavior can be compared against
today's Canvas implementation.

Initial app requirements:

- package name: `canvas-demo`,
- executable product: `canvas-demo`,
- local package dependency: `.package(name: "swift-tui", path: "../..")`,
- runner dependency: `../../Runners/SwiftTUICLI`,
- a small view target that can be tested without launching a real terminal,
- a current-Canvas drawing surface backed by `CanvasDrawing`,
- keyboard cursor movement,
- draw, erase, and clear commands,
- visible cursor overlay,
- one active foreground color, matching today's uniform Canvas style limit,
- a compact help/status row that reports mode and cursor position.

The first implementation should intentionally use only existing public Canvas
API. If it is awkward, that awkwardness is evidence for the later API design.

Verification:

```bash
cd Examples/canvas
swift run canvas-demo
swift test
```

Acceptance criteria:

- The example runs as a terminal app.
- The drawing model renders through `Canvas(Drawing)`, not a rectangle grid.
- Tests can render the view and assert Braille cells are emitted for drawn
  strokes.
- Tests cover erase/clear by proving previously lit cells disappear from the
  drawing model.

## Phase 2: Baseline Canvas Tests

Before changing Canvas internals, strengthen tests around current behavior:

- existing `CanvasViewTests` remain green,
- uniform foreground/background behavior is pinned,
- empty drawings write no visible glyphs,
- clipping behavior remains unchanged,
- draw-payload equality continues to deduplicate equal drawings.

This phase exists to keep compatibility honest while the internal backing
model changes.

## Phase 3: Internal Canvas Layer Model

Introduce an internal representation that can carry more than a Braille mask
without changing public behavior.

The likely internal shape is a small set of layers or commands:

- Braille mask layer,
- optional per-cell style layer,
- optional direct cell layer for glyph/style writes.

`CanvasContext` can continue to expose the existing Braille methods while
recording into the new internal backing. The rasterizer should first reproduce
today's output exactly, then gain new branches for direct cell writes.

Acceptance criteria:

- no public API behavior changes,
- current Canvas tests pass without fixture churn,
- the new backing can represent a styled terminal cell independent of the
  Braille mask.

## Phase 4: Direct Per-cell Canvas Drawing

Add a constrained API for drawing terminal cells directly through Canvas.

Candidate API shape:

```swift
context.setCell(
  x: x,
  y: y,
  character: " ",
  foreground: nil,
  background: color
)
```

or a narrower convenience:

```swift
context.fillCell(x: x, y: y, color: color)
```

The narrow helper should be preferred if it covers the GIF editor and example
needs. A fully general glyph API can be added later if the local use cases
justify it.

Acceptance criteria:

- one Canvas drawing can emit cells with different background colors,
- existing Braille drawings continue to work,
- direct cell writes obey clipping,
- direct cell writes compose predictably with Braille writes.

## Phase 5: Full-cell Pixel Grid Mode

Add a Canvas pixel-grid entry point for one logical pixel per terminal cell.

Candidate API shape:

```swift
Canvas.pixelGrid(
  width: width,
  height: height,
  pixels: pixels,
  mode: .fullCell
)
```

The exact public initializer can change during implementation, but the model
should stay simple:

- flat row-major pixel buffer,
- explicit width and height,
- transparent pixel handling,
- palette/indexed-color callers can pre-resolve to `Color?`,
- the rasterizer writes one terminal cell per logical pixel.

Acceptance criteria:

- a dense color grid renders without creating one view node per pixel,
- transparent pixels resolve through a caller-specified or environment-derived
  background policy,
- odd and empty dimensions are safe,
- the Canvas example can switch from current Braille drawing to full-cell
  pixel-grid rendering.

## Phase 6: Multi-color Braille Mode

Extend Braille Canvas drawing to support per-cell style.

Important constraint: this is not per-dot color. A single Braille glyph has one
foreground color for all lit dots in that terminal cell, plus one background
color. When differently colored operations touch the same Braille cell, the
style conflict must collapse to one style.

Policy:

- support per-cell foreground/background style,
- keep today's final `context.foreground` / `context.background` fallback,
- use last-writer-wins for same-cell style conflicts unless implementation
  evidence points to a better rule,
- document the limitation clearly.

Acceptance criteria:

- separate Braille cells can carry different foreground colors,
- same-cell conflicts are deterministic and tested,
- existing drawings that do not use per-cell style render exactly as before.

## Phase 7: Half-block Pixel Grid Mode

Add vertical half-block packing for near-square dense pixel rendering.

Mode:

```swift
.verticalHalfBlock
```

Mapping:

- terminal width = logical pixel width,
- terminal height = `ceil(logicalPixelHeight / 2)`,
- top logical pixel maps to foreground,
- bottom logical pixel maps to background,
- the glyph is usually `▀`,
- matching top/bottom colors may be optimized to a space with background color,
- odd final logical rows resolve the missing bottom half through the background
  policy.

`CellPixelMetrics` should inform diagnostics or mode quality. Half-blocks are
visually square when the terminal cell aspect ratio is close to 2.0. The
rendering mode should still work on other terminals, but callers should be
able to know when output is likely distorted.

Acceptance criteria:

- a 2-row logical grid renders into one terminal row,
- top and bottom colors are preserved through foreground/background styling,
- transparent top/bottom halves resolve predictably,
- odd logical heights are tested,
- the Canvas example exposes a full-cell vs half-block toggle.

## Phase 8: Pointer Precision Integration

Keep rendering independent from input precision, then add richer pointer data.

Current mouse input reports a cell `Point`. To support precise half-block and
Braille editing where possible, add optional precision alongside the existing
cell location rather than replacing it:

```swift
public struct MouseEvent {
  public var location: Point
  public var pixelLocation: PixelPoint?
  public var cellPixelOffset: PixelPoint?
}
```

Terminal path:

- continue enabling current mouse reporting,
- add SGR-Pixels `?1016` only when the capability/profile opts in,
- parse reported coordinates as pixels when pixel mode is active,
- derive `location` from `CellPixelMetrics`,
- expose sub-cell offsets for Canvas hit testing.

Hosted path:

- WASI/web and GUI transports can send pixel offsets directly.
- They do not need to emulate terminal escape protocols internally.

Canvas fallback policy:

- full-cell editing works with cell mouse,
- half-block editing uses top/bottom hit testing only when `cellPixelOffset`
  is available,
- otherwise half-block mode remains usable for display and keyboard-targeted
  editing.

Acceptance criteria:

- existing mouse tests keep passing,
- pixel mouse parsing is separately tested,
- Canvas hit testing can distinguish top vs bottom half when precision exists,
- unsupported terminals degrade to current cell behavior.

## Phase 9: GIF Editor Migration

Move `Examples/gifeditor` from rectangle-grid rendering to Canvas pixel-grid
rendering after the Canvas example validates the new API.

Migration goals:

- preserve visual output in full-cell mode,
- remove the per-pixel `Rectangle` view tree,
- keep the editor's document model unchanged,
- add optional half-block display/edit mode,
- keep keyboard cursor editing as the reliable fallback,
- use precise pointer editing only when the runtime reports sub-cell pointer
  data.

Acceptance criteria:

- `Examples/gifeditor` tests pass,
- the editor can render existing documents through Canvas,
- large canvases no longer pay per-pixel view-node resolve cost,
- half-block mode can be toggled without corrupting document coordinates.

## Phase 10: Documentation and Verification

Update public docs once API shape settles:

- Canvas DocC,
- `docs/PUBLIC_API_INVENTORY.md`,
- `docs/SOURCE_LAYOUT.md` if files move or new files are added,
- `Examples/README.md`,
- `Examples/gifeditor/README.md` Known framework gaps.

Recommended verification sequence during implementation:

```bash
swiftly run swift test --filter SwiftTUITests.CanvasViewTests
cd Examples/canvas && swift test
cd Examples/gifeditor && swift test
bun run test
```

Run the Canvas example manually at each major phase. For pointer precision,
manual checks should include at least:

- a direct terminal with only cell mouse,
- a terminal known to support SGR-Pixels `?1016`,
- a tmux session to confirm graceful fallback,
- the hosted web/GUI path if it is wired into the same feature.

## Completion Definition

The Canvas-adaptation worktree is complete when:

- `Examples/canvas` exists and exercises the Canvas feature set,
- Canvas supports dense per-cell color rendering,
- Canvas supports full-cell and vertical half-block pixel grids,
- Braille Canvas supports deterministic per-cell multi-color styling,
- GIF editor renders its pixel grid through Canvas instead of thousands of
  rectangle views,
- all targeted example tests and the repo-wide gate pass.

The broader editor feature set still needs the structural pointer-input phase
when that workstream is active: optional pointer precision should distinguish
sub-cell locations where the host reports them.
