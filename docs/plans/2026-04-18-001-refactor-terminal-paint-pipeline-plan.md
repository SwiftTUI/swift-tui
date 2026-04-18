---
title: refactor: tighten terminal paint pipeline
type: refactor
status: active
date: 2026-04-18
---

# refactor: tighten terminal paint pipeline

## Overview

Refine the terminal presentation tail of the retained render pipeline so the runtime preserves more
useful damage information, avoids duplicated full-repaint work, emits fewer bytes for localized
updates, and treats image placement as a first-class incremental concern rather than a repaint
poison pill.

The intended outcome is not a new rendering architecture. The seven-phase frame pipeline remains:

`resolve -> measure -> place -> semantics -> draw -> raster -> commit`

This plan narrows the work performed after `place` and especially after `raster`, where the current
system is correct but conservative. The highest-value changes are:

- richer damage representation than row-only dirtying
- single-owner full-repaint encoding
- stateful row-batched incremental text emission
- capability-gated synchronized output for repaint safety
- separate planning of text updates and image placement updates

## Problem Frame

The current runtime already performs selective resolve, retained measure/place reuse, and row-aware
raster reuse. The remaining inefficiency is concentrated in the final paint path:

- `DefaultRenderer.presentationDamage(...)` collapses invalidation to dirty rows, discarding
  horizontal locality before the terminal encoder sees the frame
- `TerminalPresentationPlanner` rescans every dirty row across its full width to rediscover spans
- full repaints are rendered twice: once in the planner and again in the host
- incremental text output is encoded span-by-span with self-contained style and hyperlink state,
  which favors simplicity over byte efficiency
- graphics attachment mismatches force a full presentation fallback even when text diffing could
  remain incremental
- Kitty re-placement currently reruns for all visible image attachments after incremental text
  writes, even when only a small subset is affected
- synchronized output is discussed in the async presentation proposal but is not yet implemented in
  the live host path

The user request is to deepen the current scheme, especially the final painting algorithm. This plan
therefore focuses on the terminal presentation boundary rather than upstream structural diffing.

## Requirements Trace

- R1. Reduce terminal paint CPU and byte volume for localized edits without changing visible output.
- R2. Preserve correctness for wide glyphs, continuation cells, styles, OSC 8 hyperlinks, and
  graphics attachments.
- R3. Keep resize, dropped-frame, and surface-incompatibility fallbacks safe and deterministic.
- R4. Preserve the current retained pipeline architecture and post-present commit semantics.
- R5. Add deterministic tests and diagnostics that distinguish incremental regressions from valid
  fallbacks.
- R6. Avoid introducing terminal-specific behavior into layout or semantic phases.

## Scope Boundaries

- This plan does not redesign resolve, layout, or semantic extraction.
- This plan does not change the public authoring surface in `View`.
- This plan does not introduce a new non-terminal presentation backend.
- This plan does not require broad adoption of terminal-native edit opcodes on day one.
- This plan does not promise cross-terminal synchronized-output support beyond capability-gated
  enablement where the runtime can prove support or safely opt in.

## Context & Research

### Relevant Code and Patterns

- [docs/ARCHITECTURE.md](/Users/adamz/Developer/repos/swift-terminal-ui/docs/ARCHITECTURE.md:52)
  defines the canonical seven-phase frame model and explicitly keeps terminal adaptation in the
  presentation layer.
- [docs/RUNTIME.md](/Users/adamz/Developer/repos/swift-terminal-ui/docs/RUNTIME.md:156) documents
  incremental presentation as an expected property and calls out known full-repaint fallbacks.
- [docs/TESTING_AND_FIXTURE_POLICY.md](/Users/adamz/Developer/repos/swift-terminal-ui/docs/TESTING_AND_FIXTURE_POLICY.md:71)
  treats new full-repaint fallbacks in previously incremental scenarios as regressions unless
  explicitly documented.
- [Sources/TerminalUI/TerminalUI.swift](/Users/adamz/Developer/repos/swift-terminal-ui/Sources/TerminalUI/TerminalUI.swift:269)
  computes `PresentationDamage` from directly invalidated identities after placement.
- [Sources/Core/CommitAndFrameTypes.swift](/Users/adamz/Developer/repos/swift-terminal-ui/Sources/Core/CommitAndFrameTypes.swift:657)
  currently models damage as `dirtyRows: Set<Int>`.
- [Sources/Core/Rasterizer.swift](/Users/adamz/Developer/repos/swift-terminal-ui/Sources/Core/Rasterizer.swift:74)
  seeds raster output from the previous surface when row damage exists.
- [Sources/TerminalUI/TerminalPresentation.swift](/Users/adamz/Developer/repos/swift-terminal-ui/Sources/TerminalUI/TerminalPresentation.swift:308)
  plans either full repaint or incremental span updates.
- [Sources/TerminalUI/TerminalHost.swift](/Users/adamz/Developer/repos/swift-terminal-ui/Sources/TerminalUI/TerminalHost.swift:865)
  owns paint submission, frame-drop recovery, and graphics placement ordering.
- [Sources/TerminalUI/TerminalImageRendering.swift](/Users/adamz/Developer/repos/swift-terminal-ui/Sources/TerminalUI/TerminalImageRendering.swift:131)
  handles Kitty/Sixel placement and fallback image compositing.
- [Tests/TerminalUITests/TerminalPresentationTests.swift](/Users/adamz/Developer/repos/swift-terminal-ui/Tests/TerminalUITests/TerminalPresentationTests.swift:321)
  provides the authoritative planner and host presentation test bed.
