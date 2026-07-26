# ``SwiftTUIPrimitives``

The leaf vocabulary every other SwiftTUI layer speaks: inert value types for
geometry, color and style, draw payloads, and animation math.

## Overview

`SwiftTUIPrimitives` is the bottom of the module stack. It holds **values, not
engines** — no reconciliation, no render algorithms, no terminal I/O. It builds
standalone and is Foundation-free.

```
SwiftTUIPrimitives -> SwiftTUIGraph -> SwiftTUICore -> SwiftTUIViews -> SwiftTUIRuntime
```

You rarely import this module directly. Every layer above it
`@_exported`-imports it, so `import SwiftTUIViews` (or `SwiftTUI`) already puts
`Point`, `Rect`, `Color`, `Path`, and the rest in scope. This reference exists
because those types are part of the published public surface: they appear in
the signatures of shape, canvas, pointer, and styling APIs you author against.

## Design Boundary

A type belongs here when it is inert and universally useful:

- it carries data, not behavior that depends on a graph or a frame
- it names no type from a higher layer
- it can be constructed and compared in a test with no runtime standing up

That boundary is compiler-enforced. `SwiftTUIGraph` depends on
`SwiftTUIPrimitives` **only**, so graph code cannot name a render type — and
primitives code cannot name a view type.

## Topics

### Cell And Continuous Geometry

Layout is measured in integer cells; pointer and canvas APIs carry continuous
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
