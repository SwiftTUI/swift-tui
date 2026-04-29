# Joint Proposal: Sub-Cell Pointer Input

## Status

Joint design proposal from the Codex and Claude analyses.

This proposal assumes the framework is pre-release and that existing public API
can move when the resulting model is cleaner. Minimizing migration cost is not a
goal.

## Executive Summary

TerminalUI should expose sub-cell pointer input as **fractional cell
coordinates**, not raw pixels.

Pixels are what terminal and host protocols often report. Cells are the
framework's semantic unit for layout, hit testing, gestures, Canvas drawing, and
terminal output. The framework should convert host/protocol pixel positions at
the boundary and deliver positions in continuous cell space:

- `(0.0, 0.0)` is the top-leading edge of cell `(0, 0)`.
- `(0.5, 0.5)` is the center of cell `(0, 0)`.
- `(1.0, 0.0)` is the top-leading edge of cell `(1, 0)`.

When the host only supports cell-precision mouse reporting, the same API should
produce center-estimated fractional coordinates and report the precision level.
Consumers that do not care about sub-cell input can snap to the containing cell.
Consumers that do care can use the fractional values directly.

The highest-impact design move is a type-system split:

- `Point` becomes a `Double`-valued position in cell space.
- `Size` and `Rect` become `Double`-valued continuous geometry for drawing,
  paths, and shape math.
- `Vector` becomes a `Double`-valued delta/velocity in cell space.
- `CellPoint`, `CellSize`, and `CellRect` become integer layout geometry.

This keeps terminal layout honest and integer-cell based while allowing pointer,
gesture, animation, Canvas, chart, and drawing APIs to work at sub-cell
precision.

Canvas should be redesigned around this same coordinate model: Canvas drawing
coordinates are fractional cells, and the chosen rasterization grid determines
how those cells are converted to Braille, quadrant, sextant, half-block,
full-cell, or future pixel-exact output.

## Goals

- Make pointer locations inside a cell representable when the host provides
  them.
- Keep layout, placement, hit region identity, and terminal output
  cell-denominated.
- Preserve graceful degradation on terminals that only support integer cell
  mouse input.
- Make Canvas the first-class consumer of sub-cell input without making the
  feature Canvas-only.
- Improve direct manipulation controls such as sliders, scroll thumbs, chart
  cursors, splitters, resize handles, and image annotation surfaces.
- Design for native, web, and terminal hosts without forcing all hosts to support
  the same precision.
- Avoid exposing raw pixels as the primary application API.

## Non-Goals

- Source compatibility with the current integer `Point` gesture API.
- Pixel-based layout.
- Guaranteed sub-cell precision in every terminal.
- Making core controls depend on pointer precision.
- Enabling high-volume hover tracking globally.

## Current Framework Shape

The current pointer pipeline is integer-cell based:

- `MouseEvent.location` is `Point`.
- SGR mouse parsing immediately normalizes reported coordinates into a
  zero-based integer `Point`.
- `LocalPointerEvent.location` is also `Point`.
- `DragGesture.Value`, `SpatialTapGesture.Value`, `TapGesture`, and
  `LongPressGesture` all evaluate movement and positions in integer cells.
- `CoordinateSpace.resolve(...)` subtracts an integer target origin and returns
  an integer `Point`.

Canvas is already sub-cell in output but not in input:

- `CanvasContext` exposes a hardcoded Braille 2x4 subpixel grid.
- `CanvasPixelGridDrawing` separately supports full-cell and vertical
  half-block logical pixels.
- `Examples/canvas` maps a cell hit to a fixed subpixel anchor, so dragging
  inside a single cell cannot affect the sub-cell drawing.

The hosted surfaces already receive better information than the current API
preserves:

- Native AppKit/UIKit surfaces receive pixel pointer positions.
- Web surfaces receive DOM pointer coordinates and know `cellWidth` and
  `cellHeight`.
- Both currently floor to integer cells before Swift receives the event.

The framework already exposes cell pixel geometry:

- `CellPixelMetrics` exists and distinguishes `.reported` from `.estimated`.
- `GeometryProxy.cellPixelMetrics` and `EnvironmentValues.cellPixelMetrics`
  expose that geometry.
- Runtime hosts populate cell pixel size from terminal or hosted-surface data.

This geometry is necessary but not sufficient. The design also needs a pointer
input precision and provenance model.

## Prior Art

