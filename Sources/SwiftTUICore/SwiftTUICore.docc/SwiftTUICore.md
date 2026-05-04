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

If `SwiftTUIViews` is the authoring layer and `SwiftTUI` is the runtime layer, `SwiftTUICore` is the engine in between them.

## Design Boundary

`SwiftTUICore` should not talk to the terminal directly.

That means this module can be reused for:

- snapshot rendering
- tests that inspect resolved, measured, placed, semantic, draw, or raster products
- alternate presentation experiments that still consume the same frame artifacts

## Topics

### Pipeline Products

- ``FrameArtifacts``
- ``FrameContext``
- ``CommitPlan``
- ``FrameDiagnostics``

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

### Execution Components

- ``LayoutEngine``
- ``SemanticExtractor``
- ``DrawExtractor``
- ``Rasterizer``
- ``CommitPlanner``

### Guides

- <doc:Rendering-Pipeline>
