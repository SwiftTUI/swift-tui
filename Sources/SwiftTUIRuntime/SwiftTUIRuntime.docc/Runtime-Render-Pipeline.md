# Runtime Render Pipeline

How SwiftTUI drives authored views through the runtime renderer, frame products,
commit policy, diagnostics, and host handoff.

## Overview

> Tip: The website publishes an interactive walkthrough of this pipeline at
> [swifttui.sh/pipeline](https://swifttui.sh/pipeline/); this article is the
> developer-level reference for the same machinery.

SwiftTUI has two overlapping pipeline views:

- **Phase products** are the values the engine computes:
  `resolve -> measure -> place -> semantics -> draw -> raster -> commit`.
- **Runtime stages** are the scheduling boundaries used by an interactive
  session:
  `head -> animationInjection -> latePreferenceReconciliation -> fusedFrameTail -> commit`.

`SwiftTUICore` owns the package-only phase-product types. `SwiftTUIRuntime`
owns the run loop, renderer orchestration, frame-tail scheduling, cancellation,
frame-drop policy, commit side effects, diagnostics, and presentation to a host
surface.

The direct ``DefaultRenderer`` snapshot path and the interactive ``RunLoop``
path compute the same phase work. The public one-shot path returns
``RenderSnapshot``. Package and run-loop paths keep `FrameArtifacts` as their
internal committed bundle. The interactive path adds invalidation coalescing,
frame-tail cancellation, completed-frame drop policy, host-facing damage
derivation, and presentation to a concrete surface.

For the phase-product reference, see the Rendering Pipeline article in
`SwiftTUICore`.

## Interactive Callpath

An interactive app reaches the render pipeline through scene setup and the run
loop:

```text
App.body / Scene.body
  -> collectWindowSceneSelections(...)
  -> SceneSession.run(...)
  -> RunLoop.run()
  -> RunLoop.renderPendingFramesAsync(...)
  -> DefaultRenderer.renderAsyncCancellableEliding(...)
  -> RuntimeRenderPipeline.renderCancellable(...)
  -> DefaultRenderer.computeFrameHead(...)
  -> DefaultRendererFrameTailCoordinator.renderFrameTailLayoutStage(...)
  -> DefaultRendererFrameTailCoordinator.renderFrameTailRasterStage(...)
  -> DefaultRenderer.resolveCompletedFrameCandidate(...)
  -> RunLoop.applyAcquiredFrame(...)
  -> RunLoop.presentCommittedFrame(...)
  -> presentation surface
```

The one-shot snapshot path skips the run loop and presentation surface:

```text
DefaultRenderer.render(root, proposal:)
  -> RuntimeRenderPipeline.renderOneShot(...)
  -> RenderSnapshot
```

One-shot rendering computes the same phase products, but it exposes only the
public committed snapshot. It does not own input, signals, invalidation
scheduling, async tail cancellation, or host presentation.

## Code Map

Implementation entry points are contributor-facing and mapped in the
coordination repository's
[`CODEBASE-GUIDE.md`](https://github.com/SwiftTUI/swift-tui-org/blob/main/docs/swift-tui/CODEBASE-GUIDE.md),
which pairs this article's stage descriptions with the owning source files.

## Renderer Entry Points

``DefaultRenderer`` is both the public renderer for snapshots and the
interactive run loop's rendering workhorse. It owns:

- Core components: `Resolver`, `LayoutEngine`, `SemanticExtractor`,
  `DrawExtractor`, `Rasterizer`, and `CommitPlanner`.
- Runtime state: `ViewGraph`, frame resolve state, presentation portal state,
  animation controller, render-generation sequencer, elided-frame counter, and
  frame-tail retained state.
- `FrameTailRenderer`, which runs measure, place, semantics, draw, and raster
  and stores retained frame-tail data for future reuse.

The renderer exposes three execution strategies over the same stage order:

- `render(...)`: one-shot, synchronous, returns ``RenderSnapshot``.
- `renderAsync(...)`: asynchronous frame tail, non-cancellable, returns
  ``RenderSnapshot``.
- `renderAsyncCancellable(...)`: asynchronous frame tail with queued-tail
  cancellation and completed-frame disposition policy.

Package internals use `renderArtifacts(...)` and `renderArtifactsAsync(...)`
when tests or runtime code intentionally inspect phase IR.

The run loop calls eliding variants for animation-deadline frames that cannot
affect the drawn surface. These variants commit animation state without running
the frame tail or presenting a frame.

## Runtime Stages

`RuntimeRenderPipeline` walks `RuntimeRenderStageName.orderedComposition`:

```text
head
animationInjection
latePreferenceReconciliation
fusedFrameTail
commit
```

The executor is exhaustive. If you add or reorder a stage, change the stage
enum and each executor switch.

### Head

The head stage is computed by `DefaultRendererFrameHeadCoordinator`. It:

- Allocates a render generation.
- Builds a `FrameHeadTransaction`.
- Creates checkpoints for abortable frames.
- Prepares `FrameResolveInputs` from the current resolve context, proposal,
  environment, invalidation set, transaction, and reuse policy.
- Evaluates the dirty graph frontier or the root view.
- Installs the presentation portal evaluator around the authored root.
- Snapshots retained frame-tail inputs from the previous committed frame.

The output is a `FrameHeadDraft`: resolved tree, frame-tail input, transaction,
generation, timing clock, runtime issues, and frame context for commit.

### Animation Injection

The animation stage samples the animation controller for the frame, applies the
sampled transaction, and updates the draft before downstream work reads resolved
metadata. The stage can report whether animation work is pending and whether the
frame can be elided before the frame tail runs.

### Late Preference Reconciliation

Some authored preferences depend on placement or root-level presentation state.
Late reconciliation lets the runtime update that state before the final frame
tail reads the effective tree. If reconciliation changes the required inputs,
the renderer reruns the relevant stage work instead of publishing inconsistent
artifacts.

### Fused Frame Tail

The fused frame tail is the performance node that normally computes:

```text
measure -> place -> semantics -> draw -> raster
```

It can run inline or on a frame-tail worker, depending on renderer strategy and
platform support. It consumes the resolved tree and retained inputs and returns
the downstream products plus timing and reuse diagnostics.

#### Tree depth on the worker stack

The frame-tail worker is a plain Dispatch queue, so it carries the small default
Dispatch stack (512 KiB) rather than the main thread's budget. Every tree walker
reachable from the tail is an explicit-stack loop for that reason.

One depth-limited operation remains on that thread and it is not a walker:
**releasing** a phase-product tree. `ResolvedNode`, `MeasuredNode`,
`PlacedNode`, and `DrawNode` store their children inline as `[Self]`. Thus, the
compiler's own value witnesses recurse once per level during tree destruction,
with no framework code in the trace. On macOS/arm64, the cost increases linearly
with depth. `ResolvedNode` uses approximately 475 B per level, or 1104 levels
at 512 KiB. `MeasuredNode`, `PlacedNode`, and `DrawNode` use approximately 267
B per level, or 1968 levels. Array-storage destruction sets the minimum
per-level cost. Thus, the smaller `DrawNode` has the same limit. One authored
`VStack` level uses approximately three `ResolvedNode` levels. Retained
previous-frame products keep a complete `DrawNode` tree between frames. Thus,
retained-state teardown and live frames can release deep draw trees.

If code drops an unbounded tree on a small stack, call `flattenForRelease()`.
See `DeeplyNestedValueTree`. This function drains the subtree through a heap
worklist. The release then uses O(1) stack space. This behavior is opt-in.
Automatic flattening requires a mutable class on the child storage. The package
`Sendable` policy requires a `Mutex` for reads of that class. This cost is not
acceptable on the engine's hottest accessor.

Nesting far below these bounds is first limited by resolve. This descent
recurses for each view level on the main actor. `DeferredResolveDriver`
chunks it on hosts whose stack budget is small enough to need it.

### Commit

Commit turns a completed draft into a committed frame candidate. It packages
lifecycle events, semantic handlers, runtime registrations, transaction effects,
retained frame-tail state, and diagnostics. A completed candidate can be:

- committed as package `FrameArtifacts`.
- dropped by completed-frame policy.
- cancelled before its tail starts.
- elided when an animation-deadline frame has no visible drawn effect.

Commit does not write terminal bytes or browser frames directly. Presentation is
owned by ``RunLoop`` after frame acquisition succeeds.

## Phase Products

The runtime stages preserve the same typed product order documented by
`SwiftTUICore`:

| Phase | Product | Responsibility |
| --- | --- | --- |
| resolve | `ResolvedNode` | Evaluate authored bodies and attach the identity projection, `StructuralPath`, optional entity identity, state ownership, environment, metadata, and runtime registrations. |
| measure | `MeasuredNode` | Negotiate sizes through `LayoutEngine` under layout proposals. |
| place | `PlacedNode` | Assign integer-cell frames, content bounds, and placement-time metadata. |
| semantics | `SemanticSnapshot` | Extract focus, interaction, scroll, selection, named coordinate-space, accessibility, and routing data. |
| draw | `DrawNode` | Lower placed nodes into draw commands, borders, backgrounds, effects, and payload paint instructions. |
| raster | `RasterSurface` | Paint draw commands into styled terminal cells, image attachments, and a package-level ordered presentation-layer sidecar. |
| commit | `CommitPlan` | Package lifecycle, handler installation, semantic snapshot, and transaction work. |

All seven products are gathered on package-only `FrameArtifacts` for inspection
and retained reuse. Public snapshot callers get ``RenderSnapshot``. Hosts must
consume committed host contracts such as ``SemanticHostFrame`` instead of
reaching into renderer-private retained state.

## Isolation And Scheduling

Authored `View`, `Scene`, and `App` values are main-actor APIs. Work that
evaluates authored bodies or mutates live runtime state stays on the main actor:

- resolve.
- runtime graph, state, focus, lifecycle, and task coordination.
- transaction and registration publication.
- terminal presentation commit boundaries.

The frame tail is pure over already-resolved products and can run away from the
main actor when the execution strategy supports it. That boundary separates the
runtime stage pipeline from the phase-product model. The fused tail is a
scheduling optimization over distinct products, not a different data model.

## State Ownership At Capture

`@State` ownership travels with the closures a body creates. Immediately
before a body, style body, or composed-modifier body evaluates, the
capture-bind pass writes the evaluation's state owner into the exact
container copy that code consumes — so an action, task, or submit closure
carries its owner the way a `Binding` carries its accessors, instead of
re-deriving ownership from whatever dispatch context happens to be ambient
when it later fires.

An imperative access resolves in order: the resolve-pass ambient scope
(inside a body), then the carried capture — served directly while the owner
node is live, or re-addressed through a fire-time identity refresh when a
structural churn re-minted the node under the same resolve identity (same
graph scope and a live occupant only; committed removal falls through) —
then the loud authored-seed fallback, which records the
`state-seed-fallback` soundness violation. There is no ambient
owner-guessing tier: a closure that outlives its state's committed removal
reads the seed loudly rather than another owner's slot silently.

`SWIFTTUI_STATE_CAPTURE_BINDING=0` disables the bind pass as a diagnostic
A/B lever for attributing capture regressions; it does not substitute a
different ownership model.

## Lazy Container Windowing

`LazyVStack`/`LazyHStack` content backed by an indexed source (a direct
`ForEach`) uses viewport windowing under a `ScrollView`. The scroll layout
declares a measure-time viewport. Measurement realizes and sizes only the
visible band plus overscan. It derives other allocation entries from the first
row extent. Placement materializes rows only in the visible range. Hosts and
tests can observe these results:

- Rows outside the viewport are not placed: they paint nothing, mint no
  interaction regions, and are not focus-traversal targets until scrolled
  into view. This behavior matches the SwiftUI lazy contract. Offscreen lazy
  rows do not exist yet. `scrollTo` still reaches them through the estimated
  frames in the allocation snapshot.
- The container's content size is an estimate that refines as real
  measurements replace estimates when the window moves. The scroll offset
  registry re-anchors on content-size change.
- Some shapes are ineligible. They include sources spliced into multiple cells
  per element, negotiated (`nil`) spacing, and sources without an enclosing
  scroll-declared viewport. They use exhaustive realization, byte-identical to
  the pre-windowing pipeline.
- Some live lazy sources exceed the worker-snapshot element budget. Their frames
  keep those sources live and run the frame tail on the main actor. They do not
  pre-realize every element for worker offload.

## Damage And Presentation

Renderer-private reuse hints and host-facing damage are separate concepts.

Renderer-private reuse hints let the rasterizer reuse parts of the previous
renderer-committed surface. They are inputs to frame-tail work, not a frontend
contract.

### How the reuse hint is produced

`FrameTailPresentationDamageResolver` runs *after* draw extraction. It compares
the previous committed draw tree with the current draw tree. It walks both
trees together and pairs children by position. It compares their identities
and prunes equal subtrees. It records affected rectangles when a node projection
changes. It also records them after an insertion, removal, or re-keying of a child.

Three properties are important:

- **The diff basis is the draw tree, not the placed tree and not the
  invalidation set.** `directlyInvalidated` is the invalidation *seed* set: the
  identities whose state or observation changed. Re-resolution routinely changes
  what a node paints without that node being a seed (a sibling reading a derived
  value, an environment or preference propagation, a container relaying out
  around changed content). Thus, damage from seed subtree extents omits some
  changes. The placed tree is not a sound basis. Draw extraction reuses retained
  subtrees. Therefore, byte-identical placed subtrees can emit different draw
  commands. Rasterization is a pure function of the draw tree. This fact makes
  the draw tree the only sound basis.
- **Every changed rect carries a one-cell margin.** A terminal cell is not the
  smallest unit this renderer paints. Half-block glyphs give it sub-cell
  resolution. The cell that carries the half block sits *outside* the region
  whose color it shows. A change confined to a node's bounds can therefore
  repaint the cells immediately around them. The one-cell reach is an assumed
  painter invariant, not a static type rule. The F13 comparison oracle enforces
  this invariant. It rasters every incremental frame again in DEBUG and asserts
  on a difference. Thus, a painter that exceeds the margin fails the suites.
- **No painter reads outside the row it writes.** Every painter writes cells
  or reads the cell it is about to write: `write` composites a style over the
  cell's current one, and `tintCell` and opacity baking read the same cell. A
  stroke with no explicit background carries none and keeps whatever lies
  beneath it. This is what makes the dirty-row premise hold. A dirty row is
  cleared and replayed by the same commands in the same order as a fresh
  raster, so a painter's inputs on that row are identical on both paths. The
  stroke painter used to infer an edge's background from the neighbouring row
  *outside* the ring. That read was a paint-order dependency: an unchanged
  border above a later-painted control diverged (SwiftTUI/swift-tui#5), and
  it needed a damage closure over the sampled rows. The read is gone. The one
  closure left, `presentationOrderDamageClosure`, grows the dirty set over
  rows the retained presentation-layer order needs re-recorded.
- **Animation frames barrier.** Property interpolation rewrites the resolved
  tree after invalidation. The placed animation overlay decorates the current
  tree with state that the retained baseline does not carry.
  Both are conservative barriers rather than damage contributions, because an
  incomplete "damage is complete" answer is release-only corruption under
  `.trustSoundDamage`.

A frame that produces no damage falls back to a fresh raster, so every relaxation
is bounded by a conservative nil. `FrameDiagnostics.presentation.rasterReuse`
reports the path for each committed frame. It also reports why a barrier
occurred. These fields are
`raster_path` and `raster_reuse_barriers` in the frame TSV.

Host-facing damage is derived by ``RunLoop`` against the previous
`RasterSurface` actually presented to the same runtime/frontend pair. This
derivation happens after frame acquisition because async artifacts can be
cancelled, skipped, dropped, or elided before a frontend sees them.

For hosts:

- `nil` damage means repaint the full surface.
- Non-`nil` empty damage means no visible raster cells changed.
- Non-`nil` row/range damage is relative to the previous surface presented to
  the same host.

`RasterSurface` also carries package-level ordered presentation layers. Current
terminal, WebHost/WASI, Android, and external SwiftUI host paths continue to
consume the collapsed cell grid plus image attachments. The damage derivation
still returns row/range damage for those hosts. It also treats
presentation-layer topology changes as dirty row signals. Future ordered-layer
consumers can detect authoring-order changes even when the final collapsed cells
are stable.

## Host Handoff

``RunLoop`` presents a committed frame according to the active
`RuntimeConfiguration.output` and the roles implemented by the presentation
surface.

The JSON output mode writes command-oriented output derived from the
current frame. Raster hosts consume either a raster presentation surface or a
``SemanticHostFrame``. A semantic host frame carries:

- monotonic producer sequence.
- `RasterSurface`.
- `SemanticSnapshot`.
- focused identity.
- host-facing damage.
- preferred layout size when available.

Terminal-native, WASI/browser, localhost WebHost, host-managed Android, and the
external SwiftUI host all sit below this committed-frame boundary. They share
the phase order and handoff contract. Resolve reuse, selective evaluation,
ambient binding, and stack-depth policy vary by the per-host engine profile in
<doc:Hosts-And-Platforms>.
For runtime host seams and surface roles, see <doc:Host-Integration>.

Raster image attachments are still presented after cell rasterization. If an
attachment carries blend metadata, the host path asks the shared image
compositor for a precomposed PNG variant. Its key contains the image reference,
visible rectangle, blend mode, backdrop signature, cell pixel size, and host
fallback background. The compositor expands captured backgrounds and explicit
foreground glyphs into a pixel backdrop. It uses deterministic block, braille,
and centered text approximations. Terminal graphics protocols and all hosts
then draw the variant through their normal image routes.

## Diagnostics

With no sink installed, frame diagnostics are a branch in the committed-frame
path. When a sink is installed, the runtime emits `RuntimeFrameSample` values
for committed frames, zero-artifact outcomes, and elisions.

A committed sample includes:

- phase timings for resolve, measure, place, semantics, draw, raster, and
  commit.
- worker enqueue, compute, and completion timing.
- main-actor blocked and suspended timing.
- render and desired generation.
- wake causes and coalescing counts.
- focus-sync renders.
- animation-controller active and pending state.
- queued input seen during render suspension.
- drop eligibility and completed-frame disposition.
- presentation metrics and presentation duration.

`SwiftTUIProfiling` turns the runtime's neutral diagnostic samples into
consumer-facing records, files, and summaries. The runtime does not depend on the
profiling product.

## Invariants

- Resolve and commit stay on the main actor because they evaluate authored
  bodies, mutate runtime state, and publish user-visible effects.
- Stage frame-head side effects in `FrameHeadTransaction`. Aborting,
  cancelling, or dropping a frame must not leak registrations, graph changes,
  animation state, portal state, or observation state.
- The runtime can schedule the frame tail as one fused stage, but the phase
  products remain distinct and ordered.
- Host-facing damage is derived against the previous raster surface actually
  presented to that host.
- Presentation layers consume committed frame contracts. They do not reach into
  renderer-private retained state.

## See Also

- <doc:Architecture>
- <doc:Runtime>
- <doc:Running-Apps>
- <doc:Host-Integration>
- <doc:TerminalEmbedding>