Most terminal UI frameworks expose mouse positions as cells. Crossterm and
Bubble Tea are representative: a mouse event carries row/column-style
coordinates. Ratatui keeps layout cell-based while exposing window pixel size as
geometry metadata.

The stronger precedents expose both coarse and precise information:

- Textual exposes integer cell coordinates and float pointer coordinates.
- Notcurses exposes cell coordinates plus sub-cell pixel offsets with sentinel
  values when unavailable.
- Blessed Python can request pixel mouse reporting, but that pushes pixel math
  to the consumer.

Terminal protocols also distinguish event class from coordinate encoding:

- SGR 1006 reports cells in `CSI < button ; x ; y M/m`.
- SGR-Pixels 1016 uses the same wire shape but reports pixels.
- DEC 2048 in-band size reports can provide terminal cell and pixel dimensions.

The lesson for TerminalUI is that apps almost always want cell-space positions,
not raw protocol coordinates. Swift's `Double` coordinates are the right
gradual-precision idiom: cell-only terminals produce whole-number or
center-estimated values; precise hosts produce fractional values.

References:

- XTerm control sequences: https://invisible-island.net/xterm/ctlseqs/ctlseqs.html
- Textual mouse events: https://textual.textualize.io/api/events/
- Crossterm MouseEvent: https://docs.rs/crossterm/latest/crossterm/event/struct.MouseEvent.html
- Ratatui WindowSize: https://docs.rs/ratatui/latest/ratatui/prelude/backend/struct.WindowSize.html
- Notcurses input and plane geometry: https://manpages.debian.org/experimental/libnotcurses-dev/notcurses_input.3.en.html
- WezTerm changelog: https://wezterm.org/changelog.html
- kitty protocol extensions: https://sw.kovidgoyal.net/kitty/misc-protocol/

## Core Coordinate Model

### Public Position Types

Adopt a two-family geometry model:

```swift
public struct Point: Equatable, Hashable, Sendable {
  public var x: Double
  public var y: Double
}

public struct Size: Equatable, Hashable, Sendable {
  public var width: Double
  public var height: Double
}

public struct Vector: Equatable, Hashable, Sendable {
  public var dx: Double
  public var dy: Double
}

public struct Rect: Equatable, Hashable, Sendable {
  public var origin: Point
  public var size: Size
}

public struct CellPoint: Equatable, Hashable, Sendable {
  public var x: Int
  public var y: Int
}

public struct CellSize: Equatable, Hashable, Sendable {
  public var width: Int
  public var height: Int
}

public struct CellRect: Equatable, Hashable, Sendable {
  public var origin: CellPoint
  public var size: CellSize
}
```

`Point` is a position in continuous cell space. `Size` and `Rect` are
continuous geometry for drawing, paths, shapes, and hit math. `Vector` is a
translation or velocity in continuous cell units. `CellPoint`, `CellSize`, and
`CellRect` are integer layout geometry.

This gives each role an honest name:

- Layout proposes, measures, places, draws, rasters, and commits integer cells.
- Pointer positions, gesture locations, velocities, Canvas primitives, paths,
  and animation can use fractional cell positions.

### Containing Cell And Fractions

`Point` should expose helpers:

```swift
extension Point {
  public var containingCell: CellPoint { get }
  public var fractionInCell: UnitPoint { get }
  public func snapped(_ rule: FloatingPointRoundingRule) -> CellPoint
}
```

The containing cell is `floor(x), floor(y)`. `fractionInCell` is normalized to
`0..<1` for points inside a cell.

### Pixel Provenance

Raw pixels are useful for diagnostics and image interop, but they should not be
the primary gesture location type.

```swift
public struct PixelPoint: Equatable, Hashable, Sendable {
  public var x: Double
  public var y: Double
}

public enum PointerPrecision: Equatable, Hashable, Sendable {
  case cell
  case terminalPixels(metrics: CellPixelMetrics)
  case nativePixels(metrics: CellPixelMetrics)
  case webPixels(metrics: CellPixelMetrics)
}

public struct PointerLocation: Equatable, Hashable, Sendable {
  public var location: Point
  public var cell: CellPoint
  public var precision: PointerPrecision
  public var rawPixel: PixelPoint?
}
```

Most authored APIs should expose `Point`. Event-level APIs can expose
`PointerLocation` when provenance matters.

## Degradation Semantics

Every pointer event should have a `Point`.

For precise sources:

- Convert host/protocol pixels to fractional cells using current cell metrics.
- Preserve raw pixels as optional provenance.
- Mark precision as `.subCell(...)`.

For cell-only sources:

- Produce a cell-space `Point` from the reported cell coordinate.
- Mark precision as `.cell`.

The recommended fallback coordinate is the **center of the reported cell**:

```swift
Point(x: Double(cell.x) + 0.5, y: Double(cell.y) + 0.5)
```

Center fallback is less biased for drawing and hit interpolation. Code that
wants legacy cell behavior uses `location.cell` or `location.containingCell`.

One open implementation detail is whether the framework should use center
fallback for all cell-derived pointer events or use whole-number origins for
closer SwiftUI-style coordinate arithmetic. The joint recommendation is center
fallback plus explicit snapping helpers.

## Input Event Pipeline

Normalize into `PointerLocation` at the first framework boundary:

1. Terminal/native/web host receives source-specific pointer data.
2. Host or parser converts it into `PointerLocation`.
3. `MouseEvent.location` becomes `PointerLocation`.
4. `LocalPointerEvent.location` becomes `PointerLocation`.
5. Hit testing uses `location.cell`.
6. Gesture recognizers and controls use `location.location`.

This keeps hit testing stable while preserving fractional information for
consumers.

## Gesture API

All location-bearing gestures should return continuous cell coordinates.

### DragGesture

```swift
public struct DragGesture.Value: Equatable, Sendable {
  public var time: MonotonicInstant
  public var location: Point
  public var startLocation: Point
  public var translation: Vector
  public var velocity: Vector
  public var predictedEndLocation: Point
  public var predictedEndTranslation: Vector
  public var pointer: PointerLocation
  public var path: PointerPath
}

public struct DragGesture: Gesture {
  public let minimumDistance: Double
  public let coordinateSpace: CoordinateSpace
}
```

Velocity should be floating-point cells per second. The current integer velocity
truncates slow movement and makes sub-cell input disappear.

### PointerPath

Precise drawing needs samples, not only the latest drag location. Drag
recognition already keeps samples internally for velocity. Surface them:

```swift
public struct PointerPath: Equatable, Sendable, RandomAccessCollection {
  public struct Sample: Equatable, Sendable {
    public var location: Point
    public var time: MonotonicInstant
    public var pointer: PointerLocation
  }
}
```

The runtime can still coalesce for ordinary controls, but captured precise drag
routes should be able to receive sampled paths or coalesced batches.

### SpatialTapGesture

`SpatialTapGesture.Value.location` becomes `Point`.

```swift
public struct SpatialTapGesture.Value: Equatable, Sendable {
  public var location: Point
  public var pointer: PointerLocation
}
```

### TapGesture

Keep `TapGesture` value-less. Consumers that need location should use
`SpatialTapGesture`.

Movement cancellation should be evaluated in continuous cells internally.

### LongPressGesture

`maximumDistance` becomes `Double`, measured in cells.

## Coordinate Spaces

Coordinate-space resolution should preserve fractional positions:

```swift
extension CoordinateSpace {
  public func resolve(
    terminalPoint: Point,
    targetRect: CellRect
  ) -> Point
}
```

`.local` subtracts the integer cell origin from the fractional point.
`.global` returns the terminal-space point.

`CoordinateSpace.named(_:)` currently traps. This work makes named coordinate
spaces more valuable for Canvas overlays, chart cursors, drag/drop, and
cross-container gestures. It does not need to block sub-cell input, but the
joint recommendation is to implement it in the same broader interaction pass if
scope allows.

## Capability Model

Cell pixel geometry and pointer input precision are different capabilities.

Keep `cellPixelMetrics` as geometry. Add pointer input capabilities:

```swift
public struct PointerInputCapabilities: Equatable, Sendable {
  public var precision: PointerPrecision
  public var supportsSubCellLocation: Bool
  public var supportsHover: Bool
  public var supportsPreciseScroll: Bool
}

extension EnvironmentValues {
  public var pointerInputCapabilities: PointerInputCapabilities { get set }
}
```

`GeometryProxy` should also carry this if geometry-reader code commonly needs to
adapt Canvas or chart behavior:

```swift
public struct GeometryProxy: Equatable, Sendable {
  public var size: CellSize
  public var safeAreaInsets: EdgeInsets
  public var cellPixelMetrics: CellPixelMetrics
  public var pointerInputCapabilities: PointerInputCapabilities
}
```

