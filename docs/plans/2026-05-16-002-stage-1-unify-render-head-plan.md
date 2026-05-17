---
title: "refactor: Stage 1 — unify the render head"
type: refactor
status: proposed
date: 2026-05-16
depends_on:
  - "2026-05-16-001-pipeline-driver-hardening-plan.md"
  - "../proposals/PIPELINE_DRIVER_AUDIT.md"
  - "../decisions/0004-frame-head-abort-reverted.md"
---

# Stage 1 — Unify the Render Head Implementation Plan

> **For agentic workers:** Execute this plan task-by-task with
> `superpowers:subagent-driven-development` or `superpowers:executing-plans`.
> Steps use checkbox (`- [ ]`) syntax. This is **Stage 1** of
> [`2026-05-16-001-pipeline-driver-hardening-plan.md`](./2026-05-16-001-pipeline-driver-hardening-plan.md);
> it addresses audit proposal **P2** (Finding 3).

**Goal:** Eliminate the ~115 lines of duplicated frame-head logic between the
synchronous `renderView` and the asynchronous `prepareFrameHead` by extracting a
single `computeFrameHead` function that both call, so a future fix to the head
(e.g. the selective-evaluation gate) provably reaches both render paths.

**Architecture:** `renderView` (`SwiftTUI.swift:295`) and `prepareFrameHead`
(`SwiftTUI.swift:662`) today resolve the view, drive the view graph, inject
animation, and build the `FrameTailInput` through near-identical inline code.
They were forked, not shared. This plan extracts that shared work into one
`computeFrameHead(_:context:proposal:collectsDiagnostics:mode:)` function. A
`FrameHeadMode` parameter selects execution-strategy-specific work: `.abortable`
(async) captures the five-subsystem checkpoint bundle and the worker-safe
indexed-child snapshot; `.oneShot` (sync) skips both so the synchronous path
pays neither cost. The checkpoint fields on `FrameHeadDraft` become a single
optional `FrameHeadCheckpoints?` bundle so a one-shot draft can legally carry
no checkpoints.

**Tech Stack:** Swift 6.3 strict concurrency, Swift Testing, the
`SwiftTUIRuntime` module, the `SwiftTUITests` / `SwiftTUICoreTests` suites.
Test runner: `swiftly run swift test`.

---

## Why this is behavior-preserving

The extraction is a pure refactor. Two facts make it safe:

1. **`.abortable` mode reproduces `prepareFrameHead` exactly.** Every checkpoint
   capture and the indexed-child snapshot are kept, gated on `mode == .abortable`.
2. **`.oneShot` mode reproduces `renderView`'s head exactly.** Today `renderView`
   captures no checkpoints and never calls `needsIndexedChildSourceWorkerSnapshot`.
   `.oneShot` skips both — so the head it produces is byte-identical to the
   current inline head.

The safety net is the existing test
`AsyncFrameTailRenderingTests.syncAndAsyncRendererArtifactsStayEquivalent`
(`Tests/SwiftTUITests/AsyncFrameTailRenderingTests.swift:1607`), which renders
the same view through `render` (sync) and `renderAsync` (async) with
`collectsDiagnostics: false` and asserts the artifacts are `==`. If the
extraction makes the two heads diverge, that test goes red.

## File Structure

- **Modify** `Sources/SwiftTUIRuntime/Rendering/FrameTailRenderer.swift` — add
  `FrameHeadMode` and `FrameHeadCheckpoints`; replace `FrameHeadDraft`'s five
  checkpoint fields with one optional bundle.
- **Modify** `Sources/SwiftTUIRuntime/SwiftTUI.swift` — add `computeFrameHead`;
  reduce `prepareFrameHead` to a thin `.abortable` wrapper; repoint `renderView`
  onto `computeFrameHead(.oneShot)`; update `abortPreparedFrameHead` to read the
  bundle.
- **No new files.** The existing parity test is the safety net; no new test
  files are created.

---

## Task 1: Establish the parity safety net

