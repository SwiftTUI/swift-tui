---
title: "refactor: make raster reuse sound"
type: refactor
status: completed
date: 2026-05-17
depends_on:
  - "./2026-05-16-001-pipeline-driver-hardening-plan.md"
  - "./2026-05-17-003-stage-3-compose-pipeline-plan.md"
---

# Stage 4 Plan: Make Raster Reuse Sound

## Goal

Separate fresh rasterization from the retained incremental-repaint adapter so
the optimized path has a visible soundness boundary. A fresh raster remains the
canonical `DrawNode -> RasterSurface` conversion; incremental reuse is only an
adapter over a previous surface plus sound presentation damage.

## Current Source Anchors

- `Sources/SwiftTUICore/Raster/Rasterizer.swift`
  - `rasterizeCollectingVisibleIdentities(...)` currently owns fresh surface
    allocation, previous-surface reuse, dirty-row culling, clearing, painting,
    identity collection, and damage refinement in one function.
- `Sources/SwiftTUICore/Raster/Rasterizer+Damage.swift`
  - `refinedPresentationDamage(...)` only compares rows the candidate damage
    already marked dirty.
- `Sources/SwiftTUICore/Raster/Rasterizer+Paint.swift`
  - `paint(node:...)` can skip entire subtrees outside the dirty row range.
- `Sources/SwiftTUIRuntime/Rendering/FrameTailRenderer.swift`
  - `presentationDamage(...)` is the runtime proof point that returns `nil`
    when retained layout cannot guarantee localized row damage.
- `Tests/SwiftTUITests/PipelineContractTests.swift`
  - `incrementalRasterReuseMatchesFreshRasterForMutationMatrix()` is disabled
    for Stage 4 and must become the contract test.

## Tests First

- Replace the disabled Stage 4 placeholder with a mutation matrix that compares
  incremental repaint output byte-for-byte with fresh raster output.
- Add focused `RasterizerTests` for the explicit fallback cases:
  incompatible surface size, empty damage rows, and full text/graphics repaint
  requirements must render fresh and return `nil` presentation damage.
- Keep existing image-attachment retention and refined-damage tests green.

## Implementation Tasks

- Extract a fresh rasterization operation that allocates a clean surface, paints
  the full draw tree, collects visible identities, and returns no partial
  presentation damage.
- Add a small typed incremental-reuse input that wraps `PresentationDamage` as
  soundness-critical damage. It should reject cases the rasterizer can prove
  are not safe for reuse: incompatible surface size, empty dirty rows, and full
  text or graphics repaint requirements.
- Extract an incremental repaint adapter that takes the previous surface plus
  that typed damage, reuses previous cells, clears only the damaged ranges,
  dirty-row culls the paint walk, and refines the resulting damage.
- Keep `rasterizeCollectingVisibleIdentities(...)` as the public package entry
  point that chooses incremental only when the adapter input can be built;
  otherwise it falls back to fresh raster and reports `nil` damage.
- Document the runtime contract: `FrameTailRenderer.presentationDamage(...)`
  is the proof boundary for localized reuse, and `nil` means the rasterizer and
  presenter must treat the frame as a full repaint.

## Validation

Passed:

- `swiftly run swift test --filter SwiftTUICoreTests.RasterizerTests`
- `swiftly run swift test --filter SwiftTUITests.PipelineContractTests`
- `swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests`
- `swiftly run swift test --filter SwiftTUITests.LayoutAndRenderingPipelineTests`
- `swiftly run swift test --package-path Examples/gallery`
- `bun run test`

Final repo gate log:

- `/tmp/swift-tui-test-gate-20260517-040336-76070.log`

## Exit Criteria

- Fresh raster and incremental repaint are named and separately testable.
- Incremental repaint takes typed, soundness-critical damage instead of a raw
  optional `PresentationDamage`.
- Unsuitable damage falls back to fresh raster and does not leak partial damage
  to presentation.
- The Stage 4 mutation matrix passes and is no longer disabled.
- Stage 4 status is reflected in the roadmap, tracker, and changelog.