## Terminal Protocol Strategy

Terminal pixel mouse support should be staged carefully.

Current mouse reporting enables SGR cell reporting. SGR-Pixels mode 1016 uses
the same event bytes as SGR 1006 but interprets x/y as pixels. The parser cannot
infer the coordinate unit from the event itself. Runtime state must say whether
SGR x/y are cells or pixels.

Recommended policy:

```swift
public enum PointerPrecisionPolicy: Equatable, Sendable {
  case cellOnly
  case useHostSubCellWhenAvailable
  case forceTerminalPixels
}
```

Default behavior:

- Native and web hosts use sub-cell precision when their host metrics are known.
- Unknown terminal emulators remain cell-only unless capability probing is
  credible.
- Terminal 1016 is enabled only when both pixel mouse reporting and cell pixel
  metrics are trustworthy.
- Inside tmux/screen, default to cell-only. Provide an explicit override for
  experimentation.

Terminal probing should prefer in-band, ordered data:

- Query SGR-Pixels support with DECRQM for `?1016`.
- Prefer DEC 2048, CSI 16t, or CSI 14t style geometry over unreliable
  `TIOCGWINSZ` pixel fields.
- Re-probe or refresh metrics on resize.

Parser normalization must treat both SGR 1006 and SGR-Pixels 1016 as one-based
coordinate protocols. For 1016, subtract one pixel before dividing by cell size:

```swift
let zeroBasedPixelX = encodedX - 1
let zeroBasedPixelY = encodedY - 1
let x = Double(zeroBasedPixelX) / Double(cellPixelMetrics.width)
let y = Double(zeroBasedPixelY) / Double(cellPixelMetrics.height)
```

That active coordinate mode must be runtime state; the byte stream alone cannot
distinguish 1006 cell coordinates from 1016 pixel coordinates.

Do not enable any-event tracking (`1003`) globally. It is high-volume and should
be reference-counted for explicit hover consumers.

## Native And Web Hosts

Native and web hosts should be the first precise implementations because they
already have the required information.

Native host:

- Convert AppKit/UIKit pointer positions into fractional cell `Point`.
- Preserve optional raw host pixels.
- Continue publishing cell pixel size.

Web host:

- Compute fractional cell coordinates from DOM pointer coordinates and
  `cellWidth`/`cellHeight`.
- Send decimal cell coordinates or integer cell plus fractional offsets through
  the transport.
- Keep resize messages carrying cell pixel size.

Because this project is pre-release, a clean transport break is acceptable.

## Canvas Redesign

Canvas should move from "Braille subpixel coordinate space" to "cell-space
drawing with configurable rasterization grid."

### CanvasGrid

```swift
public struct CanvasGrid: Equatable, Sendable {
  public enum Style: Equatable, Sendable {
    case braille2x4
    case octant2x4
    case sextant2x3
    case quadrant2x2
    case verticalHalfBlock
    case horizontalHalfBlock
    case fullCell
    case pixelExact
  }

  public var style: Style
  public var subdivisionsX: Int { get }
  public var subdivisionsY: Int { get }
}
```

`pixelExact` is a future/high-capability mode for graphics-protocol hosts. It
should be designed into the type system, but it does not need to ship in the
first implementation.

### CanvasContext

Canvas context should expose cell extent, chosen grid, and mapping helpers:

```swift
public struct CanvasContext: Sendable {
  public var size: CellSize
  public var grid: CanvasGrid
  public var foreground: Color
  public var background: Color?

  public func gridPoint(for location: Point) -> CellPoint
  public func gridPoint(for pointer: PointerLocation) -> CellPoint

  public mutating func setPixel(at location: Point)
  public mutating func line(from start: Point, to end: Point)
  public mutating func strokeRect(_ rect: Rect)
  public mutating func fillRect(_ rect: Rect)
  public mutating func strokeCircle(center: Point, radius: Double)
  public mutating func fillCircle(center: Point, radius: Double)

  public mutating func setCell(_ cell: CanvasCell, at location: CellPoint)
  public mutating func fillCell(_ color: Color, at location: CellPoint)
}
```

For Braille:

```swift
gridX = floor(local.x * 2)
gridY = floor(local.y * 4)
```

For vertical half-block:

```swift
gridX = floor(local.x)
gridY = floor(local.y * 2)
```

For full cell:

```swift
gridX = floor(local.x)
gridY = floor(local.y)
```

The consumer should not write `cellX * 2 + 1` or `cellY * 4 + 2`. Canvas owns
that mapping.

### Canvas And Gestures

Once both gestures and Canvas use fractional cell coordinates, the bridge is
direct:

```swift
Canvas(grid: .braille2x4, drawing)
  .gesture(
    DragGesture(minimumDistance: 0, coordinateSpace: .local)
      .onChanged { value in
        document.append(value.location)
      }
  )
```

The drawing then connects samples with `context.line(from:to:)` or rasterizes a
`PointerPath`.

Canvas should not own pointer events. Gestures remain the input API; Canvas
provides mapping and rasterization.

### Canvas Authoring Styles

Support both protocol and closure authoring:

```swift
Canvas(grid: .braille2x4, MyDrawing())

Canvas(grid: .braille2x4) { context in
  context.line(from: start, to: end)
}
```

The protocol form preserves the current `CanvasDrawing: Equatable` path and its
deduplication behavior for stable value drawings. The closure form is useful for
ad-hoc SwiftUI-style drawing. Both should lower to the same rasterizer and
`CanvasContext`.

### Path / Shape Compatibility

The Canvas redesign should anticipate a future `Path` model:

```swift
public struct Path: Equatable, Sendable {
  public mutating func move(to: Point)
  public mutating func addLine(to: Point)
  public mutating func addQuadCurve(to: Point, control: Point)
  public mutating func addCubicCurve(to: Point, control1: Point, control2: Point)
  public mutating func close()
  public func contains(_ point: Point) -> Bool
}
```

This unifies Canvas, Shape, content hit testing, chart cursors, and vector-style
drawing. It is not required for the first sub-cell input implementation, but the
Canvas API should not preclude it.

## Other API Candidates

### Slider

`Slider` should use continuous x coordinates. This is the most obvious non-Canvas
benefit and makes narrow sliders and fine-grained `Double` bindings behave
better.

### Scroll Indicators

Scroll thumb dragging should use continuous track position. This improves large
content ranges where one terminal row corresponds to many content rows.

### Charts

Charts should use fractional cell cursor positions for crosshairs, nearest-point
selection, range brushing, and data-space transforms.

### Image

Image views can later map pointer positions into rendered image pixels for
annotation, inspection, cropping, and image maps. This should wait until image
layout exposes rendered rect and cropping/letterboxing behavior clearly.

### Drop Destinations

Drop handlers should gain location context:

```swift
public struct DropContext: Equatable, Sendable {
  public var location: Point
  public var pointer: PointerLocation?
  public var modifiers: EventModifiers
}
```

This lets a multi-pane app route a drop spatially.

### Hover

Add hover as an opt-in pointer feature:

```swift
extension View {
  public func onPointerHover(_ action: @escaping (HoverPhase) -> Void) -> some View
}

public enum HoverPhase: Equatable, Sendable {
  case entered(Point)
  case moved(Point)
  case exited
}
```

Enable terminal any-motion reporting only while hover consumers exist.

### contentShape

Eventually support continuous hit shapes:

```swift
.contentShape(Circle())
.contentShape(path)
```

Initial sub-cell hit testing can remain cell-rect based, but Path-based hit
testing becomes much more useful once pointer positions are fractional.

### Scroll Wheel Precision

Continuous scroll deltas are related but separate. A future
`PointerScrollDelta` can carry fractional wheel/trackpad deltas. This proposal
focuses on pointer location.

### Lists, Tables, Menus, Pickers, Buttons

These should remain cell-native. Sub-cell precision does not materially improve
row selection or ordinary button activation.

## Implementation Plan

### Phase 1: Coordinate Types

- Introduce `Point(Double)`, `Size(Double)`, `Rect(Double)`, `Vector(Double)`,
  `CellPoint(Int)`, `CellSize(Int)`, and `CellRect(Int)`.
- Rename or migrate layout geometry to `Cell*` types.
- Add conversion and snapping helpers.
- Keep layout, placement, raster, and hit regions integer-cell based.

### Phase 2: PointerLocation Plumbing

- Add `PointerLocation`, source-discriminated `PointerPrecision`, and
  `PointerInputCapabilities`.
- Change `MouseEvent.location` and `LocalPointerEvent.location` to
  `PointerLocation`.
- Use `location.cell` for hit testing and routing.
- Synthesize cell-derived fallback locations for existing terminal input.