No code change. Confirm the characterization test and the two pipeline suites
are green on the current tree, so any later red is caused by this refactor.

**Files:** none (verification only).

- [ ] **Step 1: Run the parity test and pipeline suites**

Run:
```bash
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests
swiftly run swift test --filter SwiftTUITests.LayoutAndRenderingPipelineTests
swiftly run swift test --filter SwiftTUICoreTests.PipelineTests
```
Expected: all PASS. In particular
`syncAndAsyncRendererArtifactsStayEquivalent` passes.

- [ ] **Step 2: Record the baseline**

If any test is already failing on `main`, STOP — resolve that before
refactoring, or this plan cannot distinguish a pre-existing failure from a
regression. Do not commit; this task only establishes the baseline.

---

## Task 2: Make `FrameHeadDraft` checkpoints optional

Introduce `FrameHeadMode` and `FrameHeadCheckpoints`, and collapse the five
checkpoint fields on `FrameHeadDraft` into one optional bundle. Async behavior
is unchanged — `prepareFrameHead` still captures every checkpoint; it just
packages them differently.

**Files:**
- Modify: `Sources/SwiftTUIRuntime/Rendering/FrameTailRenderer.swift:216-234`
- Modify: `Sources/SwiftTUIRuntime/SwiftTUI.swift:122-135` (`abortPreparedFrameHead`)
- Modify: `Sources/SwiftTUIRuntime/SwiftTUI.swift:792-810` (`prepareFrameHead` return)

- [ ] **Step 1: Add `FrameHeadMode` and `FrameHeadCheckpoints`**

In `FrameTailRenderer.swift`, immediately **above** the `FrameHeadDraft` doc
comment (currently line 211, `/// Checkpointed main-actor frame head …`),
insert — do not place these between the doc comment and `struct FrameHeadDraft`,
or the comment would attach to the wrong type:

```swift
/// Selects execution-strategy-specific work when preparing a frame head.
package enum FrameHeadMode {
  /// Synchronous one-shot render: captures no checkpoints and no worker-safe
  /// indexed-child snapshot, because a one-shot head is never aborted and its
  /// frame tail runs synchronously on the main actor.
  case oneShot
  /// Asynchronous render whose head may be aborted before tail work starts.
  /// Captures the five-subsystem checkpoint bundle and the worker-safe
  /// indexed-child snapshot.
  case abortable
}

/// The five-subsystem checkpoint bundle captured for an abortable frame head.
///
/// Present only on drafts prepared with `FrameHeadMode.abortable`; a one-shot
/// draft carries `nil`. `abortPreparedFrameHead` requires this bundle.
package struct FrameHeadCheckpoints {
  var viewGraph: ViewGraph.Checkpoint
  var frameState: FrameResolveState.Checkpoint
  var presentationPortal: PresentationPortalState.Checkpoint
  var observationBridge: ObservationBridge.Checkpoint?
  var animation: AnimationController.Checkpoint
}
```

- [ ] **Step 2: Replace `FrameHeadDraft`'s checkpoint fields with the bundle**

Replace the entire `FrameHeadDraft` struct (currently `SwiftTUIRuntime/Rendering/FrameTailRenderer.swift:216-234`)
with:

```swift
package struct FrameHeadDraft {
  var clock: ContinuousClock?
  var renderGeneration: RenderGeneration
  var registrationDraft: FrameHeadRegistrationDraft
  /// The abort checkpoint bundle. `nil` for one-shot heads.
  var checkpoints: FrameHeadCheckpoints?
  var observationBridge: ObservationBridge?
  var resolveContext: ResolveContext
  var graphRootIdentity: Identity
  var frameContext: FrameContext
  var resolved: ResolvedNode
  var frameTailInput: FrameTailInput
  var runtimeIssues: [RuntimeIssue]
  var animationTimestamp: MonotonicInstant
  var resolveDuration: Duration
}
```

(Removed: `viewGraphCheckpoint`, `frameStateCheckpoint`,
`presentationPortalCheckpoint`, `observationBridgeCheckpoint`,
`animationCheckpoint`. Added: `checkpoints`. `observationBridge` stays — abort
needs the bridge reference to call `restoreCheckpoint` on it.)

