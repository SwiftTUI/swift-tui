# Shapes

Fill, stroke, clip, and animate terminal shapes, from built-in primitives to
custom paths and arcs, rasterized to Braille subpixels.

## Overview

Conform to ``Shape`` by implementing **either** ``Shape/path(in:)`` (SwiftUI-style:
return the outline for the proposed rect) **or** ``Shape/geometry`` (one of the
analytic primitive cases). The two are bridged automatically, so a custom shape
usually implements only `path(in:)`. SwiftTUI ships the primitives
``Rectangle``, ``RoundedRectangle``, ``Circle``, ``Ellipse``, and ``Capsule``.
``Circle``, ``Ellipse``, and ``Capsule`` are aspect-corrected so they read true
on any terminal cell ratio (see <doc:AspectCorrectShapes>).

```swift
struct Triangle: Shape {
  func path(in rect: Rect) -> Path {
    Path { path in
      path.move(to: Point(x: rect.origin.x + rect.size.width / 2, y: rect.origin.y))
      path.addLine(to: Point(x: rect.maxX, y: rect.maxY))
      path.addLine(to: Point(x: rect.origin.x, y: rect.maxY))
      path.closeSubpath()
    }
  }
}

Triangle().fill(.tint)                       // custom shapes compose like built-ins
Triangle().stroke(.separator, style: .heavy)
Circle().fill()                              // inherited foreground
RoundedRectangle(cornerRadius: 1)
  .inset(by: 1)
  .strokeBorder()                            // inset ring, inherited foreground
```

`fill`, `stroke`, and `strokeBorder` each come in two families. One family takes
an explicit `ShapeStyle`. The other has no style and resolves through the
inherited `foregroundStyle` (and ultimately a semantic role). A bare `Circle()`
also fills with the foreground. `strokeBorder` is available on
``InsettableShape`` only, because it insets before stroking so the ring stays
inside the frame.

## Custom paths

Build a `Path` from lines and Bézier curves (`move(to:)`,
`addLine(to:)`, `addQuadCurve(to:control:)`, `addCurve(to:control1:control2:)`,
`closeSubpath()`) or the shape constructors (`Path(_: Rect)`,
`Path(roundedRect:cornerRadius:)`, `Path(ellipseIn:)`). Curves are flattened to
polylines and filled with a winding rule (`FillRule`: `.nonZero`
by default, `.evenOdd` available). A custom shape composes with the full
modifier algebra (`fill` / `stroke` / `strokeBorder` / `foregroundStyle` /
`inset(by:)`). A custom-path `strokeBorder` clips a background to the shape's
interior the same way a rounded-rectangle border does.

Two properties to keep in mind, both consequences of the cell grid:

- **Frame-relative, not aspect-corrected.** `path(in:)` is evaluated once
  against the unit rect at resolve and the normalized path is scaled into the
  placed frame at raster. A custom shape therefore *stretches to fill its
  frame*, unlike ``Circle``, which stays round by inscribing the short axis.
  Draw the proportions you want relative to the proposed rect.
- **Sub-cell-quantized, not analytic-bit-exact.** Custom paths rasterize to the
  2×4 Braille subpixel grid with one foreground color per cell. The five
  primitives carry exact, fixture-pinned output. Arbitrary paths do not. Their
  edges are quantized to subpixels and cannot blend color across a cell.

## Draw arcs with angles

`Angle` supplies `.degrees(_:)` and `.radians(_:)`, and
`Path.addArc(center:radius:startAngle:endAngle:clockwise:)` adds a circular arc:

```swift
struct Sector: Shape {
  func path(in rect: Rect) -> Path {
    let center = Point(
      x: rect.origin.x + rect.size.width / 2,
      y: rect.origin.y + rect.size.height / 2
    )
    return Path { path in
      path.move(to: center)
      path.addArc(
        center: center,
        radius: min(rect.size.width, rect.size.height) / 2,
        startAngle: .degrees(0),
        endAngle: .degrees(120),
        clockwise: false
      )
      path.closeSubpath()
    }
  }
}

Sector().fill(Color.cyan).frame(width: 20, height: 10)
```

