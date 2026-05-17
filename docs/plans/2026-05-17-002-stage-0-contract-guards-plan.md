---
title: "test: Stage 0 - pipeline contract guards"
type: test
status: shipped
date: 2026-05-17
depends_on:
  - "2026-05-16-001-pipeline-driver-hardening-plan.md"
  - "../proposals/PIPELINE_DRIVER_AUDIT.md"
  - "../proposals/PIPELINE_BOUNDARY_HARDENING.md"
  - "../ARCHITECTURE.md"
  - "../ASYNC_RENDERING.md"
  - "../HOST_RENDERING_PIPELINES.md"
---

# Stage 0 - Pipeline Contract Guards Implementation Plan

> **For agentic workers:** Execute this plan task-by-task with
> `superpowers:executing-plans` or the local equivalent. This is **Stage 0** of
> [`2026-05-16-001-pipeline-driver-hardening-plan.md`](./2026-05-16-001-pipeline-driver-hardening-plan.md);
> it addresses audit proposals **P7**, **P10** (documentation half), and **P11**.

**Goal:** Add the low-risk contract guards that make later pipeline driver
refactors measurable before changing production behavior. Stage 0 is a test and
documentation stage only: it must not refactor `DefaultRenderer`, change
pipeline semantics, or close later-stage gaps.

**Architecture:** The current monolithic driver protects several contracts only
by convention: retained placement must refresh every resolved-derived
`PlacedNode` projection; `ResolvedNode` stored properties need an explicit phase
ownership classification; frame-drop classification must not hide committed
side effects; semantic host frames must stay sequence- and damage-consistent
through runtime churn; and `FrameArtifacts` must state which fields are
canonical products versus advisory or decorated projections. These guards pin
that behavior before Stages 1 and 3 continue structural driver work.

**Tech Stack:** Swift 6.3 strict concurrency, Swift Testing, `SwiftTUICore`,
`SwiftTUIRuntime`, `SwiftTUITests`, and `SwiftTUICoreTests`.

---

## Regression Policy

Stage 0 has two explicit groups:

1. **Must-pass baseline guards** are required before Stage 1 or Stage 3 driver
   edits can land. They cover shared head freshness, sync/async artifact parity,
   commit/drop semantics, semantic host-frame continuity, retained reuse
   freshness, and the normal repo gate.
2. **Stage-specific pending guards** may be disabled only when they expose an
   already-known gap owned by a later stage. Their disabled reason must name the
   closing stage, for example
   `@Test(.disabled("closed by Stage 4: raster reuse soundness split"))`.

Existing green tests are not candidates for tolerated regression. Only newly
added Stage 0 guards may be disabled, and disabled tests do not count as Stage 3
coverage.

## Current Source Anchors

- `Sources/SwiftTUICore/Place/PlacedNode.swift`
  - `PlacedNodeResolvedMetadata` names the resolved-to-placed projection.
  - `PlacedNode.resolvedMetadata` and `synchronizeResolvedPhaseMetadata(...)`
    are the construction/synchronization surface to guard.
- `Sources/SwiftTUICore/Measure/LayoutEngine+RetainedLayout.swift`
  - `synchronizeRetainedPhaseMetadata(placed:from:)` refreshes reused placed
    subtrees after geometry-stable retained placement.
- `Sources/SwiftTUICore/Resolve/ResolvedNode.swift`
  - Stored properties around `ResolvedNode` need an explicit phase ownership
    decision when they are added or moved.
  - `isEquivalentForMeasurement(to:)` and `isEquivalentForPlacement(to:)`
    define which resolved changes can reuse measurement or placement.
- `Sources/SwiftTUICore/Commit/FrameArtifacts.swift`
  - `FrameArtifacts` already carries phase products, presentation hints, the
    commit plan, and diagnostics; Stage 0 must document field authority.
- Existing coverage to preserve:
  - `Tests/SwiftTUITests/AsyncFrameTailRenderingTests.swift`
    (`syncAndAsyncRendererArtifactsStayEquivalent`)
  - `Tests/SwiftTUICoreTests/FrameDropEligibilityTests.swift`
  - `Tests/SwiftTUITests/AccessibilityRuntimePolicyTests.swift`
    (`runLoopPrefersSemanticHostFrameSurfaceOverRasterDamageSurface`)
  - `Tests/SwiftTUITests/DiagnosticsAndCacheTests.swift`
    (`snapshotRendererExposesArchitectureLayers`)

## Task 1 - Establish The Baseline

Run the current safety nets before adding new guards. If any command is already
red on `main`, stop and resolve or record the unrelated failure before writing
new assertions.

- [x] Run the sync/async and layout pipeline suites:

```bash
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests
swiftly run swift test --filter SwiftTUITests.LayoutAndRenderingPipelineTests
swiftly run swift test --filter SwiftTUICoreTests.PipelineTests
```

- [x] Run the existing commit/drop and runtime host-frame guards:

```bash
swiftly run swift test --filter SwiftTUICoreTests.FrameDropEligibilityTests
swiftly run swift test --filter SwiftTUITests.AccessibilityRuntimePolicyTests
swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests
bun run test
```