- [ ] **Step 3: Update `abortPreparedFrameHead` to read the bundle**

Replace the body of `abortPreparedFrameHead` (`SwiftTUI.swift:122-135`) with:

```swift
  @MainActor
  package func abortPreparedFrameHead(
    _ draft: FrameHeadDraft
  ) {
    guard let checkpoints = draft.checkpoints else {
      preconditionFailure(
        "Cannot abort a one-shot frame head — it has no checkpoints."
      )
    }
    draft.registrationDraft.discard()
    viewGraph.restoreCheckpoint(checkpoints.viewGraph)
    frameState.restoreCheckpoint(checkpoints.frameState)
    presentationPortalState.restoreCheckpoint(checkpoints.presentationPortal)
    if let observationBridge = draft.observationBridge,
      let checkpoint = checkpoints.observationBridge
    {
      observationBridge.restoreCheckpoint(checkpoint)
    }
    animationController.abortFrameHeadTransaction(checkpoints.animation)
  }
```

- [ ] **Step 4: Update `prepareFrameHead`'s return to build the bundle**

In `prepareFrameHead`, replace the `return FrameHeadDraft(...)` statement
(`SwiftTUI.swift:792-810`) with:

```swift
    return FrameHeadDraft(
      clock: clock,
      renderGeneration: renderGeneration,
      registrationDraft: registrationDraft,
      checkpoints: FrameHeadCheckpoints(
        viewGraph: viewGraphCheckpoint,
        frameState: frameStateCheckpoint,
        presentationPortal: presentationPortalCheckpoint,
        observationBridge: observationBridgeCheckpoint,
        animation: animationCheckpoint
      ),
      observationBridge: resolveContext.observationBridge,
      resolveContext: resolveContext,
      graphRootIdentity: presentationPortalContext.identity,
      frameContext: frameContext,
      resolved: resolved,
      frameTailInput: frameTailInput,
      runtimeIssues: [],
      animationTimestamp: animationTimestamp,
      resolveDuration: resolveDuration
    )
```

The local checkpoint bindings (`viewGraphCheckpoint`, `frameStateCheckpoint`,
`presentationPortalCheckpoint`, `observationBridgeCheckpoint`,
`animationCheckpoint`) are still captured earlier in `prepareFrameHead` — leave
those capture lines untouched in this task.

- [ ] **Step 5: Run the async suite to verify async behavior is unchanged**

