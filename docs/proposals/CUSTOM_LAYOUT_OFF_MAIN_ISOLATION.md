# Custom Layout Off-Main Isolation

## Status

Proposed follow-up to
[`OFF_MAIN_PIPELINE_RENDERING.md`](OFF_MAIN_PIPELINE_RENDERING.md).

The runtime now offloads built-in layout and post-layout frame-tail work when a
resolved tree contains only value-shaped layout behaviors. If any subtree uses
`.custom(CustomLayoutHandle)`, layout falls back to the main actor for the whole
tree. That fallback is intentional: the current authored `Layout` bridge is
main-actor-owned.

This document describes what would have to change before custom layout
measurement and placement can run on the frame-tail worker.

## Problem

Custom layout currently crosses from Core into View through
`CustomLayoutHandle.proxy`. The public Core protocol is `Sendable`, but the
View implementation behind authored `Layout` is `LayoutProxyBox`, a
`@MainActor` class. Its public nonisolated entry points immediately call
`MainActor.assumeIsolated` before:

- reading the erased layout box,
- creating and updating the layout cache,
- constructing `LayoutSubview` wrappers,
- running `sizeThatFits`,
- recording `placeSubviews`,
- discarding stale cache entries.

Calling those entry points from the frame-tail worker traps. More importantly,
even if the trap were avoided, the work is not value-shaped today. It can call
user-authored layout code and can mutate per-layout cache state.

## Goals

- Let custom layout measurement and placement run off the main actor when the
  authored layout is explicitly safe to do so.
- Preserve SwiftUI-shaped `Layout` semantics: cache creation, cache updates,
  repeated subview measurement, explicit placement, dimensions, and alignment
  guides.
- Keep the current main-actor fallback for layouts that are not proven safe.
- Avoid pushing locks into the main actor's authoring and retained-graph
  surfaces.
- Make the off-main eligibility decision visible to diagnostics and tests.

## Non-goals

- Running `View.body` or dynamic property evaluation off-main.
- Making every existing custom layout automatically off-main-safe.
- Supporting custom layouts that capture non-Sendable reference state on the
  worker.
- Parallelizing custom layout subtrees.
- Removing the built-in layout offload guard before replacement coverage lands.

## Current Ownership

The current flow is:

```
main actor: resolve authored Layout into LayoutProxyBox
Core:       carry CustomLayoutHandle in ResolvedNode.layoutBehavior
layout:     LayoutEngine.measure/place calls CustomLayoutHandle
main actor: LayoutProxyBox runs user Layout callbacks and cache mutation
```

That bridge was acceptable while all layout ran on the main actor. It becomes
the limiting factor once built-in layout moves to a worker.

The important boundary is not the enum case itself. `LayoutBehavior.custom` is
already part of the Sendable resolved tree. The unsafe part is the captured
proxy behind `CustomLayoutHandle`.

## Proposed Design

Introduce an explicit custom-layout execution capability:

```
enum CustomLayoutExecutionMode: Sendable {
  case mainActor
  case worker(snapshot: WorkerCustomLayoutSnapshot)
}
```

The exact type names can change, but the model should be capability-based:

- main-actor custom layout remains the default,
- worker custom layout is opt-in and snapshot-backed,
- eligibility is decided during main-actor resolve,
- the worker receives only Sendable state and Sendable callbacks,
- cache mutation belongs to the execution mode that owns the layout.

### Snapshot Shape

A worker-capable custom layout needs a Sendable snapshot containing:

- a stable debug name,
- a measurement reuse signature,
- a placement reuse signature,
- a Sendable cache value or cache token,
- Sendable `sizeThatFits` and `placeSubviews` operations,
- subview descriptors that can measure children through `LayoutEngine` without
  reading main-actor state,
- any alignment-guide and dimension data needed by `LayoutSubview`.

This should not copy the retained `ViewGraph` or authoring context. The snapshot
is a frame artifact produced after resolve, not a portable view tree.

### Cache Ownership

The current `LayoutProxyBox` cache is keyed by identity and proposal, stored in
a main-actor dictionary, and updated during measure and placement. Off-main
execution needs one of these cache models:

1. **Main-actor cache, worker computes without mutation.**
   The main actor snapshots cache input before offload and applies cache output
   after commit. This preserves main-actor ownership but adds a cache diff/apply
   step.

2. **Worker-owned cache for worker-safe layouts.**
   The frame-tail renderer owns the custom-layout cache for eligible layouts,
   like it already owns retained layout/raster state. This is cleaner for the
   offload path but requires a migration path for existing `LayoutProxyBox`
   state.

3. **No cache reuse for worker layouts initially.**
   A first prototype can disable custom-layout cache reuse off-main and measure
   the cost. This is simpler and safer, but it may erase the benefit for custom
   layouts that depend on cache amortization.

Recommendation: start with model 1 for correctness. Move to model 2 only if the
main-actor cache apply step is too expensive or too complex to reason about.

### Public API Surface

Do not make all `Layout` conformers implicitly worker-capable.

Potential opt-in shapes:

```
public protocol SendableLayout: Layout, Sendable where Cache: Sendable {}
```

or:

```
extension View {
  public func offMainLayoutEligible(_ enabled: Bool = true) -> some View
}
```

