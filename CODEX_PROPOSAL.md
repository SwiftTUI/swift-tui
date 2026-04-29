# Proposal: Sub-Cell Pointer Input

## Status

Draft for framework design discussion.

This proposal intentionally treats existing public API as movable. The project is
pre-release, so minimizing migration cost is a non-goal when a cleaner model is
available.

## Summary

TerminalUI should model precise pointer input as **continuous cell coordinates**,
not raw pixel coordinates.

The rendering and layout system should remain cell-denominated. Pointer input
should gain a higher-precision location that can express positions inside a
terminal cell when the host can provide them. When the host cannot provide that
precision, the same API should degrade to a center-of-cell estimate with an
explicit precision/source flag.

Canvas is the first and strongest consumer, but the feature should not be
designed as a Canvas-only input path. The right shape is a framework-wide pointer
location model used by gesture recognizers, controls, hosted surfaces, and
Canvas mapping helpers.

## Goals

- Represent pointer locations inside a terminal cell when available.
- Degrade gracefully on terminals that only report integer cell coordinates.
- Avoid making raw pixels the primary authored coordinate system.
- Make Canvas able to map pointer input to Braille, half-block, full-cell, and
  future grid resolutions.
- Improve direct-manipulation controls such as sliders, scroll thumbs, chart
  cursors, resize handles, and image annotation surfaces.
- Keep keyboard-first TUI workflows intact. Precise pointer input should improve
  fidelity, not become the only way to use core controls.

## Non-Goals

- Preserving source compatibility with the current integer gesture location API.
- Turning TerminalUI layout into a pixel layout system.
- Making all terminal emulators support precise input.
- Requiring applications to branch on terminal support for normal gesture use.

## Prior Art

Most terminal UI stacks expose mouse positions as integer cells:

- Crossterm `MouseEvent` exposes `column` and `row`.
- Ratatui keeps layout cell-based, while `WindowSize` can expose both cell and
  pixel dimensions.

There is useful precedent for carrying both cell and precise pointer locations:

- Textual exposes integer `x/y` and `screen_x/screen_y`, plus float
  `pointer_x/pointer_y` and `pointer_screen_x/pointer_screen_y`.

Terminal protocols and emulators already have partial support for pixel mouse
coordinates:

- XTerm SGR-Pixels mode 1016 uses the SGR mouse format but reports positions in
  pixels instead of character cells.
- WezTerm documents support for SGR-Pixels mouse reporting.
- kitty extends the XTerm SGR pixel protocol to report mouse-leave events.

Pixel geometry is also treated as advisory metadata in advanced TUI systems:

- Notcurses exposes plane pixel geometry and cell pixel dimensions for bitmap
  and visual output.

References:

- XTerm control sequences: https://invisible-island.net/xterm/ctlseqs/ctlseqs.html
- Textual mouse events: https://textual.textualize.io/api/events/
- Crossterm MouseEvent: https://docs.rs/crossterm/latest/crossterm/event/struct.MouseEvent.html
- Ratatui WindowSize: https://docs.rs/ratatui/latest/ratatui/prelude/backend/struct.WindowSize.html
- Notcurses plane geometry: https://notcurses.com/notcurses_plane.3.html
- WezTerm changelog: https://wezterm.org/changelog.html
- kitty protocol extensions: https://sw.kovidgoyal.net/kitty/misc-protocol/

## Current Framework Shape

The current pointer pipeline is integer-cell based:

- `MouseEvent.location` is `Point`.
- SGR mouse parsing subtracts one from reported x/y and immediately stores a
  zero-based cell `Point`.
- `LocalPointerEvent.location` is also `Point`.
- `DragGesture.Value`, `SpatialTapGesture.Value`, `TapGesture`, and
  `LongPressGesture` all evaluate movement and locations in integer cells.
- `CoordinateSpace.resolve(...)` subtracts an integer target origin and returns
  an integer `Point`.

The current Canvas rendering model is already sub-cell visually:

- `CanvasContext` exposes a Braille subpixel surface where each terminal cell is
  a 2x4 subpixel grid.
- `CanvasPixelGridDrawing` can render full-cell and vertical half-block logical
  pixels.
- `Examples/canvas` maps integer pointer locations to fixed subpixel centers:
  Braille uses `cellX * 2 + 1`, `cellY * 4 + 2`; half-block maps to the top half
  by default.

That means the framework can draw sub-cell output but cannot currently select
sub-cell input.