Run:
```bash
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests
```
Expected: PASS — including the `prepared frame-head abort …` tests, which
exercise `abortPreparedFrameHead`.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiftTUIRuntime/Rendering/FrameTailRenderer.swift Sources/SwiftTUIRuntime/SwiftTUI.swift
git commit -m "refactor: bundle frame-head checkpoints into optional FrameHeadCheckpoints"
```

---

## Task 3: Extract `computeFrameHead`

Move the shared head logic into one `computeFrameHead` function and reduce
`prepareFrameHead` to a thin `.abortable` wrapper. After this task the async
path runs through the extracted function; the sync path is repointed in Task 4.

**Files:**
- Modify: `Sources/SwiftTUIRuntime/SwiftTUI.swift` — add `computeFrameHead`,
  rewrite `prepareFrameHead` (`:662-811`).

- [ ] **Step 1: Add `computeFrameHead`**

Insert this function into `DefaultRenderer`, immediately **above** the existing
`prepareFrameHead` (`SwiftTUI.swift:661`):

```swift
  /// Resolves `root` and prepares the shared frame head consumed by both the
  /// synchronous one-shot renderer and the abortable async renderer.
  ///
  /// `mode` selects execution-strategy-specific work: `.abortable` captures the
  /// five-subsystem checkpoint bundle (before each subsystem is mutated) and
  /// the worker-safe indexed-child snapshot; `.oneShot` skips both, so a
  /// synchronous render pays neither the checkpoint nor the snapshot cost.
  @MainActor
  private func computeFrameHead<V: View>(
    _ root: V,
    context: ResolveContext,
    proposal: ProposedSize,
    collectsDiagnostics: Bool,
    mode: FrameHeadMode
  ) -> FrameHeadDraft {
    let clock: ContinuousClock? = collectsDiagnostics ? ContinuousClock() : nil
    let renderGeneration = renderGenerationSequencer.next()

    var resolveContext = context
    let registrationDraft = FrameHeadRegistrationDraft(
      liveRegistrations: resolveContext.runtimeRegistrations
    )
    resolveContext = resolveContext.replacingRuntimeRegistrations(
      registrationDraft.draftRegistrations
    )
    resolveContext.imageAssetResolver = imageRepository.resolver()
    resolveContext.frameState = frameState

    // Abortable heads checkpoint frameState / portal / observation BEFORE
    // `frameState.update` mutates them. One-shot heads never abort, so skip.
    let frameStateCheckpoint: FrameResolveState.Checkpoint?
    let presentationPortalCheckpoint: PresentationPortalState.Checkpoint?
    let observationBridgeCheckpoint: ObservationBridge.Checkpoint?
    switch mode {
    case .oneShot:
      frameStateCheckpoint = nil
      presentationPortalCheckpoint = nil
      observationBridgeCheckpoint = nil
    case .abortable:
      frameStateCheckpoint = frameState.makeCheckpoint()
      presentationPortalCheckpoint = presentationPortalState.makeCheckpoint()
      observationBridgeCheckpoint = resolveContext.observationBridge?.makeCheckpoint()
    }
    frameState.update(from: resolveContext, proposal: proposal)

    // The viewGraph checkpoint is captured AFTER `frameState.update` but
    // BEFORE `beginFrame`, for the same abort reason.
    let viewGraphCheckpoint: ViewGraph.Checkpoint? =
      mode == .abortable ? viewGraph.makeCheckpoint() : nil
    viewGraph.beginFrame()
    let canUseSelectiveEvaluation =
      frameState.selectiveEvaluationEnabled
      && !frameState.environmentRequiresRootEvaluation
      && !context.invalidatedIdentities.contains(resolveContext.identity)
    if canUseSelectiveEvaluation {
      viewGraph.invalidateAndQueueDirty(context.invalidatedIdentities)
    } else {
      viewGraph.invalidate(context.invalidatedIdentities)
    }
    resolveContext.viewGraph = viewGraph
    resolveContext.observationBridge?.attachViewGraph(viewGraph)
    resolveContext.observationBridge?.beginTrackingPass()
    let presentationPortalContext = resolveContext.replacingIdentity(
      with: presentationPortalIdentity(for: resolveContext.identity)
    )
    let hasExistingPresentationPortalRoot = viewGraph.containsNode(
      for: presentationPortalContext.identity
    )
    let wrappedRoot = PresentationPortalRoot(
      content: root,
      portalState: presentationPortalState,
      contentRootIdentity: resolveContext.identity
    )
    viewGraph.setRootEvaluator(rootIdentity: presentationPortalContext.identity) {
      _ = resolver.resolve(wrappedRoot, in: presentationPortalContext)
    }
    viewGraph.setEvaluator(for: presentationPortalContext.identity) {
      _ = resolver.resolve(wrappedRoot, in: presentationPortalContext)
    }
    if !hasExistingPresentationPortalRoot
      || !canUseSelectiveEvaluation
      || !context.invalidatedIdentities.isEmpty
    {
      viewGraph.queueDirty([presentationPortalContext.identity])
    }
    let (_, resolveDuration): (Void, Duration)
    // Abortable heads open an animation frame-head transaction so completion
    // closures can be deferred or discarded; one-shot heads do not.
    let animationCheckpoint: AnimationController.Checkpoint? =
      mode == .abortable ? animationController.beginFrameHeadTransaction() : nil
    animationController.beginTransitionCollection()
    if canUseSelectiveEvaluation, !viewGraph.hasDirtyWork {
      // Nothing is dirty — skip evaluation entirely and reuse the existing
      // tree snapshot. The root evaluator and registrations are untouched.
      resolveDuration = .zero
    } else {
      let dirtyEvaluationPlan = viewGraph.selectiveDirtyEvaluationPlan()
      if let dirtyEvaluationPlan {
        registrationDraft.recordRemoveSubtrees(
          rootedAt: dirtyEvaluationPlan.frontierIdentities
        )
      } else {
        registrationDraft.recordResetAll()
      }

      (_, resolveDuration) = measurePhase(clock: clock) {
        viewGraph.evaluateDirtyNodes(
          using: dirtyEvaluationPlan
        )
      }
    }
    animationController.finishTransitionCollection()
    var resolved = renderPipelineTree(from: viewGraph.snapshot())
    resolved = wrapInContainerSafeArea(
      resolved,
      context: resolveContext
    )

    // Animation: capture from/to for changed animatable properties, then apply
    // interpolated values to the resolved tree before measure. This is the
    // only pipeline insertion for animation — measure/place/draw/raster run
    // unchanged on the mutated tree.
    let animationTimestamp = MonotonicInstant.now()
    animationController.processResolvedTree(
      resolved,
      transaction: context.transaction,
      timestamp: animationTimestamp
    )
    _ = animationController.applyInterpolations(
      to: &resolved,
      at: animationTimestamp
    )

    let frameTailRetainedInput = frameTailRenderer.retainedInput(
      invalidatedIdentities: context.invalidatedIdentities
    )
    let layoutPassContext = LayoutPassContext(
      retainedLayout: frameTailRetainedInput.retainedLayout,
      invalidatedIdentities: context.invalidatedIdentities
    )
    let frameContext = FrameContext(
      environment: context.environment,
      transaction: context.transaction,
      invalidatedIdentities: context.invalidatedIdentities
    )
    var frameTailInput = FrameTailInput(
      generation: renderGeneration,
      resolved: resolved,
      proposal: proposal,
      rootIdentity: resolveContext.identity,
      retained: frameTailRetainedInput,
      layoutPassContext: layoutPassContext
    )
    // Worker-safe snapshotting of lazy indexed child sources is only needed
    // when the frame tail runs off-main. One-shot renders run the tail
    // synchronously on the main actor, so they skip it.
    if mode == .abortable,
      frameTailRenderer.needsIndexedChildSourceWorkerSnapshot(frameTailInput)
    {
      resolved = indexedChildSourceWorkerSnapshot(of: resolved)
      frameTailInput = FrameTailInput(
        generation: renderGeneration,
        resolved: resolved,
        proposal: proposal,
        rootIdentity: resolveContext.identity,
        retained: frameTailRetainedInput,
        layoutPassContext: layoutPassContext
      )
    }

    let checkpoints: FrameHeadCheckpoints?
    switch mode {
    case .oneShot:
      checkpoints = nil
    case .abortable:
      // Force-unwraps are safe: every `.abortable` branch above assigned its
      // checkpoint non-nil.
      checkpoints = FrameHeadCheckpoints(
        viewGraph: viewGraphCheckpoint!,
        frameState: frameStateCheckpoint!,
        presentationPortal: presentationPortalCheckpoint!,
        observationBridge: observationBridgeCheckpoint,
        animation: animationCheckpoint!
      )
    }

    return FrameHeadDraft(
      clock: clock,
      renderGeneration: renderGeneration,
      registrationDraft: registrationDraft,
      checkpoints: checkpoints,
      observationBridge: resolveContext.observationBridge,
      resolveContext: resolveContext,
      graphRootIdentity: presentationPortalContext.identity,
      frameContext: frameContext,
      resolved: resolved,
      frameTailInput: frameTailInput,
      runtimeIssues: [],
      animationTimestamp: animationTimestamp,
      resolveDuration: resolveDuration
    )
  }
