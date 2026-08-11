# ``SwiftTUICore``

Pure frame-pipeline types and algorithms for SwiftTUI.

## Overview

The `SwiftTUICore` module owns the parts of the system that remain independent
from terminal I/O:

- geometry and proposal types
- layout and placement infrastructure
- semantic extraction
- draw extraction
- rasterization
- commit planning
- frame diagnostics and snapshot support

If `SwiftTUIViews` is the authoring layer and `SwiftTUIRuntime` is the runtime
layer, `SwiftTUICore` is the engine in between them. Its intermediate phase IR is
package-only. Public callers usually reach committed output through
`SwiftTUIRuntime.RenderSnapshot`, ``RasterSurface``, ``SemanticSnapshot``, and
diagnostics types.

Geometry, pointer metadata, color, and draw payload vocabulary (`CellPoint`,
`Point`, `Rect`, `Path`, `Color`, `CellPixelMetrics`, `PointerLocation`, and the
rest) is *not* declared here. It lives one layer down in `SwiftTUIPrimitives`
and reaches you through `@_exported import`, so `import SwiftTUICore` puts it in
scope. See the `SwiftTUIPrimitives` reference for those types. Reconciliation
vocabulary such as `PreferenceKey`, `FocusedValues`, and
`MatchedGeometryNamespace` comes from `SwiftTUIGraph` the same way.

## Design Boundary

`SwiftTUICore` must not communicate with the terminal directly.

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
- ``SemanticSnapshot``
- ``RasterSurface``

### Guides

- <doc:Rendering-Pipeline>
