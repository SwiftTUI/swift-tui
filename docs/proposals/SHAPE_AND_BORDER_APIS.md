# Shape & Border APIs — Revamp Design

> Status: **Shipped as of Milestone 7.** Sections below describe the
> design intent; call-outs note where the landed implementation diverged
> from the original proposal.
> Audience: maintainers of swift-terminal-ui after the shape, border, and
> fill revamp landed, plus reviewers tracing why the surface looks the
> way it does.

## 1. Why this exists

Today's `Shape`/`stroke`/`strokeBorder`/`.border` surface in this repo is
roughly a transliteration of SwiftUI's. That's the right star to steer by,
but the literal port has three concrete pain points:

1. **Borders silently eat content.** `Rectangle().strokeBorder(...)` and
   `.border(.white)` draw inside the view's bounds. The default has no
   padding, so the top/bottom rows and the leading/trailing columns of the
   bordered child are overwritten by box-drawing glyphs. The user typically
   notices when text disappears, then has to reach for `.padding(1)` and
   tweak until it looks right. There is no defaulted-padding affordance,
   no compile-time hint, and no warning at runtime.

2. **The drawing model is "centered stroke" but cells aren't pixels.**
   `.stroke` and `.strokeBorder` differ in SwiftUI by `lineWidth/2`. In a
   terminal there is no half-cell, so for `lineWidth: 1` (the only width
   most callers ever use) `stroke` and `strokeBorder` collapse to the same
   visual but with subtly different layout intents that we don't surface.
   Users can't predict which one keeps text safe.

3. **You can't reach for nice extras.** There's no API for:
   - drawing a border that lives **outside** the layout box (so the
     content area is the natural full size),
   - per-corner colors,
   - dashed/patterned edges,
   - gradient strokes around a perimeter,
   - 2D gradient fills,
   - pattern fills (`░ ▒ ▓` shading),
   - or sub-cell shapes via Braille / quadrant glyphs.

   The infrastructure (`LineVariant`, `BorderBackgroundStyle`,
   `ShapeOperation`) is half-built toward several of these but doesn't
   expose them at the call site.

The current call sites tell the story. From `Examples/gallery`:

```swift
// CounterTab — uses the .border modifier with the default style
.border(.separator)

// CalculatorTab — switches to .border(.black) to get a "no visible border"
// effect because the default border + content overlap is uglier
.border(.black)
```

Both are workarounds. `CounterTab` accepts the default but content is
spaced out with explicit `.padding`s elsewhere; `CalculatorTab` actively
hides the border because it interferes with the grid below.

This document proposes a new surface that:
- ships defaults that look good without padding,
- keeps the SwiftUI mental model where it survives the cell grid,
- exposes a small, curated set of escape hatches drawn from lipgloss,
  Ratatui, Textual, and Ink,
- and gives consumers a clean extensibility seam (custom `BorderSet`,
  custom `Pattern`, custom `Shape`).

## 2. What we already have (inventory)



**Shape protocol** (`Sources/View/Shapes/ShapeStyles.swift:4-11`)

```swift
public protocol Shape: View {
  var geometry: ShapeGeometry { get }
  var kindName: String { get }
  var insetAmount: Int { get }
}
public protocol InsettableShape: Shape {}
```

**Concrete shapes** (`Sources/View/Shapes/`)
- `Rectangle` — `.geometry == .rectangle`, conforms to `InsettableShape`
- `RoundedRectangle(cornerRadius: Int)` — `.geometry == .roundedRectangle(cornerRadius:)`
- `InsetShape<Base: InsettableShape>` — generic wrapper accumulating inset

There is no `Circle`, `Ellipse`, `Capsule`, `Path`, or `UnevenRoundedRectangle`.

**ShapeGeometry** (`Sources/Core/Styling.swift:594-597`)

```swift
public enum ShapeGeometry: Equatable, Sendable {
  case rectangle
  case roundedRectangle(cornerRadius: Int)
}
```

Two cases. Adding cases here is the natural extensibility point but is
not used today.

**Stroke / fill modifiers** (`Sources/View/Shapes/ShapeStyles.swift:80-200`)

```swift
extension Shape {
  func fill<S: ShapeStyle>(_ style: S) -> some View
  func stroke<S: ShapeStyle>(_ style: S, style: StrokeStyle = .init()) -> some View
  func stroke<S, B>(_: S, style: StrokeStyle = .init(), background: B) -> some View
  func strokeBorder<S>(_: S, style: StrokeStyle = .init()) -> some View
  func strokeBorder<S, B>(_: S, style: StrokeStyle = .init(), background: B) -> some View
}
```

The `strokeBorder: Bool` field on `ShapeOperation.stroke(...)` currently
toggles a 1-cell inset on the rasterizer side. Stroke and strokeBorder
share the same rendering path; the only difference is that flag.

**LineVariant** (`Sources/Core/Styling.swift:441-454`)

```swift
public enum LineVariant: String, Equatable, Sendable {
  case automatic, ascii, single, rounded, double, heavy,
       block, outerHalfBlock, innerHalfBlock,
       presentationChrome, hidden, markdown
}
```

Twelve variants, with glyph tables in `Rasterizer.swift:1280-1455`. Today
each variant is monolithic — a `LineVariant` is a closed enum that maps
to one fixed `BorderGlyphSet` of 8 glyphs (4 edges + 4 corners). There's
no way for a consumer to define a custom variant from outside the framework.