```

- [ ] **Step 2: Reduce `prepareFrameHead` to a thin wrapper**

Replace the entire `prepareFrameHead` function (`SwiftTUI.swift:661-811`, the
`@MainActor` line through its closing brace) with:

```swift
  @MainActor
  private func prepareFrameHead<V: View>(
    _ root: V,
    context: ResolveContext,
    proposal: ProposedSize,
    collectsDiagnostics: Bool
  ) -> FrameHeadDraft {
    computeFrameHead(
      root,
      context: context,
      proposal: proposal,
      collectsDiagnostics: collectsDiagnostics,
      mode: .abortable
    )
  }
```

`renderViewAsync`, `renderAsyncCancellable`, and
`prepareFrameHeadForCancellationTesting` all keep calling `prepareFrameHead`
unchanged — `mode` stays an internal detail.

- [ ] **Step 3: Run the async suite**

Run:
```bash
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests
```
Expected: PASS. `.abortable` mode reproduces the old `prepareFrameHead` exactly,
so every async and abort test still passes.

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiftTUIRuntime/SwiftTUI.swift
git commit -m "refactor: extract computeFrameHead; prepareFrameHead delegates with .abortable"
```

---

## Task 4: Repoint `renderView` onto `computeFrameHead`

Replace `renderView`'s ~115-line inline head with a `computeFrameHead(.oneShot)`
call, deleting the duplication. The synchronous tail (late-preference layout,
frame tail, commit, diagnostics, artifacts) is unchanged.