The hosted surfaces already have better information than the current API
preserves:

- The native AppKit/UIKit surface receives pixel pointer positions and converts
  them immediately to integer cells.
- The web surface receives DOM pointer coordinates and knows `cellWidth` and
  `cellHeight`, but floors to integer cells before sending input to Swift.

The framework already exposes cell pixel geometry:

- `CellPixelMetrics` is public.
- `GeometryProxy.cellPixelMetrics` and `EnvironmentValues.cellPixelMetrics`
  expose cell dimensions and source confidence.
- Runtime hosts populate cell pixel size from `ioctl`, CSI cell-size queries,
  total text-area pixels, or hosted-surface resize messages.

This is the right geometry foundation, but it is not itself an input capability
model.

## Design Principles

### Continuous Cells Are the Public Coordinate System

The authored location should be expressed in cells as `Double`, where:

- `(0.0, 0.0)` is the top-leading edge of cell `(0, 0)`.
- `(1.0, 0.0)` is the top-leading edge of cell `(1, 0)`.
- `(0.5, 0.5)` is the center of cell `(0, 0)`.
- The containing cell is `floor(x), floor(y)`.

This keeps pointer input aligned with layout, geometry readers, coordinate
spaces, and existing cell-sized render surfaces.

### Pixels Are Metadata, Not the Primary API

Raw pixels are host/protocol details:

- Terminal pixel coordinates only make sense with a known cell size and origin.
- Native/web pixels may be logical pixels, backing pixels, or CSS pixels.
- Pixel sizes vary with font, DPI, zoom, and host scaling.

Raw pixels can still be useful for diagnostics and image integrations, so they
should be available as optional provenance metadata. They should not be the
primary gesture location type.

### Degradation Is Structural

Every pointer event should have a continuous cell point. On cell-only input, the
framework should synthesize a center-of-cell point and mark the event as
cell-derived.

Consumers should be able to write:

```swift
let local = value.location
```

and get useful behavior everywhere. Consumers that care about true precision can
ask:

```swift
if value.pointer.precision.isSubcell {
  ...
}
```

### Layout Stays Integer

This proposal does not require changing `Point`, `Size`, and `Rect` used by
layout, placement, rasterization, hit region identity, or terminal cell output.

The new coordinate family is for input, gesture math, control interpolation,
Canvas mapping, and optional pixel conversion.

## Proposed Core Types

Names are placeholders, but the model should look like this:

```swift
public struct CellPoint: Equatable, Hashable, Sendable {
  public var x: Double
  public var y: Double

  public var containingCell: Point { get }
  public var fractionInCell: UnitPoint { get }
}

public struct CellVector: Equatable, Hashable, Sendable {
  public var dx: Double
  public var dy: Double
}

public struct PixelPoint: Equatable, Hashable, Sendable {
  public var x: Double
  public var y: Double
}

public enum PointerPrecision: Equatable, Hashable, Sendable {
  case cell
  case terminalPixels
  case nativePixels
  case webPixels
}

public struct PointerLocation: Equatable, Hashable, Sendable {
  public var point: CellPoint
  public var cell: Point
  public var precision: PointerPrecision
  public var rawPixel: PixelPoint?
  public var cellPixelMetrics: CellPixelMetrics?
}
```

`CellPoint` should be the type authors normally see. `PointerLocation` should be
available when authors need provenance, degradation behavior, or raw pixel
diagnostics.

If the public surface wants fewer names, `PointerLocation` can itself expose
`x/y` and behave as the authored point. The risk is that ordinary gesture code
then carries too much protocol detail. I prefer keeping `CellPoint` as the
geometric type and `PointerLocation` as the richer event location.

## Gesture API

All gesture recognizers that return locations should return continuous
coordinates.

### DragGesture

Current shape:

```swift
public struct DragGesture.Value {
  public var location: Point
  public var startLocation: Point
  public var translation: Size
  public var velocity: Size
  public var predictedEndLocation: Point
  public var predictedEndTranslation: Size
}
```

Proposed shape:

```swift
public struct DragGesture.Value {
  public var time: MonotonicInstant
  public var location: CellPoint
  public var startLocation: CellPoint
  public var translation: CellVector
  public var velocity: CellVector
  public var predictedEndLocation: CellPoint
  public var predictedEndTranslation: CellVector
  public var pointer: PointerLocation
}
```

`minimumDistance` should become `Double`, measured in cells.

