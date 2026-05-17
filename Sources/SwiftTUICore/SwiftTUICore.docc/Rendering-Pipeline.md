# Rendering Pipeline

## Overview

Every frame in SwiftTUI moves through the same ordered phases:

```text
resolve -> measure -> place -> semantics -> draw -> raster -> commit
```

`SwiftTUICore` owns every phase after authored views have already been lowered
from `SwiftTUIViews` and before `SwiftTUIRuntime` presents the result to a
terminal or host product.

## Phase Roles

### Resolve

Produces `ResolvedNode` trees with merged environment and view metadata.

### Measure

Calculates subtree sizes under proposals through `LayoutEngine`.

### Place

Turns measured trees into final integer-cell geometry, which becomes the
authoritative source for interaction regions and content bounds.

### Semantics

Extracts focus, interaction, action, selection, scroll, named coordinate-space,
and pointer routing into `SemanticSnapshot`.

### Draw

Lowers geometry plus metadata into draw commands and collection chrome.

### Raster

Converts draw commands into `RasterSurface`, a cell grid with styles and continuation-cell handling.

### Commit

Packages lifecycle and handler-installation work into `CommitPlan`.

## Why The Split Matters

Keeping the phases explicit means layout and semantics do not need terminal escape-sequence knowledge, and runtime presentation can evolve without rewriting layout.

Layout products are integer-cell based. Pointer and Canvas APIs can still carry
continuous ``Point`` values because the runtime normalizes pointer input after
semantic routing and Canvas packs continuous cell-space samples during raster.

Later phases may carry named snapshots of earlier data, but those snapshots are
not independent owners. `PlacedNodeResolvedMetadata` names the resolved metadata
mirrored into placed nodes, `SemanticSnapshot` is a derived routing product,
`DrawNode` is a placed-to-paint projection, and `RasterSurface` owns only the
final cell grid plus raster attachments. Retained layout reuse must pair any
relaxed equivalence predicate with a refresh path before downstream phases read
the reused product.

## Related Symbols

- ``FrameArtifacts``
- ``FrameDiagnostics``
- ``CommitPlan``