**Files:**
- Modify: `Sources/SwiftTUIRuntime/SwiftTUI.swift:295-556` (`renderView`).

- [ ] **Step 1: Replace the head and bind locals**

In `renderView`, replace everything from the first line of the body
(`let clock: ContinuousClock? = collectsDiagnostics ? ...`, currently
`SwiftTUI.swift:301`) through the `renderLayoutResolvingLatePreferences(...)`
call and its result destructuring (currently `:301-422`) with:

```swift
    let draft = computeFrameHead(
      root,
      context: context,
      proposal: proposal,
      collectsDiagnostics: collectsDiagnostics,
      mode: .oneShot
    )
    let clock = draft.clock
    let resolveContext = draft.resolveContext
    let registrationDraft = draft.registrationDraft
    let renderGeneration = draft.renderGeneration
    let resolveDuration = draft.resolveDuration
    let frameContext = draft.frameContext
    let graphRootIdentity = draft.graphRootIdentity
    let animationTimestamp = draft.animationTimestamp

    let reconciledTailLayout = renderLayoutResolvingLatePreferences(
      draft.frameTailInput,
      clock: clock
    )
    let frameTailInput = reconciledTailLayout.input
    let tailLayout = reconciledTailLayout.layout
    let resolved = reconciledTailLayout.resolved
    let runtimeIssues = reconciledTailLayout.runtimeIssues
```

`resolved` is `let`, not `var`: the old `renderView` declared `var resolved`
because the *head* mutated it (`wrapInContainerSafeArea`, `applyInterpolations`).
Those mutations now live in `computeFrameHead`; in the tail, `resolved` is
assigned once from `reconciledTailLayout.resolved` and never reassigned, so
`let` is correct and avoids a never-mutated warning.

Everything from `let placed = tailLayout.baselinePlaced` onward (the old
`:423`) stays. Verify the function still begins with its existing signature and
`-> FrameArtifacts` and that the body after this insertion is the unchanged
tail.

- [ ] **Step 2: Fix the one renamed reference in the tail**

The old head bound `presentationPortalContext`; the tail used
`presentationPortalContext.identity` once, in the `viewGraph.finalizeFrame`
call (old `SwiftTUI.swift:463`). Change that single argument from:

```swift
        rootIdentity: presentationPortalContext.identity,
```

to:

```swift
        rootIdentity: graphRootIdentity,
```

This is the only reference in the tail that depended on a head-local; all other
tail locals (`clock`, `resolveContext`, `registrationDraft`, `renderGeneration`,
`resolveDuration`, `frameContext`, `animationTimestamp`, `resolved`) are bound
in Step 1 with the same names the old code used.

- [ ] **Step 3: Run the sync and async suites**