- [Tests/TerminalUITests/TerminalHostPresentationBatchingTests.swift](/Users/adamz/Developer/repos/swift-terminal-ui/Tests/TerminalUITests/TerminalHostPresentationBatchingTests.swift:15)
  already covers batching and dropped-frame recovery behavior.
- [Tests/TerminalUITests/Phase1BenchmarkScenariosTests.swift](/Users/adamz/Developer/repos/swift-terminal-ui/Tests/TerminalUITests/Phase1BenchmarkScenariosTests.swift:14)
  expresses deterministic “smaller than full repaint” performance gates.

### Institutional Learnings

- No `docs/solutions/` corpus exists in this repository today. The closest local institutional
  history is in the proposals directory, especially:
  [docs/proposals/ASYNC_PRESENTATION.md](/Users/adamz/Developer/repos/swift-terminal-ui/docs/proposals/ASYNC_PRESENTATION.md:166),
  which captures the intended behavior of dropped-frame recovery and the writer queue.

### External References

- No external framework research is required for this plan. The problem is dominated by local
  runtime architecture, existing tests, and terminal protocol choices already represented in the
  codebase.

## Key Technical Decisions

- The retained pipeline remains intact; improvements happen at the `presentationDamage`,
  `rasterizer`, `planner`, `host`, and `imageRenderer` seams.
- Damage should become more expressive than row-only, but still remain cheap to compute and cheap to
  merge.
- One layer should own full-repaint encoding. The system should not render the same full frame twice
  merely to satisfy a plan/host boundary.
- The terminal encoder should batch updates by row and maintain style state within a batch instead of
  treating each span as a self-contained paint island.
- Text diffing and graphics placement should be planned separately so image movement or placement
  updates do not automatically destroy incremental text behavior.
- Terminal-native edit operations are an optimization tier, not a prerequisite for the core refactor.
- Capability-gated synchronized output should wrap full repaints and optionally large incremental
  batches where doing so is safe and detectable.

## Open Questions

### Resolved During Planning

- Should this work redesign the whole render pipeline?
  Resolution: no. The work is constrained to the final paint scheme and its immediate inputs.

- Should synchronized output be part of the plan?
  Resolution: yes. It is already assumed by local proposal material and is directly relevant to
  repaint safety under drop recovery and resize fallback.

- Should terminal-native insert/delete operations be a first-wave requirement?
  Resolution: no. They are a follow-on optimization once the damage model and encoder are more
  precise.

### Deferred to Implementation

- Exact naming of the richer damage data types and whether they live beside or replace
  `PresentationDamage`.
  Deferred because the right names depend on how much of the model is shared between renderer,
  rasterizer, and presentation planner.

- Whether synchronized output support should be purely capability-profile based, runtime probed, or a
  hybrid.
  Deferred because the final detection shape depends on how conservative the host chooses to be for
  terminals and multiplexers already in the compatibility matrix.

- Whether row-batched output should emit style deltas between adjacent spans or normalize the row into
  one minimal script.
  Deferred because both are viable and the implementation should choose based on benchmarked
  complexity.

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation
> specification. The implementing agent should treat it as context, not code to reproduce.*

```text
Placed tree
  -> derive coarse damage candidates from invalidated identities
  -> draw extraction
  -> rasterizer reuses previous rows and records actual touched spans/rows
  -> presentation planner receives:
       - previous prepared surface
       - current prepared surface
       - rich damage (row spans / rectangles / graphics deltas)
  -> planner produces:
       - full repaint script OR
       - incremental text row batches
       - incremental graphics placement batch
       - metrics for rows, spans, cells, bytes
  -> host wraps output in synchronized mode when warranted
  -> writer submits one assembled frame payload
```

A more precise internal target shape:

```text
PresentationDamage
  text:
    row -> one or more candidate column ranges
  graphics:
    changed attachment identities
    changed placement bounds
  fallback flags:
    requiresFullTextRepaint
    requiresFullGraphicsReplay
```

The rasterizer may refine the candidate text damage using actual touched cells so the planner no
longer has to rediscover narrow spans by scanning every dirty row across full terminal width.

## Success Metrics

- Localized single-cell edits remain incremental and produce the same or fewer bytes than today.
- Wide-glyph style changes remain incremental and do not regress continuation-cell correctness.
- Full repaint no longer performs duplicate string rendering work across planner and host.
- A dropped pending frame still recovers safely, but the next repaint can be wrapped in synchronized
  output where supported.
- Text-only frames with stable image attachments do not trigger unnecessary full-repaint fallbacks.
- Kitty image re-placement is restricted to affected attachments whenever the planner can prove that
  narrower scope is safe.

## Dependencies / Prerequisites

- Existing presentation and batching tests remain the baseline safety net.
- Any synchronized-output support must be integrated without weakening current terminal capability
  detection.
- The plan assumes no change to the public `RasterSurface` API unless implementation proves that
  internal/package-only types are insufficient.

## Phased Delivery

- Phase A: data-model and planner boundary cleanup
- Phase B: richer damage propagation and row-batched text encoding
- Phase C: synchronized repaint safety and graphics/text decoupling
- Phase D: optional terminal-native edit ops and extended diagnostics

## Execution Plan

This section turns the implementation units into a mergeable execution sequence. The primary
principle is to keep the runtime shippable after every wave:

- always land characterization coverage before changing paint semantics in a fragile area
- prefer package-only seams and feature-preserving refactors before introducing new heuristics
- keep safe fallback behavior available until the new path is proven by tests and benchmarks
- avoid combining data-model changes, byte-encoding changes, and graphics changes in the same PR