The repo gate passed with full log:
`/tmp/swift-tui-test-gate-20260517-030652-26140.log`.

Expected: all pass. These are existing green tests and must not regress.

## Task 2 - Add Retained Reuse Projection Guards

Create `Tests/SwiftTUICoreTests/RetainedReuseInvariantTests.swift`.

- [x] Add a direct projection round-trip test:
  - Build a `PlacedNodeResolvedMetadata` with non-default values for every
    current field: `kind`, `environmentSnapshot`, `semanticRole`,
    `layoutMetadata`, `drawMetadata`, `semanticMetadata`, `lifecycleMetadata`,
    `drawPayload`, `layoutBehavior`, `isTransient`, and `matchedGeometry`.
  - Construct a `PlacedNode(identity:resolvedMetadata:bounds:)`.
  - Assert `placed.resolvedMetadata == metadata`.
  - Mutate `placed.resolvedMetadata` to a second non-default metadata value and
    assert the getter returns that second value.
- [x] Add a retained-subtree synchronization test:
  - Build a previous placed subtree and a current resolved subtree with the same
    identities and child shape.
  - Give the current resolved subtree different non-geometry metadata on parent
    and child nodes.
  - Call `LayoutEngine().synchronizeRetainedPhaseMetadata(placed:from:)`.
  - Assert parent and child `resolvedMetadata` match the current resolved tree's
    projected metadata while bounds, content bounds, clipping, z-index, and
    child placement are preserved.
- [x] Add a field-list tripwire:
  - Keep a local `expectedPlacedResolvedMetadataFields` manifest in the test.
  - Parse `PlacedNode.swift` for `package var` declarations inside
    `PlacedNodeResolvedMetadata`.
  - Assert the parsed list equals the manifest. A newly added projection field
    must update the manifest and the round-trip/synchronization assertions in
    the same change.

These tests are must-pass baseline guards.

## Task 3 - Add ResolvedNode Ownership Classification Guard

Add a mechanical guard for new `ResolvedNode` stored properties. Prefer a small
source-parser helper inside the test over reflection, because Swift reflection
does not reliably expose package-private stored-property names.

- [x] Add `Tests/SwiftTUICoreTests/ResolvedNodePhaseOwnershipTests.swift`.
- [x] Create a local manifest mapping each stored property on `ResolvedNode` to
  one of these categories:
  - `identity`
  - `structure`
  - `measurement`
  - `placement`
  - `semantics`
  - `draw`
  - `lifecycle`
  - `damage`
  - `commit`
  - `diagnostics`
  - `derivedCache`
- [x] Parse the `public struct ResolvedNode` body for stored `public`,
  `package`, and private backing vars. Exclude computed properties and methods.
- [x] Assert every parsed stored property has exactly one classification.
- [x] Add a short comment above the manifest explaining that adding a
  `ResolvedNode` field is an architecture decision, not a storage-only change.

This is a must-pass baseline guard. If parsing edge cases make the helper too
fragile, keep the manifest and test a manually enumerated field list in Stage 0;
do not leave the classification as prose only.

## Task 4 - Add Architecture Contract Tests

Create `Tests/SwiftTUITests/PipelineContractTests.swift` for composed-runtime
contracts that should survive Stage 1 and Stage 3 refactors.

- [x] Add a must-pass head freshness wrapper around the existing sync/async
  parity coverage:
  - Render the same view through `render` and `renderAsync` with diagnostics
    disabled.
  - Assert `FrameArtifacts` equality.
  - Include a view with command or focused-value publication so the guard is not
    only a raster comparison.
- [x] Add a must-pass commit/drop contract:
  - Reuse the existing `FrameDropEligibilityTests` blocker list where possible.
  - Assert every currently modeled committed side-effect blocker produces
    `.mustCommit`.
  - Keep `canDrop == false` as the current behavior until Stage 5 explicitly
    changes the closed impact model.
- [x] Add a must-pass semantic host-frame continuity guard:
  - Drive a run loop with a `SemanticHostFramePresentationSurface`.
  - Render at least two invalidated frames.
  - Assert sequence numbers are contiguous and each semantic host frame carries
    raster, semantics, focused identity, and damage consistently.
- [x] Add a must-pass focus/default-focus freshness guard:
  - Render a view whose default focus target changes after state or identity
    churn.
  - Assert the committed semantic snapshot and focus tracker converge on the
    current target, not a stale snapshot.
- [x] Add a retained reuse freshness guard if Task 2's core-level tests do not
  already cover a full renderer path:
  - Render a stable-geometry view twice with changed non-geometry metadata.
  - Assert the second frame's semantics/draw/lifecycle-facing projection reflects
    the current resolved tree.

These tests are the Stage 3 must-pass subset together with the repo gate.

## Task 5 - Add Disabled Later-Stage Guards

Add only the disabled tests that are useful as executable future requirements.
Each disabled reason must name the closing stage and the concrete gap.

- [x] Stage 4 disabled guard:

```swift
@Test(.disabled("closed by Stage 4: raster reuse soundness split"))
```