Run:
```bash
swiftly run swift test --filter SwiftTUITests.LayoutAndRenderingPipelineTests
swiftly run swift test --filter SwiftTUITests.AsyncFrameTailRenderingTests
swiftly run swift test --filter SwiftTUICoreTests.PipelineTests
```
Expected: all PASS. `syncAndAsyncRendererArtifactsStayEquivalent` is the key
assertion — green here means the extracted sync head matches the async head.

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiftTUIRuntime/SwiftTUI.swift
git commit -m "refactor: drive renderView through computeFrameHead, removing the forked head"
```

---

## Task 5: Verify no sync-path regression and run full gates

Confirm the one-shot path pays no checkpoint or worker-snapshot cost, that
`FrameHeadDraft` is constructed in exactly one place, and that the whole suite
plus repository policy gates pass.

**Files:** none (verification); then the roadmap doc.

- [ ] **Step 1: Confirm `.oneShot` skips checkpoint and snapshot cost**

Inspect `computeFrameHead`: every `makeCheckpoint()`,
`beginFrameHeadTransaction()`, and `needsIndexedChildSourceWorkerSnapshot(...)`
call must be inside a `case .abortable` branch or a `mode == .abortable`
condition. Run:
```bash
grep -n "makeCheckpoint\|beginFrameHeadTransaction\|needsIndexedChildSourceWorkerSnapshot" Sources/SwiftTUIRuntime/SwiftTUI.swift
```
Expected: every hit is inside an `.abortable` branch/condition of
`computeFrameHead`. No checkpoint call is reachable from `.oneShot`.

- [ ] **Step 2: Confirm a single `FrameHeadDraft` construction site**

Run:
```bash
grep -rn "FrameHeadDraft(" Sources/
```
Expected: exactly one construction — the `return FrameHeadDraft(...)` at the end
of `computeFrameHead`. (Type references in `FrameTailRenderer.swift` signatures
are fine; only the `FrameHeadDraft(` *call* must be unique.)

- [ ] **Step 3: Run the full test suite and policy gates**

Run:
```bash
swiftly run swift test
./Scripts/check_public_surface_policies.sh
./Scripts/check_concurrency_safety_policies.sh
```
Expected: all PASS. `computeFrameHead`, `FrameHeadMode`, and
`FrameHeadCheckpoints` are non-`public` (`private` / `package`), so the public
surface is unchanged.

- [ ] **Step 4: Mark the stage and commit**

In [`2026-05-16-001-pipeline-driver-hardening-plan.md`](./2026-05-16-001-pipeline-driver-hardening-plan.md),
update the Stage 1 section's `**Goal:**` line to note the detailed plan, and
add a link to this file under Stage 1's **Key files** list:
`- Detailed plan: docs/plans/2026-05-16-002-stage-1-unify-render-head-plan.md`.
Then:

```bash
git add docs/plans/2026-05-16-001-pipeline-driver-hardening-plan.md
git commit -m "docs: link Stage 1 detailed plan into the pipeline driver roadmap"
```

---

## Exit criteria

Stage 1 is complete when:

- One head implementation exists (`computeFrameHead`); `renderView` and
  `prepareFrameHead` both delegate to it.
- A fix to the selective-evaluation gate, or any other head logic, now lands in
  exactly one place and reaches both render paths.
- `FrameHeadDraft` carries an optional `FrameHeadCheckpoints` bundle; one-shot
  heads carry `nil` and pay no checkpoint cost.
- `syncAndAsyncRendererArtifactsStayEquivalent`,
  `LayoutAndRenderingPipelineTests`, `AsyncFrameTailRenderingTests`,
  `PipelineTests`, the full `swift test` run, and both policy scripts are green.

## What this plan does NOT do

- It does not name or bound the late-preference loop or animation injection —
  that is Stage 2.
- It does not introduce a composed phase abstraction — that is Stage 3.
- It does not change the checkpoint *semantics* or attempt to narrow resolve's
  effect set — `computeFrameHead` is a faithful relocation of existing behavior.
