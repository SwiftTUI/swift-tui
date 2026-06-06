# Shapes

Fill, stroke, and inset terminal shapes — the built-in primitives and custom
``SwiftTUICore/Path``-based shapes — rasterized to Braille subpixels.

## Overview

Conform to ``Shape`` by implementing **either** ``path(in:)`` (SwiftUI-style —
return the outline for the proposed rect) **or** ``geometry`` (one of the
analytic primitive cases). The two are bridged automatically, so a custom shape
usually implements only `path(in:)`. SwiftTUI ships the primitives
``Rectangle``, ``RoundedRectangle``, ``Circle``, ``Ellipse``, and ``Capsule``;
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

`fill`, `stroke`, and `strokeBorder` each come in two families: one taking an
explicit ``SwiftTUICore/ShapeStyle`` and one with no style that resolves through
the inherited `foregroundStyle` (and ultimately a semantic role) — the same way
a bare `Circle()` fills with the foreground. `strokeBorder` is available on
``InsettableShape`` only, because it insets before stroking so the ring stays
inside the frame.

## Custom paths

Build a ``SwiftTUICore/Path`` from lines and Bézier curves (`move(to:)`,
`addLine(to:)`, `addQuadCurve(to:control:)`, `addCurve(to:control1:control2:)`,
`closeSubpath()`) or the shape constructors (`Path(_: Rect)`,
`Path(roundedRect:cornerRadius:)`, `Path(ellipseIn:)`). Curves are flattened to
polylines and filled with a winding rule (``SwiftTUICore/FillRule`` — `.nonZero`
by default, `.evenOdd` available). A custom shape composes with the full
modifier algebra (`fill` / `stroke` / `strokeBorder` / `foregroundStyle` /
`inset(by:)`), and a custom-path `strokeBorder` clips a background to the shape's
interior the same way a rounded-rectangle border does.

Two properties to keep in mind, both consequences of the cell grid:

- **Frame-relative, not aspect-corrected.** `path(in:)` is evaluated once
  against the unit rect at resolve and the normalized path is scaled into the
  placed frame at raster. A custom shape therefore *stretches to fill its
  frame* — unlike ``Circle``, which stays round by inscribing the short axis.
  Draw the proportions you want relative to the proposed rect.
- **Sub-cell-quantized, not analytic-bit-exact.** Custom paths rasterize to the
  2×4 Braille subpixel grid with one foreground color per cell. The five
  primitives carry exact, fixture-pinned output; arbitrary paths do not — their
  edges are quantized to subpixels and cannot blend color across a cell.

## Differences from SwiftUI

SwiftTUI shapes target a cell grid rasterized to Braille subpixels, not a
resolution-independent vector canvas. Some of SwiftUI's `Shape` API is therefore
**deliberately absent, not missing**:

- **No `trim(from:to:)`, `offset`, `rotation`, `scale`, or `transform`.** These
  are path/vector transforms with no faithful meaning over discrete cells.
- **No `lineWidth:` stroke overloads.** Terminal strokes are one cell wide;
  ``SwiftTUICore/StrokeStyle`` carries `lineWidth` only as a reserved field.
  Stroke weight is expressed through the glyph palette (`borderSet`: `.single`,
  `.heavy`, `.double`, …) instead.
- **No `addArc` (yet).** Arc construction needs an angle type; it is a planned
  follow-on. Use `addQuadCurve`/`addCurve`, or `Path(ellipseIn:)`.
- **No general `clipShape(_:)` to an arbitrary path.** Masking is available at
  the border level (a custom-path `strokeBorder` clips its background to the
  interior); a general path clip is a planned follow-on.
- **No animatable path morphing.** Parameterized shapes animate via their own
  animatable parameters, not by interpolating dissimilar paths.

## Topics

### Shape types

- ``Shape``
- ``InsettableShape``
- ``Rectangle``
- ``RoundedRectangle``
- ``Circle``
- ``Ellipse``
- ``Capsule``

### Custom paths

- ``SwiftTUICore/Path``
- ``SwiftTUICore/FillRule``

## See Also

- <doc:AspectCorrectShapes>
