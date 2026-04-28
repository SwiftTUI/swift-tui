# Rendering Pipeline

## Overview

Every frame in TerminalUI moves through the same ordered phases:

```text
resolve -> measure -> place -> semantics -> draw -> raster -> commit
```

`Core` owns every phase after authored views have already been declared and before the runtime has presented the result to a terminal.

## Phase Roles

### Resolve

Produces `ResolvedNode` trees with merged environment and view metadata.

### Measure

Calculates subtree sizes under proposals through `LayoutEngine`.

### Place

Turns measured trees into final geometry, which becomes the authoritative source for interaction regions and content bounds.

### Semantics

Extracts focus, interaction, action, selection, and scroll routing into `SemanticSnapshot`.

### Draw

Lowers geometry plus metadata into draw commands and collection chrome.

### Raster

Converts draw commands into `RasterSurface`, a cell grid with styles and continuation-cell handling.

### Commit

Packages lifecycle and handler-installation work into `CommitPlan`.

## Why The Split Matters

Keeping the phases explicit means layout and semantics do not need terminal escape-sequence knowledge, and runtime presentation can evolve without rewriting layout.

## Related Symbols

- ``FrameArtifacts``
- ``FrameDiagnostics``
- ``CommitPlan``
