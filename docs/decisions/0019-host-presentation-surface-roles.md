---
adr: "0019"
title: "Host presentation uses focused surface roles"
status: accepted
date: 2026-05-17
sources:
  - docs/plans/2026-05-16-001-pipeline-driver-hardening-plan.md
  - docs/plans/2026-05-17-003-stage-7-presentation-seam-plan.md
  - docs/HOST_RENDERING_PIPELINES.md
  - docs/proposals/PIPELINE_DRIVER_AUDIT.md
  - docs/proposals/SEMANTIC_HOST_FRAME_API.md
---

# ADR-0019: Host presentation uses focused surface roles

## Context

`PresentationSurface` originally mixed host metrics, terminal raw-mode control,
terminal byte writing, raster presentation, damage-aware raster presentation, and
semantic host-frame presentation behind one terminal-shaped protocol. That was
convenient for `TerminalHost`, but it forced non-terminal hosts such as
`HostedRasterSurface`, WebHost, and WASI web-surface transports to implement
no-op raw-mode, cursor, and write methods just to receive committed frames.

The runtime already dispatches committed frames by role: semantic host frames
first, damage-aware raster frames second, and plain raster presentation last.
The protocol surface should match that producer/consumer split.

## Decision

Split host presentation into focused roles:

- `PresentationSurfaceMetricsProvider` for size, appearance, theme, graphics,
  and pointer capabilities used during resolve/layout.
- `TerminalCommandPresentationSurface` for raw mode, terminal output, cursor
  movement, and pointer-hover mode.
- `RasterPresentationSurface` for plain raster commits.
- package `DamageAwarePresentationSurface` for raster commits with advisory
  `PresentationDamage`.
- SPI `SemanticHostFramePresentationSurface` for semantic host-frame commits.

Keep `PresentationSurface` as the composed terminal aggregate over metrics,
terminal commands, and raster presentation so existing terminal hosts and callers
remain source-compatible.

## Status

Accepted on 2026-05-17 as Stage 7 of the pipeline-driver hardening roadmap.

## Consequences

Non-terminal semantic hosts can now receive `SemanticHostFrame` values without
pretending to be terminal command surfaces. `RunLoop` must cast to the specific
role it needs when enabling raw mode, writing JSON/accessibility output, toggling
pointer hover, or presenting a committed frame.

Terminal hosts still use the aggregate `PresentationSurface`, and compatibility
initializers preserve the old `RunLoop` and `SceneSessionResources` call shapes.
Future host capabilities should extend the narrow role they actually consume
rather than adding more requirements to the aggregate.