### Execution Strategy

- **Branching model:** land as a sequence of small focused PRs against the current mainline, not one
  long-lived branch. This work touches tests, docs, and host/runtime seams that are likely to drift.
- **Activation model:** prefer internal/package-only toggles or temporary side-by-side planner paths
  while new behavior is being characterized. Remove transitional toggles once the new path is the
  only tested path.
- **Review model:** every PR should include at least one write-shape assertion from
  `TerminalPresentationTests`, `TerminalHostPresentationBatchingTests`, or
  `TerminalGraphicsProtocolTests`, not just structural code review.
- **Performance model:** rely on deterministic work-shape metrics such as `bytesWritten`,
  `cellsChanged`, `linesTouched`, and diagnostics counters. Do not gate on wall-clock timing.
- **Fallback model:** when a new optimization path is uncertain, widen damage or force the existing
  repaint path rather than introducing drift.

### Execution Waves

- [ ] **Wave 0: Baseline characterization and guardrails**

**Objective:** Freeze current behavior around text diffs, dropped-frame recovery, and graphics
placement before changing internals.

**Covers units:** prerequisite for Units 2, 3, 5, 6

**PR shape:**
- Tests only, plus any minimal fixture/helper additions needed to express current behavior

**Primary files:**
- Modify: `Tests/TerminalUITests/TerminalPresentationTests.swift`
- Modify: `Tests/TerminalUITests/TerminalHostPresentationBatchingTests.swift`
- Modify: `Tests/TerminalUITests/TerminalGraphicsProtocolTests.swift`
- Modify: `Tests/TerminalUITests/Phase1BenchmarkScenariosTests.swift`
- Modify: `docs/TESTING_AND_FIXTURE_POLICY.md`

**Work:**
- Add characterization tests for current full repaint write shape, current span update shape, and
  current Kitty re-placement scope.
- Add at least one deterministic test showing that dropped pending frames force repaint recovery.
- Add benchmark expectations for localized edits that the later waves must preserve or improve.

**Merge gate:**
- Tests describe current behavior precisely enough that a later wave can tell whether it improved,
  preserved, or widened the paint path.

**Rollback stance:**
- Safe to revert independently; no runtime changes.

- [ ] **Wave 1: Planner/host boundary cleanup**

**Objective:** Remove duplicated full-repaint rendering and make full repaint ownership explicit.

**Covers units:** Unit 1

**PR shape:**
- Small runtime refactor plus targeted presentation tests

**Primary files:**
- Modify: `Sources/TerminalUI/TerminalPresentation.swift`
- Modify: `Sources/TerminalUI/TerminalHost.swift`
- Modify: `Tests/TerminalUITests/TerminalPresentationTests.swift`
- Modify: `Tests/TerminalUITests/TerminalHostPresentationBatchingTests.swift`

**Work:**
- Choose the single owner for full-repaint materialization.
- Update metrics plumbing so `bytesWritten` still reflects the actual payload submitted.
- Remove dead or duplicate full-repaint helpers if they are no longer needed after the ownership
  decision.

**Merge gate:**
- No production path renders the same full frame twice.
- Full repaint and resize fallback tests still pass with stable visible output.

**Rollback stance:**
- Revertable as one PR; no dependency on later waves.

- [ ] **Wave 2: Damage model expansion at the renderer boundary**

**Objective:** Replace row-only damage with a richer, still-conservative package-level model.

**Covers units:** first half of Unit 2

**PR shape:**
- Data-model and producer changes first, with planner still free to widen to old behavior

**Primary files:**
- Modify: `Sources/Core/CommitAndFrameTypes.swift`
- Modify: `Sources/TerminalUI/TerminalUI.swift`
- Modify: `Sources/Core/Rasterizer.swift`
- Modify: `Tests/TerminalUITests/TerminalPresentationTests.swift`
- Modify: `Tests/TerminalUITests/Phase1BenchmarkScenariosTests.swift`

**Work:**
- Introduce the richer damage type and adapt `DefaultRenderer.presentationDamage(...)` to produce it.
- Keep raster and planner behavior compatible by allowing them to widen to row-level or full repaint
  until they learn the richer structure.
- Add transition-only helpers for merging, normalizing, and widening damage so later waves do not
  duplicate those rules.

**Merge gate:**
- Existing incremental scenarios remain incremental.
- New tests prove that narrower candidate damage is preserved at the API boundary even if the final
  encoder has not exploited it yet.

**Rollback stance:**
- If unstable, revert before Wave 3. Do not stack row-batched encoding on top of an uncertain damage
  model.

- [ ] **Wave 3: Raster refinement and actual touched-span reporting**

**Objective:** Let the rasterizer refine candidate damage into what it truly repainted so the
presentation planner no longer has to rediscover narrow spans from wide row hints.

**Covers units:** second half of Unit 2

**PR shape:**
- Runtime change in `Rasterizer` plus diagnostics/tests

**Primary files:**
- Modify: `Sources/Core/Rasterizer.swift`
- Modify: `Sources/Core/CommitAndFrameTypes.swift`
- Modify: `Sources/TerminalUI/TerminalPresentation.swift`
- Modify: `Tests/TerminalUITests/TerminalPresentationTests.swift`
- Modify: `Tests/TerminalUITests/Phase1BenchmarkScenariosTests.swift`