### Phase 3: Gesture Migration

- Change `DragGesture`, `SpatialTapGesture`, and `LongPressGesture` to use
  continuous positions and distances.
- Convert drag velocity and predicted-end math to `Double`.
- Surface `PointerPath` samples.
- Update gesture tests for cell fallback and precise input.

### Phase 4: Native And Web Precision

- Preserve native pointer pixels and convert to fractional cells.
- Extend web transport input messages to carry fractional coordinates.
- Add hosted-surface tests proving fractional input survives transport.

### Phase 5: CanvasGrid

- Add `CanvasGrid`.
- Make `CanvasContext` cell-space and grid-aware.
- Replace fixed Braille-subpixel authoring with grid mapping helpers.
- Update `Examples/canvas` to draw at actual sub-cell pointer positions.
- Add Braille, half-block, full-cell, quadrant, and sextant mapping tests.

### Phase 6: Controls

- Update `Slider` to use continuous x.
- Update scroll indicator dragging to use continuous coordinates.
- Audit charts and direct-manipulation controls.

### Phase 7: Terminal 1016

- Add `PointerPrecisionPolicy`.
- Probe support for pixel mouse reporting and trustworthy cell pixel metrics.
- Add SGR-Pixels parsing behind explicit active coordinate-mode state.
- Include 1016 in enable/disable/reset sequences when active.
- Default to cell-only inside tmux/screen.
- Add protocol tests proving 1006 and 1016 are not confused.

### Phase 8: Hover, Drop Location, And Path

- Add opt-in hover with reference-counted any-motion tracking.
- Add `DropContext`.
- Sketch or implement `Path` enough for Canvas and future content shapes.

## Risks And Constraints

### 1006 And 1016 Ambiguity

SGR 1006 and 1016 use the same event syntax. Runtime parser state must know the
active coordinate mode.

### Cell Pixel Metric Trust

Pixel-to-cell conversion is only as good as cell metrics. Do not enable terminal
pixel input if metrics are estimated or missing.

### Multiplexers

tmux and screen can distort coordinate meaning. Default to cell-only inside
multiplexers and provide explicit override.

### Event Volume

Sub-cell input and hover can produce high event rates. Coalesce where appropriate
but preserve path samples for captured drawing routes.

### API Overreach

Raw pixel APIs can accidentally introduce a second layout model. Keep pixels as
provenance and explicit image/graphics interop data.

### Scope

Changing `Point` and introducing `Cell*` layout types is a major migration. That
is acceptable because the resulting model is cleaner and the project is
pre-release.

## Decisions

1. Public pointer positions use fractional cells.
2. `Point` becomes continuous cell position.
3. Integer layout geometry moves to `CellPoint`, `CellSize`, and `CellRect`.
4. Pixels are secondary provenance, not the primary API.
5. All location-bearing gestures migrate to continuous coordinates.
6. Drag exposes sampled paths.
7. Canvas becomes cell-space with configurable `CanvasGrid`.
8. Native and web precision should land before terminal 1016.
9. Terminal 1016 is gated by explicit policy and trustworthy metrics.
10. Hover, drop location, Path, and content shapes are aligned follow-on work.

## Open Questions

- Should cell-only fallback locations be cell centers or whole-number cell
  origins? This proposal recommends centers.
- Should `PointerLocation` be exposed directly as gesture `location`, or should
  gesture values expose `Point location` plus `PointerLocation pointer`? This
  proposal recommends the latter.
- How aggressive should terminal support probing be in unknown terminals?
- Should `CanvasGrid.pixelExact` be in the first public API even if initially
  unavailable on most hosts?
- Should `CoordinateSpace.named(_:)` ship with the first sub-cell pass or in the
  Path/content-shape follow-up?
- How should `PointerPath` sample memory be bounded for very long drags?

## Final Recommendation

Adopt sub-cell pointer input as a framework-wide coordinate redesign, not as a
Canvas patch.

The core move is:

```text
layout geometry:     integer cells    -> CellPoint / CellSize / CellRect
input and drawing:   fractional cells -> Point / Size / Rect / Vector
pixels:              optional provenance and graphics interop
```

That model preserves the terminal's cell-native layout while giving gestures,
Canvas, controls, charts, and future graphics APIs the precision they need. It
also degrades cleanly: cell-only terminals still produce useful `Point` values,
and precise hosts simply fill in the fractional part.