The protocol shape is more honest: a layout is worker-safe only if its value,
cache, and captured closures are Sendable. A modifier flag can only express
intent; it cannot prove the implementation is safe.

The public spelling should wait until implementation pressure is clearer. The
package-internal prototype can first add a worker-capable layout box for a small
set of internal test layouts.

## Migration Plan

### Stage 1: Preserve and expose the fallback

- [x] Keep `FrameTailRenderer.canOffloadLayout` conservative.
- [x] Add diagnostics for custom-layout fallback count and first fallback identity.
- [x] Add a regression test proving a tree with custom layout runs layout inline but
  still offloads raster.

Stage 1 result:

- `FrameDiagnostics` reports `customLayoutFallbackCount` and
  `firstCustomLayoutFallbackIdentity`.
- `FrameDiagnosticsLogger` records the fallback count and first fallback
  identity in the TSV stream.
- `AsyncFrameTailRenderingTests` verifies that a custom-layout frame does not
  enqueue layout work on the worker, but still suspends at the raster worker
  boundary.

Commit boundary:

```bash
git commit -m "test(renderer): cover custom layout offload fallback"
```

### Stage 2: Split custom layout proxy capabilities

- [x] Add a package-internal worker-capability query to `CustomLayoutHandle`.
- [x] Keep existing `CustomLayoutProxy` as the main-actor-compatible path.
- [x] Add a separate worker proxy protocol whose requirements do not use
  `MainActor.assumeIsolated`.
- [x] Ensure default authored `Layout` still reports main-actor-only.

Stage 2 result:

- `CustomLayoutHandle` reports `executionCapability`, `canRunOnWorker`, and an
  optional package-internal `workerProxy`.
- `WorkerCustomLayoutProxy` defines the worker-capable custom-layout execution
  shape without replacing `CustomLayoutProxy`.
- Public authored `Layout` still resolves through `LayoutProxyBox`, reports
  `mainActorOnly`, and remains on the fallback path.

Commit boundary:

```bash
git commit -m "refactor(layout): split custom layout execution capability"
```

### Stage 3: Snapshot an internal worker-safe layout

- [x] Build one package-internal custom layout fixture whose value and cache are
  Sendable.
- [x] Resolve it into a worker-capable snapshot.
- [x] Run measurement and placement on the frame-tail worker.
- [x] Keep authored public `Layout` on the fallback path.

Stage 3 result:

- `WorkerCustomLayoutSnapshot` is a package-internal, Sendable closure-backed
  snapshot for worker-capable custom layout measurement and placement.
- `CustomLayoutHandle` dispatches measurement, child measurement, and placement
  through `workerProxy` when present; otherwise it preserves the existing
  main-actor-compatible `CustomLayoutProxy` path.
- `FrameTailRenderer` only blocks layout offload for custom layout handles that
  are still `mainActorOnly`.
- Fallback diagnostics now count main-actor-only custom layouts, not
  worker-capable custom snapshots.
- `AsyncFrameTailRenderingTests` resolves a worker-backed internal custom layout
  and verifies measurement and placement run off the main thread while public
  authored `Layout` remains on the fallback path.

Stage 3 intentionally does not move cache ownership off-main. The test snapshot
uses only Sendable captured state and performs fresh measurement/placement work;
cache input/output handoff remains Stage 4.

Commit boundary:

```bash
git commit -m "test(layout): prototype worker-safe custom layout snapshot"
```

### Stage 4: Add cache handoff

- Snapshot cache input on the main actor before offload.
- Return cache output with the worker result.
- Apply cache updates on the main actor only after the frame is still the
  committed frame.
- Drop cache output for abandoned stale-frame experiments.

Commit boundary:

```bash
git commit -m "refactor(layout): hand off custom layout cache updates"
```

### Stage 5: Decide public opt-in

- Decide whether public opt-in is a protocol, modifier, or both.
- Add compile-time Sendable constraints where possible.
- Document that non-opted-in custom layouts remain correct but run layout on
  the main actor.

Commit boundary:

```bash
git commit -m "docs(layout): define off-main custom layout opt-in"
```

## Required Tests

- Built-in-only trees still run layout on the worker.
- Custom-layout trees still fall back without trapping.
- Worker-safe custom layout can measure and place on the worker.
- Repeated custom-layout measurement preserves cache semantics.
- Alignment guides and `ViewDimensions` match the main-actor path.
- Focus-sync rerender still converges when custom layout is involved.
- Animation tick frames still preserve retained-layout reuse.
- A custom layout with non-Sendable cache or main-actor-only proxy cannot enter
  the worker path.
- Full `bun run test` passes after each implementation stage.

## Risks

- Sendable annotations can create false confidence if a custom layout captures
  mutable global state.
- Cache handoff can apply stale results if it is not tied to ordered frame
  commit.
- Worker snapshots may duplicate enough `LayoutSubview` behavior that the two
  paths drift.
- A public opt-in added too early could lock in a shape before the internal
  execution model is proven.

## Recommendation

Keep the fallback for public authored custom layouts and do not attempt to move
them off-main by force.

The next useful implementation step is Stage 4: add an explicit cache handoff
for worker-capable custom layouts. That keeps the landed built-in layout offload
correct while turning the package-internal worker snapshot from a no-cache
prototype into a candidate execution model with SwiftUI-shaped cache semantics.
