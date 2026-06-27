# ``SwiftTUICore``

Pure frame-pipeline types and algorithms for SwiftTUI.

## Overview

The `SwiftTUICore` module owns the parts of the system that should stay independent from terminal I/O:

- geometry and proposal types
- layout and placement infrastructure
- semantic extraction
- draw extraction
- rasterization
- commit planning
- frame diagnostics and snapshot support

If `SwiftTUIViews` is the authoring layer and `SwiftTUIRuntime` is the runtime
layer, `SwiftTUICore` is the engine in between them. Its intermediate phase IR is
package-only; public callers usually reach committed output through
`SwiftTUIRuntime.RenderSnapshot`, ``RasterSurface``, ``SemanticSnapshot``, and
diagnostics types.

## Design Boundary

`SwiftTUICore` should not talk to the terminal directly.

That means this module can be reused for:

- snapshot rendering
- package tests that inspect resolved, measured, placed, semantic, draw, or
  raster products
- alternate presentation experiments that still consume committed public
  snapshot or host contracts

## Topics

### Public Pipeline Contracts

- ``FrameContext``
- ``FrameDiagnostics``
- ``FrameDropBlocker``
- ``SemanticSnapshot``
- ``RasterSurface``

### Geometry And Pointer Metadata

- ``CellPoint``
- ``CellSize``
- ``CellRect``
- ``Point``
- ``Size``
- ``Rect``
- ``Vector``
- ``Path``
- ``PixelPoint``
- ``PixelSize``
- ``CellPixelMetrics``
- ``PointerLocation``
- ``PointerInputCapabilities``

### Guides

- <doc:Rendering-Pipeline>
