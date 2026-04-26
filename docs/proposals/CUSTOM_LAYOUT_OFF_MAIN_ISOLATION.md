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

Implementation note: Stage 4 landed the model-1 handoff channel for
package-internal worker snapshots. Stage 5 uses model 2 for explicitly opted-in
public `SendableLayout` values because the protocol requires `Cache: Sendable`
and lets the worker proxy own the cache without crossing `LayoutProxyBox`.
Ordinary `Layout` conformers still use the main-actor-owned cache.

### Public API Surface

Do not make all `Layout` conformers implicitly worker-capable.

Chosen opt-in shape:

```
public protocol SendableLayout: Layout, Sendable where Cache: Sendable {
  var measurementReuseSignature: String { get }
  var placementReuseSignature: String { get }
}
```

The protocol shape is more honest: a layout is worker-safe only if its value,
cache, and captured closures are Sendable. The reuse signatures make retained
measurement and placement eligibility explicit, so two independent layout
values can participate in retained layout reuse only when the author declares
the fields that affect measurement and placement stable. A modifier flag can
only express intent; it cannot prove the implementation is safe.

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

- [x] Snapshot cache input on the main actor before offload.
- [x] Return cache output with the worker result.
- [x] Apply cache updates on the main actor only after the frame is still the
  committed frame.
- [x] Keep cache output application centralized so abandoned stale-frame
  experiments can drop output by not invoking the apply step.

Stage 4 result:

- `LayoutPassContext` now carries worker-produced
  `WorkerCustomLayoutCacheUpdate` values alongside layout work metrics.
- Worker-capable custom layout callbacks receive the active `LayoutPassContext`
  so they can emit cache output without mutating main-actor-owned state on the
  worker.
- `FrameTailLayoutOutput` returns the collected cache updates to the main actor.
- `DefaultRenderer` applies returned worker custom-layout cache updates on the
  main actor after commit planning, and before storing the committed retained
  frame.
- The worker snapshot regression test verifies that cache apply runs once, runs
  on the main thread, and applies to the committed custom-layout identity.

Current limitation: there is still no public authored-layout cache snapshot.
The handoff channel is now in place, but public `LayoutProxyBox` remains
main-actor-only until Stage 5 decides the opt-in surface and the cache payload
shape for real authored layouts.

Commit boundary:

```bash
git commit -m "refactor(layout): hand off custom layout cache updates"
```

### Stage 5: Decide public opt-in

- [x] Decide whether public opt-in is a protocol, modifier, or both.
- [x] Add compile-time Sendable constraints where possible.
- [x] Document that non-opted-in custom layouts remain correct but run layout on
  the main actor.

Stage 5 result:

- The public opt-in is protocol-based: `SendableLayout` refines `Layout` and
  `Sendable`, requires `Cache: Sendable`, and requires stable measurement and
  placement reuse signatures.
- A more-constrained `SendableLayout.callAsFunction` routes direct
  `MyLayout { ... }` authoring through the worker-capable erasure path.
- `AnyLayout` has a constrained `SendableLayout` initializer that installs a
  worker-safe proxy for non-built-in custom layouts while preserving the
  existing `LayoutProxyBox` fallback path.
- Ordinary public `Layout` conformers remain main-actor-only and continue to
  report custom-layout fallback diagnostics.
- The async renderer regression suite verifies that an opted-in public
  `SendableLayout` measures and places off the main thread and reuses its cache
  between measurement and placement.

Current limitation: `SendableLayout` is an author contract backed by Swift's
`Sendable` constraints; it cannot prove that a layout avoids mutable globals or
other external side effects. The worker proxy uses a worker-owned cache scoped
like the existing main-actor bridge.

Commit boundary:

```bash
git commit -m "docs(layout): define off-main custom layout opt-in"
```

### Stage 6: Pin semantic parity and retained reuse

- [x] Verify worker-side `LayoutSubview.dimensions(in:)` reads the same
  alignment-guide values used by the main-actor custom-layout path.