**Work:**
- Record actual touched spans or touched rectangles while painting dirty regions.
- Feed refined damage forward into the presentation planner.
- Preserve existing visibility bookkeeping for animation scheduling.

**Merge gate:**
- Planner work for localized updates is observably narrower than pre-wave behavior.
- No stale-pixel regressions appear in continuation-cell or trailing-shrink cases.

**Rollback stance:**
- If actual touched-span reporting proves too invasive, keep the richer candidate-damage model from
  Wave 2 and defer refinement to a later iteration.

- [ ] **Wave 4: Row-batched, stateful text encoding**

**Objective:** Reduce repeated escape-sequence and cursor-addressing overhead by encoding
incremental text as row-oriented batches.

**Covers units:** Unit 3

**PR shape:**
- Planner/renderer/host refactor focused on incremental text only

**Primary files:**
- Modify: `Sources/TerminalUI/TerminalPresentation.swift`
- Modify: `Sources/TerminalUI/TerminalHost.swift`
- Modify: `Tests/TerminalUITests/TerminalPresentationTests.swift`
- Modify: `Tests/TerminalUITests/TerminalHostPresentationBatchingTests.swift`
- Modify: `Tests/TerminalUITests/Phase1PresentationIntegrationTests.swift`

**Work:**
- Introduce the row-batch representation.
- Convert `SpanUpdate` planning either into row batches directly or into a lowering step from spans
  to batches.
- Keep style and hyperlink state local to the batch encoder.
- Update host assembly so it writes the batch payload without re-planning segments.

**Merge gate:**
- Multi-segment row updates emit fewer bytes than the old per-span path.
- Hyperlink and style-order tests pass unchanged or are updated only to reflect the new, intentionally
  better write shape.

**Rollback stance:**
- If style/hyperlink stability is not yet solid, keep the richer damage model and defer batching.

- [ ] **Wave 5: Synchronized repaint framing**

**Objective:** Add synchronized-output envelopes around repaints and any future large incremental
batches where warranted.

**Covers units:** Unit 4

**PR shape:**
- Capability and host framing work, plus tests and docs

**Primary files:**
- Modify: `Sources/TerminalUI/TerminalPresentation.swift`
- Modify: `Sources/TerminalUI/TerminalHost.swift`
- Modify: `Tests/TerminalUITests/TerminalPresentationTests.swift`
- Modify: `Tests/TerminalUITests/TerminalHostPresentationBatchingTests.swift`
- Modify: `docs/proposals/ASYNC_PRESENTATION.md`
- Modify: `docs/RUNTIME.md`

**Work:**
- Add synchronized-output support detection.
- Envelope full-repaint writes in the host submission path.
- Ensure drain/shutdown behavior cannot leave the terminal mid-envelope.

**Merge gate:**
- Supported terminals get exactly one synchronized-output envelope around the intended payload.
- Unsupported terminals preserve current behavior.

**Rollback stance:**
- Revert independently if terminal compatibility is worse than expected; no other wave should depend
  on synchronized-output support.

- [ ] **Wave 6: Graphics/text planning split**

**Objective:** Keep text diffing incremental even when graphics placement changes and reduce
unnecessary image replay.

**Covers units:** Unit 5

**PR shape:**
- Planner/host/image-renderer change with heavy graphics regression coverage

**Primary files:**
- Modify: `Sources/TerminalUI/TerminalPresentation.swift`
- Modify: `Sources/TerminalUI/TerminalHost.swift`
- Modify: `Sources/TerminalUI/TerminalImageRendering.swift`
- Modify: `Tests/TerminalUITests/TerminalGraphicsProtocolTests.swift`
- Modify: `Tests/TerminalUITests/TerminalPresentationTests.swift`

**Work:**
- Split compatibility checks into text compatibility and graphics compatibility.
- Add a graphics delta representation.
- Narrow Kitty re-placement scope where overlap and attachment-delta reasoning is explicit.

**Merge gate:**
- Text-only updates with stable images stay incremental.
- Graphics protocol tests prove no image drift or disappearance.

**Rollback stance:**
- If targeted replay is not yet trustworthy, keep the text/graphics split but widen graphics replay
  back to the current all-visible-attachments behavior.

- [ ] **Wave 7: Terminal-native edit-op lowering**

**Objective:** Add a bounded optimization tier for common mutations after the core model is stable.

**Covers units:** Unit 6

**PR shape:**
- Optional optimization PR, explicitly non-blocking for the rest of the roadmap

**Primary files:**
- Modify: `Sources/TerminalUI/TerminalPresentation.swift`
- Modify: `Sources/TerminalUI/TerminalHost.swift`
- Modify: `Tests/TerminalUITests/TerminalPresentationTests.swift`
- Modify: `Tests/TerminalUITests/Phase1PresentationIntegrationTests.swift`

**Work:**
- Detect a small safe subset of transformations for `EL`/`ECH` and possibly row insert/delete ops.
- Keep a kill-switch or local disable path while behavior is being proven.

**Merge gate:**
- Visible output matches the non-optimized path exactly.
- Targeted benchmarks show a real byte reduction on the covered patterns.

**Rollback stance:**
- Fully optional. Defer rather than forcing it into the critical-path refactor.

- [ ] **Wave 8: Diagnostics, docs, and steady-state hardening**

**Objective:** Make the new paint path legible, measurable, and maintainable once the behavior has
settled.

**Covers units:** Unit 7

**PR shape:**
- Diagnostics and documentation cleanup, plus any final benchmark updates

