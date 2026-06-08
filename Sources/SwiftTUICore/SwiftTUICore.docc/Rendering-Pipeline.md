# Rendering Pipeline

## Overview

Every SwiftTUI frame product moves through the same ordered phase products:

```text
resolve -> measure -> place -> semantics -> draw -> raster -> commit
```

`SwiftTUICore` owns those products after authored `SwiftTUIViews` values have
been lowered and before `SwiftTUIRuntime` presents the result to a terminal,
browser, or host-managed surface. The runtime may schedule measure, place,
semantics, draw, and raster as a fused frame-tail performance node, but the
products retain distinct ownership and diagnostics.

This article describes the product model. For runtime scheduling, cancellation,
host handoff, and diagnostics, see the Runtime Render Pipeline article in the
`SwiftTUIRuntime` documentation.

## Runtime Mapping

Interactive sessions drive the phase products through runtime stages:

```text
head -> animationInjection -> latePreferenceReconciliation -> fusedFrameTail -> commit
```

The runtime stages are scheduling boundaries, not new frame products.
`resolve` happens while building the frame head. `measure`, `place`,
`semantics`, `draw`, and `raster` usually run in the fused frame tail. `commit`
publishes the resulting frame products plus lifecycle and handler effects.

The direct `DefaultRenderer.render` snapshot path and the interactive run-loop
path both produce ``FrameArtifacts``. The interactive path adds invalidation
coalescing, frame-tail cancellation, completed-frame disposition, host-facing
presentation damage, and presentation to a concrete surface.

## Phase Roles

### Resolve

Produces `ResolvedNode` trees with the resolved identity projection,
`StructuralPath`, optional `EntityIdentity`, state ownership, merged
environment, view metadata, and runtime registrations.

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

Converts draw commands into `RasterSurface`, a cell grid with styles,
attachments, image attachments, continuation-cell handling, and a package-level
ordered presentation-layer sidecar. The final cell grid plus image attachments
remain the compatibility boundary for hosts. The sidecar records compact cell
fragments and image attachment paint events in raster order so package tests and
future host replay paths can inspect authoring order without replacing the
collapsed surface.

Image attachments remain host presentation records; when an image is under an
active blend mode, the raster phase records visible backdrop metadata, including
cell backgrounds, explicit foreground colors, glyphs, and continuation spans,
so the runtime can precompose a blended image variant without changing the cell
grid model.

### Commit

Packages lifecycle and handler-installation work into `CommitPlan`.

## Why The Split Matters

Keeping the phases explicit means layout and semantics do not need terminal
escape-sequence knowledge, and runtime presentation can evolve without
rewriting layout.

Layout products are integer-cell based. Pointer and Canvas APIs can still carry
continuous ``Point`` values because the runtime normalizes pointer input after
semantic routing and Canvas packs continuous cell-space samples during raster.

Later phases may carry named snapshots of earlier data, but those snapshots are
not independent owners. `PlacedNodeResolvedMetadata` names the resolved metadata
mirrored into placed nodes, `SemanticSnapshot` is a derived routing product,
`DrawNode` is a placed-to-paint projection, and `RasterSurface` owns the final
cell grid, raster attachments, and package-level presentation-order sidecar.
Retained layout reuse must pair any relaxed equivalence predicate with a refresh
path before downstream phases read the reused product.

## Performance Shape

Steady-state performance depends on how much work each phase can avoid:

- Resolve should scale with the dirty frontier plus retained-reuse bookkeeping
  after the initial frame.
- Layout and placement are tree/layout dependent, and eligible frame-tail work
  can run away from the main actor.
- Semantics and draw walk the effective placed tree.
- Raster can reuse the previous renderer-committed surface when damage is
  sound.
- Commit stays on the main actor and should publish only the changed runtime
  registration scope on narrow updates.

The runtime re-derives host-facing damage against the last frame actually
presented to that host. Renderer-private raster reuse hints are never a
frontend contract.

## Related Symbols

- ``FrameArtifacts``
- ``FrameDiagnostics``
- ``CommitPlan``