- [x] Verify opted-in public `SendableLayout` values retain measurement and
  placement across draw-only frame-tail updates.
- [x] Keep unsigned custom layouts excluded from retained placement reuse.

Stage 6 result:

- `SendableLayout` now requires `measurementReuseSignature` and
  `placementReuseSignature`, matching the package-internal worker snapshot
  contract.
- `ResolvedNode.supportsRetainedReuse` admits `.custom` layout nodes only when
  both signatures are present and all children can retain layout reuse.
- `AsyncFrameTailRenderingTests` covers a public `SendableLayout` that reads
  `ViewDimensions` and a custom vertical alignment guide on the worker.
- The async renderer regression suite now proves draw-only border phase changes
  reuse both measurement and placement work for an opted-in `SendableLayout`.

### Stage 7: Pin focus-sync convergence

- [x] Cover default-focus synchronization through a public `SendableLayout` on
  the composed runtime path.
- [x] Cover Tab-driven focus movement through a public `SendableLayout` on the
  composed runtime path.
- [x] Assert the layout still measures and places on the frame-tail worker while
  focus synchronization rerenders.

Stage 7 result:

- `AsyncFrameTailRenderingTests` now runs a `RunLoop` whose root view wraps
  focused buttons in an opted-in public `SendableLayout`.
- The test waits for default-focus synchronization to publish the first focused
  identity, sends Tab, waits for the second focused identity and `FocusState`
  value to render, then exits through the real input path.
- The same test verifies the `SendableLayout` recorder's last measurement and
  placement callbacks did not run on the main thread.

Stage 7 also hardened `HostedSceneSessionTests` by increasing that suite's
polling timeout from 5s to 15s. The previous 5s budget was repeatedly too tight
under the full parallel root test run while passing in isolation.

### Stage 8: Adopt the opt-in in example layouts

- [x] Audit the repository's real custom-layout conformers for honest
  `SendableLayout` candidates.
- [x] Migrate the TerminalUI layout showcase's pure `FlowLayout` and
  `RingLayout` examples.
- [x] Keep Apple SwiftUI mirror examples unchanged.
- [x] Add example-package coverage proving the migrated layouts enter the
  async frame-tail worker path without custom-layout fallback diagnostics.

Stage 8 result:

- `Examples/layouts` now marks `FlowLayout` and `RingLayout` as
  `SendableLayout` values with reuse signatures derived from the fields that
  affect measurement and placement.
- `Examples/LayoutsSwiftUI` remains a SwiftUI comparison surface and does not
  import or adopt TerminalUI's worker-layout opt-in.
- The layout example behavior tests now include async renderer checks for both
  custom layouts, requiring worker timings and zero custom-layout fallback
  diagnostics.

### Stage 9: Adopt the opt-in for framework-owned custom layouts

- [x] Audit framework-owned custom `Layout` conformers in `Sources/`.
- [x] Migrate pure value-shaped framework layouts to `SendableLayout`.
- [x] Add async renderer coverage for real framework surfaces that previously
  depended on main-actor custom-layout fallback.

Stage 9 result:

- `WindowHostLayout` now conforms to `SendableLayout`.
- `AsyncFrameTailRenderingTests` now renders `WindowHostLayout` through
  `DefaultRenderer.renderAsync` and requires worker timings with zero
  custom-layout fallback diagnostics.
- `ScrollViewLayout` initially remained on the main-actor custom-layout fallback.
  Attempting to move it into `SendableLayout` made the interactive demo's
  headless run-loop selection-mode test crash with a signal-10 test helper
  exit. Its existing retained-layout reuse signatures remain in place for the
  main-actor fallback path.
- `TabViewContainerLayout` initially remained on the main-actor custom-layout fallback.
  Attempting to move it into `SendableLayout` made the gallery tab-click runtime
  input path crash with a signal-10 test helper exit, while the simpler async
  renderer surface passed. The fallback is now explicitly covered until that
  composed runtime path is debugged.
- Test-only custom layouts and the SwiftUI mirror examples remain ordinary
  `Layout` conformers unless they are explicitly serving worker-path coverage.