Velocity should become floating point cells per second. The current integer
velocity truncates slow movement and makes sub-cell motion disappear.

### SpatialTapGesture

`SpatialTapGesture.Value.location` should become `CellPoint`.

The value can also expose:

```swift
public var cellLocation: Point { location.containingCell }
public var pointer: PointerLocation
```

### TapGesture

`TapGesture` remains value-less, but movement cancellation should use continuous
distance internally.

On cell-derived input, movement between two cell centers remains a whole-cell
movement, preserving current terminal behavior.

### LongPressGesture

`maximumDistance` should become `Double`.

### CoordinateSpace

`CoordinateSpace.resolve` needs a continuous variant that preserves fractional
coordinates:

```swift
func resolve(
  terminalPoint: CellPoint,
  targetRect: Rect
) -> CellPoint
```

The existing integer coordinate spaces can remain for layout and hit identity.
If named coordinate spaces remain unsupported, that is acceptable for an initial
implementation. Precise Canvas and overlay work will make named spaces more
valuable, so this should be revisited.

## Event Pipeline

The internal input path should change from `Point` to `PointerLocation` at the
first normalized event boundary.

Recommended path:

1. Terminal/native/web host receives source-specific pointer data.
2. Host normalizes it into `PointerLocation`.
3. `MouseEvent.location` becomes `PointerLocation`.
4. `LocalPointerEvent.location` becomes `PointerLocation`.
5. Hit testing uses `location.cell`.
6. Gesture recognizers and controls use `location.point`.

This keeps hit testing cell-stable while allowing sub-cell consumers to see the
real input.

## Terminal Protocol Strategy

Current terminal raw mode enables mouse tracking with:

```text
CSI ? 1002 h
CSI ? 1006 h
```

Sub-cell terminal reporting would add:

```text
CSI ? 1016 h
```

However, mode 1016 uses the same SGR event shape as mode 1006. The application
must know whether incoming coordinates are cells or pixels. If a terminal ignores
1016 but still reports 1006 cell coordinates, interpreting those values as
pixels would corrupt input.

Recommended policy:

```swift
public enum PointerPrecisionPolicy: Sendable, Equatable {
  case cellOnly
  case subcellWhenKnown
  case forceTerminalPixels
}
```

Default policy should be `subcellWhenKnown` for hosted native/web surfaces and
known-good terminal profiles, and `cellOnly` for unknown terminals until
capability detection is credible.

`forceTerminalPixels` is useful for experimentation and for users who know their
terminal supports 1016.

Do not enable any-event mouse tracking (`1003`) by default. It can produce high
event volume and is only useful for hover-style interactions. Button-event
tracking plus pixel coordinates is enough for drag, tap, Canvas drawing, sliders,
and scroll thumbs.

## Native And Web Hosts

Native and web hosts should ship first because they already have the required
information.

Native host:

- Convert `NSEvent`/UIKit pointer positions into continuous cell coordinates.
- Preserve optional pixel position in `rawPixel`.
- Continue publishing `cellPixelSize`.

Web host:

- Change the input message format to include continuous coordinates or raw
  pixel offsets.
- Prefer sending continuous cell x/y as decimals to avoid duplicate conversion
  on the Swift side.
- Keep `cellWidth` and `cellHeight` in resize messages for environment metrics.

Example web message shape:

```text
mouse:down:2.42:0.61:primary:0:0:0
```

or, if preserving integer fields is useful:

```text
mouse:down:2:0:0.42:0.61:primary:0:0:0
```

Because this is pre-release, a clean protocol break is acceptable. A structured
message would be more future-proof, but the current transport uses compact
colon-delimited control messages, so either decimal coordinates or appended
fraction fields fit the existing style.

## Canvas Redesign

Canvas is the strongest reason to do this work. The current API asks authors to
draw in Braille subpixel coordinates, but the gesture system can only identify a
cell.

The Canvas API should expose explicit output resolution and mapping helpers.

```swift
public enum CanvasResolution: Equatable, Sendable {
  case fullCell
  case verticalHalfBlock
  case quadrant2x2
  case sextant2x3
  case braille2x4
}

extension CanvasResolution {
  public var columnsPerCell: Int { get }
  public var rowsPerCell: Int { get }
}
```

`CanvasContext` should expose both cell size and drawing-grid size:

```swift
public struct CanvasContext {
  public var cellSize: Size
  public var resolution: CanvasResolution
  public var gridSize: Size

  public func gridPoint(for location: CellPoint) -> Point
  public func gridPoint(for pointer: PointerLocation) -> Point
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

This removes the current example-level hard-coding that maps every pointer hit
to a fixed subpixel center.

### Canvas Drawing Model

The current `CanvasDrawing.draw(into:)` model is useful, but too narrowly tied
to Braille subpixels.

Options:

1. Keep `CanvasDrawing` and make `CanvasContext` resolution-aware.
2. Add a new `Canvas` initializer that takes a drawing closure and provides a
   richer context.
3. Split low-level grid drawing from higher-level continuous drawing primitives.

Recommended direction:

- Preserve the ability to write integer grid cells.
- Add continuous drawing helpers that rasterize into the configured resolution.
- Avoid putting event handling inside Canvas. Use gestures for input, and use
  Canvas mapping helpers to convert gesture locations into drawing coordinates.

Example authoring shape:

```swift
Canvas(.braille2x4) { context in
  context.stroke(path, style: .foreground(.cyan))
}
.gesture(
  DragGesture(minimumDistance: 0, coordinateSpace: .local)
    .onChanged { value in
      document.draw(to: context.gridPoint(for: value.location))
    }
)
```

The exact syntax will differ because gesture closures do not currently receive a
Canvas context. The important part is that Canvas owns resolution mapping, not
each app.

### Pointer Samples

Precise Canvas drawing needs more than one latest drag location.

The current input coalescing path intentionally collapses high-rate pointer
movement. That is appropriate for many controls, but it hurts drawing because a
stroke can skip over many sub-cell samples under load.

Recommended addition:

```swift
public struct PointerSample: Equatable, Sendable {
  public var time: MonotonicInstant
  public var location: CellPoint
  public var pointer: PointerLocation
}

extension DragGesture.Value {
  public var samples: [PointerSample]
}
```

The runtime can still coalesce for controls, but captured precise drag routes
should be able to receive sampled paths or coalesced batches.

## Other API Redesign Candidates

### Slider

`Slider` currently maps pointer location using integer `event.location.x`.
It should use continuous x. This gives immediate benefit for narrow sliders and
fine-grained `Double` bindings.

### Scroll Indicators

Scroll thumb dragging should use continuous track position. This improves large
content ranges where one terminal row corresponds to many content rows.

### Charts

Charts should expose continuous cursor locations for crosshairs, nearest-point
selection, tooltips, and range brushing.

### Image

Image views are a good future consumer. Pointer locations can map into image
pixel coordinates for annotation, inspection, cropping, and image maps.

This should wait until the image API exposes the rendered image rect and
letterboxing/cropping behavior clearly.

### contentShape And Hit Testing

Initial hit testing can stay cell-rect based. Eventually, `contentShape` should
support continuous hit shapes so thin handles, charts, and Canvas regions can
define precise interaction areas.

### Lists, Tables, Pickers, Menus, Buttons

These should remain cell-native. Sub-cell input does not materially improve row
selection or button activation.

### Scroll Wheel Precision

High-resolution trackpad scrolling is related but separate. `deltaX` and
`deltaY` are currently integers. A future `PointerScrollDelta` could carry
continuous deltas, but this proposal is about pointer location.

## Capability Surface

The existing `cellPixelMetrics` environment value answers: "how large is a
cell?"

Precise input also needs: "how precise is pointer input?"

Proposed environment:

```swift
public struct PointerInputCapabilities: Equatable, Sendable {
  public var locationPrecision: PointerPrecision
  public var supportsSubcellLocation: Bool
  public var supportsHover: Bool
  public var supportsPreciseScroll: Bool
}

