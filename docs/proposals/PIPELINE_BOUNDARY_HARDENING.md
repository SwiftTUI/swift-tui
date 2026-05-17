# Pipeline Boundary Hardening

## Status

Implemented in the durable docs and focused boundary tests. The current
source-of-truth ownership model lives in
[`ARCHITECTURE.md`](../ARCHITECTURE.md#important-data-products), source
ownership anchors live in [`SOURCE_LAYOUT.md`](../SOURCE_LAYOUT.md), and the
async frame-tail vocabulary lives in
[`ASYNC_RENDERING.md`](../ASYNC_RENDERING.md#current-contract).

This proposal remains as background for the staged reasoning that led to the
current contracts.

This document proposes a direction for hardening SwiftTUI's frame pipeline
boundaries. It is intentionally not a step-by-step implementation plan. The
goal is to define the end state clearly enough that future slices can move in
the same direction, while leaving each slice free to choose the smallest safe
implementation that the codebase supports.

## Context

The frame pipeline is one of the repo's central contracts:

```text
resolve -> measure -> place -> semantics -> draw -> raster -> commit
```

That split is visible in `DefaultRenderer`, `FrameTailRenderer`, `Renderer`,
`FrameArtifacts`, and the phase-specific products:

- `ResolvedNode`
- `MeasuredNode`
- `PlacedNode`
- `SemanticSnapshot`
- `DrawNode`
- `RasterSurface`
- `CommitPlan`

The split has held up well. It lets tests point at the right abstraction,
keeps terminal presentation concerns out of layout and semantics, and gives
runtime diagnostics a useful vocabulary for "computed" versus "reused" work.
The hardening work should protect that split, not collapse it.

The recent placed metadata work closed one concrete gap: retained placement can
reuse cached geometry while still synchronizing current resolved metadata into
the placed tree. The final conservative shape was important. `PlacedNode` now
routes that synchronization through `PlacedNodeResolvedMetadata`, but it keeps
the existing physical storage layout because placing large boxed metadata under
a new stored aggregate exposed stack-safety and lifetime risk. That result is
useful guidance for the broader effort: the destination is clearer ownership
and safer boundaries, not type reshaping for its own sake.

## Problem

Several pipeline products necessarily carry information that originated in an
earlier phase. Some of that is legitimate: later phases need a stable snapshot
of style, semantic metadata, draw payloads, lifecycle hooks, geometry, or host
state. Some of it is cache policy: retained layout needs previous resolved,
measured, and placed products to decide whether work can be reused. Some of it
is transitional: a field may have started as a convenient mirror and then become
observable by another subsystem.

The risk is not duplication by itself. The risk is unspecific duplication:

- a field exists in more than one phase product without a named owner,
- a retained-reuse predicate ignores a field but no synchronizer refreshes it,
- a downstream phase reads an upstream mirror without tests proving freshness,
- a field is part geometry, part semantics, and part draw policy,
- a cache indexes a decorated product when it meant to index the canonical
  product, or
- a storage cleanup changes stack-safety or copy behavior while trying to make
  types look cleaner.

The current code has already solved pieces of this locally:

- `NodeLayoutInfo` groups layout-relevant metadata for measurement cache use.
- `PlacedNodeResolvedMetadata` groups the resolved metadata transferred into
  placed nodes.
- `FrameTailRetainedState.storeCommittedFrame` explicitly stores the baseline
  placed tree rather than the animation-decorated placed tree.
- `FrameTailInput`, `FrameTailLayoutOutput`, and `FrameTailOutput` name the
  async frame-tail boundary even though those types are implementation details.
- late preference reconciliation folds layout-realized resolved content back
  into the committed resolved tree before semantics, draw, raster, and commit.

Those are good local patterns, but there is not yet one repo-wide rule for how
phase products should own, mirror, project, or cache data.

## Vision

The end state should be a pipeline whose products have explicit contracts:

- Each phase product has a short description of what it owns, what it derives,
  and what it deliberately carries forward.
- Any duplicated field is classified as one of:
  - authoritative state,
  - derived projection,
  - retained-cache key,
  - presentation or host snapshot,
  - diagnostic artifact, or
  - transitional compatibility.
- Every projection across a phase boundary has one named construction or
  synchronization path.
- Retained reuse can safely ignore geometry-stable fields only when a refresh
  path proves the downstream product is still current.
- Transient animation overlays are kept separate from canonical layout products
  unless the code explicitly says a decorated product is wanted.
- Phase diagnostics continue to identify where work happened, where it was
  reused, and where a fallback path ran.
- Stack-safety and value-semantics tests guard any storage reshaping.

In that destination, reading a phase product should answer two questions
quickly:

1. Why is this field here?
2. If this field originated earlier, which boundary updates it and which tests
   prove it stays fresh under reuse?

The target is not a "pure" tree per phase at any cost. Some cross-phase
snapshots are the right representation. The target is that every snapshot has a
name, an owner, and a freshness story.

## Non-Goals

- Do not collapse the seven phases.
- Do not move authored `View.body`, dynamic-property evaluation, runtime
  registration mutation, lifecycle, or commit side effects off the main actor as
  part of this effort.
- Do not make public API changes unless a later, separately reviewed change
  needs them.
- Do not replace retained layout, async frame-tail rendering, or animation
  overlay handling wholesale.
- Do not treat "less duplicated data" as automatically better than "explicit
  mirrored data with a tested sync path".
- Do not add locks or reference storage only to make a phase product look
  smaller.

## Current Boundary Map

### Resolve Output

`ResolvedNode` is the richest phase product. It owns the lowered structure plus
environment, transaction, layout behavior, layout metadata, draw metadata,
semantic metadata, lifecycle metadata, draw payload, preferences, retained-reuse
eligibility, indexed-child-source hooks, layout-dependent content, transient
state, and matched-geometry configuration.

That breadth is expected because resolve is the point where authored view state,
environment, modifiers, handlers, and runtime registrations are gathered into a
value-shaped tree. The hardening question is which fields should remain
authoritative here, which should be projected into later products, and which
equivalence predicates need named subsets.

Existing named subsets:

- `NodeLayoutInfo` for layout-relevant metadata.
- `NodeSemanticInfo` for semantic metadata access.
- `NodeDrawInfo` for draw metadata and payload access.
- `NodeLifecycleInfo` for lifecycle metadata access.

### Measure Output

`MeasuredNode` is comparatively clean. It owns proposal, measured size,
children, and container allocation snapshots. Lazy-stack allocation data lives
here because placement needs measurement-time allocation decisions.

The main hardening question is not field ownership; it is cache identity. The
measurement cache relies on `ResolvedNode.isEquivalentForMeasurement`, which is
allowed to ignore visual-only changes but must not ignore anything that changes
measurement. Any future reduction here should be evidence-driven and guarded by
measurement-cache tests.

### Place Output

`PlacedNode` owns final bounds, content bounds, clipping, z-index, child
placement, subtree counts, semantic role, and the current resolved metadata
that semantics, draw, lifecycle, and animation need after placement.

The recent hardening slice made the projection from `ResolvedNode` to
`PlacedNode` explicit through `PlacedNodeResolvedMetadata`. It did not make
that grouped metadata the stored representation. That should remain acceptable
unless a future slice proves a stored aggregate is safe under deep-tree,
copy-on-write, and frame-artifact destruction tests.

The next questions around placement are:

- whether all later consumers really need to read from `PlacedNode`, or whether
  some should receive a narrower projection,
- whether retained placement's equivalence predicates and synchronizers are
  fully paired, and
- whether baseline placement versus animation-decorated placement is named
  consistently at every cache boundary.

### Semantics Output

`SemanticSnapshot` owns runtime routing products: interaction regions, focus
regions, navigation routes, scroll routes, selection routes, named coordinate
spaces, accessibility nodes, live announcements, and accessibility warnings.

It is a derived product, not a metadata carrier. Its hardening work should
focus on extraction inputs and route freshness:

- semantic extraction reads placed geometry plus semantic, layout, draw, and
  environment metadata,
- transient nodes must be filtered consistently,
- interaction gates and disabled state must be reflected at route generation,
  not patched later, and
- route geometry must match the committed placed tree, including after retained
  layout reuse and late preference reconciliation.

### Draw Output

`DrawNode` owns draw commands, post-commands, draw metadata, environment
snapshot, bounds, clipping, and children.

This is another projection boundary. Draw extraction converts a placed tree into
an explicit paint tree, but rasterization still needs style and environment
snapshots for command painting. The hardening question is whether `DrawNode`
should keep broad metadata or whether some command forms should capture more of
their own resolved paint inputs. That question should be answered by concrete
raster/readability/performance evidence, not by a blanket rule.

### Raster Output

`RasterSurface` owns the final cell grid and style runs. It should stay below
layout, semantics, and draw policy. Presentation capability adaptation and
terminal-control sanitization remain presentation-boundary work, not raster
work.

The raster hardening question is mostly around retained previous-surface reuse,
presentation damage, and drawn-identity diagnostics: those outputs should be
classified as presentation hints or diagnostics, not as new sources of layout
or semantic truth.

### Commit Output

`CommitPlan` packages semantic, lifecycle, and handler-installation work for
the runtime. Commit remains a main-actor boundary because `ViewGraph`
finalization, registration restoration, lifecycle, tasks, focus, and
presentation side effects are ordered runtime work.

Hardening here should make preview commit, candidate commit, completed-frame
drop, and actual commit easier to reason about. In particular, a completed
frame that is dropped as visual-only must not leak registration, lifecycle, or
retained-baseline side effects.

## Proposed Approach

### 1. Start With An Inventory, Not A Refactor

Build a short phase-boundary inventory before changing more storage. For each
phase product, record:

- authoritative fields,
- fields projected from earlier phases,
- downstream consumers,
- retained-cache predicates that include or ignore the field,
- synchronizers or constructors that refresh the field, and
- focused tests that would fail if the field went stale.

The inventory can live in this proposal at first or graduate into
`ARCHITECTURE.md` / `SOURCE_LAYOUT.md` once the vocabulary settles. The
important outcome is shared language before broader edits.

### 2. Define Boundary Contracts Incrementally

For each boundary, add or tighten a named contract:

- resolved -> measured: measurement equivalence and layout metadata inputs,
- resolved -> placed: placement equivalence plus resolved-metadata
  synchronization,
- placed -> semantics: route extraction inputs and transient/filter policy,
- placed -> draw: draw projection inputs and command ownership,
- draw -> raster: paint inputs, clipping, and surface damage,
- artifacts -> retained state: canonical baseline versus decorated products,
- tail candidate -> commit: side-effect ordering and drop eligibility.

These contracts should initially be small comments, helper types, or tests in
the existing files. A contract only needs a new abstraction when the existing
shape makes the invariant hard to express.

### 3. Pair Every Relaxed Equivalence With A Freshness Proof

Retained reuse is where boundary mistakes are most expensive. A relaxed
equivalence predicate is useful only if the ignored data either truly does not
matter downstream or is refreshed before a downstream phase observes it.

Future hardening should make this pairing explicit:

- measurement equivalence can ignore visual-only draw inputs when measurement
  is unaffected,
- placement equivalence can ignore geometry-stable metadata when placement is
  unaffected,
- retained placement must synchronize the current metadata onto reused placed
  nodes,
- retained frame state must cache baseline layout products, not transient
  overlays, and
- completed-frame drop policy must not discard side-effect-bearing candidates.

Each new or relaxed predicate should land with a mutation test that changes an
ignored field and proves the downstream phase either remains unaffected or sees
the refreshed value.

### 4. Prefer Projections Before Storage Reshaping

The `PlacedNodeResolvedMetadata` result should guide the rest of the work. A
named projection value can clarify a boundary without immediately changing the
physical storage of a hot tree type.

The default sequence should be:

1. Name the projection.
2. Route construction or synchronization through it.
3. Add freshness, value-semantics, and stack-safety coverage.
4. Only then consider whether the projection should become stored
   representation.

That sequence keeps the architecture moving toward clearer types while avoiding
large hidden changes to copy cost, destructor behavior, and deep-tree stack use.

### 5. Keep Async Frame-Tail Boundaries In The Same Model

Async rendering should be treated as a consumer of the same phase contracts, not
as a parallel architecture. `FrameHeadDraft`, `FrameTailInput`,
`FrameTailLayoutOutput`, `FrameTailOutput`, and `CompletedFrameCandidate` are
already boundary products. They should be reviewed with the same questions:

- Which data is canonical?
- Which data is a snapshot for worker safety?
- Which data is a diagnostic?
- Which data is safe to discard?
- Which side effects are only previewed versus actually committed?

This is especially important around late preference reconciliation, worker
custom-layout cache updates, retained frame state, completed-frame dropping, and
main-actor fallback diagnostics.

### 6. Let Tests Describe The Boundary

The hardening suite should be built from small tests that name the boundary they
protect. Useful categories:

- retained measurement ignores a visual-only change and still measures
  correctly,
- retained placement ignores a geometry-stable change and refreshes downstream
  metadata,
- semantic extraction sees current accessibility and interaction metadata after
  retained placement reuse,
- draw extraction sees current style and payload after retained placement reuse,
- lifecycle commit sees current lifecycle metadata while transient overlays are
  excluded,
- baseline retained placement does not persist animation overlays,
- completed visual-only drops do not commit lifecycle or registration changes,
- deep trees remain stack-safe after any storage reshaping, and
- async and sync render paths produce equivalent artifacts for the same eligible
  frame.

Broad integration and gallery-path tests still matter, but each hardening slice
should have at least one focused test that fails at the boundary being changed.

### 7. Update Docs With Each Landed Boundary

When a hardening slice lands, update the durable docs at the same time:

- `ARCHITECTURE.md` for phase ownership and conceptual contracts,
- `SOURCE_LAYOUT.md` for file-level ownership changes,
- `ASYNC_RENDERING.md` when frame-head or frame-tail ownership changes,
- `PERFORMANCE_EVALUATION.md` when a change needs perf evidence, and
- `TODO.md` / `CHANGELOG.md` for planned and completed work tracking.

The docs should not accumulate implementation archaeology. Proposal text can
remain exploratory, but source-of-truth docs should describe the current
contract after each tranche.

## Suggested Tranches

These tranches are ordered by risk rather than by purity.

### Tranche 1: Boundary Inventory

Create the inventory of phase-product fields, consumers, cache predicates, and
freshness tests. This can be documentation-only unless the inventory reveals a
small obvious bug.

Exit signal: maintainers can point to each duplicated field and say whether it
is authoritative, projected, cached, diagnostic, or transitional.

### Tranche 2: Retained Layout Freshness Matrix

Expand retained-layout coverage around the existing equivalence predicates.
Focus on fields that are intentionally ignored by measurement or placement
reuse but still matter later.

Exit signal: relaxed equivalence predicates have paired freshness tests, and
new predicates have a clear rule for when a sync path is required.

### Tranche 3: Semantics And Draw Projections

Audit `SemanticExtractor` and `DrawExtractor` reads from `PlacedNode`. Introduce
narrow projection helpers only where they clarify ownership or remove repeated
field plumbing. Avoid reshaping `PlacedNode` storage unless a narrower
projection has already proved useful.

Exit signal: semantics and draw inputs are named well enough that a stale-field
bug has an obvious owner.

### Tranche 4: Frame-Tail And Retained-State Contracts

Review `FrameHeadDraft`, `FrameTailInput`, layout output, raster output,
completed-frame candidates, and retained state through the same boundary
language. Make baseline/decorated products explicit everywhere they cross an
async or retained boundary.

Exit signal: a completed async candidate's path from resolve through commit or
drop can be explained without relying on incidental field names.

### Tranche 5: Storage Simplification Where Proven Safe

After the projection and test matrix exists, revisit whether any duplicated
storage can be removed or replaced by stored grouped products. This should be a
cleanup tranche, not the first proof of correctness.

Exit signal: any storage reshaping has value-semantics, deep-tree stack-safety,
artifact destruction, sync/async parity, and retained-layout coverage.

## Acceptance Criteria For The Broader Effort

The hardening effort is done when:

- `ARCHITECTURE.md` describes the phase-product ownership model without
  hand-waving around mirrored metadata.
- `SOURCE_LAYOUT.md` points maintainers to the helper types that define each
  major phase projection.
- Every relaxed retained-reuse predicate has an adjacent or clearly linked
  freshness test.
- The baseline placed tree versus animation-decorated placed tree distinction
  is mechanically hard to misuse.
- Sync and async rendering share the same boundary vocabulary.
- Stack-safety tests cover any phase product whose storage shape changed.
- `bun run test` remains the completion gate for each shared runtime tranche.

## Open Questions

- Should the phase-boundary inventory become a permanent document, or should it
  be folded into `ARCHITECTURE.md` once the audit is complete?
- Should projection helpers live beside the source phase, the destination
  phase, or the boundary that computes them?
- Is there enough value in a mechanical guardrail for phase products, or are
  focused tests and source-layout docs sufficient?
- Should retained-reuse predicates expose named "ignored but synchronized"
  field lists for review?
- Which current fields are transitional compatibility rather than durable
  pipeline contract?

## Recommended Next Step

Do the inventory tranche first. It is the cheapest way to turn the current
deep investigation into a shared map. After that, pick the smallest retained
layout freshness gap that the inventory exposes and land it as one commit with
focused tests, docs updates, and the full repo gate.
