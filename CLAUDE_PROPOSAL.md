# Sub-Cell Pointer Detection — Design Analysis

**Status:** Pre-implementation analysis. No migration cost concerns.
**Scope:** Sub-cell pointer detection, Canvas API redesign, ripple effects across the framework.

---

## TL;DR (one paragraph)

The terminal's "natural" sub-cell input protocol (xterm DECSET 1016) reports **device pixels**. The right unit for *this framework* to expose to user code is **fractional cells (`Double`)**, not pixels — because cells are already the load-bearing unit of layout, hit-testing, gesture velocity, and animation, and because fractional cells degrade gracefully (an integer-only terminal just produces integer-valued `Double`s; user code that doesn't care about sub-cell can `Int(value.location.x)` and never know). The `Point` type should become `Double`-valued. Every gesture's `Value.location` follows. **Canvas should be redesigned in cell-space (`Double`) with a pluggable `CanvasGrid` (Braille / octant / sextant / quadrant / half-block / full-cell) chosen by the consumer**, eliminating the hardcoded 2×4 Braille assumption and making pointer-driven drawing trivial. Capability is mostly implicit (probe on startup, expose precision via `@Environment` for power users), and the framework should explicitly disable 1016 inside tmux. Graphics-protocol terminals (Kitty/iTerm2) plus 1016 unlock a *second* Canvas mode: real pixel-perfect interactive vector graphics, which is worth designing into the API from day one.

> **Insight.** The deepest finding from research: every TUI framework that exposes sub-cell pointer input has chosen *some* representation of "cell + fractional-or-pixel offset." None has chosen pure pixels at the public API level. The reason is that hit-testing and layout are cell-grained; a pixel-only API forces every consumer to redo the cell math. Notcurses uses `(y, x, ypx, xpx)` with `-1` sentinels; Textual smooths internally and exposes cells only; blessed-py is the lone outlier with absolute pixels and a capability check. The Swift-native answer in a SwiftUI-style API is **fractional cells as `Double`** — it subsumes both "cell-only" and "cell + sub-cell offset" without introducing optionals or sentinels.

---

## 1. What's actually in the framework today

Concrete shapes confirmed by reading source:

```swift
// Sources/Core/GeometryTypes.swift
public struct Point: Equatable, Sendable { var x: Int; var y: Int }
public struct Size:  Equatable, Sendable { var width: Int; var height: Int }
public struct Rect:  Equatable, Sendable { var origin: Point; var size: Size }

// Sources/TerminalUI/InputReader.swift
public struct MouseEvent: Equatable, Sendable {
  public var kind: Kind             // down/up/moved/dragged/scrolled
  public var location: Point        // integer cells (parsed from SGR 1006)
  public var modifiers: Modifiers
}

// Sources/View/Gestures/DragGesture.swift
public struct DragGesture.Value {
  var location, startLocation, predictedEndLocation: Point   // Int cells
  var translation, velocity, predictedEndTranslation: Size   // Int cells, Int cells/sec
  var time: MonotonicInstant
}

// Sources/View/Gestures/SpatialTapGesture.swift
public struct SpatialTapGesture.Value { var location: Point }   // Int cells

// Sources/View/Canvas.swift  + Sources/Core/CanvasDrawing.swift
public struct CanvasContext {
  public let width, height: Int     // hardcoded Braille subpixel: cellW*2, cellH*4
  // primitives: setPixel(x:y:Int), line, strokeRect, fillRect, strokeCircle,
  // fillCircle, strokeEllipse, fillEllipse, setCell, fillCell ...
  // ALL coordinates are Int subpixels in a fixed 2×4 grid.
}

// Sources/Core/CellPixelMetrics.swift
public struct CellPixelMetrics: Equatable, Sendable {
  public let width, height: Int     // device pixels per cell (advisory)
  public let source: Source         // .reported | .estimated (8×16 fallback)
}
```

The `MouseEvent` parser today only handles SGR (1006). No 1016, no DEC Locator, no DEC 2048 in-band size reports. Point/Size/Rect are integer-cell throughout, so sub-cell precision has nowhere to live.

The **Examples/canvas demo reveals the user-side pain perfectly**: in `Examples/canvas/Sources/CanvasDemoViews/CanvasDemoView.swift:198–215`, the consumer is forced to invent the missing precision themselves:

```swift
public static func subpixelPoint(forLocalCell point: Point, in cellSize: Size) -> CanvasSketchPoint {
  let cellX = min(max(0, point.x), cellSize.width - 1)
  let cellY = min(max(0, point.y), cellSize.height - 1)
  return CanvasSketchPoint(
    x: min(cellX * 2 + 1, cellSize.width * 2 - 1),     // hardcoded center-of-cell
    y: min(cellY * 4 + 2, cellSize.height * 4 - 1)
  )
}
```

A drag *within* a single cell paints zero new sub-pixels — every cell pins to the same `(cell*2+1, cell*4+2)` anchor. This is the clearest motivating case: sub-cell pointer input would let a drag inside a single cell produce real motion across the 2×4 sub-grid.

---

## 2. Research findings: how the ecosystem handles this

### 2.1 Terminal mouse protocols

The mouse-tracking modes are *encoding-format orthogonal to* the *event-class* modes. You enable one event class (X10 / 1000 / 1002 / 1003) **and** one encoding (default-32-offset / 1005 / 1006 / 1015 / 1016). Mode 1016 implies SGR-style encoding plus pixel coordinates.

| Mode | Function | Coordinate unit |
|------|----------|-----------------|
| **9 (X10)** | Click only, default encoding | cells, 1-based, max 223 |
| **1000** | Press + release + wheel | cells, 1-based, max 223 |
| **1002** | Above + drag motion | cells |
| **1003** | All motion (even no button held) | cells |
| **1005** | UTF-8 encoding extension | cells, max 2015; *do not use* |
| **1006 (SGR)** | `CSI < b ; x ; y M/m` decimal, no upper bound | **cells, 1-based** |
| **1015 (URXVT)** | `CSI b ; x ; y M`, button +32 | cells; "not recommended" per xterm spec |
| **1016 (SGR-Pixels)** | Identical wire format to 1006 | **pixels, 1-based** |

**Key invariants for 1016** (verified across xterm, foot, kitty, mintty, ghostty):

