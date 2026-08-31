# ``SwiftTUIPrimitives``

The leaf vocabulary every other SwiftTUI layer speaks: inert value types for
geometry, color and style, draw payloads, and animation math.

## Overview

> Note: Apps use these types constantly — ``CellSize``, ``Alignment``,
> ``Animatable`` — but never import this module directly; the vocabulary
> arrives through `import SwiftTUI` or any other authoring product. Start
> from the
> [`SwiftTUI` module](https://swifttui.sh/docs/documentation/swifttui) unless
> you are working on the framework itself.

`SwiftTUIPrimitives` is the bottom of the module stack. It holds **values, not
engines**. It contains no reconciliation, render algorithms, or terminal I/O.
It builds independently and is Foundation-free.

```
SwiftTUIPrimitives -> SwiftTUIGraph -> SwiftTUICore -> SwiftTUIViews -> SwiftTUIRuntime
```

You rarely import this module directly. Every layer above it
`@_exported`-imports it, so `import SwiftTUIViews` (or `SwiftTUI`) already puts
`Point`, `Rect`, `Color`, `Path`, and the rest in scope. This reference
documents those types because they are part of the published public surface.
They appear in the signatures of shape, canvas, pointer, and styling APIs that
you use.

## Design Boundary

A type belongs here when it is inert and universally useful:

- it carries data, not behavior that depends on a graph or a frame
- it names no type from a higher layer
- it can be constructed and compared in a test with no runtime standing up

That boundary is compiler-enforced. `SwiftTUIGraph` depends on
`SwiftTUIPrimitives` **only**. Thus, graph code cannot name a render type, and
primitives code cannot name a view type.

## Topics

### Cell And Continuous Geometry

SwiftTUI measures layout in integer cells. Pointer and canvas APIs carry continuous
cell-space values.

- ``CellPoint``
- ``CellSize``
- ``CellRect``
- ``Point``
- ``Size``
- ``Rect``
- ``Vector``
- ``Path``
- ``FillRule``

### Pixel Metrics

- ``PixelPoint``
- ``PixelSize``
- ``CellPixelMetrics``

### Layout Vocabulary

- ``Alignment``
- ``HorizontalAlignment``
- ``VerticalAlignment``
- ``Axis``
- ``Edge``
- ``EdgeInsets``
- ``Spacing``
- ``ProposedSize``
- ``ProposedDimension``
- ``ViewDimensions``
- ``UnitPoint``
- ``UnitRect``
- ``UnitSize``

### Pointer Metadata

- ``PointerLocation``
- ``PointerInputCapabilities``
- ``HoverPhase``
- ``PointerPrecision``

### Coordinate Spaces

- ``NamedCoordinateSpace``

### Color And Style

- ``Color``
- ``ShapeStyle``
- ``AnyShapeStyle``
- ``SemanticStyleRole``
- ``Gradient``
- ``LinearGradient``
- ``RadialGradient``
- ``MeshGradient``
- ``StrokeStyle``
- ``BorderSet``
- ``BorderBlend``
- ``TextStyle``
- ``BlendMode``
- ``Theme``

### Canvas And Draw Payloads

- ``CanvasDrawing``
- ``CanvasContext``
- ``CanvasGrid``
- ``CanvasCell``
- ``BrailleCanvas``
- ``GridSample``

### Animation Math

- ``Animatable``
- ``VectorArithmetic``
- ``AnimatablePair``
- ``AnimatableArray``
- ``EmptyAnimatableData``

### Frame Pipeline Metadata

- ``FrameDropBlocker``
- ``MonotonicInstant``
