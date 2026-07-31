# SwiftTUI Codebase Guide

> A first-week onboarding map and set of end-to-end traces for engineers new to the
> SwiftTUI framework. This guide is **navigational and behavioral**: it tells you
> *where things live* and *how behavior flows*, and it points at the deeper
> reference docs rather than reproducing them. All paths are relative to the
> `swift-tui` package root unless prefixed with another repo name.

## Orientation

SwiftTUI is a **SwiftUI-shaped UI framework**. You author the same value types you
know from SwiftUI — `App`, `Scene`, `View`, `@State`, `@FocusState`, `VStack`,
the `Layout` protocol — and that *one* authored view tree is rendered, unchanged,
to **five hosts**. The canonical enumeration and packaging boundaries live in
[docs/HOSTS-AND-PLATFORMS.md](HOSTS-AND-PLATFORMS.md). Every host shares the
same authored tree, phase order, and phase-product contracts. The selected
engine profile can change resolve reuse, evaluation, ambient binding, and stack
depth before host-specific presentation consumes the finished frame.

The core mental model is three sentences long. **One authored tree, five hosts.** A
**frame pipeline** turns that tree into a single committed frame by running it
through seven typed phase products — `resolve → measure → place → semantics → draw
→ raster → commit`. A **run loop** decides *when* to make a frame: it parks until an
input event, a signal, a `@State` invalidation, or an animation deadline wakes it,
then produces exactly one coalesced frame and presents it. The engine that computes
phase products knows nothing about terminals or hosts; the run loop and the host
adapters live above it.