**StrokeStyle** (`Sources/Core/Styling.swift:462-487`)

```swift
public struct StrokeStyle: Equatable, Sendable {
  public var lineWidth: Int          // clamped to >= 1
  public var lineVariant: LineVariant
}
```

Two fields. No dash pattern, no per-side variant override, no animation phase.

**BorderBackgroundStyle** (`Sources/Core/Styling.swift:490-585`)

A four-edge optional `AnyShapeStyle` for "what color sits behind the
glyph on each edge." Already supports per-edge color, which is more than
SwiftUI does.

**The .border View modifier** (`Sources/View/Modifiers/StyleModifiers.swift:114-149`)

```swift
public func border<S: ShapeStyle>(_ style: S, width: Int = 1) -> some View {
  overlay {
    Rectangle().strokeBorder(style, style: .init(lineWidth: width), background: nil)
  }
}
```

i.e. `.border` is implemented as `.overlay(Rectangle().strokeBorder(...))`.
It draws **inside** the content's frame, overwriting the outer rows and
columns. It does not add to the content's intrinsic size, and there is no
automatic padding.

This is the single biggest footgun in the current API. Everything else
flows from it.

## 3. Lessons from other ecosystems

Detailed research is in §6; the punchlines are:

**SwiftUI** is the mental-model anchor. Keep `Shape` / `InsettableShape`,
keep `fill` / `stroke` / `strokeBorder` / `.border`, keep `ShapeStyle` as
the universal "thing you can paint with" protocol. Diverge only where the
cell grid forces it (sub-cell widths, half-cell stroke centering, squircle
corners, true ellipses).

**lipgloss** is the gold standard for TUI. Three things to lift wholesale:

1. **The `Border` struct.** A flat record of strings (one per edge, corner,
   join), where each edge can be a multi-rune sequence that the renderer
   *cycles through* per cell. That gives you free dashed borders without
   needing a separate dash type. The 13-slot layout (TRBL edges + 4
   corners + middle joins for tables) is the right shape.

2. **Frame math.** lipgloss's invariant: declared width includes border
   and padding. `wrap_at = width - borderH - paddingH`. The border lives
   *on* the frame. Adopt this verbatim — it's the hard part of TUI layout
   that lipgloss got right.

3. **`Blend1D` / `Blend2D` + `BorderForegroundBlend`.** CIELAB-interpolated
   gradients including a perimeter blend that flows continuously around
   the border, plus an offset for animation. This is the feature lipgloss
   has and SwiftUI does not, and it's perfect for terminal cells where
   you have 1 color per cell anyway.

**Ratatui** — `Borders::ALL` as bitflags (per-edge toggles compose better
than four separate bools), and `Block::inner(area) -> Rect` as a pure
function the layout engine threads through children. The latter is exactly
how a "border that adds to the frame" wants to be implemented.

**Textual** — `(offset: CGFloat, color: Color)` gradient stops. lipgloss's
positional-stops design (where you replicate colors to weight a stop)
can't express "10%/90%" without ugly tricks. Use Textual's tuple shape.

**Ink** — `singleDouble`/`doubleSingle` hybrid borders, `borderDimColor`,
`borderTop`/`borderRight`/`borderBottom`/`borderLeft` per-side toggles.
The hybrid borders are a cute trick worth shipping in the defaults set.

**termui (Go) / Textual `Canvas`** — Braille-canvas drawing with a 2×4
subpixel grid per cell. Nobody else in the TUI ecosystem ships a real
"shape" primitive that goes beyond rectangles, and Braille is the standard
escape hatch for "I want to draw a circle / a sparkline / a plot." Worth
having a `Canvas` view as the answer to "how do I draw arbitrary shapes."

## 4. Design

### 4.1 Defaults that don't hurt

The single biggest change. The new `.border(...)` modifier:

```swift
extension View {
  /// Draws a border around this view. The border lives **outside** the
  /// view's content frame — i.e. the view grows by `border.frameInsets`
  /// to make room. The content area is unchanged.
  ///
  /// Default style is `.outerHalfBlock` in the current foreground style,
  /// which never overlaps content and looks like a soft outset card.
  public func border(
    _ style: some ShapeStyle = .foreground,
    set: BorderSet = .outerHalfBlock,
    sides: Edge.Set = .all
  ) -> some View
}
```

Three things to note:

1. **`set: BorderSet = .outerHalfBlock`** — the default is the outer
   half-block (`▀ ▄ ▌ ▐ ▛ ▜ ▙ ▟`), drawn *outside* the content frame.
   This is deliberately a "fairly ugly" but fully visible default per the
   user's goal: anyone reading the code immediately sees a border, and
   no text is occluded. It's also actually quite attractive in practice
   — half-blocks have a soft shadow-like quality that reads as a card.
2. **`sides: Edge.Set = .all`** — switch to a Ratatui-style bitflag so
   `.border(sides: [.top, .bottom])` works. SwiftUI doesn't have this;
   it's a strict win.
3. **The default is "outset," not "inset."** This is the breaking change
   from current behavior and the central design call. See §5 for the
   rationale and migration.

A view with `.border()` and nothing else expands its frame by the
border's frame insets:

