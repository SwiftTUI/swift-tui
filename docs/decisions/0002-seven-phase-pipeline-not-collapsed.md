---
adr: "0002"
title: "Seven-phase pipeline, not collapsed"
status: superseded
date: 2026-04-29
sources:
  - docs/ARCHITECTURE.md
  - docs/RUNTIME.md
  - Sources/SwiftTUICore/SwiftTUICore.docc/Rendering-Pipeline.md
  - docs/decisions/0019-composed-runtime-render-pipeline.md
superseded_by:
  - docs/decisions/0019-composed-runtime-render-pipeline.md
---

# ADR-0002: Seven-phase pipeline, not collapsed

> Superseded for runtime-driver governance by
> [ADR-0019](0019-composed-runtime-render-pipeline.md). This ADR remains the
> historical record for defending the typed phase-product split.

## Context

At the phase-product level, a frame in SwiftTUI moves through seven distinct
typed products:

```
resolve → measure → place → semantics → draw → raster → commit
```

Each phase produces a typed artifact (`ResolvedNode`, `MeasuredNode`,
`PlacedNode`, `SemanticSnapshot`, `DrawNode`, `RasterSurface`,
`CommitPlan`) and keeps a distinct ownership contract.

The cheaper alternative would be to collapse adjacent phases that have
no semantic boundary today: measure+place into one geometry pass,
draw+raster into one rendering pass, semantics+draw into one extraction
pass. Each collapse saves a few hundred lines of plumbing, removes a
type, and makes the data flow shorter.

The original ADR did not distinguish that type split from the production
runtime driver. The driver now has its own accepted record:
[ADR-0019](0019-composed-runtime-render-pipeline.md). `DefaultRenderer`
executes the shipped runtime composition:

```
head → animation injection → late-preference reconciliation → fused frame tail → commit
```

The fused tail produces the typed products above, but the runtime does not
schedule seven independent closure stages for each frame.

## Decision

The seven phases stay strictly separated. Adjacent phases share input
shape but are kept in distinct files, with distinct artifact types, and
exercised by distinct test suites.

## Status

Superseded on 2026-05-17 for runtime-driver governance by
[ADR-0019](0019-composed-runtime-render-pipeline.md). The phase-product split
remains accepted; the production driver shape is governed by ADR 0019.

## Consequences

**Enabled:**

- **Tests can pin exact behavior at the right abstraction boundary.**
  Layout regressions assert against `MeasuredNode` / `PlacedNode`, not
  against a combined "render output." Semantic regressions assert
  against `SemanticSnapshot` independently of the styled output.
- **Layout and semantics do not need terminal escape-sequence
  knowledge.** All ANSI/Kitty/Sixel awareness is confined to raster and
  presentation. The same authored view tree can be rendered for
  previews, snapshots, ASCII output, ANSI16, ANSI256, or true-color
  terminals without rewriting layout.
- **Runtime presentation can evolve without rewriting layout.** Async
  frame-tail offload and the later composed runtime driver were able to fuse
  scheduling while preserving measure/place/semantics/draw/raster products.
- **Diagnostics can attribute work to phases.** `FrameDiagnostics`
  records resolve reuse, measurement cache hits, and presentation
  damage independently. When something regresses we know whether it was
  reuse, measurement, or paint.

**Costs:**

- More types, more files, more boilerplate. Roughly 2,000 lines of
  per-phase scaffolding that a collapsed pipeline wouldn't carry.
- Adjacent phases sometimes need redundant lookups (e.g. semantic and
  draw both need to walk placed nodes). The redundancy is intentional —
  collapsing it would reintroduce coupling.

**Discipline imposed:**

- New behavior must declare which phase it belongs to. Modifiers that
  affect layout live in `LayoutEngine.swift`; modifiers that affect
  styling live in the rasterizer.
- Adding state that flows across phases requires a new typed artifact
  field, not a side-channel.
- Documentation must not use `FrameArtifacts` breadth or the old generic
  `Renderer<Root>` helper as evidence that the runtime driver exposes seven
  independent scheduling stages.

The bet: **regression tests that resist localization** and
**diagnostic signals that distinguish reuse from recomputation** are
worth more than the boilerplate they cost. So far the bet has held —
every async-rendering, retained-layout, and incremental-paint
optimization has landed without rewriting layout, because layout is its
own phase.
