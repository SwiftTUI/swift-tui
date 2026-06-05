# Shapes

Fill, stroke, and inset terminal shapes with a SwiftUI-shaped API, rasterized
to Braille subpixels.

## Overview

A shape conforms to ``Shape`` by describing its geometry — the single
author-facing requirement, mirroring SwiftUI's `path(in:)`. SwiftTUI ships
``Rectangle``, ``RoundedRectangle``, ``Circle``, ``Ellipse``, and ``Capsule``.
``Circle``, ``Ellipse``, and ``Capsule`` are aspect-corrected so they read true
on any terminal cell ratio (see <doc:AspectCorrectShapes>).

Shapes render through fill and stroke operations:

```swift
Circle().fill(.tint)                       // explicit style
Circle().fill()                            // inherited foreground
Rectangle().stroke(.separator, style: .heavy)
RoundedRectangle(cornerRadius: 1)
  .inset(by: 1)
  .strokeBorder()                          // inherited foreground, inset ring
```

`fill`, `stroke`, and `strokeBorder` each come in two families: one that takes
an explicit ``SwiftTUICore/ShapeStyle`` and one with no style that resolves
through the inherited `foregroundStyle` (and ultimately a semantic role) — the
same way a bare `Circle()` fills with the foreground. `strokeBorder` is
available on ``InsettableShape`` only, because it insets the geometry before
stroking so the ring stays inside the frame.

## Differences from SwiftUI

SwiftTUI shapes target a cell grid rasterized to Braille subpixels, not a
resolution-independent vector canvas. Some of SwiftUI's `Shape` API is
therefore **deliberately absent, not missing**:

- **No `path(in:)`.** Shapes are described by the
  ``SwiftTUICore/ShapeGeometry`` enum, which the rasterizer maps to subpixels
  with terminal-aware aspect correction. There is no free-form `Path`, and so
  no custom-path shapes.
- **No `trim(from:to:)`, `offset`, `rotation`, `scale`, or `transform`.** These
  are path/vector transforms with no faithful meaning over discrete cells,
  where partial glyphs and sub-cell rotation cannot be represented.
- **No `lineWidth:` stroke overloads.** Terminal strokes are one cell wide;
  ``SwiftTUICore/StrokeStyle`` carries `lineWidth` only as a reserved field
  (always 1). Stroke weight is expressed through the glyph palette
  (`borderSet`: `.single`, `.heavy`, `.double`, …) instead.
- **No `FillStyle`.** Even-odd winding rules and antialiasing are vector
  concepts; cell fills are exact.

What SwiftTUI keeps from SwiftUI: ``Shape`` / ``InsettableShape``, the `fill` /
`stroke` / `strokeBorder` modifier families (including the foreground-defaulting
forms), and `inset(by:)` (in whole cells).

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