```
Content area: 10×3
              ┌──────────┐
              │  hello   │       ← inside the content area
              │   world  │
              │          │
              └──────────┘
              Total area: 12×5 (or 10×5 for half-block which uses 0
              horizontal cells but 1 row above + 1 row below)
```

For variants where the glyphs naturally live inside cells (full block,
single line, rounded, double, heavy, ASCII), the default behavior is to
**still draw outside** by adding 1 row + 1 column of padding around the
content. The border draws into that padding row/column, not into the
content. The half-block variants are special: they fit in half a cell
visually, so the frame inset on top/bottom is 1 row each but feels lighter.

### 4.2 The `BorderSet` type

Lift directly from lipgloss, with minor Swift seasoning:

```swift
public struct BorderSet: Equatable, Sendable {
  public var top: String
  public var bottom: String
  public var left: String
  public var right: String

  public var topLeading: String
  public var topTrailing: String
  public var bottomLeading: String
  public var bottomTrailing: String

  // Joins (used by Table / Grid; optional for plain views)
  public var middleLeading: String
  public var middleTrailing: String
  public var middle: String
  public var middleTop: String
  public var middleBottom: String

  /// Whether this border draws *inside* the content frame or *outside* it.
  /// Outset borders add to the frame insets so content is never occluded.
  public var placement: Placement
  public enum Placement: Equatable, Sendable {
    case outset           // adds rows/cols around content (default)
    case inset            // overdraws the outermost rows/cols of content
    case decorative       // draws on the frame edges; content unchanged but
                          // edge cells are blended (used by half-block sets)
  }

  public init(/* … */)
}
```

Each edge field is a `String`, not a `Character`, so:

- multi-grapheme borders work,
- each edge can be 2+ runes (e.g. `"─·"`) for **free dashed borders** —
  the renderer cycles through the runes per cell,
- empty string means "no glyph" → that side is skipped (bitflag-style
  toggling falls out for free).

The size each edge contributes to the frame is the *display width of the
widest grapheme in that edge*. So a CJK or emoji edge correctly reports
2 columns. This matches lipgloss's `GetTopSize`/`GetLeftSize`.

### 4.3 Built-in `BorderSet`s

Replace the closed `LineVariant` enum with a set of static factories on


```swift
extension BorderSet {
  /// Default. `▀ ▄ ▌ ▐ ▛ ▜ ▙ ▟`, placement = .decorative.
  public static let outerHalfBlock: BorderSet

  /// `▄ ▀ ▐ ▌ ▗ ▖ ▝ ▘`, draws a recessed look from inside the frame.
  public static let innerHalfBlock: BorderSet

  /// Solid `█` on every edge. Bold and unmissable; looks like a thick
  /// shadow. Placement = .outset.
  public static let block: BorderSet

  /// `─ │ ┌ ┐ └ ┘ ├ ┤ ┼ ┬ ┴`. Placement = .outset.
  public static let single: BorderSet

  /// `─ │ ╭ ╮ ╰ ╯ …`. Placement = .outset.
  public static let rounded: BorderSet

  /// `═ ║ ╔ ╗ ╚ ╝ ╠ ╣ ╬ ╦ ╩`. Placement = .outset.
  public static let double: BorderSet

  /// `━ ┃ ┏ ┓ ┗ ┛ ┣ ┫ ╋ ┳ ┻`. Placement = .outset.
  public static let heavy: BorderSet

  /// Hybrid: single horizontals, double verticals.
  /// `─ ║ ╓ ╖ ╙ ╜ …`. Placement = .outset.
  public static let singleDouble: BorderSet

  /// Hybrid: double horizontals, single verticals.
  /// `═ │ ╒ ╕ ╘ ╛ …`. Placement = .outset.
  public static let doubleSingle: BorderSet

  /// `- | + + + +`. Placement = .outset, fallback when Unicode is unsafe.
  public static let ascii: BorderSet

  /// All spaces. Same frame insets as `.single`, but invisible — useful
  /// for keeping layout stable while toggling borders.
  public static let hidden: BorderSet

  /// All empty strings. Zero frame insets, no draw at all.
  public static let none: BorderSet

  /// Dashed: edges cycle `"─·"` and `"│·"`. Placement = .outset.
  public static let dashed: BorderSet

  /// Heavy dashed using `┄┅` family. Placement = .outset.
  public static let dashedHeavy: BorderSet

  /// Markdown table style, `|`/`-`/`+`. Used by markdown rendering.
  public static let markdown: BorderSet
}
```

This gives ~15 ready-to-use sets. The user never needs to remember a
`LineVariant` enum case — autocomplete on `BorderSet.` shows the menu.

A custom border:

```swift
let stars = BorderSet(
  top: "★", bottom: "★",
  left: "┃", right: "┃",
  topLeading: "╔", topTrailing: "╗",
  bottomLeading: "╚", bottomTrailing: "╝",
  placement: .outset
)
view.border(.yellow, set: stars)
```

### 4.4 The `.border` modifier(s)

Three overloads on `View`:

```swift
extension View {
  /// Most common — uniform style and set, all sides.
  public func border(
    _ style: some ShapeStyle = .foreground,
    set: BorderSet = .outerHalfBlock,
    sides: Edge.Set = .all
  ) -> some View

  /// Per-side coloring (lipgloss BorderForeground shorthand).
  public func border(
    _ style: BorderEdgeStyle,
    set: BorderSet = .outerHalfBlock,
    sides: Edge.Set = .all
  ) -> some View

  /// Perimeter gradient — wraps a 1D gradient continuously around all
  /// four sides. `phase` rotates the start point, for animation.
  public func border(
    blend stops: BorderBlend,
    set: BorderSet = .outerHalfBlock,
    sides: Edge.Set = .all,
    phase: Double = 0
  ) -> some View
}
```

`BorderEdgeStyle` is the per-side analogue of `BorderBackgroundStyle`,
but for foreground:

```swift
public struct BorderEdgeStyle: Sendable {
  public var top, right, bottom, left: AnyShapeStyle?

  // 1 / 2 / 3 / 4-color shorthand mirroring CSS:
  public init(_ all: some ShapeStyle)
  public init(topBottom: some ShapeStyle, leftRight: some ShapeStyle)
  public init(top: some ShapeStyle, leftRight: some ShapeStyle, bottom: some ShapeStyle)
  public init(top: some ShapeStyle, right: some ShapeStyle,
              bottom: some ShapeStyle, left: some ShapeStyle)
}
```

`BorderBlend` is the gradient type (see §4.6).

### 4.5 Shapes — minimal, extensible, mostly SwiftUI-ish

Keep `Shape` / `InsettableShape`. Extend with what's reachable in the cell
grid; reject what isn't.

**Built-ins to ship:**

```swift
public struct Rectangle: InsettableShape { … }
public struct RoundedRectangle: InsettableShape {
  public let cornerRadius: Int
  public init(cornerRadius: Int)
}
public struct Capsule: InsettableShape { … }       // pill, max corner radius
public struct Circle: InsettableShape { … }        // largest circle in rect
public struct Ellipse: InsettableShape { … }       // fits rect (warning: cell aspect)
```