**Primary files:**
- Modify: `Sources/Core/CommitAndFrameTypes.swift`
- Modify: `Tests/TerminalUITests/Phase1BenchmarkScenariosTests.swift`
- Modify: `Tests/TerminalUITests/Phase5ReliabilityGatesTests.swift`
- Modify: `docs/RUNTIME.md`
- Modify: `docs/SOURCE_LAYOUT.md`
- Modify: `docs/TESTING_AND_FIXTURE_POLICY.md`

**Work:**
- Add final diagnostics fields for synchronized framing, graphics replay scope, and damage precision.
- Update docs so future contributors understand the new tail architecture.
- Remove transitional toggles or compatibility shims introduced during earlier waves.

**Merge gate:**
- Documentation matches implementation.
- Benchmark and reliability suites encode the new steady-state expectations.

**Rollback stance:**
- Cleanup-only; safe to adjust in follow-up PRs if wording or diagnostics evolve.

### Suggested PR Sequence

1. `paint-path baseline characterization`
2. `presentation full-repaint ownership cleanup`
3. `rich presentation damage model`
4. `raster touched-span refinement`
5. `row-batched incremental text encoding`
6. `synchronized output support for repaint framing`
7. `split text and graphics presentation planning`
8. `optional terminal edit-op lowering`
9. `paint-path diagnostics and docs hardening`

### Per-Wave Verification Cadence

Every wave that changes runtime behavior should verify all of the following:

- planner correctness:
  `Tests/TerminalUITests/TerminalPresentationTests.swift`
- host write shape and dropped-frame recovery:
  `Tests/TerminalUITests/TerminalHostPresentationBatchingTests.swift`
- whole-path incremental scenarios:
  `Tests/TerminalUITests/Phase1PresentationIntegrationTests.swift`
- work-shape and incremental gates:
  `Tests/TerminalUITests/Phase1BenchmarkScenariosTests.swift`

Waves that touch graphics must also verify:

- `Tests/TerminalUITests/TerminalGraphicsProtocolTests.swift`

Waves that modify host shutdown or writer framing should additionally verify:

- any raw-mode lifecycle or interactive-host tests already covering reset/drain behavior

### Hold Points

Stop and reassess before proceeding to the next wave if any of these occur:

- a previously incremental scenario becomes full repaint without an intentional, documented reason
- wide-glyph or continuation-cell tests start failing under hinted damage
- graphics placement requires broadening replay scope beyond what the wave intended
- synchronized output support introduces terminal-compatibility uncertainty
- benchmark assertions show more bytes written for localized edits after a supposed optimization

If a hold point is hit, prefer:

1. widening or disabling the new optimization path
2. landing supporting diagnostics
3. revisiting the narrower optimization in a later PR

## Implementation Units

- [ ] **Unit 1: Unify full-repaint ownership and simplify presentation planning**

**Goal:** Remove duplicated full-repaint rendering work and make the plan/host boundary represent
what the host will actually write.

**Requirements:** R1, R3, R4

**Dependencies:** None

**Files:**
- Modify: `Sources/TerminalUI/TerminalPresentation.swift`
- Modify: `Sources/TerminalUI/TerminalHost.swift`
- Modify: `Tests/TerminalUITests/TerminalPresentationTests.swift`
- Modify: `Tests/TerminalUITests/TerminalHostPresentationBatchingTests.swift`

**Approach:**
- Refactor `TerminalPresentationPlan` so full repaint is owned by exactly one layer.
- Remove the current split where the planner computes `renderedOutput` while the host recomputes
  full repaint rows via `fullRepaintWriteSteps(...)`.
- Prefer one of these shapes:
  - planner emits a full repaint write script and the host only appends graphics and framing
  - planner emits structural repaint steps and the host is solely responsible for materializing the
    text payload
- Keep `TerminalPresentationMetrics` behavior stable while changing the ownership model underneath.

**Patterns to follow:**
- Existing planner/host split in `TerminalPresentation.swift` and `TerminalHost.swift`
- Current batching tests in
  `Tests/TerminalUITests/TerminalHostPresentationBatchingTests.swift`

**Test scenarios:**
- First presentation still produces the same visible full repaint payload as before.
- Resize fallback still produces a safe full repaint.
- Dropped-frame recovery still forces a full repaint, but only one full-frame render path executes.
- Metrics remain consistent with the bytes actually submitted.

**Verification:**
- There is no production path that renders a full frame once in the planner and again in the host.
- Full repaint tests pass with unchanged visible output expectations unless intentionally updated for
  a new single-owner encoding shape.

- [ ] **Unit 2: Replace row-only `PresentationDamage` with a richer damage model**

**Goal:** Preserve more locality from invalidation and placement into the paint tail so the
  presentation stage does not need to rediscover narrow changes from full-width row scans.

**Requirements:** R1, R2, R4, R6

**Dependencies:** Unit 1

**Files:**
- Modify: `Sources/Core/CommitAndFrameTypes.swift`
- Modify: `Sources/TerminalUI/TerminalUI.swift`
- Modify: `Sources/Core/Rasterizer.swift`
- Modify: `Tests/TerminalUITests/TerminalPresentationTests.swift`
- Modify: `Tests/TerminalUITests/Phase1BenchmarkScenariosTests.swift`

**Approach:**
- Replace `dirtyRows: Set<Int>` with a richer package-level damage type that can represent at least:
  - text row ranges or per-row spans
  - optional graphics-specific invalidation
  - explicit full-repaint fallback flags
- Keep the producer cheap:
  `DefaultRenderer.presentationDamage(...)` should continue using retained placement information, but
  instead of reducing bounds to rows only, preserve the horizontal extent of previous and current
  placed bounds.
