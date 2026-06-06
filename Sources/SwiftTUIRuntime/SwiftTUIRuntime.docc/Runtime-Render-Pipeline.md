# Runtime Render Pipeline

How SwiftTUI drives authored views through the runtime renderer, frame products,
commit policy, diagnostics, and host handoff.

## Overview

SwiftTUI has two overlapping pipeline views:

- **Phase products** are the values the engine computes:
  `resolve -> measure -> place -> semantics -> draw -> raster -> commit`.
- **Runtime stages** are the scheduling boundaries used by an interactive
  session:
  `head -> animationInjection -> latePreferenceReconciliation -> fusedFrameTail -> commit`.

`SwiftTUICore` owns the phase-product types. `SwiftTUIRuntime` owns the run
loop, renderer orchestration, frame-tail scheduling, cancellation, frame-drop
policy, commit side effects, diagnostics, and presentation to a host surface.

The direct ``DefaultRenderer`` snapshot path and the interactive ``RunLoop``
path both produce `FrameArtifacts`. The interactive path adds invalidation
coalescing, frame-tail cancellation, completed-frame drop policy, host-facing
damage derivation, and presentation to a concrete surface.

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
  -> FrameArtifacts
```

One-shot rendering computes the same phase products, but it does not own input,
signals, invalidation scheduling, async tail cancellation, or host presentation.

## Code Map

Use these files as entry points when tracing the implementation:

| Question | Start here |
| --- | --- |
| How does an app become a run loop? | `Sources/SwiftTUIRuntime/Scenes/WindowSceneSelection.swift`, `Sources/SwiftTUIRuntime/Scenes/SceneSession.swift`, platform runners under `Platforms/` |
| How does the run loop decide a frame is needed? | `Sources/SwiftTUIRuntime/RunLoop/RunLoop.swift`, `Sources/SwiftTUIRuntime/RunLoop/RunLoop+Rendering.swift`, `Sources/SwiftTUIRuntime/RunLoop/RunLoop+FrameAcquisition.swift` |
| What is the renderer entry point? | `Sources/SwiftTUIRuntime/SwiftTUI.swift` |
| What executes the runtime stages? | `Sources/SwiftTUIRuntime/Rendering/RuntimeRenderPipeline.swift` |
| Where does resolve happen? | `Sources/SwiftTUIRuntime/Rendering/DefaultRendererFrameHeadCoordinator.swift`, `Sources/SwiftTUIViews/Foundation/ViewFoundation.swift`, `Sources/SwiftTUICore/Resolve/ViewGraph.swift` |
| Where do measure, place, semantics, draw, and raster run? | `Sources/SwiftTUIRuntime/Rendering/FrameTailRenderer.swift`, `Sources/SwiftTUIRuntime/Rendering/FrameTailRenderer+InlineStages.swift` |
| Where does commit decide effects and completed-frame disposition? | `Sources/SwiftTUIRuntime/Rendering/DefaultRenderer+CompletedFrameCandidates.swift` |
| Where does a committed frame reach hosts? | `Sources/SwiftTUIRuntime/RunLoop/RunLoop+Presentation.swift`, `Sources/SwiftTUIRuntime/Terminal/PresentationSurface.swift` |
| Where are frame diagnostics emitted? | `Sources/SwiftTUIRuntime/RunLoop/RunLoop+FrameDiagnostics.swift`, `Sources/SwiftTUIRuntime/Diagnostics/RuntimeFrameSample.swift`, `Sources/SwiftTUIProfiling/` |

Paths are relative to the `swift-tui` package root.

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

- `render(...)`: one-shot, synchronous, returns `FrameArtifacts`.
- `renderAsync(...)`: asynchronous frame tail, non-cancellable.
- `renderAsyncCancellable(...)`: asynchronous frame tail with queued-tail
  cancellation and completed-frame disposition policy.

The run loop calls eliding variants so animation-deadline frames that cannot
affect the drawn surface can commit animation state without running the frame
tail or presenting a frame.

## Runtime Stages

`RuntimeRenderPipeline` walks `RuntimeRenderStageName.orderedComposition`:

```text
head
animationInjection
latePreferenceReconciliation
fusedFrameTail
commit
```

The executor is deliberately exhaustive: adding or reordering a stage changes the
stage enum and each executor switch.

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

It may run inline or on a frame-tail worker, depending on renderer strategy and
platform support. It consumes the resolved tree and retained inputs and returns
the downstream products plus timing and reuse diagnostics.

### Commit

Commit turns a completed draft into a committed frame candidate. It packages
lifecycle events, semantic handlers, runtime registrations, transaction effects,
retained frame-tail state, and diagnostics. A completed candidate can be:

- committed and returned as `FrameArtifacts`;
- dropped by completed-frame policy;
- cancelled before its tail starts;
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
| raster | `RasterSurface` | Paint draw commands into styled terminal cells and image attachments. |
| commit | `CommitPlan` | Package lifecycle, handler installation, semantic snapshot, and transaction work. |

All seven products are gathered on `FrameArtifacts` for inspection and retained
reuse. Hosts should consume committed host contracts such as
``SemanticHostFrame`` instead of reaching into renderer-private retained state.

## Isolation And Scheduling

Authored `View`, `Scene`, and `App` values are main-actor APIs. Work that
evaluates authored bodies or mutates live runtime state stays on the main actor:

- resolve;
- runtime graph, state, focus, lifecycle, and task coordination;
- transaction and registration publication;
- terminal presentation commit boundaries.

The frame tail is pure over already-resolved products and can run away from the
main actor when the execution strategy supports it. That boundary is why the
runtime stage pipeline is different from the phase-product model: the fused tail
is a scheduling optimization over distinct products, not a different data model.

## Damage And Presentation

Renderer-private reuse hints and host-facing damage are separate concepts.

Renderer-private reuse hints let the rasterizer reuse parts of the previous
renderer-committed surface. They are inputs to frame-tail work, not a frontend
contract.

Host-facing damage is derived by ``RunLoop`` against the previous
`RasterSurface` actually presented to the same runtime/frontend pair. This
derivation happens after frame acquisition because async artifacts can be
cancelled, skipped, dropped, or elided before a frontend sees them.

For hosts:

- `nil` damage means repaint the full surface.
- Non-`nil` empty damage means no visible raster cells changed.
- Non-`nil` row/range damage is relative to the previous surface presented to
  the same host.

## Host Handoff

``RunLoop`` presents a committed frame according to the active
`RuntimeConfiguration.output` and the roles implemented by the presentation
surface.

JSON and accessible output modes write command-oriented output derived from the
current frame. Raster hosts consume either a raster presentation surface or a
``SemanticHostFrame``. A semantic host frame carries:

- monotonic producer sequence;
- `RasterSurface`;
- `SemanticSnapshot`;
- focused identity;
- host-facing damage;
- preferred layout size when available.

Terminal-native, WASI/browser, localhost WebHost, and hosted SwiftUI surfaces all
sit below this committed-frame boundary. For host selection and surface roles,
see <doc:Host-Integration>.

Raster image attachments are still presented after cell rasterization. If an
attachment carries blend metadata, the host path asks the shared image
compositor for a precomposed PNG variant keyed by the image reference, visible
rect, blend mode, backdrop signature, cell pixel size, and host fallback
background. Terminal graphics protocols, WASI/WebHost image records, and the
SwiftUI host then draw that variant through their normal image routes.

## Diagnostics

With no sink installed, frame diagnostics are a branch in the committed-frame
path. When a sink is installed, the runtime emits `RuntimeFrameSample` values
for committed frames, zero-artifact outcomes, and elisions.

A committed sample includes:

- phase timings for resolve, measure, place, semantics, draw, raster, and
  commit;
- worker enqueue, compute, and completion timing;
- main-actor blocked and suspended timing;
- render and desired generation;
- wake causes and coalescing counts;
- focus-sync rerenders;
- animation-controller active and pending state;
- queued input seen during render suspension;
- drop eligibility and completed-frame disposition;
- presentation metrics and presentation duration.

`SwiftTUIProfiling` turns the runtime's neutral diagnostic samples into
consumer-facing records, files, and summaries. The runtime does not depend on the
profiling product.

## Invariants

- Resolve and commit stay on the main actor because they evaluate authored
  bodies, mutate runtime state, and publish user-visible effects.
- Frame-head side effects must be staged in `FrameHeadTransaction`; aborting,
  cancelling, or dropping a frame must not leak registrations, graph changes,
  animation state, portal state, or observation state.
- The frame tail may be scheduled as one fused runtime stage, but the phase
  products remain distinct and ordered.
- Host-facing damage is derived against the previous raster surface actually
  presented to that host.
- Presentation layers consume committed frame contracts; they do not reach into
  renderer-private retained state.

## See Also

- <doc:Architecture>
- <doc:Runtime>
- <doc:Running-Apps>
- <doc:Host-Integration>
- <doc:TerminalEmbedding>