- Wire format identical to 1006: `CSI < button ; xPixel ; yPixel [M|m]` — the only difference is *interpretation* of the two numeric fields.
- Origin is **top-left, 1-based** (matching 1006).
- DECRQM query: `CSI ? 1016 $ p` returns DECRPM `CSI ? 1016 ; Pm $ y`.
- Coordinates are **not** clamped: Ghostty, kitty, foot, and pre-patch-404 xterm have all reported negative values when the mouse drags above/left of the viewport.

**Companion protocol — DEC 2048 ("in-band size reports")**: `CSI ? 2048 h` enables push reports of the form `CSI 48 ; height_chars ; width_chars ; height_pix ; width_pix t`. Spec states explicitly: *"if a terminal cannot determine pixel sizes, it reports them as 0."* Supported by ghostty, iTerm2, kitty, foot, contour, bobcat. **This is the mechanism for resolving pixels-per-cell reliably** — much better than `TIOCGWINSZ.ws_xpixel/ws_ypixel`, which are notoriously unreliable in WSL/conpty/SSH.

### 2.2 Terminal support matrix for 1016 (April 2026)

| Terminal | 1016 status |
|---|---|
| **xterm** | Yes (since patch 359, Aug 2021) |
| **foot** | Yes |
| **kitty** | Yes, with leave-window extension |
| **WezTerm** | Yes |
| **Ghostty** | Yes |
| **mintty / wsltty** | Yes (xterm 360-aligned) |
| **Contour** | Yes |
| **xterm.js (used by VSCode)** | Yes |
| **iTerm2** | **No** — feature-reporting spec lists 1000/1002/1003/1006/1007 only |
| **Alacritty** | **No** |
| **Windows Terminal** | **No** — open issue #18591, "Backlog", PR #19949 in flight |
| **Terminal.app (macOS)** | **No** — supports SGR (1006) only |
| **VTE / GNOME Terminal / Konsole** | No public evidence of support |
| **tmux / screen** | Pass-through only with explicit `allow-passthrough on`; tmux itself does not interpret pixel coordinates, and the inner pane's pixel coords don't match outer terminal reality across resizes/splits. **Treat tmux as effectively breaking 1016.** |

### 2.3 How other TUI frameworks expose this

- **Notcurses** (the most thoughtful design): `ncinput { y, x: int, ypx, xpx: int }` — cell coords plus sub-cell pixel offsets. Sentinel `-1` for "not available." The implementation: integer division gives the cell, modulo gives the sub-cell pixel offset.
- **Ratatui / crossterm**: cells only in stable. PR #929 adds `EnableMousePixelCapture` and a `cell_size()` helper; sub-cell math left to the application.
- **Textual** (Python): uses 1016 + 2048 internally for smoother scrollbars. Public mouse event still surfaces cell `x,y` integers; pixel data is internal smoothing only.
- **Bubble Tea (v2, Go)**: zero-based cell `(X, Y)`. No public sub-cell or 1016 field, even though `charmbracelet/x/ansi` parses 1016 sequences.
- **Blessed (Python, Jeff Quast)**: the second-best API. Set `report_pixels=True`; mouse event then has `.x` and `.y` in **absolute pixels**. Capability check: `term.does_mouse(report_pixels=True)`.
- **prompt_toolkit, ncurses, blessed-node**: cell-only. No sub-cell support.

### 2.4 The folklore wisdom

- "Pixel coords without cell coords is annoying" — the consumer almost always wants both.
- "Cell coords without sub-cell offsets is fine when cells are honest" — for buttons and lists, drop pixel info entirely.
- "Don't try to invent fractional cell coordinates as floats." Both notcurses and Textual chose integer cells + integer sub-cell pixels rather than `Float(5.7, 2.3)` cells.

> **The above advice is correct for languages without strong gradual-precision idioms (C, Python). It's the wrong choice for Swift.** In a SwiftUI-style API, `Double` *is* the gradual-precision idiom; using it lets cell-only terminals produce integer-valued doubles and sub-cell terminals produce fractional ones, with no optionality and no sentinel. This proposal departs from notcurses on this point.

### 2.5 Pitfalls and surprises

- **GPU-rendered terminals are fine; tiling WMs are mostly fine.** Reporting is in logical (window) pixels, not framebuffer pixels.
- **Some terminals lie about pixel size.** `TIOCGWINSZ.ws_{x,y}pixel` is `0` in WSL and Windows Terminal, faked in `Win32-OpenSSH`. Use DEC 2048 / `CSI 14 t` / `CSI 16 t` instead.
- **Negative values** are normal for 1016 in xterm-pre-404, ghostty, kitty. Code defensively.
- **Leave events**: 1016 alone has no "mouse left window" event. Only kitty's extension provides this today.
- **iTerm2 and Terminal.app on macOS do not implement 1016 as of April 2026.** Significant for any macOS-targeted TUI.
- **Detection over multiplexers**: DECRQM replies can be intercepted/altered by tmux. Test the whole pipeline.

---

## 3. The core design question — pixels vs. fractional cells

The framing in the original ask was: *"it may be less useful to give pixels than fractional cell values."* This is correct, and stronger than the framing implies.

### 3.1 Five reasons to choose fractional cells over pixels at the public API boundary

**(a) It composes with the existing layout model with zero friction.** Every `CoordinateSpace.resolve(terminalPoint:targetRect:)` is currently `pointer - rect.origin`, an integer subtraction. With fractional cells it's still `pointer - rect.origin` — just `Double - Int`. With absolute pixels, every transform additionally divides by `cellPixelMetrics.{width,height}`, which (i) requires the consumer to have `cellPixelMetrics` in scope, (ii) breaks when `cellPixelMetrics` is `.estimated` or stale, (iii) introduces rounding error on every transform.

**(b) It is independent of cell size.** A drag from `(5.0, 2.0)` to `(5.5, 2.0)` means "moved half a cell" regardless of whether the cell is 8×16 or 12×24 device pixels. The DragGesture velocity semantics (cells/second) map directly to that intuition. With absolute pixels, velocity in `pixels/second` is opaque — you'd have to publish *two* velocities, or force the consumer to divide.

**(c) It degrades gracefully without optionals or sentinels.** When the terminal supports only 1006, fractional values come out integer-valued. Code that never asked for sub-cell precision (`Int(value.location.x)`) gets exactly what it got before. Code that *does* care just uses the Doubles. **No `if let subCell = value.subCellOffset {…}` branches anywhere**, no `-1` sentinels (notcurses), no separate capability dance for the 90% case. This is the load-bearing ergonomic argument.