- Let the rasterizer accept the richer damage model and either:
  - use it directly to clear only candidate spans, or
  - retain row clearing internally but record actual touched spans while repainting nodes
- Prefer monotonic safety: when the runtime cannot prove narrow damage, it should widen the damage or
  drop back to the existing full-row/full-frame behavior.

**Execution note:** Start characterization-first for current incremental scenarios so the richer
damage model does not silently widen work volume.

**Technical design:** *(directional guidance, not implementation specification)*

```text
PresentationDamage
  textRows: [Int: [Range<Int>]]   // merged, normalized, package-only
  graphicsInvalidation: Set<Identity>
  requiresFullTextRepaint: Bool
  requiresFullGraphicsReplay: Bool
```

**Patterns to follow:**
- Current conservative fallback rules in `TerminalUI.presentationDamage(...)`
- Current raster reuse behavior in `Rasterizer.rasterizeCollectingVisibleIdentities(...)`

**Test scenarios:**
- Mid-row text edits carry a narrower damage hint than a whole-row invalidation.
- Bounds changes that move a control horizontally but not vertically preserve column locality.
- Unstable sibling bounds still trigger safe widening or full fallback.
- Existing wide-glyph normalization tests continue to pass under hinted damage.

**Verification:**
- Incremental planner inputs contain more precise damage than `Set<Int>` rows alone.
- Previously passing incremental tests still pass, and new benchmark assertions show equal or lower
  `cellsChanged` and `bytesWritten` for localized updates.

- [ ] **Unit 3: Introduce row-batched, stateful incremental text encoding**

**Goal:** Reduce terminal bytes and repeated escape-sequence churn by encoding incremental text
updates as row-oriented batches with shared style state rather than isolated span strings.

**Requirements:** R1, R2, R5

**Dependencies:** Unit 2

**Files:**
- Modify: `Sources/TerminalUI/TerminalPresentation.swift`
- Modify: `Sources/TerminalUI/TerminalHost.swift`
- Modify: `Tests/TerminalUITests/TerminalPresentationTests.swift`
- Modify: `Tests/TerminalUITests/TerminalHostPresentationBatchingTests.swift`
- Modify: `Tests/TerminalUITests/Phase1PresentationIntegrationTests.swift`

**Approach:**
- Replace or supplement `SpanUpdate` with a row-batch representation that groups ordered changed
  segments under one row anchor.
- Teach `TerminalSurfaceRenderer` to encode a row batch while carrying active style and hyperlink
  state across adjacent segments.
- Preserve continuation-cell and wide-glyph normalization. The batching layer must not split across a
  glyph boundary even if the damage model proposes multiple nearby spans.
- Keep the host dumb where possible: once the planner has produced a row batch, the host should only
  append cursor movement and payload framing, not re-plan segment layout.

**Technical design:** *(directional guidance, not implementation specification)*

```text
IncrementalTextRowBatch
  row: Int
  anchorColumn: Int
  segments:
    - relativeColumnOffset
    - renderedText
    - cellsChanged
```

**Patterns to follow:**
- Existing `diffSpans`, `normalizeSpan`, and `renderSpan` logic
- Existing tests that assert narrow incremental writes rather than full repaints

**Test scenarios:**
- Two spans on the same row are emitted as one row-batched payload when safe.
- Style transitions within a row batch emit correct resets and do not leak into later segments.
- Hyperlink transitions remain self-contained and valid when multiple segments share a row batch.
- Shrinking text still clears trailing cells correctly.

**Verification:**
- Multi-span row updates produce fewer bytes than the current “cursor move + renderedSpan per span”
  shape.
- Existing correctness tests for styles, hyperlinks, and wide glyphs continue to pass.

- [ ] **Unit 4: Add capability-gated synchronized output framing**

**Goal:** Prevent repaint tearing on terminals that support synchronized output, especially on full
repaints and dropped-frame recovery.

**Requirements:** R2, R3, R5

**Dependencies:** Unit 1

**Files:**
- Modify: `Sources/TerminalUI/TerminalPresentation.swift`
- Modify: `Sources/TerminalUI/TerminalHost.swift`
- Modify: `Tests/TerminalUITests/TerminalPresentationTests.swift`
- Modify: `Tests/TerminalUITests/TerminalHostPresentationBatchingTests.swift`
- Modify: `docs/proposals/ASYNC_PRESENTATION.md`
- Modify: `docs/RUNTIME.md`

**Approach:**
- Extend terminal capability representation to include synchronized-output support or a package-only
  equivalent used by the host.
- Decide during implementation whether support is static, probed, or hybrid.
- Wrap full repaint payloads in synchronized begin/end sequences when supported.
- Optionally wrap large incremental payloads too, but only if the host can do so without harming
  unsupported terminals or multiplexers.
- Ensure batching and async writer behavior remain unchanged semantically: synchronized framing is a
  write-envelope concern, not a planning concern.

**Patterns to follow:**
- Existing capability-profile detection style in `TerminalPresentation.swift`
- Async writer and drop-recovery model in `TerminalHost.swift`

**Test scenarios:**
- Supported-capability hosts wrap repaint payloads in begin/end synchronized-output markers.
- Unsupported-capability hosts preserve the current payload shape.
- Drop recovery still forces full repaint and now benefits from synchronized framing where enabled.
- Raw-mode shutdown drains pending frames and does not leave synchronized mode unterminated.