**How to use this guide.** It has two halves that answer two different questions.
[The map](#the-map) is the **horizontal** view — *where does X live?* — covering the
module graph, the strict layering, the phase-products-vs-runtime-stages duality, and
a consolidated subsystem table. [The flows](#the-flows) are the **vertical** traces
— *how does behavior move end to end?* — each a self-contained walk in the style of
the existing render-pipeline article (mental model → callpath → Code Map →
step-by-step → invariants/gotchas). Read the map first to build the skeleton, then
read whichever flow matches the bug or feature in front of you. The flows reference
the map's "Where does X live?" table constantly, so keep it handy.

This guide **complements** the existing architecture docs — it does not duplicate
them. For the canonical within-a-frame trace, see
<doc:Runtime-Render-Pipeline> (`Sources/SwiftTUIRuntime/SwiftTUIRuntime.docc/Runtime-Render-Pipeline.md`).
For layered architecture, see [docs/ARCHITECTURE.md](ARCHITECTURE.md); for the host
matrix, [docs/HOSTS-AND-PLATFORMS.md](HOSTS-AND-PLATFORMS.md); for accessibility,
[docs/ACCESSIBILITY.md](ACCESSIBILITY.md); for build/test workflow,
[docs/DEVELOPMENT.md](DEVELOPMENT.md).

---

## The map

Once you understand *how one frame is rendered* (the vertical trace in
<doc:Runtime-Render-Pipeline>), the next question is *where everything lives*. This
section maps the codebase **horizontally** — it tells you which door to open, not
what is behind it. The [flows](#the-flows) below open those doors.

### Mental model: one package, strict one-way layering

SwiftTUI is **one SwiftPM package** with a strict, one-directional layering. An
author writes `View`/`Scene`/`App` values; that same authored tree is rendered to
five hosts by running it through seven typed phase products. The layers are stacked
so the engine never knows about terminals and the authoring surface never knows
about run loops:

```text
SwiftTUIPrimitives  (leaf value vocabulary: geometry, styles, draw/layout metadata; no engine)
  -> SwiftTUIGraph  (reconciliation engine: retained graph, state, invalidation, reuse, scheduler)
    -> SwiftTUICore  (render engine: layout, extraction, raster, commit)
      -> SwiftTUIViews  (authoring surface: View, controls, layouts, property wrappers, gestures)
        -> SwiftTUIRuntime  (run loop, renderer orchestration, scenes, host integration, terminal)
          -> SwiftTUI  (batteries-included convenience re-export)
```

Peer products (`SwiftTUIAnimatedImage`, `SwiftTUIProfiling`) and
the host runners under `Platforms/` hang off the side of this spine — none of them
are *in* the spine.

### The module graph as one callpath

Read the arrows as the *legal direction of dependency*; crossing one backwards is a
layering violation:

```text
SwiftTUIPrimitives
  -> SwiftTUIGraph            (Graph depends on Primitives)
  -> SwiftTUICore             (Core depends on Graph + Primitives)
  -> SwiftTUIViews            (Views depends on Core)
  -> SwiftTUIRuntime          (Runtime depends on Core + Views)
     -> SwiftTUI              (convenience product re-exports Runtime + WebHostCLI + AnimatedImage)
SwiftTUIAnimatedImage -> SwiftTUIViews          (peer product, bundled into SwiftTUI)
SwiftTUIProfiling     -> SwiftTUIRuntime        (optional, opt-in; nothing in the default graph depends on it)
Platforms/CLI         (SwiftTUICLI / TerminalRunner)          -> SwiftTUIRuntime
Platforms/WASI        (SwiftTUIWASI / WASIRunner)             -> SwiftTUIRuntime
Platforms/WebHost     (SwiftTUIWebHost / WebHostRunner)       -> SwiftTUIRuntime
Platforms/WebHost     (SwiftTUIWebHostCLI / WebHostCLIRunner) -> SwiftTUIWebHost + SwiftTUICLI + SwiftTUIArguments
Platforms/Android     (SwiftTUIAndroidHost)                   -> SwiftTUIRuntime
Platforms/Embedding   (SwiftTUITerminal / SwiftTUIPTYPrimitives) -> SwiftTUIRuntime  (macOS/Linux only)
Platforms/Arguments   (SwiftTUIArguments)                     -> SwiftTUIRuntime
```

The two non-terminal **native** hosts live in *separate repos*, not this package:
the SwiftUI host in `swift-tui-swiftui` (`SwiftUIHost`) and the Kotlin/Compose UI in
`swift-tui-android`. The `SwiftTUIAndroidHost` target *in this package* is only the
Swift-side bridge (a JNI/C ABI over `HostedSceneSession`); the Compose view that
consumes it ships from `swift-tui-android`.

### What each module owns

| Module | Home | Owns | Hard boundary |
| --- | --- | --- | --- |
| **SwiftTUIPrimitives** | `Sources/SwiftTUIPrimitives/` | Inert value vocabulary: geometry, identity, style and color-science values, draw/layout metadata, pointer and semantic values, and animatable math. | Leaf internal target: no engine or render-pipeline algorithms; depends only on the standard library plus the vendored figlet-font payload. **Foundation-free** and builds standalone. |
| **SwiftTUIGraph** | `Sources/SwiftTUIGraph/` | Reconciliation: the retained graph and immutable resolve product, state slots, dependency/invalidation planning, reuse and checkpoints, lifecycle/entity routing, runtime registries, the frame scheduler, and animation intent. | AttributeGraph analog. Does **no layout, draw, raster, or commit work**; depends on Primitives only and is **Foundation-free**. |
| **SwiftTUICore** | `Sources/SwiftTUICore/` | The render engine: `LayoutEngine`, measure/place products, semantic and draw extractors, rasterizer, commit planner, content engines, style resolution, focus tracking, and frame-drop/elision policy. | Depends on Graph + Primitives and re-exports both. **Foundation-free** and **terminal-IO-free**; internal, not a published product. |
| **SwiftTUIViews** | `Sources/SwiftTUIViews/` | The authoring surface: `View`/`ViewModifier`/`ViewBuilder`, controls, stacks, the `Layout` protocol, `@State`/`@Binding`/`@FocusState`/`@Environment`, gestures, presentation, scrolling, shapes. | **Foundation-free.** `View` is body-only, `@MainActor`-isolated; lowering to primitives is package-internal. `@_exported`-imports Core (which re-exports Graph + Primitives) so the published `SwiftTUIViews` product is a self-sufficient authoring surface for external view libraries. |
| **SwiftTUIRuntime** | `Sources/SwiftTUIRuntime/` | `RunLoop`, `DefaultRenderer`, the runtime stage pipeline, scenes (`App`/`Scene`/`WindowGroup`), terminal hosting, host-frame contracts, input, animation controller, lifecycle, diagnostics emission. | The first layer allowed to touch terminal IO and Foundation. |
| **SwiftTUI** | `Sources/SwiftTUI/` | Convenience re-export: `App.main()`, standard flags, `--web` launch, animated-image support. | Also kept **Foundation-free** (writes UTF-8 to stdout without Foundation). |
| **SwiftTUIAnimatedImage** | `Sources/SwiftTUIAnimatedImage/` | Finite pre-composed animated-image playback, GIF/PNG import-export. | Peer product; bundled into `SwiftTUI`. |
| **SwiftTUIProfiling** | `Sources/SwiftTUIProfiling/` | `.profiling()` scene modifier; per-frame timing, memory, CPU/RSS signals routed to TSV/JSONL/summary sinks. | Opt-in, env-gated (`SWIFTTUI_PROFILE`); the runtime never depends on it — it consumes the neutral `FrameDiagnosticSink`/`RuntimeFrameSample` contract. |
| **Platforms/** runners | `Platforms/{CLI,WASI,WebHost,Android,Embedding,Arguments}/Sources/` | One host runner or transport each. **No nested Swift packages** — every target is declared in the root `Package.swift`. | Hosts sit *below* the committed-frame boundary; they consume committed contracts, not renderer-private state. |

> The Foundation-free boundary is enforced, not aspirational: the
> `no-foundation-in-library-products` prek hook blocks source-level imports in
> Primitives, Graph, Core, Views, and `SwiftTUI`;
> `Scripts/check_foundation_free_layers.sh` additionally proves that Primitives,
> Graph, Core, and Views do not load Foundation transitively. Where Graph needs
> something Foundation would normally provide, it keeps a raw representation instead
> — e.g. a dropped file path remains a raw string in
> `Sources/SwiftTUIGraph/Runtime/DroppedPath.swift`.

### Two pipeline views are the same work

This is the single most important idea to hold straight, because three of the four
flows cross it. There are **two views of the same work**, not two pipelines:

```text
Phase products (the typed values the engine computes — owned by Graph and Core,
using Primitives' leaf vocabulary):
  resolve -> measure -> place -> semantics -> draw -> raster -> commit
   Resolved-  Measured-  Placed-  Semantic-   Draw-   Raster-   Commit-
   Node       Node       Node     Snapshot    Node    Surface   Plan

Runtime stages (the scheduling boundaries an interactive session uses — owned by SwiftTUIRuntime):
  head -> animationInjection -> latePreferenceReconciliation -> fusedFrameTail -> commit
```

The **phase products are the data model**; the **runtime stages are the scheduling
model**. `head` does resolve on the main actor. The **fused frame tail** is one
runtime stage that internally produces five phase products
(`measure → place → semantics → draw → raster`) and may run *off* the main actor.
`commit` is the shared terminal that returns to the main actor. The full mechanics
are in <doc:Runtime-Render-Pipeline>; this map only locates the subsystems each
stage drives, and [§3a](#3a-the-render-pipeline-condensed) condenses the trace.

### Where does X live?

The navigational core of this map. Each row is a cross-cutting subsystem, its home,
and the key types you will land on. The flows below cite back to these homes.

| Subsystem | Directory | Key types (file) |
| --- | --- | --- |
| **Resolve / reconciliation graph** | `Sources/SwiftTUIGraph/Resolve/` | The retained `ViewGraph` and `ViewNode`, immutable `ResolvedNode`, `AnyStateSlot`, and `StructuralDiff`. Start at `ViewGraph.evaluateDirtyNodes`; the authored-body driver remains `Resolver.resolve` in `Sources/SwiftTUIViews/Foundation/ViewFoundation.swift`. |
| **Layout (measure + place)** | `Sources/SwiftTUICore/Measure/` and `Sources/SwiftTUICore/Place/` | `LayoutEngine`, `MeasuredNode`, and `PlacedNode`; the authored `Layout` protocol lives in `Sources/SwiftTUIViews/Layout/CustomLayout.swift`. Proposal/response uses `ProposedSize` from `Sources/SwiftTUIPrimitives/Geometry/GeometryTypes.swift`. |
| **Geometry** | `Sources/SwiftTUIPrimitives/Geometry/` | Cell space (`CellPoint`/`CellSize`/`CellRect`), continuous space (`Point`/`Size`/`Rect`), pixel space (`PixelPoint`/`PixelSize`), `Axis`, and `Path`. Graph-aware `Anchor` types live in `Sources/SwiftTUIGraph/Geometry/`. |
| **State & observation** | `Sources/SwiftTUIViews/State/` (authoring) + `Sources/SwiftTUIGraph/Resolve/` and `Sources/SwiftTUIGraph/Runtime/` (engine) | `State`, `Binding`, and `AuthoringContext` on the authored side; `AnyStateSlot` and `StateContainer` on the graph side. Follow invalidation through `DependencyTracker` and `InvalidationSourceTrace`, then `ViewGraph.queueDirtyForStateChange`. |
| **Focus** | `Sources/SwiftTUICore/Semantics/` (render-time tracking) + `Sources/SwiftTUIGraph/Semantics/` (graph values) + `Sources/SwiftTUIViews/State/` and `Sources/SwiftTUIViews/Focus/` (authoring) | `FocusTracker` remains in Core; `FocusedValues`, `FocusParticipation`, `AutomaticFocusPolicy`, and graph-facing focus metadata live in Graph. `FocusState`, `FocusedValue`, and `DefaultFocus` are authored in Views. |
| **Gestures & pointer** | `Sources/SwiftTUIViews/Gestures/` (authoring) + `Sources/SwiftTUIGraph/Semantics/` (recognition) + `Sources/SwiftTUIPrimitives/Pointer/` (values) | `Gesture`, `DragGesture`, `TapGesture`, `LongPressGesture`, and `GestureState`; Graph's `GestureRecognizer`; Primitives' `HoverPhase` and `PointerLocation`. Run-loop hit testing starts at `Sources/SwiftTUIRuntime/RunLoop/RunLoop+PointerHitTesting.swift`. |
| **Environment** | `Sources/SwiftTUIViews/Environment/` | `Environment`, `EnvironmentValues`, `ResolveContext`, `StyleEnvironment`, and `PointerInputEnvironment`. |
| **Animation** | `Sources/SwiftTUIRuntime/Lifecycle/` (driver) + `Sources/SwiftTUIViews/Animation/` (authoring) + `Sources/SwiftTUIGraph/Animation/` (intent) + `Sources/SwiftTUIPrimitives/Animation/` (math) | `AnimationController`, `ScrollMomentumController`, and `PointerVelocitySampler`; authored `Animation`/`withAnimation`/`PhaseAnimator`/`TimelineView`/`AnyTransition`; Graph's `AnimationProtocols`; Primitives' `AnimatableArray`. |
| **Presentation** | `Sources/SwiftTUIViews/Presentation/` | Boolean and optional-item modifiers emit through `PresentationTriggerLeaf`; `PresentationCoordinatorRegistry` owns family ordering and Escape dispatch; `OverlayStackEntryHost` registers presenter `onDismiss` observers on committed entry teardown. `fullScreenCover` reuses the sheet family with an internal full-screen surface mode. |
| **Semantics / accessibility** | `Sources/SwiftTUICore/Semantics/` + `Sources/SwiftTUIRuntime/Accessibility/` | Core's `SemanticExtractor` and `SemanticSnapshot`; Runtime's `LinearAccessibilityRenderer` and `LiveRegionAnnouncer`. |
| **Draw / raster** | `Sources/SwiftTUICore/Draw/` and `Sources/SwiftTUICore/Raster/` | `DrawExtractor` → `DrawNode`; `Rasterizer` → `RasterSurface`. Braille/canvas drawing and image compositing also live under Draw. |
| **Commit** | `Sources/SwiftTUICore/Commit/` | `CommitPlanner` → `CommitPlan`; `FrameArtifacts` gathers all seven products; `PresentationDamage` describes host-facing raster damage. |
| **Styling** | `Sources/SwiftTUIPrimitives/Styling/` + `Sources/SwiftTUICore/Styling/` | Primitives owns `Color`, `Theme`, `BorderSet`, gradients, shapes, appearance, and structural text-style values; Core owns render-time collection-style layout and text-style resolution. |
| **Runtime registries** | `Sources/SwiftTUIGraph/Runtime/` | Per-node “what did this view register” tables: `ActionScope`, `CommandRegistry`, `LocalGestureRegistry`, `LocalTaskRegistry`, `LocalKeyHandlerRegistry`, `PreferenceValues`, and `RuntimeRegistrationSet`. |
| **Run loop & rendering** | `Sources/SwiftTUIRuntime/RunLoop/` and `Sources/SwiftTUIRuntime/Rendering/` | `RunLoop`, `DefaultRenderer`, `RuntimeRenderPipeline`, and the frame-head/frame-tail coordinators. |
| **Scenes & hosting** | `Sources/SwiftTUIRuntime/Scenes/` | `App`, `Scene`, `WindowGroup`, `SceneSession`, `HostedSceneSession`, and `WindowSceneSelection`. |
| **Terminal & host contracts** | `Sources/SwiftTUIRuntime/Terminal/` | `TerminalHost`, `PresentationSurface`, and `SemanticHostFrame` — the committed-frame contract non-terminal hosts consume. |
| **Host runners** | `Platforms/` | `TerminalRunner`, `WASIRunner`, `WebHostRunner`, `WebHostCLIRunner`, the `SwiftTUIAndroidHost` ABI, and `SwiftTUIArguments`. |

### Three subsystems worth a closer look on day one

These are the ones whose *shape* is non-obvious and most often misread — and each one
underlies a flow below.

**Resolve is two graphs, not one.** `ViewGraph`
(`Sources/SwiftTUIGraph/Resolve/ViewGraph.swift`) is the *live, retained, mutable*
graph of `ViewNode`s that persists across frames and owns
identity, state ownership, and runtime registrations. `ResolvedNode`
is the *immutable, per-frame* product of resolve. A new
engineer's most common mistake is treating `ResolvedNode` as if it carried
persistent state — it does not; persistence lives in `ViewGraph`/`ViewNode`. Inside
`ViewGraph`, the ~36 retained fields are grouped into nine `package` value sub-structs
(`Sources/SwiftTUIGraph/Resolve/ViewGraphFieldGroups.swift`: `GraphIndex`, `DirtyState`,
`FrameCommitState`, `LifecycleEventBuffers`, …) so an abortable frame's *checkpoint*
copies them wholesale and `restore` cannot silently drop one —
`ViewGraphCheckpointTotalityTests` enforces the coverage. Start at
`ViewGraph.evaluateDirtyNodes` to follow dirty-frontier evaluation. Reuse
(retained reuse + memoized-body reuse) is decided here against the frame's
invalidation set. The [interaction flow](#3b-the-interaction--update-loop) lives and
dies on this distinction.

**Layout is recursive size negotiation, not a constraint solver.** A parent proposes
a `ProposedSize` to each child; the child reports a wanted size; the parent places
the child. `LayoutEngine` (`Sources/SwiftTUICore/Measure/LayoutEngine.swift`)
drives both measure and place — note the directory split (`Measure/` for sizing,
`Place/` for positioning) is *one* `LayoutEngine` struct with `+`-suffixed extension
files, **not** two types. The authored `Layout` protocol
(`Sources/SwiftTUIViews/Layout/CustomLayout.swift`) is the public hook; `Layout`
requires `Sendable` (value and cache), so the renderer can run any custom layout on
the frame-tail worker.

**The host boundary is a committed contract, never renderer internals.** Below
`commit`, every host consumes a *committed* frame: a `RasterSurface` plus a
`SemanticHostFrame` (`Sources/SwiftTUIRuntime/Terminal/PresentationSurface.swift`).
The pipeline contracts above the host are shared by all five; the selected engine
profile may change reuse strategy without changing those contracts, and the
presentation transport differs below them. The
[five-hosts flow](#3d-one-app-five-hosts) is entirely about what happens below this
line.

### Map-level invariants

- **Dependency direction is one-way.** `Primitives → Graph → Core → Views → Runtime
  → SwiftTUI`. Peer
  products and `Platforms/` runners depend *into* the spine, never the reverse. Core
  is never allowed to know a Runtime or host type.
- **Primitives, Graph, Core, and the authoring/convenience layers are source-level
  Foundation-free and terminal-IO-free**, enforced by prek hooks. The separate
  `Scripts/check_foundation_free_layers.sh` proves the transitive boundary through
  Views; the `SwiftTUI` convenience target legitimately re-exports Runtime/WebHost
  dependencies that load Foundation. Terminal/POSIX/Foundation implementation code
  starts no earlier than `SwiftTUIRuntime`.
- **One package, many products.** All `Platforms/` sources are targets in the root
  `Package.swift`; there are no nested SwiftPM packages under `Platforms/`.
- **`SwiftTUIProfiling` is strictly opt-in.** Nothing in the default graph depends on
  it; the runtime emits neutral `RuntimeFrameSample`s through `FrameDiagnosticSink`.
- **Hosts consume committed contracts** (`RasterSurface` + `SemanticHostFrame`),
  never renderer-private retained state.

### Map-level gotchas

- **`Resolver` lives in Views, not Graph.** Despite `ResolvedNode`/`ViewGraph`
  living in `Sources/SwiftTUIGraph/Resolve/`, the
  `Resolver` entry point that evaluates authored bodies is
  `Sources/SwiftTUIViews/Foundation/ViewFoundation.swift` — because it must call
  `View.body`, a Views concept. Resolve straddles the Graph/Views seam through
  erased evaluator thunks rather than a reverse module dependency.
- **The two non-terminal native hosts are in other repos.** The SwiftUI surface
  (`SwiftUIHost`) is in `swift-tui-swiftui`; the Compose UI is in
  `swift-tui-android`. The `SwiftTUIAndroidHost` target *here* is only the
  Swift-side JNI/C ABI bridge.
- **`Measure/` and `Place/` are one engine.** Two directories for readability, both
  holding `LayoutEngine+*.swift` extensions of the single struct. Don't look for
  separate "measurer" and "placer" types.
- **State directories are split by role.** Authoring property wrappers live in
  `Sources/SwiftTUIViews/State/`; the *storage and ownership* live in
  `Sources/SwiftTUIGraph/`. A state bug usually means visiting both.
- **WASI breaks ship green.** The Linux Repo Gate does **not** compile `wasm32-wasi`,
  so a WASI-only break passes CI and only surfaces in the examples/site gates after a
  tag is cut. New files touching C stdio/POSIX must be WASI-safe; cross-build before
  tagging. This gotcha recurs in three flows below — internalize it now.
- **`SwiftTUICore` is internal.** Not a published product; consumers reach it only
  re-exported through `SwiftTUIViews` or `SwiftTUIRuntime`. Public API you add in
  Core becomes visible only if a higher layer re-exports it.

---

## The flows

Four vertical traces, each self-contained. They share terminology with the map and
cross-reference each other. The first condenses the existing render-pipeline article;
the next three were written to complement it — they trace the lifecycle *around* a
frame, the reactivity *into* a frame, and the host adapters *out of* a frame.

```text
            [3c] bootstrap & lifecycle  -- starts the loop, owns when frames run
                         |
                         v
   event --[3b] interaction loop--> resolve --[3a] render pipeline--> commit --[3d] five hosts--> screen
```

### 3a. The render pipeline (condensed)

> **Full trace:** <doc:Runtime-Render-Pipeline> — how one authored tree becomes one
> committed frame. This is a tight summary so the other flows have a shared
> vocabulary; read the full article for the phase-by-phase detail.

**Mental model.** One authored `View` tree becomes one committed frame by flowing
through seven typed phase products: `resolve → measure → place → semantics → draw →
raster → commit`. Each product is an immutable value computed from the previous one;
`DefaultRenderer` owns the components that compute them, and `RunLoop` owns
presentation and per-host damage afterward.

**The two views, restated.** As [the map](#two-pipeline-views-are-the-same-work)
explains, the seven phase products are the *data model*; the runtime stages
`head → animationInjection → latePreferenceReconciliation → fusedFrameTail → commit`
are the *scheduling model* over the same work. The scheduling boundaries matter for
concurrency: **`resolve` (head) and `commit` stay on the main actor; the fused tail
(`measure → place → semantics → draw → raster`) may run off the main actor** for
throughput. This actor split is why `Layout` requires `Sendable` (value and cache) — the
worker may run any custom layout (see the map's layout note) — and why nothing
in the tail may touch live `ViewGraph`/`@State` mutable state.

**Where the boundaries are.** The other flows hand off to this one at precise points:

- [3b, the interaction loop](#3b-the-interaction--update-loop) stops at the resolve
  boundary (`DefaultRenderer.render*` / `ViewGraph.evaluateDirtyNodes`) and resumes
  at focus convergence after commit. It never re-traces the phase products.
- [3d, five hosts](#3d-one-app-five-hosts) begins at `commit`: it consumes the
  public `RenderSnapshot`/`RasterSurface`/`SemanticHostFrame` contracts and never
  reaches up into renderer-private tail state.

**Key types.** Package IR flows `ResolvedNode` → `MeasuredNode` → `PlacedNode` →
`SemanticSnapshot` → `DrawNode` → `RasterSurface` → `CommitPlan`. Graph owns
`ResolvedNode` in `Sources/SwiftTUIGraph/Resolve/`; Core owns the remaining render
products under `Sources/SwiftTUICore/` (`Measure/`, `Place/`, `Semantics/`, `Draw/`,
`Raster/`, `Commit/`). Runtime orchestration lives in
`Sources/SwiftTUIRuntime/Rendering/`. `FrameArtifacts` gathers all seven products as
the package-only committed bundle; public one-shot callers see `RenderSnapshot`, and
hosts consume `RasterSurface`/`SemanticHostFrame`.

**Invariant to carry into the other flows.** Hosts consume committed contracts, never
renderer-private state; reuse hints (e.g. rasterizer surface reuse) must not leak
past `commit`. This is the contract that makes "one tree, five hosts" hold.

### 3b. The interaction → update loop

> Vertical trace: *"How does a keypress become an updated screen?"* This is the
> **reactivity edge**: event → handler → `@State` write → invalidation → coalesced
> frame → dirty-frontier re-resolve. It hands off to [3a](#3a-the-render-pipeline-condensed)
> at resolve and resumes at focus convergence.

**Mental model.** A running SwiftTUI app is a single `@MainActor` event loop wrapped
around a renderer, with two interleaving halves: an **intake** half that turns raw
transport bytes into typed runtime events and folds them into a coalescing scheduler,
and a **frame** half that — once the scheduler reports a frame is due — re-resolves
only the part of the tree a `@State` write touched, runs the render pipeline, and
presents to whichever host is attached.

The reactivity model is the load-bearing idea. A keypress never re-renders the whole
tree by itself. It runs a handler; the handler writes `@State`; the write records a
dirty node-id and asks the scheduler for an invalidation; the scheduler *coalesces*
that with any others into one `ScheduledFrame`; the loop consumes that frame and asks
the `ViewGraph` to evaluate only the **dirty frontier** (the topmost dirty nodes),
reusing every unchanged subtree. Focus and pointer state ride alongside as separate
invalidation sources, and a small **focus-sync convergence loop** re-resolves when
applying focus changes the semantic graph.

Everything that evaluates an authored body or mutates live runtime state stays on the
main actor. Byte *reading* happens off-actor; the event *stream* re-enters the main
actor at the run loop.

**End-to-end callpath.**

```text
terminal/transport bytes
  -> InputReader.makeTerminalInputEventStream()         // off-actor DispatchSource read
  -> TerminalInputEventDecoder.decode(_:)               // bytes -> [InputEvent] via TerminalInputParser.feed
  -> AsyncStream<InputEvent>  (coalesced mouse bursts)
  -> RunLoop.makeEventPump() input Task                 // wraps as RuntimeEvent, buffers
  -> EventPumpBuffer.enqueue(_:)                         // merges coalescible pointer events
  -> continuation.yield()                               // wakes the AsyncStream<Void>
  -> RunLoop.run() while-loop: iterator.next()
  -> RunLoop.drainPendingEvents / drainPendingRenderEvents
  -> RunLoop.handle(_:)                                  // RunLoop+EventDispatch.swift
       -> scheduler.requestInput()                       // a wake cause
       -> RunLoop.handleKeyPress(_:) / handleMouseEvent(_:)
  -> localKeyHandlerRegistry.dispatch / localActionRegistry.dispatch / focusTracker.move…
  -> closure body sets @State: State.wrappedValue.set
  -> DynamicStateLocation.setValue
  -> ViewNode.setStateSlot(ordinal:value:invalidationIdentity:)
       -> ViewGraph.queueDirtyForStateChange(key)        // marks dirty node-ids
       -> invalidator.requestInvalidation(of:)           // invalidator IS the FrameScheduler
  -> FrameScheduler coalesces -> ScheduledFrame
  -> RunLoop.renderPendingFramesAsync(...)               // scheduler.consumeReadyFrame
  -> RunLoop.acquireFrameArtifactsAsync -> DefaultRenderer.render*  // <-- render pipeline boundary (3a)
  -> ViewGraph.evaluateDirtyNodes(using: plan)           // re-resolve dirty frontier only
  -> [render pipeline: measure->place->semantics->draw->raster->commit]  // see 3a / Runtime-Render-Pipeline
  -> RunLoop.processFocusSyncIteration(...)              // converge focus/scroll, maybe rerender
  -> RunLoop.applyAcquiredFrame -> presentCommittedFrame -> presentation surface  // <-- five-hosts boundary (3d)
```

**Code Map.**

| Question | Start here |
| --- | --- |
| Where do raw bytes become events? | `Sources/SwiftTUIRuntime/Input/InputReader.swift`, `Input/TerminalInputStreamReading.swift`, `Input/TerminalInputParser.swift` |
| What is the run loop's event-intake shape? | `Sources/SwiftTUIRuntime/RunLoop/RunLoop.swift` (`run()` / `runWithInstalledAnimationSinks()`), `RunLoop/RunLoop+EventPump.swift`, `RunLoop/EventPumpBuffer.swift` |
| Where is a key/pointer event routed to handlers? | `Sources/SwiftTUIRuntime/RunLoop/RunLoop+EventDispatch.swift`, `RunLoop/RunLoop+PointerHandling.swift` |
| How does a `@State` write turn into an invalidation? | `Sources/SwiftTUIViews/State/State.swift`, `Sources/SwiftTUIGraph/Resolve/ViewNode.swift` (`ViewNode.setStateSlot`), `Sources/SwiftTUIGraph/Pipeline/Scheduler.swift` (`FrameScheduler`) |
| How are wakes coalesced into one frame? | `Sources/SwiftTUIGraph/Pipeline/Scheduler.swift` (`FrameScheduler`), `RunLoop/RunLoop+Rendering.swift` |
| How does a write re-resolve exactly the right subtree? | `Sources/SwiftTUIGraph/Resolve/ViewGraph.swift` (`ViewGraph.queueDirtyForStateChange`, `ViewGraph.evaluateDirtyNodes`), `Resolve/ViewGraphDirtyEvaluationPlanning.swift`, `Resolve/ViewGraphInvalidationPlanning.swift` |
| Why might a frame re-render after focus moves? | `Sources/SwiftTUIRuntime/RunLoop/RunLoop+FocusSync.swift`, `Sources/SwiftTUICore/Semantics/FocusTracker.swift` |
| Where does intake hand off to the render pipeline? | `Sources/SwiftTUIRuntime/RunLoop/RunLoop+ResolveContext.swift`, `RunLoop/RunLoop+FrameAcquisition.swift` |

**Step 1 — Bytes become typed input events (off the main actor).** The transport
hands raw bytes to `InputReader`. On Apple/Linux, `makeTerminalInputEventStream()`
opens a `DispatchSource.makeReadSource` on the input fd (`InputReader.swift:178`) and
in the handler calls `drainAvailableTerminalInput(from:maxBytesPerRead:)`
(`TerminalInputStreamReading.swift:93`), looping `read(2)` until `EAGAIN`. Under WASI
there is no Dispatch, so a detached task polls with `readTerminalInputChunk` and an
`InputPollBackoff` (`InputReader.swift:60`). Bytes go through
`TerminalInputEventDecoder.decode(_:)` feeding `TerminalInputParser` to produce typed
`InputEvent`s (`.key`, `.mouse`, `.paste`, `.drop`). Coalescible pointer bursts arm a
*single* delayed `DispatchWorkItem` (`InputReader.swift:208`) rather than rescheduling
per event — the fix for the "scroll does nothing until I click" stall, where a
continuous burst pushed the flush deadline forward forever. Events reach the loop only
as an `AsyncStream<InputEvent>` via the `TerminalInputReading` protocol
(`Input/InputReading.swift:9`).

**Step 2 — The event pump re-enters the main actor and buffers.**
`RunLoop.makeEventPump()` (`RunLoop+EventPump.swift:15`) launches a `Task` that
consumes the stream, wraps each event as `RuntimeEvent.input(...)`, and calls
`EventPumpBuffer.enqueue(_:)`. The buffer is a `Mutex`-guarded staging area
(`EventPumpBuffer.swift:12`) that merges coalescible pointer events in place
(`mergedEvent`, `EventPumpBuffer.swift:54`). Each enqueue `yield()`s a `Void` token on
an `AsyncStream<Void>` — that token is the only thing that wakes the loop. Signals
(`SIGWINCH`) and the scheduler wake-handler feed the same token stream, so the loop
awaits exactly one thing.

**Step 3 — The run loop drains and routes.** `RunLoop.run()` installs the scheduler
as the invalidator for state, focus, and observation
(`stateContainer.invalidator = scheduler`, `RunLoop.swift:246`) and awaits the token
stream. On wake it greedily drains via `drainPendingEvents` then
`drainPendingRenderEvents` (`RunLoop+EventPump.swift:145`, `:170`). Each event passes
to `RunLoop.handle(_:)` (`RunLoop+EventDispatch.swift:10`), which registers a wake
cause (`scheduler.requestInput()` for key/paste/drop; for mouse only when
`shouldScheduleFrame(for:)` agrees — scroll alone does not force a frame,
`RunLoop+PointerHandling.swift:27`) then dispatches. `handleKeyPress`
(`RunLoop+EventDispatch.swift:43`) is the routing priority ladder: modifier
`keyCommand` scopes along the focus chain → configured exit bindings → focused node's
local key-handler → app-level `keyHandler` → framework Escape/dismiss → edit-mode
text → focus navigation (Tab/arrows via `focusTracker`) → activation
(`return`/`space` → `localActionRegistry.dispatch`). A non-`nil` `RunLoopExitReason`
exits the loop; otherwise the frame half runs. Pointer events route through
`handleMouseEvent` → `handleMouseDown/Up/Drag/Move/Scroll`
(`RunLoop+PointerHandling.swift:5`), hit-testing against `latestSemanticSnapshot`.

**Step 4 — A handler writes `@State`; the write records dirt and requests
invalidation.** `State.wrappedValue`'s setter (`State/State.swift:247`) resolves the
live `DynamicStateLocation` for the current graph-scoped owner and calls `setValue`.
For a graph-backed owner, `setValue` reaches `ViewNode.setStateSlot(...)`. Two things
happen — **but only if the value actually changed** (`slot.set` reports `didChange`):

1. `ownerGraph.queueDirtyForStateChange(key)` inserts the
   owning node-id (and recorded *reader* node-ids) into `graphLocalDirtyNodeIDs` and
   marks them `isDirty`. The reader set comes from dependency tracking recorded during
   resolve (`ViewNode.stateSlot`): under reader attribution a
   read records on the node that genuinely read the value, so projecting a binding
   into a disjoint subtree (a sheet background) records nothing and that subtree is
   spared.
2. `invalidator.requestInvalidation(of:)` — and the invalidator *is the
   `FrameScheduler`* — with identities from `stateChangeInvalidationIdentities`
   on `ViewNode`. A `withAnimation` on the stack routes through
   `AnimationAwareInvalidating` so the frame carries the animation request.

The correctness point: the dirty *graph* mutation (1) and the scheduler *intent* (2)
are separate. (1) tells the next resolve which nodes to re-evaluate; (2) tells the
loop a frame is owed.

**Step 5 — The scheduler coalesces every wake into one `ScheduledFrame`.**
`FrameScheduler` in `Sources/SwiftTUIGraph/Pipeline/Scheduler.swift` accumulates a
set of `WakeCause`
(`.input`, `.invalidation`, `.signal`, `.external`, `.deadline`), a union of
`invalidatedIdentities`, signal names, and the nearest animation deadline. Ten
keypresses and a focus move between two frames produce **one** `ScheduledFrame` whose
identities are the union and whose `intentRequestCount` records how many merged
intents. `FrameScheduler.consumeReadyFrame(at:)` atomically drains and clears that
state; `hasPendingFrame`/`nextWakeInstant` let the loop decide whether to render now,
sleep to a deadline, or block.

**Step 6 — The loop re-resolves the dirty frontier.** In
`RunLoop.renderPendingFramesAsync(...)` (`RunLoop+Rendering.swift:293`) the driver
samples `frameClock()` once as `consumedAt`, consumes with it
(`consumeReadyFrame(for:at:)`), and derives this frame's `frameInstant` as
`scheduledFrame.triggeredDeadline ?? consumedAt` — the one instant every
frame-scoped consumer downstream reads instead of the clock. It then
builds a `ResolveContext` carrying `scheduledFrame.invalidatedIdentities`
(`RunLoop+ResolveContext.swift:64`), then acquires artifacts via
`acquireFrameArtifactsAsync → DefaultRenderer.render*`. Inside resolve,
`ViewGraph.evaluateDirtyNodes(using:)` is where reuse pays
off. With selective evaluation enabled (after the first frame, `RunLoop.swift:322`),
`ViewGraphDirtyEvaluationPlanner` computes `dirtyFrontierNodes`
(`ViewGraphDirtyEvaluationPlanning.swift:63`) — the **topmost** dirty nodes (a dirty
node with a dirty ancestor is dropped) mapped to their nearest evaluator ancestor.
Only those call `.evaluate()`; every other subtree is reused via retained `ViewNode`
reuse. If no valid plan exists (first frame, forced root, or untracked invalidated
ids), it falls back to `rootEvaluator?()` — a full re-resolve. This is the mechanism
turning "press a key → one `@State` write" into "re-resolve one button," not "re-resolve
the app."

**Step 7 — Hand off to the render pipeline, then converge focus.** The `ResolvedNode`
tree flows into the pipeline proper ([3a](#3a-the-render-pipeline-condensed)). This
trace resumes at `RunLoop.processFocusSyncIteration(...)`
(`RunLoop+FocusSync.swift:56`): it publishes the new `SemanticSnapshot`, prunes
orphaned gestures, releases pointer capture for vanished regions, then reconciles
focus (`focusTracker.updateRegions`, default-focus binding, focused-values, scroll
sync). If *applying* focus changed the semantic graph, the iteration returns
`.rerender` and the convergence loop re-resolves (retaining reuse to carry first-pass
measurement/scroll state) under a graph-derived budget (`FocusSyncConvergenceState`,
`RunLoop+FocusSync.swift:21`). This is why a focus move can cost an extra re-resolve:
focus is deliberately excluded from `EnvironmentSnapshot` equality, so the old and new
focused controls must recompute — `retainedReuseSuppressionScopeForFrameSafety()`
(`RunLoop+Rendering.swift:396`) narrows reuse off for exactly those identities.

**Step 8 — Present.** Once converged, `applyAcquiredFrame`
(`RunLoop+Rendering.swift:106`) merges lifecycle carry-forward, updates
`latestSemanticSnapshot` (the snapshot the *next* event's hit-testing and key routing
read), derives host-facing damage against the previously presented `RasterSurface`,
and calls `presentCommittedFrame` to the active surface — the boundary [3d](#3d-one-app-five-hosts)
picks up. It also reschedules the next animation deadline if the tick reports pending
work, and clears any transient press identity.

**Invariants and gotchas.**

- **Main-actor confinement.** Byte *reading* is off-actor, but the event *stream*
  re-enters the main actor at the event-pump `Task`, and everything after — handler
  dispatch, `@State` writes, invalidation, resolve, commit, presentation — is
  `@MainActor` (`RunLoop` is `@MainActor`, `RunLoop.swift:4`). Never mutate live
  runtime state from the reader side.
- **The invalidator IS the scheduler.** `stateContainer.invalidator`,
  `focusTracker.invalidator`, and `ViewNode.invalidator` all point at the same
  `FrameScheduler` at loop start (`RunLoop.swift:246`). A `@State` write outside a
  running loop (snapshot `DefaultRenderer`) has a `nil` invalidator and silently
  no-ops the schedule — do not conflate that "no-invalidator snapshot" behavior with
  live-graph behavior.
- **Two-channel invalidation must stay in sync.** A write both *queues graph-local
  dirt* and *requests a scheduler intent*. If the dirty node-ids and scheduled
  identities diverge, `ViewGraphDirtyEvaluationPlanner.targetPlan` bails to a full
  root re-resolve (`ViewGraphDirtyEvaluationPlanning.swift:31`). Selective evaluation
  depends on both channels naming the same nodes.
- **`didChange` gating.** `ViewNode.setStateSlot` only invalidates when the value
  actually changed. Writing an equal value is intentionally inert.
- **Coalescing is correctness, not just speed.** Pointer bursts merge twice (delayed
  flush in `InputReader`, in-place in `EventPumpBuffer.enqueue`) and key/state intents
  collapse in the scheduler. Breaking single-flush-per-cluster reintroduces the
  scroll-stall bug; breaking scheduler coalescing turns one logical update into N
  frames.
- **Invalidation must not leak across reuse.** Identities excluded from
  `EnvironmentSnapshot` equality (focus, press) would otherwise be read stale from a
  reused subtree. The frame-safety reuse-suppression scope
  (`RunLoop+Rendering.swift:396`) and the focus-sync convergence loop exist precisely
  to re-resolve those identities — do not "fix" a stale-focus bug by widening
  suppression to `.all` when a narrower identity set is nameable.

### 3c. App bootstrap & run-loop lifecycle

> Vertical trace: *"How does `MyApp.main()` start up, run, and shut down?"* This
> traces the lifecycle *around* the frame loop — where [3b](#3b-the-interaction--update-loop)
> traces what happens *during* one iteration of it.

**Mental model.** A SwiftTUI app is an **`async` program**, not a synchronous one.
`@main` binds the compiler-synthesized async entry point; the app declares a tree of
`Scene`s; a runner picks one host, constructs one `RunLoop` per scene, and that loop
owns the lifecycle: it enters raw mode, paints a first frame, then parks on an
`AsyncStream` woken by **two** independent sources — input/signal events and a frame
**deadline** (animation/momentum cadence, 33 ms) — and on every wake drains events,
renders pending frames, and re-arms the next deadline. It exits when input ends (EOF),
a fatal signal arrives, or an exit-key fires, unwinding through `defer` blocks that
restore the terminal. The engine is terminal-IO-free; everything OS-specific lives in
`SwiftTUIRuntime/Terminal/` and `Platforms/`.

One load-bearing subtlety threads the whole trace: **`App.main()` is `async`** (it
refines swift-argument-parser's `AsyncParsableCommand`). A bare `MyApp.main()` — muscle
memory from synchronous `SwiftUI.App.main()` — resolves to the *synchronous*
`ParsableCommand.main()` overload, which never starts the runtime. Each launch layer
ships a `static func main() -> Never` shim specifically to turn that mistake into one
loud, accurate error.

**End-to-end callpath.**

```text
@main App  (compiler binds the async entry point)
  -> SwiftTUI.App.main() async                          [convenience App async entry]
  -> WebHostCLIRunner.run(Self.self)                     [Platforms/WebHost/Sources/SwiftTUIWebHostCLI/WebHostCLIRunner.swift:17]
  -> SwiftTUIOptions.parse(...).runtimeConfiguration()   (config.web != nil ? web : terminal)
  -> TerminalRunner.run(app, configuration:)            [Platforms/CLI/Sources/SwiftTUICLI/TerminalRunner.swift]
  -> TerminalRunner.launch -> collectWindowSceneSelections(from: app.body)
  -> SceneRuntime(selection:isPrimary:configuration:)    [Platforms/CLI/Sources/SwiftTUICLI/SceneRuntime.swift:29]
       (builds TerminalHost + InputReader + defaultSignalReader)
  -> SceneRuntime.run -> installCrashGuard()             [SceneRuntime.swift:113,165]
  -> selection.run(...) -> SceneSession.run(...)         [Sources/SwiftTUIRuntime/Scenes/SceneSession.swift:244]
  -> RunLoop(...).run()                                  [Sources/SwiftTUIRuntime/RunLoop/RunLoop.swift:229]
  -> runWithInstalledAnimationSinks()                    [RunLoop.swift:245]
       terminalCommandSurface.enableRawMode()            [RunLoop.swift:254 -> TerminalHost.swift:162]
       eventPump = makeEventPump()                       [RunLoop+EventPump.swift:15]
       scheduler.requestInvalidation([rootIdentity])     [RunLoop.swift:305]  -- arm first frame
       renderPendingFramesAsync(...)                     [RunLoop.swift:316]  -- FIRST FRAME
       renderer.enableSelectiveEvaluation()              [RunLoop.swift:322]
  -> while await iterator.next() != nil { ... }          [RunLoop.swift:340]  -- STEADY STATE
       drainPendingEvents -> handle(event) -> renderPendingFramesAsync   // see 3b
       scheduler.nextWakeInstant -> eventPump.scheduleDeadlineWake(...)
  -> defer: lifecycleCoordinator.shutdown(); disableRawMode()   [RunLoop.swift:257-262]
  -> RunLoopResult(exitReason: .inputEnded | .signal | .userExit)
```

**Code Map.**

| Question | Start here |
| --- | --- |
| How does an app *become* a run loop? | `Sources/SwiftTUIRuntime/Scenes/SceneSession.swift:244` (`SceneSession.run` constructs `RunLoop`) |
| What does `@main MyApp.main()` actually call? | `SwiftTUI.App.main() async` and `Platforms/Arguments/Sources/SwiftTUIArguments/SwiftTUICommand.swift:113,141` (the synchronous-launch diagnostic path) |
| Why does a bare `MyApp.main()` print usage and exit? | `Platforms/Arguments/Sources/SwiftTUIArguments/SwiftTUICommand.swift:113,141` (`synchronousLaunchDiagnosticMessage`, `failSynchronousLaunch`) |
| Terminal vs WebHost routing? | `Platforms/WebHost/Sources/SwiftTUIWebHostCLI/WebHostCLIRunner.swift:51` (`configuration.web != nil`) |
| Where is the host + input/signal readers built? | `Platforms/CLI/Sources/SwiftTUICLI/SceneRuntime.swift:47-89` |
| How are scenes discovered from `App.body`? | `Sources/SwiftTUIRuntime/Scenes/WindowSceneSelection.swift:66` (`collectWindowSceneSelections`) |
| Where is raw mode entered / restored? | `RunLoop.swift:253-262`; `Terminal/TerminalHost.swift:162` / `:225` |
| Where is the alternate screen entered? | `Terminal/TerminalHost.swift:209` (`enterAlternateScreen`, `ESC[?1049h`) |
| What is the steady-state run-loop tick? | `RunLoop.swift:340-452` (`while await iterator.next()`) |
| How does the loop wait on input *vs* the frame deadline? | `RunLoop+EventPump.swift:31`; `RunLoop.swift:444-451` + `FrameScheduler.nextWakeInstant` |
| What drives the ~33 ms deadline? | `Lifecycle/AnimationController.swift:158`, `RunLoop+ScrollMomentum.swift:6`; armed via `RunLoop+PostCommitSupport.swift:118,131,173` |
| How are SIGINT/SIGTERM/SIGWINCH handled? | `RunLoop+EventDispatch.swift:10` (`handle`) + `:232` (`signalDisposition`); reader `Platforms/CLI/Sources/SwiftTUICLI/SignalReader.swift:10` |
| What restores the terminal on crash / abnormal exit? | `SceneRuntime.swift:165` (`installCrashGuard`); `Terminal/TerminalProcessExitCleanup.swift:47` (`atexit`) |
| WASI / Android (no CFRunLoop) entry points? | `Platforms/WASI/Sources/SwiftTUIWASI/WASIRunner.swift:80`; `Platforms/Android/Sources/SwiftTUIAndroidHost/AndroidMainExecutorPump.swift:38` |

**Step 1 — `@main` and the launch shim.** The authored type conforms to
`SwiftTUI.App`, which refines `SwiftTUIRuntime.App` plus `SwiftTUICommand`
(`App.swift:18`). `SwiftTUICommand → AsyncParsableCommand`, so `@main` synthesizes a
call to the **async** `static func main()` at `App.swift:29`, which either routes
through argument parsing (`runParsedCommand`) or calls `WebHostCLIRunner.run(Self.self)`.
Co-located is the trap shim `static func main() -> Never` (`App.swift:59`), duplicated
in every launch layer. It is the most-derived *synchronous* `main()`, so a bare
`MyApp.main()` selects it; its `-> Never` return makes it invalid as `@main`, so
`@main` still binds the async one. It calls `failSynchronousLaunch`
(`SwiftTUICommand.swift:141`), printing the diagnostic from
`synchronousLaunchDiagnosticMessage` (`:113`) to stderr — identical text in DEBUG and
release, deliberately bypassing ArgumentParser's DEBUG-only path.

**Step 2 — Host routing and runtime configuration.** `WebHostCLIRunner.run`
(`:17→32→39`) parses `CommandLine.arguments` into `SwiftTUIOptions`, produces a
`RuntimeConfiguration`, then branches at `:51`: `configuration.web != nil` →
`WebHostRunner.run`, else `TerminalRunner.run`. `RuntimeConfiguration` carries the
knobs the loop reads — `output` (`.tui`), `motion`, `debug`, optional `web`. The plain
terminal path uses the env-detecting `RuntimeConfiguration.detect(environment:isStdoutTTY:)`,
honoring `NO_COLOR`, `LANG=C`, `SWIFTTUI_*` with no app code.

**Step 3 — Scene selection.** `TerminalRunner.launch` evaluates `app.body` and runs
`collectWindowSceneSelections(from:)` (`WindowSceneSelection.swift:66`), a
`WindowSceneVisitor` flattening the `@SceneBuilder` tree into `[SelectedWindowScene]`.
Empty ⇒ `AppLaunchError.noScenes`. Each selection captures the scene's `rootIdentity`
(`Identity(components: ["App", id])`, `Scenes/App.swift:163`) and a `runSceneClosure`
deferring to `SceneSession.run`. `CLIMode.parse` then routes between running (`.app`)
and the multi-instance socket subcommands (`.listInstances`, `.listScenes`,
`.attach`).

**Step 4 — Per-scene host construction.** `launchApp` builds one `SceneRuntime` per
selection, the first marked `isPrimary`. `SceneRuntime.init` (`SceneRuntime.swift:29`)
wires host resources for the primary scene: `presentationSurface: TerminalHost(...)`
(owns the real tty), `terminalInputReader: InputReader()`,
`signalReader: defaultSignalReader()` (over `[.sigint, .sigterm, .sigwinch]`,
`SignalReader.swift:10`), and `capabilityProfile = TerminalCapabilityProfile.detect(...).applying(configuration)`.
Secondary scenes get a pty-backed `TerminalHost` so they can be `attach`ed later. Each
`SceneRuntime` runs in its own `Task` inside a `withThrowingTaskGroup` alongside the
`SceneDiscoveryServer`; the first task to finish tears the group down via
`defer`/`cancelAll`.

**Step 5 — Crash guard, then `RunLoop` construction.** For the primary scene,
`SceneRuntime.run` calls `installCrashGuard()` (`:113,165`) **before** raw mode: it
snapshots `termios` via `tcgetattr` and registers a `CrashSignalHandler.ResetAction`
(vendored `CrashSignalHandler.install`) for fatal signals, so
a SIGSEGV/SIGABRT resets mouse reporting, shows the cursor, resets style, and exits the
alternate screen *from inside the signal handler* before the process dies;
`defer { CrashSignalHandler.uninstall() }` removes it on normal exit. `selection.run →
SceneSession.run` (`SceneSession.swift:244`) builds the `EnvironmentSnapshot` and
constructs the `RunLoop` (`:266`), handing it the surface, readers, `FrameScheduler`,
`StateContainer`, `FocusTracker`, and `exitKeyBindings`, optionally installing a
`frameSink` (profiling, or `SWIFTTUI_FRAME_TRACE`), then calls `runLoop.run()`. The
`RunLoop` initializer defaults `renderMode = .environmentDefault()` (i.e. `.async`).

**Step 6 — Raw mode, alternate screen, and the first frame.** `RunLoop.run()`
(`:229`) installs the task-local animation/transition/completion/accessibility sinks
(so concurrent hosted scenes can't steal each other's registrations) and calls
`runWithInstalledAnimationSinks()` (`:245`), the lifecycle spine:

1. Wires `scheduler` as the invalidator for `stateContainer`, `focusTracker`,
   `observationBridge` (`:246-248`) — so a `@State` mutation or focus change calls
   `scheduler.requestInvalidation(...)` and wakes the loop (the same wiring
   [3b](#3b-the-interaction--update-loop) depends on).
2. If `output == .tui`, calls `terminalCommandSurface?.enableRawMode()` (`:254`).
   `TerminalHost.enableRawMode` (`TerminalHost.swift:162`) checks `isATTY`,
   `cfmakeraw`s, sets `O_NONBLOCK`, activates a `TerminalRawModeSession` (registering
   the `atexit` cleanup — Step 8), then writes entry sequences: enter alternate screen
   (`ESC[?1049h`, `:209`), clear, home, hide cursor, enable mouse, enable bracketed
   paste. A mid-sequence failure is unwound by the `defer` at `:192`.
3. Registers the matching `defer { lifecycleCoordinator.shutdown(); disableRawMode() }`
   (`:257-262`) — the single teardown point that restores the terminal however the
   loop exits.
4. Builds the event pump and gets `iterator = eventPump.stream.makeAsyncIterator()`.
5. **Arms the first frame** with `scheduler.requestInvalidation(of: [rootIdentity])`
   (`:305`), then renders it with `renderPendingFramesAsync(...)` (`:316`) — the first
   trip through the [3a](#3a-the-render-pipeline-condensed) tail.
6. Calls `renderer.enableSelectiveEvaluation()` (`:322`) so subsequent frames
   re-evaluate only dirty subtrees (the optimization [3b](#3b-the-interaction--update-loop)
   step 6 relies on).

**Step 7 — The steady-state tick (input vs. the frame deadline).** The pump is an
`AsyncStream<Void>` (`RunLoop+EventPump.swift:31`) yielded by three sources: an input
task (`:63`), a signal task (`:104`), and the scheduler's wake handler (`:114`, fires
on any `requestInvalidation`/`requestDeadline`). The `Void` yield is just a "wake up"
signal; events live in the `EventPumpBuffer`. A `DeadlineWakeState` lets the loop
schedule a timed self-wake via `scheduleDeadlineWake(_:)`. The steady loop is
`while await iterator.next() != nil` (`RunLoop.swift:340`). Each wake:

1. `drainPendingEvents` (`:354`) pulls buffered events.
2. If any, `drainPendingRenderEvents` coalesces stragglers, then each goes through
   `handle(event)` ([3b](#3b-the-interaction--update-loop) step 3): a key press →
   `requestInput()` + `handleKeyPress` (may return `.userExit`); a signal →
   `requestSignal` + `signalDisposition` (`SIGWINCH → .continueFrame`, else
   `.exit(.signal(name))`, `:232`); mouse/paste/drop → `requestInput` + dispatch.
3. After events, `renderPendingFramesAsync(...)` drains the scheduler one full frame
   per ready entry.
4. The loop computes the next self-wake via `scheduler.nextWakeInstant(after:)`
   and, if a deadline is pending in the future,
   `eventPump.scheduleDeadlineWake(...)`. With no pending cause and no deadline,
   `nextWakeInstant` returns `nil` and the loop simply blocks — **fully idle, zero
   CPU** — until input/signal/invalidation arrives.

The ~33 ms deadline is *demand-driven*, not a fixed timer. After a frame commits,
`requestNextAnimationFrameIfNeeded` (`RunLoop+PostCommitSupport.swift:103`) arms
`scheduler.requestDeadline(...)` only while the `AnimationController` has pending work
(`frameInterval = .milliseconds(33)`, `AnimationController.swift:158`); scroll
momentum/fling arms its own 33 ms cadence (`RunLoop+ScrollMomentum.swift`). A static
screen arms no deadline. `FrameScheduler.consumeReadyFrame` tags the produced
`ScheduledFrame` with a `.deadline` cause when `nextDeadline <= now`,
distinguishing an animation frame from an input/invalidation frame.

**Step 8 — Teardown and restore.** The loop returns a `RunLoopResult` with one of
three `RunLoopExitReason`s: `.inputEnded` (stream finished — stdin EOF, both pump
tasks done), `.signal(name)` (a non-`SIGWINCH` signal, flushed before exit so the last
frame paints), or `.userExit(KeyPress)`. `terminationDisposition(for:)`
(`RunLoop+RuntimeSupport.swift:40`) lets a registered termination handler **veto** an
exit by mapping it to `.cancel`, re-arming the root and continuing. On the way out, the
`defer` at `RunLoop.swift:257` runs `lifecycleCoordinator.shutdown()` (cancels `.task`
bodies, fires `onDisappear`) and `disableRawMode()` (`TerminalHost.swift:225`), which
drains the writer and **synchronously** writes the exit sequences then restores the
saved `termios`. Belt-and-suspenders for paths that bypass the `defer`: the
`enableRawMode` `atexit` action (`TerminalProcessExitCleanup.swift:47,61`) and the
crash guard. The three restore layers — `defer`, `atexit`, crash handler — are
intentionally redundant.

**Invariants.**

- **`@main` binds the async `main()`.** A bare `MyApp.main()` is a bug; the `-> Never`
  shim (`App.swift:59`) makes it fail loudly. Launch with `@main` and no explicit
  `main()` call.
- **The scheduler is the only thing that schedules frames.** `@State` writes, focus,
  observation, input, signals, and animation deadlines all funnel through
  `FrameScheduler.request*`; the loop never re-renders speculatively.
- **Raw-mode entry and restore are paired by `defer`.** `enableRawMode` (`:254`) is
  matched by `disableRawMode` in the `defer` (`:259`); do not add an early `return`
  between them that skips the `defer`.
- **One flexible deadline source per concern.** Animation (`AnimationController`) and
  momentum (`ScrollMomentumController`) each arm their own 33 ms deadline; momentum is
  deliberately *not* routed through the animation controller.
- **A static screen must idle.** If `nextWakeInstant` returns non-`nil` on a screen
  with no animation, something is leaking a deadline — the "loop stays hot" class of
  bug (`RunLoop+PostCommitSupport.swift:150-174` documents the re-arm conditions).

**Gotchas.**

- **The sync-`main()` trap is silent in release.** In DEBUG, ArgumentParser's
  synchronous overload aborts with a misleading availability error; in release the
  guard is compiled out and it *silently prints usage and exits 0*. The `-> Never`
  shim is the only consistent signal — don't delete it when refactoring launch layers.
- **WASI and Android have no CFRunLoop.** On Darwin/Linux the OS run loop continuously
  drains the main-actor executor, so `await`, `.task` resumptions, and deadline wakes
  flow for free. **WASI** runs single-shot per surface message via `WASIRunner`
  (`WASIRunner.swift:80`) over a `WebSurfaceTransport`, resizes synthesized as
  in-process `SIGWINCH`. **Android** must explicitly install a host-driven main
  executor: `AndroidMainExecutorPump.installIfNeeded()`
  (`AndroidMainExecutorPump.swift:54`) swaps in `HostMainExecutor` via
  `_createExecutors` *before any main-actor work*, and the Kotlin host calls
  `drainReadyJobs()` ~30 Hz to run queued jobs (see [3d](#3d-one-app-five-hosts)). Under
  Android the loop also uses `renderMode == .sync` with a `directWake` bypass
  (`RunLoop.swift:264-296`). Installing a custom main executor *after* the platform
  default materializes is a fatal error.
- **`SIGWINCH` is not an exit.** `signalDisposition` (`RunLoop+EventDispatch.swift:232`)
  maps only `SIGWINCH → .continueFrame`; every other signal exits. A new "soft" signal
  must be added there or it tears the session down.
- **Signal teardown must be signal-safe.** The crash path and `atexit` path write fixed
  reset byte arrays and call `tcsetattr` directly — no allocation, no Swift runtime
  calls. Keep new reset logic in the precomputed `resetBytes`, never inline async work
  into a handler.
- **WASI-only breaks ship green.** As the map warns, the Linux Repo Gate does not
  compile `wasm32-wasi`. Anything in the bootstrap/terminal path not gated
  `#if !canImport(WASILibc)` only fails after a tag is cut. Cross-build
  `SwiftTUIRuntime` for the WASI SDK before tagging.
- **The first frame may render twice.** After the initial `renderPendingFramesAsync`
  (`:316`), the loop re-checks `scheduler.hasPendingFrame(at:)` (`:326`) and may render
  once more before steady state — a frame queued during first-frame setup (e.g. an
  `onAppear` invalidation) is flushed immediately.

### 3d. One App, five hosts

> Vertical trace: *"How does the same authored tree reach a terminal, a browser, a
> native SwiftUI view, and an Android Compose surface?"* This flow lives entirely
> **below** the committed-frame boundary — it picks up exactly where [3b](#3b-the-interaction--update-loop)
> step 8 calls `presentCommittedFrame`.

**Mental model.** A SwiftTUI program authors **one** view tree, and that tree is
rendered through the same phase sequence and contracts for every host. Graph
owns resolve, Core owns the render products, and Runtime orchestrates them; the
process's engine profile may change resolve mechanics above the boundary. The
presentation host enters **below the committed-frame boundary** through a thin
surface adapter that turns a finished frame into terminal bytes, a JSON wire
frame, or native pixels.

The single contract every non-terminal host consumes is the value type
`SemanticHostFrame` (`Sources/SwiftTUIRuntime/Terminal/PresentationSurface.swift`):
a committed `RasterSurface` plus the `SemanticSnapshot`, focused identity, host-facing
raster damage, monotonic producer `sequence`, and preferred layout size. Everything
above the boundary shares one contract and phase order, modulo the engine
profile; everything below is a per-host adapter.

```text
App.body  ->  RunLoop (shared engine, host-selected profile)
           ->  phase products (3a): resolve -> measure -> place -> semantics -> draw -> raster -> commit
           ->  FrameArtifacts (package committed)    === COMMITTED-FRAME BOUNDARY ===
           ->  RenderSnapshot / host contracts       === PUBLIC-HOST BOUNDARY ===
           ->  RunLoop.presentCommittedFrame(artifacts, damage:)
                 -> SemanticHostFrame  ───────────┬──> HostWireFrameModel ─┬──> WASI stdout
                                                  │                        ├──> WebHost WebSocket
                                                  │                        └──> Android ABI
                                                  └──> HostedRasterSurface ────> SwiftUI host
                 -> RasterSurface (+ ANSI plan) ─────> TerminalHost ────────────> terminal bytes
```

**Code Map.** Per host, the entry file and how it consumes the committed frame.

| Host | Entry file | How it consumes the frame |
| --- | --- | --- |
| Shared boundary | `Sources/SwiftTUIRuntime/RunLoop/RunLoop+Presentation.swift` | `RunLoop.presentCommittedFrame(_:damage:)` branches on `RuntimeConfiguration.output` and the roles the surface implements; builds a `SemanticHostFrame` for semantic-frame surfaces or takes a raster role for terminal presentation. |
| Terminal (CLI / Embedding) | `Sources/SwiftTUIRuntime/Terminal/TerminalHost.swift`, `Platforms/CLI/Sources/SwiftTUICLI/TerminalRunner.swift` | `TerminalHost.present(_:damage:)` plans incremental vs full repaint and writes ANSI/cell bytes + image protocols. |
| WASI static bundle | `Platforms/WASI/Sources/SwiftTUIWASI/WASIRunner.swift`, `Platforms/WASI/Sources/WASISurfaceBridge/WebSurfaceTransport.swift` | `WebSurfaceTransport.present(_:)` JSON-encodes the frame via `WebSurfaceFrameEncoder` and writes it to a stdout file descriptor. |
| localhost WebHost | `Platforms/WebHost/Sources/SwiftTUIWebHost/WebHostRunner.swift`, `Platforms/WebHost/Sources/SwiftTUIWebHost/WebSocketSurfaceTransport.swift` | Same `WebSurfaceFrameEncoder` wire frame as WASI, but bytes go over a WebSocket pump instead of a file descriptor. |
| Native SwiftUI host | `SwiftUIHostSceneHost`, `NativeRasterSurfaceRenderer` (in the sibling `swift-tui-swiftui` package) | `HostedRasterSurface.onFrame` stores the frame on an `@Observable`; SwiftUI repaints by drawing the `RasterSurface` cell-by-cell into a `CGContext` (NSView/UIView). |
| Android Compose host | `Platforms/Android/Sources/SwiftTUIAndroidHost/AndroidHostSceneHost.swift`, `Platforms/Android/Sources/SwiftTUIAndroidHost/AndroidMainExecutorPump.swift` | `HostedRasterSurface.onFrame` stores the frame; the ABI copy path encodes it as a converged web-surface record (encode-at-copy); Kotlin pulls bytes across the ABI each tick and *drives the Swift main executor* manually. |

**Step 0 — Everything above the boundary is shared.** Each host builds a
`SceneSessionResources(presentationSurface:…)` and runs the **same** `SceneSession →
RunLoop → DefaultRenderer`. The host injects only a *surface object* and an *input
reader*; the run loop, invalidation coalescing, animation controller, `@State`
ownership, layout, raster, and commit policy are identical **modulo the per-host
engine profile**.
`TerminalRunner`, `WebHostRunner`, `WASIRunner`, and
`HostedSceneSession.start()` all construct
`SceneSessionResources` the same way and differ only in the `presentationSurface`.
WASI defaults to the stack-lean profile while the other hosts default to full
reuse. See
[docs/HOSTS-AND-PLATFORMS.md](HOSTS-AND-PLATFORMS.md), the owner of per-host
engine-profile truth.

**Step 1 — The committed-frame boundary.**
`RunLoop.presentCommittedFrame(artifacts:damage:)` derives host-facing damage against
the surface *this* run loop last presented (`previousPresentedRasterSurface`, diffed
by `presentationDamage(for:)`), then dispatches by capability, in order:

1. `output == .json` → `presentJSONFrame`.
2. `output == .accessible` → `presentLinearAccessibilityFrame`.
3. surface is `SemanticHostFramePresentationSurface` → build a `SemanticHostFrame`
   (sequence, raster, scroll-enriched semantics, focused identity, damage, preferred
   size) and `present(_:)` it. **WASI, WebHost, SwiftUI, and Android take this path.**
4. surface is `DamageAwarePresentationSurface` → `present(raster, damage:)`. **Terminal
   takes this path.**
5. plain `RasterPresentationSurface` → full repaint fallback.

Roles are defined in
`Sources/SwiftTUIRuntime/Terminal/PresentationSurface.swift`. A terminal conforms to
the aggregate `PresentationSurface`; non-terminal hosts conform to the narrow
`SemanticHostFramePresentationSurface` plus `PresentationSurfaceMetricsProvider`.

**Step 2 — Terminal: ANSI/cell bytes + image protocols.** `TerminalHost` is the only
host that owns raw mode and writes terminal control bytes. Its
`TerminalHost.present(_:damage:)` plans a strategy
(`TerminalPresentationPlanner` → full repaint vs incremental row batches) and lowers it
via `TerminalHostPresentationEmissionBuilder` in
`Sources/SwiftTUIRuntime/Terminal/TerminalHost+PresentationEmission.swift`:
cursor moves, `eraseToEndOfLine`, styled cell runs, and Kitty/Sixel/iTerm image
write-steps. The CLI runner wires a real terminal device; the embedding products
(`Platforms/Embedding/`) wire a PTY-backed emulator view. The whole emission builder is
compiled out under `#if !canImport(WASILibc)` — terminal byte I/O is not WASI-safe.

**Step 3 — One wire, three consumers.** WASI, WebHost, and Android serialize the
**same JSON wire frame** through `WebSurfaceFrameEncoder.encode(_:…)` in
`Sources/SwiftTUIRuntime/Terminal/WebSurfaceFrameEncoder.swift`. The encoder lives
in Runtime, not the WASI bridge, because the wire is host-neutral. The
frame becomes a `\u{1E}surface:{…}` record carrying `width`/`height`, a deduplicated
`styles` table, per-row cell runs, image attachments, raster `damage`, accessibility
tree, announcements, and scroll regions (versioned, with optional delta encoding).

Records also carry **delivery-coupling** keys, so a consumer can tell whether a
record is applicable to the state it actually holds rather than assuming it
received everything:

- `epoch` — the encoding state a record was produced from (a process-local
  `epochID`). A consumer that sees a new epoch has a fresh baseline.
- `gen` — the record's generation within that epoch, starting at 1 and
  increasing once per committed full or delta record.
- `baselineGen` — on a delta only: the generation immediately preceding it in
  that epoch. With `epoch`, this is what lets a consumer *reject* a stale,
  reordered, or non-contiguous delta instead of silently applying it to the
  wrong baseline.
- `stylesBase` — on a delta only, and only when the `styleAppend` capability is
  negotiated: the retained style table's length, onto which the record's
  `styles` are spliced. Undeclared streams retransmit the whole accumulated
  table, byte for byte as before.

The uplink is the other half: a `resync:{"scope":"keyframe"}` request clears
the encoder's baseline so the next record is full within the same epoch, and an
image-scoped resync requests re-transmission of specific attachment IDs. This
is what makes the wire *self-recovering* rather than dependent on a consumer
that never forgets — the `(epoch, gen)` tuple is encoder-owned and is **not**
the runtime frame `sequence`.

> **Normative source: [HOST-WIRE-CONTRACT.md](HOST-WIRE-CONTRACT.md).** That
> document, not this guide, defines wire mechanics — field semantics,
> capability negotiation, applicability rules, and the per-stage state at
> `HEAD`. The summary here exists to orient a reader walking the pipeline; if
> the two ever disagree, the contract wins and this passage is the bug.

The three consumers differ in where the bytes go:

- **WASI** (`WebSurfaceTransport` in
  `Platforms/WASI/Sources/WASISurfaceBridge/WebSurfaceTransport.swift`) writes to a
  stdout file descriptor — the statically-linked `wasm32-wasi` bundle. `WASIRunner`
  also has a *manifest mode* (`SWIFTTUI_MODE=manifest`) that
  prints the `SceneManifest` JSON without running, so a static site can enumerate an
  app's scenes ahead of time.
- **WebHost** (`WebSocketSurfaceTransport` in
  `Platforms/WebHost/Sources/SwiftTUIWebHost/WebSocketSurfaceTransport.swift`)
  hands the *same* encoder output to a `ByteSinkPump` draining over a WebSocket, the
  static browser bundle served from `WebHostBrowserBundle`.
- **Android** encodes the same host-wire model when Kotlin calls
  `AndroidHostSceneHost.copyLatestFrameBytes`, then copies the record across the
  ABI to Compose.

The two browser transports advertise an identical `TerminalCapabilityProfile`
(unicode, true color,
`emitsStyleEscapeSequences: false` — styles travel in JSON, not ANSI). The encoded
WASI/WebHost frames are consumed by the **TypeScript runtime in the sibling
`swift-tui-web` repo**, while Android's copy is consumed by its Kotlin parser.
Terminal and the external SwiftUI host consume the committed frame directly and do
not use this wire.

**Step 4 — Native SwiftUI host: `SemanticHostFrame` → `CGContext`.** The SwiftUI host
lives in `swift-tui-swiftui` and uses no transport — it consumes the frame in-process.
`SwiftUIHostSceneHost` (in the sibling `swift-tui-swiftui` package)
constructs a `HostedRasterSurface` (the shared runtime surface,
`Sources/SwiftTUIRuntime/Scenes/HostedRasterSurface.swift`) whose `onFrame` stores
`frame.raster`/`frame.semantics`/`frame.focusedIdentity`/`frame.rasterDamage`
on an `@Observable`, dropping any frame whose `sequence` is stale. SwiftUI observation
triggers a repaint, and `NativeRasterSurfaceRenderer.draw(...)` walks the
`RasterSurface` cell grid into a
`CGContext` inside an NSView/UIView: background fills, box-drawing glyphs (procedural
via `BoxDrawingRenderer`, else font text), underline/strikethrough, image attachments.
`frame.rasterDamage` becomes `CGRect` dirty rects via `dirtyRects(for:…)`, so
SwiftUI repaints only changed rows. The accessibility tree and focused identity drive a
native accessibility overlay.

**Step 5 — Android Compose host: converged host wire, host-driven main executor.** The
Android host (`Platforms/Android/`) also wraps a `HostedRasterSurface` via
`AndroidHostSceneHost`, with
`frameDelivery: .assumedMainActor`. Consumed frames are encoded at copy time as
converged web-surface records (style-table cells, image attachments —
precomposed PNG when blended — accessibility, scroll regions, damage,
terminalStyle), which Kotlin pulls across the ABI with
`AndroidHostSceneHost.copyLatestFrameBytes`
and renders into a Compose surface. The Android-only twist is *scheduling*, not
rendering (cross-reference [3c](#3c-app-bootstrap--run-loop-lifecycle)'s WASI/Android
gotcha): there is **no CFRunLoop on a bare JNI embedding**, so the Swift main-actor job
queue would never drain. `AndroidMainExecutorPump`
installs a custom `HostMainExecutor` via `_createExecutors(factory:)` at JNI bring-up,
and the Kotlin render loop calls `AndroidHostSceneHost.tick()` ~30 Hz, which
calls `drainReadyJobs()` and returns. The default off-main executor stays libdispatch's
self-driving global pool, so `Task.sleep` timers still fire on worker threads; only the
hop *back* to `@MainActor` is host-driven. This is the only host that drives the
runtime's clock by hand — but the runtime, layout, and raster above it are the same
engine.

**Invariants and gotchas.**

- **Hosts consume committed contracts, never renderer-private state.** The only things
  a host sees are `SemanticHostFrame` / `RasterSurface` / `SemanticSnapshot`. Renderer
  reuse hints must not leak past `commit` — the same invariant [3a](#3a-the-render-pipeline-condensed)
  states.
- **Damage is per-host.** `presentationDamage(for:…)`
  diffs against `previousPresentedRasterSurface` — the surface *this* run loop last
  presented to *this* host. Each host has its own run loop instance, so damage is never
  shared and async-dropped/elided frames never corrupt another host's baseline. `nil`
  damage = full repaint; non-`nil` empty = nothing visible changed.
- **One frame, one boundary, one host wire.** `HostWireSchema` records the rule that
  every serialized host speaks one wire. WASI, WebHost, and
  `AndroidHostSceneHost` all consume the same encoder contract, so changing it changes
  all three consumers at once. Android gates decoding with Kotlin's
  `SUPPORTED_WEB_SURFACE_VERSION`; the Swift encoder and Kotlin parser must evolve
  together.
- **Style transport differs by host, by design.** Terminal may lower styles to
  ANSI, the two browser transports disable style escape emission, and retained
  native hosts consume `ResolvedTextStyle` structurally from the committed raster.
  Never assume a non-terminal host paints ANSI.
- **Only `TerminalHost` writes control bytes / owns raw mode.** Everything in
  `Terminal/*PresentationEmission*` is compiled out under `#if !canImport(WASILibc)`. A
  WASI-only break ships green on the Linux gate and only surfaces in the
  `swift-tui-examples`/`swift-tui-site` gates — cross-build for `wasm32-wasi` before
  tagging.
- **Native hosts are retained surfaces; terminal/web are streamed.** SwiftUI and
  Android hold the latest frame on an observed/boxed object and repaint on demand,
  deduplicating on `SemanticHostFrame.sequence`. Terminal and web *push* every committed
  frame as bytes. `sequence` exists precisely so a retained host can drop stale async
  frames without inferring freshness from callback order.
- **Blended image attachments precompose once, in shared code.** When an attachment
  carries blend metadata, every raster-image host asks the shared `ImageBlendCompositor`
  for a precomposed PNG keyed by reference/rect/blend mode rather than re-implementing
  compositing.

---

## First tasks / where to start reading

A suggested first-week reading order, each tied to a section above:

1. **Read [the map's "Where does X live?" table](#where-does-x-live)** and skim the
   three deep-dive subsystems. Then open `Sources/SwiftTUIGraph/Resolve/ViewGraph.swift`
   and `ViewNode.swift` and confirm for yourself that `ResolvedNode` carries no
   persistent state — this is the single most clarifying half-hour you can spend.
2. **Read <doc:Runtime-Render-Pipeline> in full**, then re-read
   [§3a](#3a-the-render-pipeline-condensed). You now have the data model.
3. **Trace one keypress** with [§3b](#3b-the-interaction--update-loop) open beside
   `RunLoop+EventDispatch.swift` and `RunLoop+Rendering.swift`. Set a breakpoint in
   `ViewGraph.evaluateDirtyNodes` and watch the dirty frontier
   shrink to one node on a `@State` toggle.
4. **Launch an app** under the CLI host and follow [§3c](#3c-app-bootstrap--run-loop-lifecycle)
   from `SwiftTUI.App.main() async` through `RunLoop.run()`. Try a bare
   `MyApp.main()` once to see the `-> Never` trap fire.
5. **Run the same app under `--web`** and read [§3d](#3d-one-app-five-hosts) — confirm
   WebHost, WASI, and Android share one encoder contract. The build/test commands for
   all hosts are in [docs/DEVELOPMENT.md](DEVELOPMENT.md).

Good first changes live at the edges where the contract is narrow: a new
chart view in the external `swift-tui-charts` package (no engine risk), or a new key
binding in the `handleKeyPress` ladder. A host-wire field is deliberately broader:
it touches `HostWireFrameModel`/`HostWireSchema`, `WebSurfaceFrameEncoder`, and the
TypeScript and Kotlin decoders. Avoid the resolve planner, the actor split in the
fused tail, and reuse suppression until you have traced a frame end to end — those
are the areas where the map's invariants bite hardest.

Before any commit, remember the recurring trap from three of the flows: **the Linux
Repo Gate does not compile `wasm32-wasi`.** Cross-build for the WASI SDK before tagging
anything that touches input, terminal, or presentation code.

## See Also

- <doc:Runtime-Render-Pipeline> — the full within-a-frame vertical trace (§3a
  condenses it).
- <doc:Host-Integration> — embedding the runtime in a host surface (the §3d contract,
  from the host author's side).
- [docs/ARCHITECTURE.md](ARCHITECTURE.md) — the layered architecture the map formalizes.
- [docs/HOSTS-AND-PLATFORMS.md](HOSTS-AND-PLATFORMS.md) — the host/platform matrix
  underlying §3d.
- [docs/RENDER-PIPELINE.md](RENDER-PIPELINE.md) — pipeline reference complementing §3a.
- [docs/ACCESSIBILITY.md](ACCESSIBILITY.md) — the semantics/accessibility subsystem.
- [docs/DEVELOPMENT.md](DEVELOPMENT.md) — build, test, and cross-build (incl. WASI)
  workflow.