**(d) It matches SwiftUI's signature shape.** SwiftUI's `DragGesture.Value.location: CGPoint` (which is two `CGFloat`s). The framework already advertises itself as "faithful SwiftUI parity." Doubles are the obvious unit choice; pixels would be a divergence from SwiftUI's idiom for no clear gain.

**(e) The terminal protocol is an implementation detail of the framework, not the consumer.** SGR-Pixels (1016) reports pixels because the terminal's event loop only knows about pixels — that's what the windowing system delivers. The framework's job is to convert at the boundary using the cell-pixel size it just queried via DEC 2048 / `CSI 16 t`. By the time pointer data reaches user code, it has already been re-expressed in the application's native unit. Don't punch the protocol detail through the API.

### 3.2 The legitimate counter-argument, addressed

*"But fractional cells lose information when cellPixelMetrics is unreliable."* True. If the terminal fakes ws_xpixel/ws_ypixel as 0 (WSL, Win32-OpenSSH), our internal `cellWidth` divisor is wrong, and fractional cells will be off-scale. Mitigations:

- The framework *prefers DEC 2048* in-band reports over `TIOCGWINSZ` for cell size — DEC 2048 is in-band and ordering-coherent with mouse reports.
- If neither is available, the framework should **not** enable 1016 in the first place (the cellPixelMetrics divisor would be a guess). Falling back to 1006 produces honest integer cells — much better than silently-wrong fractions.
- This keeps the "fractional value is trustworthy" invariant. If `Environment.pointerPrecision == .subCell`, the fractional values are real. Otherwise they're integer-valued, which is also fine.

### 3.3 A pixel API as a *secondary*, not primary, surface

There's still a place for raw pixel data: when the consumer wants to drive a Kitty/iTerm graphics-protocol overlay at honest pixel precision (e.g., a SwiftUI-style `Image` that needs to know "the pointer is at framebuffer pixel (47, 13) within this image"). This is a real use case but should be **derived**, not primary:

```swift
extension Point {
  public func devicePixels(in metrics: CellPixelMetrics) -> (x: Int, y: Int) {
    (Int((x * Double(metrics.width)).rounded()),
     Int((y * Double(metrics.height)).rounded()))
  }
}
```

The pixel form is a 2-line conversion at the call site that needs it. The fractional-cell form is the API contract.

---

## 4. Type system reshaping

> **Insight.** The cleanest split is to recognize that the codebase's `Point` is doing two jobs today: representing layout anchors (integer cells, e.g., `Rect.origin`) AND positions (currently integer cells, future fractional cells). These two roles want different types. SwiftUI elides this with `CGPoint` everywhere, but at the cost of constant rounding in the layout engine. Terminal layout is genuinely integer; positions are not.

### 4.1 The recommended split

Two-type split rather than CGPoint-everywhere, because it makes layout semantics legible:

```swift
// Layout anchor (integer cells). Used by Rect.origin, GeometryProxy size, layout engine.
public struct CellPoint: Equatable, Sendable {
  public var x: Int
  public var y: Int
}
public struct CellSize: Equatable, Sendable { /* .width: Int, .height: Int */ }
public struct CellRect: Equatable, Sendable { var origin: CellPoint; var size: CellSize }

// Position (fractional cells, Double). Used by every pointer/location-bearing API.
public struct Point: Equatable, Sendable {
  public var x: Double
  public var y: Double
  public init(x: Double, y: Double) { ... }
  public init(_ cellPoint: CellPoint) { x = Double(cellPoint.x); y = Double(cellPoint.y) }
}
public struct Vector: Equatable, Sendable {
  public var dx: Double
  public var dy: Double
}
```

