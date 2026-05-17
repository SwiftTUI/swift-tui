---
title: "docs: reconcile pipeline governance"
type: docs
status: shipped
date: 2026-05-17
depends_on:
  - "./2026-05-16-001-pipeline-driver-hardening-plan.md"
  - "./2026-05-17-003-stage-3-compose-pipeline-plan.md"
  - "./2026-05-17-004-stage-4-raster-reuse-soundness-plan.md"
  - "./2026-05-17-005-stage-5-frame-drop-surface-plan.md"
  - "./2026-05-17-004-stage-6-worker-recursion-hardening-plan.md"
  - "./2026-05-17-006-explicit-layout-work-stack-migration-plan.md"
  - "./2026-05-17-003-stage-7-presentation-seam-plan.md"
  - "../decisions/0019-composed-runtime-render-pipeline.md"
---

# Stage 8 Plan: Reconcile Pipeline Governance

## Goal

Make the durable documentation describe the shipped runtime pipeline instead of
the pre-hardening claim that a seven-closure generic driver was the production
pipeline. Stage 8 closes the governance-drift finding from
[`PIPELINE_DRIVER_AUDIT.md`](../proposals/PIPELINE_DRIVER_AUDIT.md) after the
driver and supporting hardening stages have landed.

The end state is:

```text
Runtime driver:
head -> animation injection -> late-preference reconciliation -> fused frame tail -> commit

Phase products:
resolve -> measure -> place -> semantics -> draw -> raster -> commit
```

The runtime driver is the actual scheduling contract. The seven phase products
remain the inspection and ownership model, and `FrameArtifacts` is described as
an inspection bundle rather than proof that each product is independently
scheduled at runtime.

## Source Anchors

- `docs/ARCHITECTURE.md`
  - `Frame Pipeline` still names the seven phase products, but needs to
    distinguish product order from runtime scheduling.
  - `Important Data Products` already contains the Stage 0
    `FrameArtifacts` authority table and should remain the source of truth for
    architectural field authority.
- `Sources/SwiftTUIRuntime/SwiftTUIRuntime.docc/Architecture.md`
  - Mirrors the architecture overview exposed through DocC and must not repeat
    stale driver language.
- `AGENTS.md`
  - The short agent guide should point to the same driver/product distinction.
- `docs/decisions/0002-seven-phase-pipeline-not-collapsed.md`
  - Defends the phase-product type split. It must be amended so ADR 0019 is the
    runtime-driver authority.
- `docs/decisions/0019-composed-runtime-render-pipeline.md`
  - Accepted Stage 3 runtime-driver ADR and the wording source for the shipped
    composition.
- `docs/proposals/PIPELINE_DRIVER_AUDIT.md`
  - Findings must be annotated as resolved, deferred, or still open rather than
    left as current-state contradictions.
- `docs/plans/2026-05-16-001-pipeline-driver-hardening-plan.md`
  - Parent roadmap should become shipped and cross-link the per-stage plans.

## Tasks

- [x] Update architecture docs to state the shipped runtime composition,
  execution strategies, and phase-product inspection model.
- [x] Update AGENTS and Runtime DocC architecture text so short-form and
  published docs match the durable architecture doc.
- [x] Amend ADR 0002 to mark the runtime-driver portion superseded by ADR 0019
  while preserving the accepted phase-product split.
- [x] Annotate the audit summary and proposal sections with shipped, deferred,
  or open outcomes:
  - P1/P2/P3 resolved by Stages 1-3.
  - P4/P5 resolved by Stage 6, with WASI fallback documented as a compatibility
    boundary.
  - P6 resolved by Stage 5.
  - P7/P11 resolved by Stage 0 guardrails.
  - P8 resolved by Stage 4.
  - P9 resolved by Stage 7.
  - P10 resolved by Stage 0 source docs plus Stage 8 architecture wording.
  - Finding 4 narrowing was deferred at Stage 8 and is now complete in the
    follow-up plan; Finding 10 was completed later by the source-breaking
    diagnostics cleanup.
- [x] Mark this Stage 8 plan and the parent roadmap as shipped; update the
  docs index and TODO/CHANGELOG records.
- [x] Run documentation checks and the repo gate.

## Validation

Passed on 2026-05-17:

- `git diff --check`
- Current-source contradiction search:

  ```bash
  rg -n 'visible in .*Pipeline|visible in .*DefaultRenderer|Every frame flows through seven strict phases|the production runtime schedules seven independent|Renderer<Root>` helper as evidence|Pipeline/    .+seven phases|FrameArtifacts.*architectural evidence|FrameArtifacts.*architecture contract' AGENTS.md docs/ARCHITECTURE.md docs/SOURCE_LAYOUT.md docs/decisions Sources/SwiftTUIRuntime/SwiftTUIRuntime.docc Sources/SwiftTUICore/SwiftTUICore.docc
  ```

  found only negating guardrail language in the updated architecture/ADR text,
  not a current-state assertion that contradicts the shipped driver.
- `bun Scripts/check_doc_frontmatter.ts`
- `Scripts/check_stable_doc_source_paths.sh`
- `bun run test` (full log:
  `/tmp/swift-tui-test-gate-20260517-081201-88333.log`)

## Exit Criteria

- The durable architecture docs, AGENTS guide, Runtime DocC architecture page,
  ADR 0002, and ADR 0019 tell one consistent story: `DefaultRenderer` runs the
  composed runtime pipeline; seven phase products remain explicit typed
  artifacts.
- `FrameArtifacts` is documented as a broad inspection bundle with field
  authority, not as evidence that runtime scheduling exposes every phase as an
  independent stage.
- The audit remains useful as an evidence record, but each finding now has a
  clear shipped, deferred, or open outcome.
- `TODO.md` has no stale pipeline-hardening active item, and `CHANGELOG.md`
  records the completed roadmap with hash-prefixed doc links.