Zero points along positive x, and positive angles point toward positive y.
`clockwise: true` decreases the angle; because terminal y increases downward,
this looks counterclockwise on screen. Arcs use cubic segments of at most 90
degrees. An empty path moves to the arc's start; an existing subpath connects
to it with a line. Equal endpoints add nothing, while an authored difference
of at least one turn draws a full circle without closing it. Nonpositive radii
and nonfinite inputs leave the path unchanged.

## Clip a subtree

`clipShape(_:)` clips the view and its descendants to a
built-in or custom shape in the view's placed frame:

```swift
Text("A clipped card")
  .frame(width: 24, height: 7)
  .background(Color.blue)
  .clipShape(RoundedRectangle(cornerRadius: 2))
```

The mask samples coverage at cell centers. A wide glyph appears only when its
entire cell span is covered, and nested clips intersect. This is a drawing
operation: it does not change layout or hit testing. Apply `contentShape(_:)`
separately when interaction should follow a shape. Image content uses the same
clip coverage across terminal, browser, and native hosts.

## Animate compatible paths

`Path` conforms to `Animatable`. Paths can interpolate when their
ordered element kinds match: move with move, line with line, quadratic with
quadratic, cubic with cubic, and close with close. Anchor and control points
must be finite. Keep this topology stable while changing coordinates in an
animated state update, and the runtime can morph the custom shape.

For explicit sampling, check `start.isInterpolable(to: end)` and use
`start.interpolated(to: end, progress: fraction)`. Progress is clamped to
`0...1`; incompatible topology or nonfinite progress snaps to the destination.
Adding a segment or changing a line into a curve is not a morph. In particular,
changing an arc's sweep can change its cubic segment count. Use stable segments
or a cross-fade when the outlines have different structures.

## Dash And Join A Stroke

`StrokeStyle` carries SwiftUI's `dash`, `dashPhase` and `lineJoin`. A border, a
rectangle stroke and a `Divider` draw through one renderer, so the same style
draws the same cells on all three.

```swift
Rectangle().stroke(style: StrokeStyle(borderSet: .single, dash: [2, 1]))
//  ┌─ ── ──╷
//  ╵       ╵
//  │       │
//  ╶─ ── ──
```

Dash lengths are measured along the outline in cell widths. A cell is about
twice as tall as it is wide, so a vertical cell counts as about two units and a
dash is the same physical length on every edge: the `╷` over `╵` above is one
dash, as long as `──`. A dash end that falls inside a cell draws a half-line
(`╴╶╵╷`). The double palette has no half-line glyphs, so it dashes in whole
cells. The cells of an unpainted segment are left as they were. Put a fill or a
`background` under the stroke to paint them.

The pattern runs clockwise. A `Rectangle` and a view's `border` measure it from
the top-leading corner, and a `RoundedRectangle` from the middle of its trailing
edge, as SwiftUI does. `dashPhase` animates; see <doc:Animating-Views>.

`lineJoin: .round` draws the arc corners (`╭╮╰╯`) where the glyph palette has
them, which in Unicode is the light weight only. A `RoundedRectangle` draws them
with either join. The size of its `cornerRadius` has no other effect: a cell
grid has one size of rounded corner.

Curved shapes and custom paths dash too, in Braille dots, and in the same unit:
`dash: [2, 2]` is the same length on a `Circle` as on a `Rectangle`. They have no
line glyphs to choose, so the stroke style's `borderSet` and `lineJoin` have no
effect on them.

## Join Lines That Share A Cell

A cell holds one glyph. Where two line strokes reach the same cell, SwiftTUI
draws the glyph that shows both, so a `Divider` joins the border it runs into:

```swift
VStack(alignment: .leading, spacing: 0) {
  Text(" title")
  Divider()
  Text(" body")
}
.padding(.vertical, 1)
.border(.foreground)
//  ┌───────┐
//  │title  │
//  ├───────┤
//  │body   │
//  └───────┘
```