`Rect.contains(_ point: Point)` accepts `Point` (Double) and uses half-open intervals `[x, x+w) × [y, y+h)`, matching SwiftUI semantics. Hit-testing stays cell-rect-grained (gestures route to the rect that contains the pointer's integer-floored location), and sub-cell precision flows *through* the rect to the consumer untouched.

### 4.2 Naming

`CellPoint` / `CellRect` / `Point` are honest. An alternative is `IntegerPoint` / `Point` (mirroring CG's `CGPoint` having no integer counterpart), but `Cell-` is the better name in this domain since "cell" is already the unit-of-discourse throughout the codebase.

If the two-type split feels heavy, the strict alternative is **just one `Point` (Double-valued) and have `Rect.origin` be `Point`**. The layout engine then snaps to integer cells when allocating frames. SwiftUI does this. It's slightly more "ambient floats" but is conceptually unified.

### 4.3 Velocities, distances, predicted ends

Once `Point` is Double, every co-traveler converts:

```swift
public struct DragGesture.Value {
  public var location, startLocation, predictedEndLocation: Point         // Double
  public var translation, velocity, predictedEndTranslation: Vector       // Double
  public var time: MonotonicInstant
}

public struct DragGesture {
  public let minimumDistance: Double         // was Int (cells)
  public let coordinateSpace: CoordinateSpace
}

public struct LongPressGesture {
  public let minimumDuration: Duration
  public let maximumDistance: Double         // was Int (cells)
}

public struct MouseEvent {
  public var location: Point                 // was Int Point
  public var kind: Kind
  public var modifiers: Modifiers
}
```

This is a sweeping change in *shape* but a tiny change in *meaning* — every `Int` becomes a `Double`, with integer values when 1016 isn't supported. SwiftUI parity also improves (their numeric type is CGFloat).

---

## 5. Capability detection and graceful degradation

The framework needs a small state machine on startup:

1. **Probe** — emit `CSI ? 1016 $ p` (DECRQM for SGR-Pixels). Wait ≤100 ms. Parse `CSI ? 1016 ; Pm $ y`.
2. **Probe** — emit `CSI ? 2048 h` (enable in-band size reports) and watch for the first `CSI 48 ; H ; W ; Hpx ; Wpx t` reply.
3. **Decide**:
   - If 1016 `Pm ∈ {1, 3}` *and* 2048 produced a non-zero pixel size: enable 1016, set `pointerPrecision = .subCell`.
   - Else: leave 1006 enabled, `pointerPrecision = .cell`.
4. **Special-case tmux** — if `$TMUX` is set or `$TERM` starts with `screen-`/`tmux-`, default `pointerPrecision = .cell` and skip 1016. Allow override via an explicit `App` modifier (`.allowSubCellPointerInsideTmux()`).
5. **Re-probe** on `SIGWINCH` — cell-pixel size can change when the user changes font.

### 5.1 What the consumer sees

```swift
public enum PointerPrecision: Equatable, Sendable {
  case cell                                      // integer-valued Doubles
  case subCell(metrics: CellPixelMetrics)        // fractional Doubles trustworthy
}

extension EnvironmentValues {
  public var pointerPrecision: PointerPrecision { get }
}
```

Most consumers don't read it. A drawing app does: shows "Use a Kitty/foot/Ghostty/WezTerm terminal for sub-cell precision" in unsupported terminals and disables fine-brush tools.

> **Insight.** The existing `CellPixelMetrics.Source` (`.reported` / `.estimated`) anticipates exactly this confidence question — it's already in the codebase. Compose with it: `subCell(metrics:)` carries the same confidence flag, so consumers can branch on `.estimated` if they need to (e.g., to disable a feature that only makes sense with honest pixel data). The pre-existing shape lines up neatly.

### 5.2 What the framework does internally

When `pointerPrecision == .subCell`, the SGR parser converts pixels → fractional cells before constructing `MouseEvent`:

```swift
// inside InputReader, parse path for SGR-Pixels
let cellX = Double(pixelX) / Double(cellPixelWidth)
let cellY = Double(pixelY) / Double(cellPixelHeight)
let location = Point(x: cellX, y: cellY)
```

When `.cell`, parser produces integer-valued Doubles. The boundary between protocols and the rest of the framework is *one place* in the parser.

---

## 6. Canvas — a complete redesign

Canvas is the single biggest beneficiary of sub-cell pointer input, and it deserves redesign. The current API is hardcoded to a 2×4 Braille grid — both the coordinate space (integer "subpixels" of size cellW×2 by cellH×4) and the rasterization style. With fractional pointer input flowing in cell-space, the Canvas API has an obvious cleaner shape.

### 6.1 The fundamental rethink

The current design says: *"Canvas's coordinate space is Braille subpixels, and its size is cells × subdivision."*
The redesign says: *"Canvas's coordinate space is cells (Double), and its rasterization grid is configurable."*

```swift
public struct Canvas<Drawing: CanvasDrawing>: View, ResolvableView {
  public let drawing: Drawing
  public let grid: CanvasGrid                  // how to rasterize sub-cell drawings
  public init(grid: CanvasGrid = .braille, _ drawing: Drawing)
}

public struct CanvasGrid: Equatable, Sendable {
  public let style: Style                      // .braille, .octant, .sextant, .quadrant,
                                               // .verticalHalfBlock, .horizontalHalfBlock,
                                               // .fullCell, .pixelExact (graphics protocol)
  public var subdivisionsX: Int { style.subdivisionsX }   // 2 for Braille/octant/quadrant/halfBlock-V
  public var subdivisionsY: Int { style.subdivisionsY }   // 4 for Braille/octant; 3 for sextant; 2 for quadrant; 2 for halfBlock-V

  public static let braille = CanvasGrid(style: .braille)
  public static let octant = CanvasGrid(style: .octant)
  public static let sextant = CanvasGrid(style: .sextant)
  public static let quadrant = CanvasGrid(style: .quadrant)
  public static let verticalHalfBlock = CanvasGrid(style: .verticalHalfBlock)
  public static let fullCell = CanvasGrid(style: .fullCell)
  public static let pixelExact = CanvasGrid(style: .pixelExact)   // requires Kitty/iTerm graphics
}
```

### 6.2 CanvasContext primitives in cell-space

All drawing primitives now take `Point` (Double cells) and `Vector`/`Double` for sizes. No more "subpixel coordinates":

```swift
public struct CanvasContext: Sendable {
  public let size: CellSize          // frame extent in cells (integer, from layout)
  public var foreground: Color
  public var background: Color?
  public let grid: CanvasGrid        // chosen rasterization style

  // All primitives in cell-space. Sub-cell precision preserved through to rasterizer.
  public mutating func setPixel(at: Point)                  // sets the grid sub-cell containing `at`
  public mutating func line(from: Point, to: Point)         // sub-cell Bresenham
  public mutating func strokeRect(_ rect: Rect)             // Rect with Double origin/size
  public mutating func fillRect(_ rect: Rect)
  public mutating func strokeCircle(center: Point, radius: Double)
  public mutating func fillCircle(center: Point, radius: Double)
  public mutating func strokeEllipse(center: Point, radii: Vector)
  public mutating func fillEllipse(center: Point, radii: Vector)

  // Cell-grained writes — unchanged in semantics, but their parameter type is CellPoint
  public mutating func setCell(_ cell: CanvasCell, at: CellPoint)
  public mutating func fillCell(_ color: Color, at: CellPoint)
  public mutating func clearCell(at: CellPoint)

  // New: pointer-aware drawing helper
  public mutating func stroke(_ path: PointerPath)          // see §7 below
}
```

A consumer painting from a drag now writes:

```swift
struct PaintDrawing: CanvasDrawing, Equatable {
  var stroke: [Point]                                       // fractional cells, captured from drag
  func draw(into ctx: inout CanvasContext) {
    guard stroke.count >= 2 else {
      if let p = stroke.first { ctx.setPixel(at: p) }
      return
    }
    for (a, b) in zip(stroke, stroke.dropFirst()) {
      ctx.line(from: a, to: b)                              // sub-cell Bresenham at grid res
    }
  }
}
```

No `* 2 + 1` and `* 4 + 2` anywhere. The 2×4 has moved into `CanvasGrid.braille.subdivisionsX/Y` where the rasterizer can use it; the consumer doesn't multiply.

### 6.3 Rasterizer responsibilities

Internally the rasterizer takes the fractional-cell drawing operations and projects them onto the chosen grid:

- For `.braille`: each sub-cell pixel is `(cellX, cellY) + (sx/2, sy/4)` for `sx ∈ {0,1}, sy ∈ {0,1,2,3}`. Convert `Point(x, y)` → `(floor(x*2), floor(y*4))` → set the corresponding bit.
- For `.octant` (Unicode 16 octants in the 1FB00 block): same 2×4 layout but a different glyph table.
- For `.sextant`: 2×3.
- For `.quadrant`: 2×2.
- For `.verticalHalfBlock`: 1×2.
- For `.fullCell`: 1×1, fills cell backgrounds (current `CanvasPixelGridDrawing` is this case).
- For `.pixelExact`: emit a Kitty/iTerm graphics-protocol image. The drawing context renders into an actual pixel buffer at `cellPixelMetrics × frameCells` resolution; output is base64-encoded image escape sequences inserted into the cell raster. Only available when the host advertises Kitty/iTerm graphics support.

The same `CanvasContext` API works across all of these. A sparkline drawing that today writes `setPixel(x: 5, y: 13)` on a Braille canvas works unchanged on octant or quadrant — just lower resolution. A high-end Kitty-graphics-protocol Canvas runs the same drawing at honest pixel resolution.

> **Insight.** The framework currently has *two* sub-cell paths: the Braille path (`CanvasContext.setPixel` etc.) and the `CanvasPixelGridDrawing` half-block/full-cell path. They have different APIs, different coordinate systems, and the consumer chooses by picking a constructor. With the redesign, **both become specializations of one API parameterized by `CanvasGrid`**. The half-block path becomes "use `Canvas(grid: .verticalHalfBlock)` and call `ctx.setPixel`/`ctx.fillRect`." The author writes drawing code once and varies the grid.

### 6.4 Bridging Canvas to gestures

Once Canvas's coordinate space is "cells (Double)," the gesture-to-canvas bridge is one identity transform:

```swift
.gesture(
  DragGesture(minimumDistance: 0)
    .onChanged { value in
      stroke.append(value.location)        // already in fractional cells; perfect for Canvas
    }
)
```

The `.local` coordinate space already lives in cell coordinates with origin at the gesture target rect. If that target rect is a Canvas's frame, `value.location` is a fractional position in the Canvas's drawing space. Drop into `ctx.line(from:to:)` directly.

This also means **the gesture coordinate space is the same coordinate space as the Canvas**. They are no longer separate domains the consumer has to translate between.

---

## 7. The "PointerPath" idea — capture, not just sample

The current DragGesture exposes `location` and `startLocation` only. For drawing apps, that's lossy: between two `.dragged` events the framework receives many coalesced motion events (`coalescedInputEvents` in InputReader.swift merges them to reduce work), and the consumer never sees the intermediate samples. A drawing app then has to fake interpolation with `ctx.line(from: lastLocation, to: currentLocation)`, which produces visible kinks at the sample boundaries.

A natural addition while we're touching gesture API:

```swift
public struct DragGesture.Value {
  // existing fields...
  public var path: PointerPath
}

public struct PointerPath: Equatable, Sendable, RandomAccessCollection {
  // Sequence of (location, time) samples received since the gesture began.
  public struct Sample: Equatable, Sendable {
    public let location: Point          // fractional cells
    public let time: MonotonicInstant
  }
  public typealias Element = Sample
  // standard collection conformance
}
```

The framework already keeps a `samples: [Sample]` array inside `DragGestureRecognizer` (DragGesture.swift:91–94, used for velocity computation). Surface it. Drawing apps now write:

```swift
.onChanged { value in
  for sample in value.path.suffix(from: lastIndex) {
    ctx.line(from: previous, to: sample.location)
    previous = sample.location
  }
  lastIndex = value.path.endIndex
}
```

No more visible kinks. Same idea for `SpatialTapGesture` if you want it (probably overkill; taps don't need paths).

> **Insight.** This is the kind of feature that's only obvious *after* sub-cell precision lands. With cell-grained input, an in-cell drag is invisible anyway, so capturing intermediate samples adds nothing. With sub-cell precision, every intermediate sample carries new information. The two features (sub-cell + path capture) are co-dependent — each makes the other useful — and are exactly the sort of thing to design together at pre-release time when nothing is sacred.

---

## 8. Other APIs worth touching while we're here

The full list of ripples worth seriously considering, ordered by leverage:

### 8.1 Drop destination location

`DropDestinationHandler = ([DroppedPath]) -> Bool` today carries no location. A user dropping a file onto a multi-pane app has no way to ask "which pane?" Add it:

```swift
public typealias DropDestinationHandler =
  @MainActor @Sendable ([DroppedPath], DropContext) -> Bool

public struct DropContext: Equatable, Sendable {
  public let location: Point          // fractional cells, in destination's local space
  public let modifiers: EventModifiers
}
```

Free with sub-cell pointer input — the drop event arrives as a paste/mouse-coupled event sequence and the parser already has the cursor location at drop time.

### 8.2 Hover events (new)

The framework currently has no hover API. Sub-cell precision makes hover dramatically more useful (a hover at fractional cell `(5.7, 2.1)` is more like a "cursor on a graph" than a "cursor in a button"). With DECSET 1003 ("any-event tracking, even no button held") plus 1016, you can build:

```swift
extension View {
  public func onPointerHover(_ action: @escaping (HoverEvent) -> Void) -> some View
  public func onPointerHoverChange(_ action: @escaping (HoverPhase) -> Void) -> some View
}

public enum HoverPhase: Equatable, Sendable {
  case entered(Point)
  case moved(Point)
  case exited
}
```

Tooltips, crosshair-on-chart, hot-zone highlighting, "scrubbing" interactions. Not strictly required for the sub-cell change, but it's the natural co-feature.

Note: 1003 is bandwidth-heavy (every motion event traverses the wire), so wire it up only when a view actually opts into hover. Reference-count subscribers; emit `CSI ? 1003 h` on first subscriber, `CSI ? 1003 l` on last.

### 8.3 SpatialTapGesture & TapGesture

`SpatialTapGesture.Value.location` becomes `Point` (Double). Sub-cell precision for the tap location.

`TapGesture.Value` is currently `Void`. Consider making it `SpatialTapGesture.Value`'s shape so consumers don't have to switch types when they realize they wanted the location. SwiftUI keeps them separate because the tap-without-location case has merit (cleaner API for "I just want to know it tapped"). **Recommendation: keep them separate.**

### 8.4 LongPressGesture maximumDistance

`maximumDistance: Int` (cells) becomes `Double`. The default of "1 cell" stays integer-valued (Double 1.0). Consumers who want sub-cell tightness can now write `maximumDistance: 0.5`.

### 8.5 GeometryProxy

`GeometryProxy.size: Size` (Int) stays integer — frames are integer-cell-sized in this framework, and that's correct. Add a single field:

```swift
public struct GeometryProxy: Equatable, Sendable {
  public var size: CellSize
  public var safeAreaInsets: EdgeInsets
  public var cellPixelMetrics: CellPixelMetrics
  public var pointerPrecision: PointerPrecision    // NEW
}
```

This lets a Canvas-using drawing app branch UI based on capability without dipping into `@Environment`.

### 8.6 Coordinate spaces — finish `.named(_:)`

`CoordinateSpace.named(_:)` currently traps with `fatalError`. With fractional-cell pointers, it'd be a good time to implement it: a named coordinate space is a snapshot of a particular ancestor's `targetRect` that survives across the view tree. SwiftUI uses it for "drag from one container, drop into another, both reporting positions in the source's frame." Implement once, gain composability for free.

### 8.7 Animated drag-following

The DragGesture velocity is currently `Size` (Int cells/sec) and predictedEndLocation is integer. With Doubles, you can drive a **rubber-band overshoot** or **inertial deceleration** in the framework's animation system without quantization stutter. Real UX improvement for scroll views and pannable canvases.

### 8.8 Touch/stylus differentiation (future)

Nothing in the SGR-Pixels protocol differentiates touch from mouse. But Kitty's mouse extensions can carry source kind, and DEC Locator separates "mouse" from "tablet." A future-proof `MouseEvent` could carry an optional `pointerKind: PointerKind` field (`.mouse`, `.touch`, `.stylus(pressure: Double, tilt: Vector)`); for now nothing fills it, but the field's existence means stylus terminals (rare today, plausible tomorrow) integrate without an API break.

### 8.9 The `coordinateSpace` parameter ergonomics

DragGesture/SpatialTapGesture both take a `coordinateSpace: CoordinateSpace = .local`. This is correct but verbose. Consider `.local` being implicit in the gesture-attaching modifier and removing the parameter unless the consumer wants something different. Pre-release, no migration cost.

---

## 9. Tmux, SSH, and other operational realities

Pitfalls the design must respect:

- **Inside tmux, 1016 is broken in the general case.** Even with `allow-passthrough on`, pixel coordinates reflect the outer terminal's window, not the tmux pane, and tmux doesn't know per-pane pixel offsets. **Disable 1016 by default when `$TMUX` is set.** Provide an opt-in for users who know they're not splitting.

- **Some terminals fake `TIOCGWINSZ` pixel fields as 0.** WSL and Windows Terminal are explicit offenders. **Prefer DEC 2048 (`CSI ? 2048 h` for push reports) or `CSI 16 t` query over `TIOCGWINSZ.ws_xpixel/ws_ypixel`.** If only `TIOCGWINSZ` is available and reports zero, use `.estimated` and don't enable 1016.

- **iTerm2 and Apple Terminal don't support 1016** as of 2026. macOS users running with default tools will see `pointerPrecision = .cell`. The framework should run perfectly there — graceful degradation is the point.

- **Pixel coordinates can be negative or overshoot terminal bounds** in some terminals (Ghostty, Kitty — when a drag exits the window). Don't clamp on the framework side; consumers can clamp themselves if they care. Negative fractional cells are fine semantically.

- **Re-probe on `SIGWINCH`.** Cell pixel size changes if the user changes font.

- **Detection over multiplexers is unreliable.** DECRQM replies can be intercepted by tmux. Trust the probe as a hint, not a contract. The fall-back path (1006-only) must always work as a baseline.

---

## 10. Creative extensions the redesign opens up

Once fractional-cell pointer input and a grid-pluggable Canvas are landed, several things become natural that aren't natural today.

### 10.1 A unified Path / Shape / Canvas hierarchy

The framework already has `Shape` (cell-grained, integer). With fractional `Point`, you can introduce a real `Path`:

```swift
public struct Path: Equatable, Sendable {
  public mutating func move(to: Point)
  public mutating func addLine(to: Point)
  public mutating func addQuadCurve(to: Point, control: Point)
  public mutating func addCubicCurve(to: Point, control1: Point, control2: Point)
  public mutating func addArc(center: Point, radius: Double, startAngle: Double, endAngle: Double)
  public mutating func close()
  public func contains(_ point: Point) -> Bool
}

extension CanvasContext {
  public mutating func stroke(_ path: Path, lineWidth: Double = 1)
  public mutating func fill(_ path: Path)
}

public protocol Shape: View {
  func path(in rect: Rect) -> Path
}
```

Now a `Shape` is a `Path`-producing thing, a `Canvas` rasterizes any drawing onto a configurable grid, and a gesture's location is testable against a `Path` for hit-on-curve interactions. **The whole graphics API becomes uniform**, and SwiftUI parity gets dramatically deeper.

This is the most ambitious idea in the analysis. Pre-release status makes it the right time. It's also the most expensive — but it's a single conceptual move that absorbs Canvas, Shape, and Path into one model. **At minimum, sketch out whether this is the direction before locking in a separate Canvas redesign that doesn't anticipate it.**

### 10.2 The "honest pixels" Canvas mode (`.pixelExact`)

When the host supports Kitty/iTerm2 graphics protocol AND 1016 sub-cell input, the framework can offer `Canvas(grid: .pixelExact)`:

- Drawing operations rasterize into a real pixel buffer of size `frameCells.width × cellPixelMetrics.width × frameCells.height × cellPixelMetrics.height`.
- The buffer is encoded as a Kitty/iTerm graphics image and emitted in the cell raster.
- Pointer events arrive at full pixel precision (`cellPixelMetrics.width × cellPixelMetrics.height` resolution within a cell).
- Suddenly the terminal becomes a credible (low-res) graphics surface.

This is a real frontier. Existing in-the-wild attempts (e.g., tmpvar's "Rendering Interactive Graphics in Kitty") confirm it works in production but are rarely attempted because no framework wires the pieces together. Doing it via a single grid choice on Canvas is unusually elegant — the same drawing code that targets Braille just retargets to honest pixels.

The framework should advertise `Capabilities.canvasModes: Set<CanvasGrid.Style>` in the environment so consumers can pick the best available mode without manual probing.

### 10.3 Snap modifier

```swift
extension View {
  public func pointerSnap(to grid: CanvasGrid) -> some View
}
```

When attached, all gesture locations propagated through this view's subtree are snapped to the nearest grid sub-cell *before* delivery. Useful for crisp paint apps that want the consumer to receive only valid grid positions. Implementable as a coordinate-space transform inserted between the runloop and the gesture recognizer.

### 10.4 PointerOverlay debugging

A dev-time view that draws the current pointer position as a small crosshair at fractional cell precision. Useful for verifying 1016 actually works on a given terminal. `App.environment(\.pointerOverlayEnabled, true)`.

### 10.5 Velocity-based predictive UI

Today the framework's animation system has no concept of input velocity. With fractional `Vector` velocity, animations can be *initiated with momentum* (drag-to-fling, predictive scroll-snap). This is a UI-quality leap; SwiftUI does it well. The plumbing change is small once velocities are Doubles.

### 10.6 Hit-testing on Path / Shape

Once `Path.contains(_ point: Point)` exists and pointers are fractional, gestures can target arbitrary shapes — not just rectangles. SwiftUI does this with `.contentShape(...)`. The framework can:

```swift
.contentShape(Circle())     // gesture only fires when pointer is within the circular region
.contentShape(Path { ... })
```

Useful for clickable icons, custom widget shapes, and pie-chart slices.

### 10.7 Signal-sample reporting

For a charting/scope-style view, the consumer might want "pointer at fractional cell `(5.7, 2.1)` corresponds to data sample 1247.3 in my time series." That's just a coordinate transform from cell-space → data-space, which is trivial with Doubles. The framework can offer a reusable `ChartCoordinateSpace` with `chart.coordinateSpace.dataValue(at: pointerLocation)`. Builds the foundation for a real charts API on top of the existing `TerminalUICharts` module.

---

## 11. Open questions and tradeoffs

Things to resolve before committing to the design — written as questions, with the recommended lean.

**Q1. One `Point` (Double) or two types (`CellPoint` Int + `Point` Double)?**
*Lean: two types.* `CellPoint` for layout/`Rect.origin`, `Point` for positions. The semantic distinction — "cells you can land on" vs. "positions in cell-space" — is real and worth naming. SwiftUI elides it because its layout is inherently float-grained; this framework's layout is integer-grained, which makes the distinction natural.

**Q2. Should `Rect` get fractional origins / sizes for animations?**
*Lean: not yet.* `Rect` is layout. Layout in this framework is integer-cell. Don't muddy it. If you ever want sub-cell-precise animated frames, introduce `AnimatedRect` (Double-backed) at that point.

**Q3. Should TapGesture surface a location now that we have sub-cell?**
*Lean: no.* Keep TapGesture locationless. Consumers who want location use SpatialTapGesture. The two-type design captures intent.

**Q4. Make `pointerPrecision` per-window or global?**
*Lean: global, but per-window override possible.* Different windows in a multi-window terminal could have different cell-pixel metrics in theory. In practice nobody supports multi-pane sub-cell anyway. Start global, expand later.

**Q5. Should `.pixelExact` Canvas be a different Canvas type, or the same?**
*Lean: same.* `Canvas(grid: .pixelExact)` is the natural fit. The cost is that pixel-exact rasterization has very different perf characteristics — full pixel buffer + image-encoding round-trip vs. Braille-glyph cell writes. The consumer should understand this. Document it; don't bifurcate the type.

**Q6. Path / Shape unification — now or later?**
*Lean: design for it now, ship Canvas-grid first.* Sketch the `Path` type and ensure `Canvas`'s primitive set is `Path`-compatible (i.e., the rasterizer can take a Path and stroke/fill it). Implementation can come later. Crucially, **don't ship a Canvas redesign that won't compose with a future Path**.

**Q7. Path-capture in DragGesture — opt-in or always?**
*Lean: always.* Already maintained internally; surfacing the array adds zero marginal cost. Memory is bounded by gesture duration.

**Q8. What about the `SpatialTapGesture.Value`'s sub-cell location for non-1016 terminals?**
*Lean: integer-valued Double, same as everywhere else.* Consumer sees `Point(x: 5.0, y: 2.0)` even when only cell-precision was available. No optionality.

**Q9. Should the framework expose pure-pixel `MouseEvent.devicePixelLocation: (Int, Int)?` for graphics-protocol consumers?**
*Lean: as a derived computed property, not a stored field.* `event.location.devicePixels(in: env.cellPixelMetrics)`. Keep the primary surface fractional-cells.

**Q10. Naming of the grid type.**
*Lean: `CanvasGrid` over `Rasterization` / `SubCellGrid` / `PixelGrid`.* Reads at the call site as `Canvas(grid: .braille)` / `Canvas(grid: .pixelExact)`. Cohesive with the existing `CanvasPixelGridMode` (which becomes a deprecated alias / replaced).

---

## 12. Summary of recommended changes (the diff at the type level)

| Surface | Today | Recommended |
|---|---|---|
| `Point` | `(Int, Int)`, "cell coordinates" | `(Double, Double)`, "fractional cell coordinates" |
| `CellPoint` | (didn't exist) | `(Int, Int)`, layout anchors |
| `Vector` | (didn't exist) | `(Double, Double)`, velocities/translations |
| `Size` | `(Int, Int)`, cells | (kept Int) used for layout extents |
| `Rect.origin` | `Point(Int)` | `CellPoint` |
| `Rect.contains` | `(Point Int) -> Bool` | `(Point Double) -> Bool`, half-open |
| `MouseEvent.location` | `Point(Int)` | `Point(Double)` |
| `DragGesture.Value.location` | `Point(Int)` | `Point(Double)` |
| `DragGesture.Value.velocity` | `Size(Int)` cells/sec | `Vector(Double)` cells/sec |
| `DragGesture.Value.path` | (didn't exist) | `PointerPath` (sample sequence) |
| `DragGesture.minimumDistance` | `Int` | `Double` |
| `LongPressGesture.maximumDistance` | `Int` | `Double` |
| `SpatialTapGesture.Value.location` | `Point(Int)` | `Point(Double)` |
| `CanvasContext.width/height` | `Int` Braille subpixels | `CellSize` (integer-cell extent), `grid: CanvasGrid` |
| Canvas primitives | Int subpixels, fixed 2×4 | `Point(Double)` cells, `grid`-pluggable |
| `Canvas(pixelGridWidth:…)` | separate API for cell-grid | replaced by `Canvas(grid: .fullCell, …)` |
| `CoordinateSpace.resolve` | `Point(Int) - Rect.origin(Int)` | `Point(Double) - CellPoint(Int)` |
| `CoordinateSpace.named(_:)` | traps | implemented |
| `EnvironmentValues.pointerPrecision` | doesn't exist | `.cell` / `.subCell(metrics:)` |
| Hover events | don't exist | `.onPointerHover { … }` (DECSET 1003 + 1016) |
| Drop destination | location-less | location-bearing via `DropContext` |
| Tmux behavior | inherited from system | 1016 disabled by default inside `$TMUX` |
| Capability detection | none | DECRQM 1016 + DEC 2048 probe at startup, re-probe on SIGWINCH |
| `CellPixelMetrics` | exposed | retained, primary use becomes "internal pixel→cell conversion + advisory aspect-ratio" |
| `Path` | didn't exist | introduced (Double, cell-space) |
| `Shape.path(in:)` | (cell-grained) | `Path` (Double-grained); old shapes still produce integer-aligned paths |

---

## 13. The shortest summary of the recommendation

1. **Make `Point` Double-valued; keep cells the unit.** Pixels are the protocol detail; cells are the application's contract.
2. **Probe DECRQM(?1016) + DEC 2048 at startup; expose the result as `EnvironmentValues.pointerPrecision`.** Gracefully degrade to integer-valued Doubles when 1016 is unavailable. Disable 1016 inside tmux by default.
3. **Redesign Canvas in cell-space with a pluggable `CanvasGrid`** (Braille/octant/sextant/quadrant/halfBlock/fullCell/pixelExact). Drawing primitives accept `Point(Double)`. The hardcoded 2×4 dies.
4. **Capture pointer paths**, not just locations, in DragGesture. Sub-cell precision makes the intermediate samples valuable.
5. **Sketch `Path` and a Path/Shape/Canvas unification now**, even if implementation lands later. Make sure the Canvas redesign composes with it.
6. **Add hover, drop-location, snap-to-grid, and pixelExact graphics**: these are the natural co-features. Pre-release means nothing is sacred — bundle them into one coherent type-system shift instead of incremental layers.

The single decision that defines all the others is the first one: **fractional cells are the right unit at the API boundary**. Everything else falls out of that.

---

## 14. References

### Specs and protocols

- [Xterm Control Sequences (invisible-island.net)](https://www.invisible-island.net/xterm/ctlseqs/ctlseqs.html)
- [Xterm Change Log (invisible-island.net)](https://invisible-island.net/xterm/xterm.log.html)
- [Terminal Guide — mouse modes overview](https://terminalguide.namepad.de/mouse/)
- [Terminal Guide — DEC Locator](https://terminalguide.namepad.de/seq/csi_sz_t_tick/)
- [VT510 DECRQM (vt100.net)](https://vt100.net/docs/vt510-rm/DECRQM.html)
- [VT510 DECRPM (vt100.net)](https://vt100.net/docs/vt510-rm/DECRPM)
- [DEC Locator Mouse memo (vt100.net)](https://vt100.net/shuford/terminal/dec_vt_mouse.html)
- [In-band size reports / DEC 2048 (rockorager gist)](https://gist.github.com/rockorager/e695fb2924d36b2bcf1fff4a3704bd83)

### Terminal implementations

- [foot SGR-Pixel issue #762](https://codeberg.org/dnkl/foot/issues/762), [foot PR #871](https://codeberg.org/dnkl/foot/pulls/871/files), [foot-ctlseqs man](https://www.mankier.com/7/foot-ctlseqs)
- [WezTerm 1016 issue #1457](https://github.com/wezterm/wezterm/issues/1457)
- [Microsoft Terminal 1016 issue #18591](https://github.com/microsoft/terminal/issues/18591)
- [Microsoft Terminal TIOCGWINSZ #8581](https://github.com/microsoft/terminal/issues/8581), [WSL TIOCGWINSZ #12265](https://github.com/microsoft/WSL/issues/12265)
- [Win32-OpenSSH faking pixel dimensions #2349](https://github.com/PowerShell/Win32-OpenSSH/issues/2349)
- [tmux #4099 (CSI fallback when TIOCGWINSZ is 0)](https://github.com/tmux/tmux/issues/4099)
- [Ghostty discussion #9647 (negative coords in 1016)](https://github.com/ghostty-org/ghostty/discussions/9647)
- [Ghostty discussion #2362 (sub-cell math, 1016+2048)](https://github.com/ghostty-org/ghostty/discussions/2362)
- [Kitty changelog](https://sw.kovidgoyal.net/kitty/changelog/) and [protocol extensions](https://sw.kovidgoyal.net/kitty/protocol-extensions/)
- [iTerm2 feature-reporting spec](https://iterm2.com/feature-reporting/)
- [xterm.js VT features (1016 supported)](https://xtermjs.org/docs/api/vtfeatures/)
- [xterm.js mouse modes PR #2316](https://github.com/xtermjs/xterm.js/pull/2316)
- [Contour passive mouse tracking](https://github.com/contour-terminal/vt-extensions/blob/master/passive-mouse-tracking.md)
- [Mintty changelog (1016 support)](https://github.com/mintty/mintty/wiki/Changelog)

### TUI frameworks

- [Notcurses use-1016 issue #2326](https://github.com/dankamongmen/notcurses/issues/2326)
- [Notcurses USAGE.md](https://github.com/dankamongmen/notcurses/blob/master/USAGE.md), [notcurses_input(3)](https://manpages.debian.org/experimental/libnotcurses-dev/notcurses_input.3.en.html)
- [crossterm pixel coords issue #873](https://github.com/crossterm-rs/crossterm/issues/873) and [PR #929](https://github.com/crossterm-rs/crossterm/pull/929)
- [Ratatui canvas pixel-mouse issue #735](https://github.com/ratatui/ratatui/issues/735), [Marker docs](https://docs.rs/ratatui/latest/ratatui/symbols/enum.Marker.html)
- [Textual smoother scrolling blog](https://textual.textualize.io/blog/2025/02/16/smoother-scrolling-in-the-terminal-mdash-a-feature-decades-in-the-making/)
- [Bubble Tea v2 upgrade guide](https://github.com/charmbracelet/bubbletea/blob/main/UPGRADE_GUIDE_V2.md), [charmbracelet/x/ansi pkg](https://pkg.go.dev/github.com/charmbracelet/x/ansi)
- [Blessed (Python) mouse docs](https://blessed.readthedocs.io/en/latest/mouse.html), [api/mouse](https://blessed.readthedocs.io/en/latest/api/mouse.html)
- [tmux FAQ + allow-passthrough](https://github.com/tmux/tmux/wiki/FAQ)

### Application examples

- [tmpvar — Rendering Interactive Graphics in Kitty](https://tmpvar.com/articles/rendering-interactive-graphics-in-kitty/)
- [PixelArtTUI](https://github.com/Cvaniak/PixelArtTUI), [utu](https://github.com/sile/utu)