Curated incremental-raster mutation matrix must compare incremental repaint
output byte-for-byte with a fresh raster.

- [x] Stage 5 disabled guard:

```swift
@Test(.disabled("closed by Stage 5: closed frame-drop impact model"))
```

All committed side-effect kinds, including any future side-effect records not
visible from `FrameArtifacts` alone, must force non-droppable frames or be
classified by a closed impact product.

- [x] Stage 6 disabled guard:

```swift
@Test(.disabled("closed by Stage 6: worker and recursion safety"))
```

Worker dispatch and deep tree processing must avoid unbounded hand-rolled
threads or unbounded recursive destruction on the frame-tail path.

- [x] Stage 7 disabled guard:

```swift
@Test(.disabled("closed by Stage 7: presentation seam split"))
```

Semantic host-frame consumers must receive semantic frames without inheriting
terminal-command obligations.

Disabled tests are allowed only if they compile and are skipped by Swift
Testing. They must not hide failures in existing tests or must-pass Stage 0
guards.

## Task 6 - Document FrameArtifacts Field Authority

Update `Sources/SwiftTUICore/Commit/FrameArtifacts.swift` and
`docs/ARCHITECTURE.md`. This is documentation-only.

- [x] Add a doc-comment authority table near `FrameArtifacts`:
  - Canonical phase products: `resolvedTree`, `measuredTree`,
    `semanticSnapshot`, `drawTree`, `rasterSurface`.
  - Decorated/baseline-sensitive projection: `placedTree`; retained-layout
    baselines must store the canonical placement product rather than an
    animation-decorated current-frame variant.
  - Advisory hints: `presentationDamage`, `drawnIdentities`.
  - Side-effect plan: `commitPlan`.
  - Diagnostics: `diagnostics`.
- [x] Update `docs/ARCHITECTURE.md`'s data-products table to point at that
  authority table and repeat the baseline/decorated placed-tree rule in one
  sentence.
- [x] Do not change `FrameArtifacts` storage, initializers, visibility, or
  equality in Stage 0.

## Task 7 - Verify And Ship Stage 0

- [x] Run focused new suites:

```bash
swiftly run swift test --filter SwiftTUICoreTests.RetainedReuseInvariantTests
swiftly run swift test --filter SwiftTUICoreTests.ResolvedNodePhaseOwnershipTests
swiftly run swift test --filter SwiftTUITests.PipelineContractTests
```

- [x] Re-run baseline suites:

```bash
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests
swiftly run swift test --filter SwiftTUITests.LayoutAndRenderingPipelineTests
swiftly run swift test --filter SwiftTUICoreTests.PipelineTests
swiftly run swift test --filter SwiftTUICoreTests.FrameDropEligibilityTests
swiftly run swift test --filter SwiftTUITests.AccessibilityRuntimePolicyTests
swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests
```

- [x] Run the repo gate:

```bash
bun run test
```

- [x] Mark this plan `status: shipped`.
- [x] Update the roadmap and `docs/TODO.md`:
  - Stage 0 should be marked shipped or linked to the shipped commit.
  - The TODO entry should move from "execute Stage 0" to the next unblocked
    stage.
- [x] Add a concise `docs/CHANGELOG.md` entry when removing a completed TODO.

## Exit Criteria

- Must-pass baseline guards pass on current `main`.
- No existing green test regresses.
- Every disabled Stage 0 guard names Stage 4, Stage 5, Stage 6, or Stage 7 in
  its disabled reason and compiles as a skipped test.
- Disabled guards are not counted as Stage 3 coverage.
- `FrameArtifacts` field authority is documented in source comments and
  `docs/ARCHITECTURE.md`.
- `bun run test` passes.

## Non-Goals

- No production behavior changes.
- No `DefaultRenderer` composition.
- No frame-drop model rewrite.
- No raster reuse refactor.
- No worker/recursion implementation change.
- No presentation seam split.

## Shipped Record

Stage 0 adds must-pass retained-reuse projection guards, a
`ResolvedNode` phase-ownership manifest guard, and pipeline contract tests for
sync/async parity, frame-drop blockers, semantic host-frame continuity,
focus/default-focus freshness, and retained semantic metadata freshness. The
later-stage raster, frame-drop closure, worker/recursion, and presentation seam
guards are present as disabled Swift Testing cases with Stage 4, Stage 5,
Stage 6, and Stage 7 ownership in their disabled reasons.

Verification:

```bash
swiftly run swift test --filter SwiftTUICoreTests.RetainedReuseInvariantTests
swiftly run swift test --filter SwiftTUICoreTests.ResolvedNodePhaseOwnershipTests
swiftly run swift test --filter SwiftTUITests.PipelineContractTests
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests
swiftly run swift test --filter SwiftTUITests.LayoutAndRenderingPipelineTests
swiftly run swift test --filter SwiftTUICoreTests.PipelineTests
swiftly run swift test --filter SwiftTUICoreTests.FrameDropEligibilityTests
swiftly run swift test --filter SwiftTUITests.AccessibilityRuntimePolicyTests
swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests
```