### Stage 10: Move ScrollView after fixing worker stack depth

- [x] Diagnose the `ScrollViewLayout` worker-path crash on the composed runtime
  path.
- [x] Move frame-tail layout work onto a dedicated large-stack layout worker on
  Darwin instead of the default dispatch worker stack.
- [x] Migrate `ScrollViewLayout` to `SendableLayout`.
- [x] Update async renderer coverage so framework-owned `ScrollView` requires
  worker layout timings and zero custom-layout fallback diagnostics.
- [x] Keep lazy indexed child sources on the main actor until their child-source
  callbacks have a worker-safe snapshot.

Stage 10 result:

- The signal-10 failure reproduced as an `EXC_BAD_ACCESS` on
  `swift-terminal-ui.frame-tail-renderer` while recursively placing the resolved
  tree, before any test assertion failed. The backtrace showed layout placement
  stack exhaustion rather than a bad ScrollView measurement or placement value.
- Async layout now uses a lazy `FrameTailLayoutWorker` with an 8 MiB pthread
  stack on Darwin. Raster work and synchronous renderer coordination remain on
  the existing serial dispatch queue.
- `ScrollViewLayout` now conforms to `SendableLayout`; its measurement
  signature depends on axes and indicator visibility, and its placement
  signature also includes scroll offset.
- ScrollViews with lazy indexed content still keep layout on the main actor.
  `ForEachIndexedChildSource` currently uses `MainActor.assumeIsolated` for its
  identity and child-resolution callbacks, so the frame-tail offload gate rejects
  trees with indexed child sources until that source is snapshotted for worker
  use.
- The existing `InteractiveRuntimeTests/headlessRunLoopChangesSelectionMode`
  runtime path covers the previous crash shape once `ScrollViewLayout` can run
  off-main.
- `TabViewContainerLayout` remained on the main-actor fallback pending a separate
  retry against the larger layout worker.

### Stage 11: Move TabView after the worker-stack fix

- [x] Retry `TabViewContainerLayout` on the worker after Stage 10's dedicated
  layout worker.
- [x] Migrate `TabViewContainerLayout` to `SendableLayout`.
- [x] Update async renderer coverage so framework-owned `TabView` requires
  worker layout timings and zero custom-layout fallback diagnostics.
- [x] Re-run the gallery tab-click repro that previously crashed.

Stage 11 result:

- `TabViewContainerLayout` now conforms to `SendableLayout` with stable
  measurement and placement signatures.
- `AsyncFrameTailRenderingTests` now renders a real `TabView` through
  `DefaultRenderer.renderAsync` and requires layout worker timings with zero
  custom-layout fallback diagnostics.
- `Examples/gallery` `GalleryTabSwitchTests/clickingGalleryTabSwitchesSelection`
  passes with `TabViewContainerLayout` opted in, indicating the earlier
  signal-10 failure was covered by the Stage 10 worker-stack fix and indexed
  source offload gate.

## Required Tests

- Built-in-only trees still run layout on the worker.
- Custom-layout trees still fall back without trapping.
- Worker-safe custom layout can measure and place on the worker.
- Repeated custom-layout measurement preserves cache semantics.
- Alignment guides and `ViewDimensions` match the main-actor path. Covered for
  public `SendableLayout`; broaden if package-internal worker snapshots gain
  additional subview APIs.
- Focus-sync rerender still converges when custom layout is involved. Covered
  for public `SendableLayout` on the runtime input path.
- Animation tick frames still preserve retained-layout reuse. Covered for
  draw-only async frame-tail updates on public `SendableLayout`.
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

The off-main custom-layout path now has coverage for the public opt-in's core
semantic risks: worker execution, cache reuse, `LayoutSubview` dimensions,
custom alignment guides, retained layout reuse across draw-only updates, and
focus-sync rerender convergence. Broader adoption should continue layout by
layout: migrate only conformers that can honestly satisfy `SendableLayout`, and
leave the main-actor fallback in place for anything with non-Sendable or
side-effectful cache semantics.