extension EnvironmentValues {
  public var pointerInputCapabilities: PointerInputCapabilities { get set }
}
```

This keeps geometry and input capability separate. A terminal can report cell
pixel metrics without supporting pixel mouse input.

## Implementation Plan

### Phase 1: Types And Internal Plumbing

- Add `CellPoint`, `CellVector`, `PixelPoint`, `PointerPrecision`, and
  `PointerLocation`.
- Add conversion helpers from integer `Point`.
- Change `MouseEvent.location` and `LocalPointerEvent.location` to
  `PointerLocation`.
- Use `location.cell` for hit testing.
- Keep terminal parser cell-based initially and synthesize center-of-cell
  `PointerLocation`.

### Phase 2: Gesture Migration

- Change `DragGesture.Value` and `SpatialTapGesture.Value` to continuous
  locations.
- Change `DragGesture.minimumDistance` and `LongPressGesture.maximumDistance` to
  `Double`.
- Update velocity and predicted-end math to use `Double`.
- Add convenience projections for cell-snapped use.
- Update gesture tests to cover cell fallback and sub-cell locations.

### Phase 3: Native And Web Precision

- Preserve native pointer pixel locations and convert to continuous cells.
- Extend web input messages to carry decimal cell locations or fraction fields.
- Update hosted-surface tests to verify fractional input survives transport.

### Phase 4: Canvas Mapping

- Add `CanvasResolution`.
- Make `CanvasContext` expose cell size, grid size, and mapping helpers.
- Update `Examples/canvas` to draw at actual sub-cell locations.
- Add tests for Braille, half-block, and full-cell pointer mapping.

### Phase 5: Controls

- Update `Slider` to use continuous x.
- Update scroll indicator dragging to use continuous coordinates.
- Audit charts and other direct manipulation controls as they exist.

### Phase 6: Terminal Pixel Protocol

- Add an explicit pointer precision policy.
- Add terminal-host support for SGR-Pixels mode 1016 behind that policy.
- Ensure enable/disable/reset sequences include 1016 when active.
- Teach the parser whether SGR coordinates are cells or pixels.
- Convert pixel coordinates using current cell metrics.
- Add terminal-protocol tests that prove 1006 and 1016 are not confused.

### Phase 7: Pointer Samples

- Carry sampled drag paths through coalescing for captured precise pointer
  routes.
- Expose samples on `DragGesture.Value`.
- Add Canvas drawing tests that prove fast sub-cell strokes do not drop
  essential path points.

## Risks

### Ambiguous Terminal Protocol State

SGR 1006 and SGR-Pixels 1016 use the same event shape. The parser cannot infer
the coordinate unit from the bytes alone. The active mouse coordinate mode must
be explicit runtime state.

### Pixel Coordinate Origin

Terminal pixel reports need careful origin handling. Cell SGR coordinates are
one-based. Pixel reports should be normalized by subtracting one pixel before
dividing by cell size if the terminal follows the same coordinate origin.

This needs protocol-specific tests.

### Event Volume

Sub-cell pointer movement can produce high event rates. Do not enable hover
tracking globally. Coalescing remains important for controls, while drawing
needs sample batches.

### API Overreach

Raw pixel APIs can leak a second layout system into the framework. Keep pixels
as optional input provenance and image interop metadata.

## Alternatives Considered

### Expose Raw Pixels Everywhere

Rejected. Pixels are host-specific, scale-specific, and require cell metrics to
be meaningful. They also push app authors toward a non-terminal layout model.

### Add `preciseLocation` Beside Existing Integer `location`

Viable, but not preferred. It preserves migration compatibility at the cost of
making the worse coordinate the default. Since migration cost is explicitly not a
goal, the primary `location` should become the better model.

### Make This Canvas-Only

Rejected. Canvas is the first beneficiary, but the input path is shared by
gestures, controls, hosted surfaces, and future chart/image interactions.

### Replace All Geometry With Floating Point

Rejected. Layout, placement, raster, and terminal output are cell-native. The
continuous model belongs to pointer input and drawing interpolation.

## Open Questions

- Should the public rich event type be `PointerLocation`, `PointerPoint`, or
  something closer to SwiftUI naming?
- Should `DragGesture.Value.location` be `CellPoint` with a separate `pointer`,
  or should it be `PointerLocation` directly?
- Should cell-derived fallback use cell center `(x + 0.5, y + 0.5)` or cell
  origin `(x, y)`? This proposal recommends center.
- How should terminal 1016 support be detected without an allowlist?
- Should precise pointer support be automatic when a precise consumer exists, or
  explicitly requested at scene/window level?
- Should pointer sample arrays be bounded by count, time window, or byte budget?
- Should `CoordinateSpace.named` be implemented as part of this work or left
  separate?

## Recommended Decision

Adopt a new continuous cell pointer model across the input and gesture system:

- Public authored positions are `Double` cell coordinates.
- Integer cells remain available for hit identity and snapping.
- Raw pixels are optional provenance.
- Canvas becomes resolution-aware and owns mapping from continuous cells to
  output grids.
- Native/web precision ships before terminal 1016.
- Terminal pixel reporting is guarded by an explicit precision policy.

This is the cleanest way to make sub-cell pointer input useful without turning
TerminalUI into a pixel UI framework.