**Verification:**
- Repaint writes are framed exactly once when synchronized output is enabled.
- Proposal and runtime documentation agree on the implemented behavior.

- [ ] **Unit 5: Separate text planning from graphics placement planning**

**Goal:** Prevent graphics attachment changes from unnecessarily forcing text full repaints and limit
graphics replay to affected attachments.

**Requirements:** R1, R2, R3

**Dependencies:** Unit 2, Unit 3

**Files:**
- Modify: `Sources/TerminalUI/TerminalPresentation.swift`
- Modify: `Sources/TerminalUI/TerminalHost.swift`
- Modify: `Sources/TerminalUI/TerminalImageRendering.swift`
- Modify: `Tests/TerminalUITests/TerminalGraphicsProtocolTests.swift`
- Modify: `Tests/TerminalUITests/TerminalPresentationTests.swift`

**Approach:**
- Split surface compatibility checks into:
  - text-surface compatibility
  - graphics-placement compatibility
- Allow the planner to keep incremental text updates when text cells remain diffable even if image
  attachment placement changed.
- Add a graphics delta representation so the host can request placement writes only for changed or
  text-overlapped attachments.
- Preserve the existing safe fallback where a graphics mismatch can still escalate to a full replay
  when attachment identity, bounds, or protocol constraints make narrower recovery unsafe.
- Restrict Kitty re-placement after incremental text writes to attachments intersecting changed text
  rows or explicitly dirtied graphics placement records.

**Execution note:** Add characterization coverage first for current Kitty behavior, since image
placement correctness is easier to regress than plain text diffing.

**Patterns to follow:**
- Existing `preparedSurface(...)` and `graphicsWriteSteps(...)` ordering in
  `TerminalImageRendering.swift`
- Current graphics tests in `TerminalGraphicsProtocolTests.swift`

**Test scenarios:**
- Text-only incremental changes with stable image attachments do not force a full repaint.
- Incremental text writes re-place only intersecting Kitty attachments when safe.
- Attachment-bounds changes can trigger graphics replay without poisoning text diffing.
- Sixel and fallback image modes preserve existing visual ordering semantics.

**Verification:**
- Planner compatibility logic distinguishes text and graphics concerns.
- Graphics protocol tests continue to pass with narrower write scopes where expected.

- [ ] **Unit 6: Add optional terminal-native edit-op lowering**

**Goal:** Introduce a second-stage optimization tier for common terminal mutations such as tail clears
or row insertion/deletion once the richer damage and batched encoding model is in place.

**Requirements:** R1, R3, R6

**Dependencies:** Unit 3

**Files:**
- Modify: `Sources/TerminalUI/TerminalPresentation.swift`
- Modify: `Sources/TerminalUI/TerminalHost.swift`
- Modify: `Tests/TerminalUITests/TerminalPresentationTests.swift`
- Modify: `Tests/TerminalUITests/Phase1PresentationIntegrationTests.swift`

**Approach:**
- Add a lowering stage that detects a small set of safe transformations:
  - trailing text shrink -> erase/clear op instead of literal spaces where capabilities permit
  - simple scroll-like row shifts -> insert/delete line or scroll-region style ops, only when the
    current host semantics make them unambiguous
- Keep this feature gated and optional. The system should always be able to fall back to literal text
  painting if the opcode optimization is unsupported or hard to prove safe.
- Defer any terminal-specific micro-optimizations that materially complicate correctness around wide
  glyphs, graphics placement, or alternate-screen state.

**Patterns to follow:**
- Existing conservative fallback philosophy in the presentation planner
- Existing integration tests that assert incremental writes are smaller than full repaints

**Test scenarios:**
- Trailing-tail deletes produce the same final visible surface as literal space repainting.
- Scroll-like row shifts still remain incremental and correct.
- Unsupported terminals or disabled optimization mode preserve the prior paint behavior.

**Verification:**
- The optimization can be disabled without affecting correctness.
- Incremental write size decreases measurably for the targeted patterns.

- [ ] **Unit 7: Expand diagnostics, benchmarks, and documentation around paint-path behavior**

**Goal:** Make regressions in paint precision visible and keep the intended behavior legible to
future contributors.

**Requirements:** R5

**Dependencies:** Units 1-6 as implemented

**Files:**
- Modify: `Sources/Core/CommitAndFrameTypes.swift`
- Modify: `Tests/TerminalUITests/Phase1BenchmarkScenariosTests.swift`
- Modify: `Tests/TerminalUITests/Phase5ReliabilityGatesTests.swift`
- Modify: `docs/RUNTIME.md`
- Modify: `docs/SOURCE_LAYOUT.md`
- Modify: `docs/TESTING_AND_FIXTURE_POLICY.md`

**Approach:**
- Add diagnostics that expose:
  - candidate damage width/rows vs actual emitted width/rows
  - whether synchronized output was used
  - whether graphics replay was full or targeted
  - whether an edit-op lowering path was chosen
- Extend benchmark scenarios so they express paint-shape expectations, not just whether something was
  incremental.
- Update documentation to reflect the new tail architecture and any sanctioned fallback cases.

**Patterns to follow:**
- Existing diagnostics summarization in `FrameDiagnostics`
- Existing performance gates in `Phase1BenchmarkScenariosTests.swift`
- Existing policy language in `docs/TESTING_AND_FIXTURE_POLICY.md`

**Test scenarios:**
- Idle rerender still converges to zero output.
- Single-character edits, focused button presses, and scroll steps remain incremental.
- New targeted graphics paths are reflected in deterministic metrics.
- Previously incremental cases do not silently become full repaints without documented cause.