Borders, rectangle strokes and dividers all join, in any order. Two lines that
cross draw `┼`. The junction takes the color of the stroke drawn last, because a
cell has one foreground.

The end of a `Divider` is drawn to the edge of its cell, so that a lone divider
is `─` from end to end. That cap gives way to a line that crosses it, which is
why the divider above ends in `├` and not `┼`. It is also how borders on single
sides meet in a corner, and that is the way to color the sides of a border
differently:

```swift
content
  .border(.red, sides: .top)
  .border(.blue, sides: .leading)
//  ┌────     the corner is blue, as the leading border is drawn last
//  │
```

Light joins heavy, and light joins double where each axis keeps one weight
(`╟`). Unicode has no glyph for the other mixes, such as heavy with double. Every
arm in the cell then takes the weight of the stroke drawn last. The `.ascii`
palette joins in its own glyphs: `-` and `|` make `+`.

Only strokes join. `Text` that contains box-drawing characters is text, and a
stroke that reaches it draws over it. The half-block palettes draw against a
side of the cell and not through its middle, so they do not join. Braille
strokes on curved shapes do not join. Lines in neighboring cells do not join:
two bordered views side by side are `┐┌`, not `┬`.

## Trim A Shape

`trim(from:to:)` keeps the part of a shape's outline between two fractions of
its length. It is how a progress ring and a line that draws itself on are built:

```swift
Circle()
  .trim(from: 0, to: progress)
  .stroke(.tint)
```

The outline starts where SwiftUI starts it and runs clockwise. A `Rectangle`
starts at its top-leading corner. A `RoundedRectangle`, a `Circle`, an `Ellipse`
and a `Capsule` start at the middle of their trailing edge and go down first. A
custom path starts where you authored it to. A fraction is a share of the
outline's length on screen, so a quarter of a rectangle is a quarter of the way
round it, whatever its proportions in cells.

```swift
Rectangle().trim(from: 0, to: 0.25).stroke(style: .single)   // 9 x 4
//  ╶──────╴
```

On a line glyph palette, a trim end that falls inside a cell draws a half-line,
as a dash end does. A dash on a trimmed stroke is measured from the start of the
trimmed part. The interval animates on a stroke; see <doc:Animating-Views>.

A fill of a trimmed shape closes the trimmed outline with a straight line and
fills it, as SwiftUI does. It takes the custom-path route, so it stretches to its
frame: a trimmed `Circle` fill is not aspect-corrected the way a `Circle` fill
is, and its interval does not animate smoothly.

## Differences from SwiftUI

SwiftTUI shapes target a cell grid rasterized to Braille subpixels, not a
resolution-independent vector canvas. Some of SwiftUI's `Shape` API is therefore
**deliberately absent, not missing**:

- **No SwiftUI-style shape transform modifiers.** Shape `rotation`, `scale`,
  `offset` and `transform` modifiers are absent. `trim(from:to:)` exists. To author a path
  in a different coordinate space, use `Path.scaledBy(sx:sy:)` and
  `Path.translatedBy(dx:dy:)`. View-level `.offset` moves the placed result.
- **No `lineWidth:` stroke overloads.** Terminal strokes are one cell wide.
  `StrokeStyle` carries `lineWidth` only as a reserved field.
  Stroke weight is expressed through the glyph palette (`borderSet`: `.single`,
  `.heavy`, `.double`, …) instead. A thick solid band is a fill: fill the shape,
  then fill `inset(by:)` over it.
- **`lineJoin` has two cases.** `.miter` and `.round`. No glyph draws a bevel.
- **Clipping uses cell coverage.** It is not a pixel-antialiased mask and does
  not alter interaction regions.
- **Path morphing needs compatible topology.** Dissimilar paths snap rather
  than inventing a correspondence between unrelated segments.

## Topics

### Shape types

- ``Shape``
- ``InsettableShape``
- ``Rectangle``
- ``RoundedRectangle``
- ``Circle``
- ``Ellipse``
- ``Capsule``

## See Also

- <doc:AspectCorrectShapes>
- <doc:Animating-Views>