`Capsule`/`Circle`/`Ellipse` are new. They render via Braille subpixel
glyphs (`⠀`–`⣿`, 2×4 pixels per cell) when stroked or filled, which gives
real curves at typical sizes. At sub-Braille resolutions (e.g. a 5×3


**Rejected from the SwiftUI list:**

- `UnevenRoundedRectangle` — corner radii of 1 cell each are nearly
  indistinguishable; not worth the API surface. Add later if asked.
- `Path` (general bezier) — replaced by `Canvas` (see §4.8) which is
  better adapted to the grid.
- `RoundedCornerStyle.continuous` — accepted as a parameter for source
  parity, treated as a synonym for `.circular`.

**`stroke` / `strokeBorder` semantics:**

```swift
extension Shape {
  func fill(_ style: some ShapeStyle) -> some View

  /// Draws a stroke that, for `lineWidth: 1`, sits on the perimeter of
  /// the shape. For `lineWidth: 2+`, the stroke extends `floor(width/2)`
  /// cells *outside* the shape's nominal bounds (i.e. the layout box is
  /// expanded). This matches SwiftUI's `stroke` semantically.
  func stroke(
    _ style: some ShapeStyle,
    style: StrokeStyle = .init(),
    background: BorderBackgroundStyle? = nil
  ) -> some View
}

extension InsettableShape {
  /// Insets `self` by `style.lineWidth`, then strokes. The stroke lies
  /// entirely inside the original bounds. This matches SwiftUI's
  /// `strokeBorder` semantics modulo the half-cell impossibility:
  /// for `lineWidth: 1` we inset by 0 (because there's no half cell),
  /// and the stroke is drawn on the outermost row/col.
  func strokeBorder(
    _ style: some ShapeStyle,
    style: StrokeStyle = .init(),
    background: BorderBackgroundStyle? = nil
  ) -> some View
}
```

Document the half-cell divergence in one place (the `StrokeStyle` doc
comment) and never again. Most users will reach for `.border(...)` — the
`stroke`/`strokeBorder` pair is the SwiftUI escape hatch for callers who
already know what they want.

### 4.6 `ShapeStyle` and gradients

Keep `ShapeStyle` as the universal painter protocol. Existing conformers
(`Color`, `SemanticShapeStyle`, `LinearGradient`, `AnyShapeStyle`) stay.
Add:

```swift
public struct LinearGradient: ShapeStyle, Sendable {
  public var stops: [Stop]
  public var startPoint: UnitPoint
  public var endPoint: UnitPoint

  public struct Stop: Sendable {
    public var location: Double   // 0…1, Textual-style
    public var color: Color
    public init(location: Double, color: Color)
  }

  // Convenience: even-spaced from a list of colors.
  public init(colors: [Color], from: UnitPoint = .leading, to: UnitPoint = .trailing)
}

public struct RadialGradient: ShapeStyle, Sendable {
  public var stops: [LinearGradient.Stop]
  public var center: UnitPoint
  public var startRadius: Double
  public var endRadius: Double
}

public struct PatternFill: ShapeStyle, Sendable {
  public var glyph: Character        // ░ ▒ ▓ ▪ · ⋯
  public var foreground: Color
  public var background: Color?

  public static let lightShade  = PatternFill(glyph: "░", foreground: .primary, background: nil)
  public static let mediumShade = PatternFill(glyph: "▒", foreground: .primary, background: nil)
  public static let heavyShade  = PatternFill(glyph: "▓", foreground: .primary, background: nil)
  public static let dots        = PatternFill(glyph: "·", foreground: .primary, background: nil)
}
```

Everything is sampled per-cell at rasterization time. Linear and radial
gradients use CIELAB blending (lipgloss's `Blend1D` ported to Swift —
single dependency on a tiny color-space helper). Stops are
`(location, color)` tuples so off-center stops express naturally:

```swift
LinearGradient(stops: [
  .init(location: 0.0, color: .red),
  .init(location: 0.1, color: .red),
  .init(location: 0.9, color: .blue),
  .init(location: 1.0, color: .blue)
], from: .leading, to: .trailing)
```

For perimeter gradients on borders specifically, `BorderBlend` is a 1D
gradient that the border modifier samples around the rectangle's
perimeter, not across the body:

```swift
public struct BorderBlend: Sendable {
  public var stops: [LinearGradient.Stop]
  public init(_ stops: LinearGradient.Stop...)
  public init(_ colors: [Color])
}
```

```swift
view.border(blend: BorderBlend([.red, .yellow, .blue, .red]),
            set: .rounded,
            phase: animationPhase)
```

`phase` is a 0…1 rotation around the perimeter. Driving it with the
existing animation pipeline gets you a chasing-light border for free.

> **Update (April 13, 2026 — Animatable-protocol migration).**
> `LinearGradient.startPoint` / `endPoint` and `RadialGradient.center`
> are now typed as `UnitPoint`, not `Alignment`. The original draft
> above, written before the migration, used `Alignment` for both
> roles because `Alignment` already exposed the named-corner
> constants (`.topLeading`, `.bottomTrailing`, etc.) the gradient
> endpoints want to read. Two reasons drove the type change:
>
> 1. `Alignment` is a *named-slot* type — it picks one of a discrete
>    set of layout positions and is consumed by the stack/grid
>    layout engines that map a name to a placement. There is no
>    coordinate arithmetic on it. `UnitPoint`, by contrast, is a
>    continuous unit-square coordinate (`x ∈ [0, 1]`, `y ∈ [0, 1]`)
>    with the same named constants exposed as static initializers.
>    Gradient endpoints need the *coordinates*, not the slot identity.
> 2. Animation requires linear interpolation between two endpoint
>    values. Interpolating between two named slots is meaningless;
>    interpolating between two `UnitPoint`s is the obvious componentwise
>    blend. Phase 0 of the migration added an `Animatable` conformance
>    on `UnitPoint`, and Phase 1 swapped the gradient property types
>    so the controller could see the diff.
>
> `Alignment` itself stays unchanged and remains the authoring type
> for stack/overlay/background alignment parameters (`VStack`, `HStack`,
> `ZStack`, `.frame(alignment:)`, etc.). The two types coexist; the
> rule is "named slot for layout, continuous coordinate for paint."
>
> See `docs/proposals/ANIMATABLE_PROTOCOL_MIGRATION.md` for the full
> migration plan and the rationale for the `Animatable`-protocol
> pipeline that consumes the new `UnitPoint` properties.

### 4.7 Layout integration: borders are part of the frame

The current rasterizer-side trick of "inset by 1 inside the frame" goes
away. Instead the border is a `LayoutBehavior` that, like `.padding`,
adds to the frame insets returned by the layout pass. Concretely, a new
`LayoutBehavior` case:

```swift
case border(BorderSet, foreground: BorderEdgeStyle?, background: BorderBackgroundStyle?, sides: Edge.Set)
```

At layout time we compute frame insets from the border set
(`top.displayWidth`, `bottom.displayWidth`, `left.displayWidth`,
`right.displayWidth`, masked by `sides`) and stack them onto the child's
proposal exactly the way `.padding` does. The rasterizer then has a
strict invariant: the border draws **into the inset rows/columns**, never
into the child's interior.

This is the lipgloss/Ratatui approach (`Block::inner(area) -> Rect`) and
it makes the "did my border eat my text" class of bug structurally
impossible. Today's `strokeBorder: Bool` flag in `ShapeOperation` becomes
dead and is removed; everything goes through the layout-aware path.

For inset placement (`.innerHalfBlock`, the legacy "border draws into
content" mode for users who know what they're doing), the layout
contribution is 0 and the rasterizer overlays glyphs on the outermost
row/col after the child has drawn. This stays available as an explicit
opt-in:

```swift
view.border(.foreground, set: .innerHalfBlock)  // explicitly inset
```

### 4.8 The `Canvas` escape hatch

For arbitrary drawing — circles at sub-Braille sizes, plots, sparklines,
ASCII art, hand-drawn glyphs — ship a `Canvas` view that exposes a
2×4-subpixel-per-cell drawing surface backed by Braille glyphs:

```swift
public struct Canvas<Drawing: CanvasDrawing>: View {
  public init(@CanvasBuilder drawing: () -> Drawing)
}

public protocol CanvasDrawing {
  func draw(into context: CanvasContext)
}

public struct CanvasContext {
  public var size: (width: Int, height: Int)   // in Braille subpixels
  public var foreground: Color
  public var background: Color?

  public mutating func setPixel(x: Int, y: Int, color: Color? = nil)
  public mutating func line(from: (Int, Int), to: (Int, Int), color: Color? = nil)
  public mutating func rect(_ rect: (x: Int, y: Int, w: Int, h: Int), color: Color? = nil)
  public mutating func circle(center: (Int, Int), radius: Int, color: Color? = nil)
  public mutating func text(_ string: String, at: (Int, Int))
}
```

This is the dispenser for "I want to draw a real curve." It consciously
sits *outside* the `Shape` protocol because anything inside `Shape` has
to play nicely with `fill`/`stroke`/`strokeBorder` and that algebra is
not worth the complexity for arbitrary drawings. Borrowed straight from
termui's canvas and Textual's `Canvas`.


Common case (a sparkline):

```swift
Canvas {
  Sparkline(values: cpuHistory)
}
.frame(width: 30, height: 4)
```

`Sparkline` here is a user-defined `CanvasDrawing` — the extensibility
seam.

### 4.9 Extensibility seams

The full list, summarized for reviewers:

1. **`BorderSet` is a public struct.** Anyone can define a custom border
   without touching the framework. Multi-rune edges give dashed/patterned
   borders for free.
2. **`BorderSet.Placement` is a public enum.** Custom sets can opt into
   `.outset` (the safe default), `.inset` (the legacy mode), or
   `.decorative` (half-block).
3. **`ShapeStyle` is a public protocol.** New paint kinds (animated
   shimmers, procedural patterns, theme-aware tints) drop in.
4. **`Shape` is a public protocol.** New geometry contributes via
   `ShapeGeometry` cases (we'd add `.circle`, `.ellipse`, `.capsule` and
   leave room for `.path([CanvasOp])` if anyone needs it).
5. **`CanvasDrawing` is a public protocol.** Plot types, charts, ASCII
   art generators all conform without depending on framework internals.


### 4.10 What this looks like at the call site

Today (CalculatorTab.swift, lines 40-56, abridged):

```swift
Rectangle().fill(Color.clear).overlay(alignment: .bottomTrailing) { … }
  .frame(height: 3)
  .border(.black)            // ← workaround: invisible-color border
  .padding(1)
```

Tomorrow:

```swift
Rectangle().fill(Color.clear).overlay(alignment: .bottomTrailing) { … }
  .frame(height: 3)
  .border()                  // ← outer half-block, doesn't eat content
```

A "card with a thick rounded border and a chasing rainbow":

```swift
VStack { … }
  .padding(.horizontal, 2)
  .border(blend: BorderBlend([.red, .yellow, .green, .cyan, .blue, .magenta, .red]),
          set: .rounded,
          phase: animationPhase)
```

A focus ring on a button:

```swift
Button("Save") { … }
  .border(focused ? .accent : .clear, set: .heavy)
```

Per-edge coloring for a status panel:

```swift
panel
  .border(BorderEdgeStyle(top: .green, leftRight: .secondary, bottom: .red))
```

A pattern fill instead of a solid:

```swift
Rectangle().fill(PatternFill.lightShade)
```

A real circle:

```swift
Circle()

  .frame(width: 10, height: 5)   // Braille pixels make it readable
```

A hand-drawn meter:

```swift
Canvas { meterDrawing(value: 0.42) }
  .frame(width: 20, height: 3)
```

## 5. The breaking change: outset borders by default

The single breaking call is changing `.border(...)` from inset to outset.
Today's behavior is "inset (overdraws content)"; the new default is
"outset (adds to frame)."

Why break it:

- The current default is the source of every "my text disappeared" bug
  in this surface. It's the loud reason for this revamp.
- The two existing call sites in the demo (`CounterTab.border(.separator)`
  and `CalculatorTab.border(.black)`) both want outset behavior — neither
  is relying on the inset semantics, they're just working around them.
- The mental model for new users is much cleaner: "a border lives around
  the box, not in it."



There is no automatic source-compat shim for "give me the old default."
Users get the new default; if they want the old one they ask for it.
The whole point is to make the easy path safe.

## 6. Appendix — research notes

Captured here so future maintainers don't have to redo the survey.

### 6.1 SwiftUI surface

- `Shape` protocol: `func path(in rect: CGRect) -> Path`. Conforms to
  `View` so a shape is a renderable thing on its own.
- `InsettableShape` adds `inset(by: CGFloat) -> Self.InsetShape`.
- `.fill(_:)`, `.stroke(_:lineWidth:)`, `.stroke(_:style:)`,
  `.strokeBorder(_:lineWidth:)`, `.strokeBorder(_:style:)`. The last two
  are only on `InsettableShape`.
- **Critical doc quote**: "strokeBorder is equivalent to insetting self
  by lineWidth/2 and stroking the resulting shape with lineWidth as the
  line-width." So `.stroke` = stroke centered on the perimeter (half
  spills outside); `.strokeBorder` = stroke entirely inside the bounds.
  In a cell grid this distinction collapses at `lineWidth: 1` and
  reappears at `lineWidth: 2`. We document this once.
- `View.border(_:width:)` is a `View` modifier (not a `Shape` modifier).
  In SwiftUI it's `self.overlay(Rectangle().stroke(content, lineWidth:
  width))` — note `stroke`, not `strokeBorder`. The border spills *outside*
  the content frame. We invert this default but keep the modifier name.
- `ShapeStyle` is the universal "thing you can paint with" protocol.
  `Color`, `LinearGradient`, `RadialGradient`, `AngularGradient`,
  `MeshGradient`, `Material`, `HierarchicalShapeStyle` (`.primary` …
  `.quinary`), and a dozen semantic singletons all conform.
  **Lift verbatim**: `fill`/`stroke`/`strokeBorder`/`.border` should all
  take `some ShapeStyle`, never just `Color`.

### 6.2 lipgloss / bubbletea

- `lipgloss.Border` is a flat struct of 13 strings: top/bottom/left/right
  edges, four corners (TL/TR/BL/BR), and middle joins (ML/MR/M/MT/MB)
  used by tables. Each field is a `string` so multi-rune graphemes fit;
  the renderer cycles through runes per cell on the four edges, giving
  free dashed borders. Corner colors inherit the adjacent horizontal
  edge — a known simplification that we *can* fix in the Swift port by
  rendering corners with their own color slot.
- Predefined sets (full glyph table): `NormalBorder` (single line),
  `RoundedBorder`, `ThickBorder` (heavy), `DoubleBorder`, `BlockBorder`,
  `OuterHalfBlockBorder`, `InnerHalfBlockBorder`, `HiddenBorder`,
  `MarkdownBorder`, `ASCIIBorder`. We mirror all of these and add
  `singleDouble`, `doubleSingle`, `dashed`, `dashedHeavy` from Ink/Ratatui.
- Frame math invariant: `Width(n)` is the **block width including border
  and padding**. Layout: `wrapAt = width - borderH - paddingH`. Border
  contributes `borderH = max(top widest rune width, bottom widest)` per
  axis. **Adopt verbatim** — this is the contract that prevents border
  bugs.
- `Style.BorderForeground(c ...color.Color)` shorthand: 1 / 2 / 3 / 4
  colors map T / TB+LR / T+LR+B / TRBL respectively, CSS-shorthand-style.
  Our `BorderEdgeStyle` initializers replicate this.
- **`Blend1D(steps int, stops ...color.Color)`** — CIELAB-blended linear
  gradient. **`Blend2D(width, height, angle float64, stops ...)`** — 2D
  gradient sampled from a 1D ramp along a rotated axis. Cheap, continuous
  in rotation. We port both.
- **`Style.BorderForegroundBlend(colors ...)`** — produces a 1D blend of
  length `(w+h+2)*2` and wraps it continuously around the perimeter.
  **`BorderForegroundBlendOffset(n)`** rotates the start point — that's
  how chasing-border animations work. We mirror as `view.border(blend:
  BorderBlend, phase: Double)`.
- lipgloss has **no `BackgroundBlend`** (no 2D body gradient via the
  Style API) and **no shape primitives at all** beyond rectangles. Both
  gaps we should fill. The half-block borders (`OuterHalfBlockBorder`,
  `InnerHalfBlockBorder`) are the only "rounded-ish" trick lipgloss
  ships, and they're really just glyph choices — there's no curve math.

### 6.3 Ratatui (Rust)

- `Borders::ALL` as bitflags: `Borders::TOP | Borders::BOTTOM | Borders::
  LEFT | Borders::RIGHT`. Composes better than per-side bools. We use
  `Edge.Set` (already exists in this repo) the same way.
- `BorderType` enum: `Plain, Rounded, Double, Thick,
  QuadrantInside, QuadrantOutside, LightDoubleDashed, LightTripleDashed,
  LightQuadrupleDashed, HeavyDoubleDashed, HeavyTripleDashed,
  HeavyQuadrupleDashed`. The dashed family uses `┄ ┅ ┆ ┇ ┈ ┉ ┊ ┋ ╌ ╍ ╎ ╏`
  glyphs. We collapse to two `dashed` / `dashedHeavy` sets in the
  defaults; users can author the dash density themselves via custom sets.
- `Block::inner(area: Rect) -> Rect` — pure function returning the
  content rectangle after subtracting borders+padding. **This is the
  cleanest layout integration.** We lift it as the contract for the new
  layout-aware border behavior.
- No gradients in core ratatui (third-party `tachyonfx` adds them).

### 6.4 Textual (Python)

- Borders set via CSS, per-side rules: `border-top: round red; border-
  bottom: heavy $accent`. Per-side independent style **and** color, which
  is richer than lipgloss's one-style-per-block model. We support per-
  side coloring via `BorderEdgeStyle` and per-side toggling via `Edge.
  Set`, but per-side *style mixing* (e.g. top=double, bottom=single) is
  out of scope for v1 — `BorderSet` is monolithic. If asked we add a
  `BorderSet.compose(top:right:bottom:left:)` factory.
- **`LinearGradient(angle, stops)`** where `stops: Sequence[tuple[float,
  Color]]`. Proper `(offset, color)` tuples. **Adopt this stop shape**
  — it's strictly more expressive than lipgloss's positional list.
- `background-tint: color 20%;` — translucent tint over whatever's
  underneath. Already covered by our existing `Color.opacity`.

### 6.5 Ink (JS/React)

- Per-side props: `borderStyle`, `borderColor`, `borderTopColor` /
  `borderRightColor` / `borderBottomColor` / `borderLeftColor`,
  `borderDimColor` (CSI 2 faint), `borderBackgroundColor` per-side.
  Per-side toggles `borderTop` / `borderRight` / `borderBottom` /
  `borderLeft`. The JS API is verbose but the data model maps cleanly
  to our `BorderEdgeStyle` + `Edge.Set`.
- `borderStyle` values come from `cli-boxes`: `single`, `double`, `round`,
  `bold`, `singleDouble`, `doubleSingle`, `classic`, `arrow`. The two
  hybrid styles are the interesting bit — single horizontals + double
  verticals (and vice versa). We ship both in defaults.
- Yoga/Flexbox layout means border lives **inside** the declared width
  (content-box-ish). Same as lipgloss. Same as our proposal.

### 6.6 termui / Textual `Canvas`

- 2×4 Braille subpixel grid per cell. `⠀` (U+2800) through `⣿` (U+28FF).
  Each cell holds 8 dots, addressable as a bitmask. This is the standard
  TUI escape hatch for "draw a real curve." termui exposes a `Canvas`
  primitive built on it; Textual has `Canvas` and `LineDraw`.
- We ship a `Canvas` view as `Shape`'s sibling for arbitrary drawing.
  Shapes stay axis-aligned + analytic (rect / rounded rect / circle /
  ellipse / capsule); Canvas is the dispenser for everything else.

## 7. Open questions

Things I'd want to nail down before implementing:

1. **Default border color.** SwiftUI uses the parent's foreground style.
   This repo has `SemanticShapeStyle` (`.foreground`, `.separator`,
   `.accent`). Best default is `.foreground` so a card on a dark
   background gets a light border and vice versa. Need to confirm
   `.foreground` resolves correctly through theming.
2. **Half-block frame contribution.** `.outerHalfBlock` reads as half a
   row but the cell grid still consumes a full row. Do we contribute 1
   row or 0 rows to the layout? Proposal: 1 row (predictable layout) but
   document that the visual weight is half.
3. **Animation phase plumbing.** `border(blend:phase:)` needs an
   `AnimatableData` conformance so `withAnimation` drives `phase`. The
   existing animation pipeline (per `project_animation_design.md`)
   should already cover this — needs a quick check.
4. **Tables.** lipgloss's middle-join glyphs (`├ ┤ ┼ ┬ ┴`) exist for
   tables. This repo doesn't have a `Table` view yet; we keep the join
   slots in `BorderSet` for forward compatibility but the rasterizer
   ignores them in v1.
5. **Width-2 graphemes in border edges.** lipgloss handles CJK / emoji
   borders via `widest rune width`. Our `BorderSet` should compute
   `top.displayWidth` (and friends) using the same wcwidth-aware logic
   already used by `Text` rendering. Pull from there, don't re-derive.
6. **Custom shape rasterization.** New `Shape` types added by consumers
   would need to either return a `ShapeGeometry` case the rasterizer
   knows about, or render via `Canvas`. The clean version is to make
   `Shape.path(in:) -> [CellOp]` (analogous to SwiftUI's `Path`) the
   primitive, and have all built-ins go through it. This is a v2 concern;
   v1 keeps the closed `ShapeGeometry` enum and the user extension story
   is "use `Canvas`."

## 8. Out of scope (deferred)

- Angular gradients, mesh gradients (huge fidelity loss in cells).
- True bezier `Path` API (replaced by `Canvas`).
- `UnevenRoundedRectangle` (low value at cell resolution).
- Per-side `BorderSet` mixing (e.g. top=double, bottom=single).
- Per-corner foreground colors (lipgloss can't either; not blocking).
- Border *background* gradients (lipgloss doesn't have this; we can ship
  it later via `BorderBackgroundStyle` accepting `LinearGradient`).
- `Material` / blur. Not meaningful in cells.
- Antialiasing. Always a no-op; we accept an `antialiased:` parameter on
  `stroke` for SwiftUI source parity and ignore the value.

## 9. TL;DR

- New `.border(_:set:sides:)` modifier. Default set is `.outerHalfBlock`,
  default placement is **outset** (border lives around the box, doesn't
  eat text), default style is `.foreground`.
- `BorderSet` is a public struct of 13 strings (lipgloss's shape) with a
  `Placement` axis. ~15 built-ins shipped; trivial to define your own.
  Multi-rune edges = free dashed borders.
- `BorderEdgeStyle` for per-side foreground colors; `BorderBackgroundStyle`
  (existing) for per-side backgrounds.
- `BorderBlend` + `view.border(blend:phase:)` for perimeter gradients
  including chasing-light animation.
- `Shape` keeps SwiftUI's protocol shape. Built-ins gain `Circle`,
  `Ellipse`, `Capsule`. `stroke` vs `strokeBorder` semantics preserved
  with one documented half-cell divergence at `lineWidth: 1`.
- `LinearGradient`/`RadialGradient` with Textual-style `(location, color)`
  stops, CIELAB blending. `PatternFill` for `░ ▒ ▓` shading.
- `Canvas` view for arbitrary drawing via 2×4 Braille subpixels.
- Border layout integrates as a `LayoutBehavior`, exactly like padding.
  Inset placement remains available as opt-in for callers who know what
  they want.
- One breaking change: the default `.border(...)` flips from inset to
  outset. This is the change that makes the easy path safe.