**Verification:**
- The repo has documentation for the final paint path that matches the implementation.
- Benchmark and reliability suites catch widened fallbacks or byte-volume regressions deterministically.

## System-Wide Impact

- **Interaction graph:** This work primarily affects the render tail, but it crosses `DefaultRenderer`,
  `Rasterizer`, `TerminalPresentationPlanner`, `TerminalHost`, `TerminalImageRenderer`, and the async
  writer recovery path.
- **Error propagation:** Write errors should continue surfacing through the writer’s pending-error
  mechanism; synchronized framing and new batch types must not swallow or defer errors differently.
- **State lifecycle risks:** The biggest lifecycle risk is drift between what the host thinks the
  terminal shows and what was actually written. Drop recovery and graphics replay must preserve the
  current “force full repaint after loss of certainty” rule.
- **API surface parity:** Keep public APIs stable unless implementation proves that a package-only
  type boundary is insufficient. Most changes should remain in package/internal runtime seams.
- **Integration coverage:** Unit tests on planner types are insufficient by themselves. Cross-layer
  tests must assert actual buffered writes for full repaint, incremental text, graphics placement, and
  dropped-frame recovery.

## Risk Analysis & Mitigation

- **Risk:** Richer damage becomes unsound and causes stale pixels.
  Mitigation: maintain monotonic safety. Any uncertainty widens damage or forces the existing
  fallback behavior.

- **Risk:** Row-batched encoding introduces style or hyperlink leakage across segments.
  Mitigation: add explicit tests around style resets, OSC 8 open/close ordering, and wide-glyph
  boundaries before enabling aggressive batching.

- **Risk:** Synchronized output support behaves differently under multiplexers.
  Mitigation: capability-gate conservatively and keep the feature envelope separate from paint logic
  so it can be disabled without touching planner semantics.

- **Risk:** Graphics/text decoupling causes image drift after incremental writes.
  Mitigation: start with characterization tests for current Kitty behavior, then narrow replay scope
  only where overlap and placement reasoning are explicit.

- **Risk:** Terminal-native edit ops make the paint path too complex too early.
  Mitigation: keep Unit 6 optional and land it only after the core data-model and encoder
  improvements have stabilized.

## Documentation / Operational Notes

- `docs/RUNTIME.md` should be updated to describe the richer damage path and synchronized repaint
  behavior once implemented.
- `docs/SOURCE_LAYOUT.md` should reflect any reallocation of planner/host responsibilities.
- `docs/TESTING_AND_FIXTURE_POLICY.md` should explicitly mention targeted graphics replay if it
  becomes part of the supported incremental contract.
- If synchronized output support is added, the compatibility expectations for terminals and
  multiplexers should be documented at the host/capability level.

## Alternative Approaches Considered

- Keep the current row-only damage model and optimize only host-side string assembly.
  Rejected because it preserves the largest wasted work source: rediscovering narrow spans from
  full-width dirty rows.

- Push terminal-native edit ops first.
  Rejected because edit ops sit at the very end of the pipeline and do not solve the upstream
  information loss that currently limits the final painting algorithm.

- Move image placement into the raster surface itself so text and graphics always share one diffing
  model.
  Rejected for now because the repo already models protocol-backed images as terminal escape-sequence
  side effects rather than cells. Forcing them into the raster model would be a larger architectural
  shift than the user asked for.

## Sources & References

- Related code:
  [Sources/TerminalUI/TerminalUI.swift](/Users/adamz/Developer/repos/swift-terminal-ui/Sources/TerminalUI/TerminalUI.swift:269)
- Related code:
  [Sources/Core/CommitAndFrameTypes.swift](/Users/adamz/Developer/repos/swift-terminal-ui/Sources/Core/CommitAndFrameTypes.swift:657)
- Related code:
  [Sources/Core/Rasterizer.swift](/Users/adamz/Developer/repos/swift-terminal-ui/Sources/Core/Rasterizer.swift:74)
- Related code:
  [Sources/TerminalUI/TerminalPresentation.swift](/Users/adamz/Developer/repos/swift-terminal-ui/Sources/TerminalUI/TerminalPresentation.swift:308)
- Related code:
  [Sources/TerminalUI/TerminalHost.swift](/Users/adamz/Developer/repos/swift-terminal-ui/Sources/TerminalUI/TerminalHost.swift:865)
- Related code:
  [Sources/TerminalUI/TerminalImageRendering.swift](/Users/adamz/Developer/repos/swift-terminal-ui/Sources/TerminalUI/TerminalImageRendering.swift:131)
- Related tests:
  [Tests/TerminalUITests/TerminalPresentationTests.swift](/Users/adamz/Developer/repos/swift-terminal-ui/Tests/TerminalUITests/TerminalPresentationTests.swift:321)
- Related tests:
  [Tests/TerminalUITests/TerminalHostPresentationBatchingTests.swift](/Users/adamz/Developer/repos/swift-terminal-ui/Tests/TerminalUITests/TerminalHostPresentationBatchingTests.swift:15)
- Related tests:
  [Tests/TerminalUITests/TerminalGraphicsProtocolTests.swift](/Users/adamz/Developer/repos/swift-terminal-ui/Tests/TerminalUITests/TerminalGraphicsProtocolTests.swift:347)
- Related proposal:
  [docs/proposals/ASYNC_PRESENTATION.md](/Users/adamz/Developer/repos/swift-terminal-ui/docs/proposals/ASYNC_PRESENTATION.md:166)
