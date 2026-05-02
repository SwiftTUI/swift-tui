---
title: "refactor: async frame-head draft transaction"
type: refactor
status: shipped
date: 2026-05-01
depends_on:
  - "2026-05-01-005-async-rendering-r0-inventory.md"
  - "2026-04-26-002-frame-head-abort-plan.md"
  - "../ASYNC_RENDERING.md"
---

# Async Frame-Head Draft Transaction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to
> implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for
> tracking. Commit after every task that reaches a green checkpoint.

**Goal:** Complete Option 3: implement Option 1 step by step, beginning with
draft frame-head infrastructure, and enable pre-start tail cancellation only
after prepared frame heads are proven abortable.

**Architecture:** Frame-head work stays on the main actor, but its runtime
registration side effects move into draft registries and commit data. Live
registries are updated only at `finishFrame`, and reconstruction uses the
committed `ViewGraph` and committed node handlers as the source of truth. Once
registry, graph, animation, lifecycle, task, and retained-tail state all have
abort proof, `FrameTailRenderer` may cancel queued tail jobs before worker
layout starts.

**Tech Stack:** Swift 6.3, Swift Testing, `DefaultRenderer`,
`FrameTailRenderer`, `RunLoop.run()`, `RuntimeRegistrationSet`, `ViewGraph`,
`ViewNode`, `FrameDiagnosticsLogger`, Bun repo gate.

## Implementation Result

Shipped on `main` as a sequence of green checkpoints:

- `9b593a9` Add frame-head registration draft infrastructure
- `49e29f0` Route async frame heads through draft registrations
- `8e5301e` Share registration draft commits across render paths
- `212950e` Cover draft registration commit boundaries
- `78b43d4` Add view graph checkpoints for frame-head transactions
- `623cca3` Prove prepared frame heads can be aborted
- `288a15c` Gate frame-head effects behind commit
- `e4f25b7` Cancel queued frame tails before worker start
- `517f057` Tighten queued tail cancellation semantics
- `1eb734e` Restore live graph registrations after selective frames

The shipped runtime policy is pre-start cancellation only. A queued tail job may
cancel before worker layout starts when a newer render intent is pending. The
prepared frame head is discarded through the frame-head draft/checkpoint
transaction. Started and completed worker work still commits in order, and
completed-frame dropping remains unimplemented.

---

## Option 3 Boundary

Option 3 is not a third runtime policy. It is the staged execution plan for the
Option 1 architecture:

- Start with infrastructure that makes prepared frame heads draft-only where
  possible.
- Keep the shipped `commit_ordered` policy while the draft and rollback seams
  are being built.
- Add tests that fail against the current live-registration mutation behavior.
- Make sync and async rendering share the same registration commit semantics.
- Add a package-internal abort test hook only after the draft transaction exists.
- Enable cancellable tail submissions only for jobs that are still queued and
  have not begun layout.
- Preserve ordered commit for every tail job that has started or completed.

Do not restore live runtime state from a per-frame draft registry snapshot. A
draft registry sees only the current evaluation frontier and cache-hit
restores. The durable source of truth for rebuilding live registrations is the
committed `ViewGraph` plus committed node handlers and registration aliases.

## Files

- Create: `Sources/Core/FrameHeadRegistrationDraft.swift`
  - Owns scratch registries for frame-head evaluation.
  - Records the pending live mutation (`resetAll` or `removeSubtrees`).
  - Commits by applying the recorded live mutation and restoring registrations
    from the committed graph.
- Modify: `Sources/Core/RuntimeRegistrationSet.swift`
  - Add a package helper for making a fully concrete scratch set.
  - Keep `resetAll`, `removeSubtrees`, and `restore(from:)` as the only low-level
    registry mutation primitives.
- Modify: `Sources/View/Environment/Environment.swift`
  - Add `ResolveContext.replacingRuntimeRegistrations(_:)`.
  - Ensure children inherit draft registries when a parent context is redirected.
- Modify: `Sources/TerminalUI/TerminalUI.swift`
  - Add the registration draft to `FrameHeadDraft`.
  - Route async `prepareFrameHead` through scratch registries.
  - Commit registration changes in `finishFrame`.
  - Apply the same transaction to sync `renderView`.
  - Add package-internal testing seams for prepared-frame abort proof after the
    state checkpoint exists.
- Modify: `Sources/Core/Graph/ViewGraph.swift`
  - Add a package checkpoint type for graph-owned frame-head mutations.
  - Add restore coverage for root/evaluator, dirty, lifecycle, alias,
    diagnostics, dependency, and live-identity state.
- Modify: `Sources/Core/Graph/ViewNode.swift`
  - Add a package checkpoint type for node-owned mutable state used during
    dirty evaluation.
- Modify: `Sources/Core/Graph/DependencyTracker.swift`
  - Add checkpoint/restore for in-progress dependency capture.
- Modify: `Sources/TerminalUI/FrameDiagnosticsLogger.swift`
  - Add queued-tail cancellation diagnostics after cancellation is implemented.
- Modify: `Sources/TerminalUI/RunLoop+Rendering.swift`
  - Race queued-tail state against coalesced render intent only after abort proof.
- Modify: `Tests/TerminalUITests/AsyncFrameTailRenderingTests.swift`
  - Add draft-registration, abort-proof, cancellation, and committed-order
    runtime-path tests.
- Modify: `Tests/CoreTests/Graph/ViewGraphTests.swift`
  - Add focused graph registration rebuild and checkpoint tests.
- Modify: `docs/ASYNC_RENDERING.md`
  - Link this plan and update progress as stages ship.
- Modify: `docs/README.md`
  - Keep this plan discoverable while active and move it to implementation
    records when shipped.

## Invariants

- `resolve` remains main-actor work.
- No concurrent render may mutate one `DefaultRenderer`.
- No completed worker result may be dropped in this tranche.
- A tail job in `started` or `completed` state must finish and commit in order.
- `RuntimeRegistrationSet.resetAll()` and `.removeSubtrees(rootedAt:)` must not
  touch live run-loop registries during `prepareFrameHead`.
- A prepared frame can be discarded only if graph state, animation state,
  lifecycle/task state, worker custom-layout cache updates, retained tail input,
  and runtime registrations all return to the pre-prepare committed state.
- `RunLoop.run()`-level tests are required for registration, focus, scroll,
  input, and lifecycle proof.
- `FrameDropEligibility` remains observational until a separate completed-frame
  drop tranche is designed.

## Task 1: Add A Failing Live-Registration Isolation Test

**Files:**
- Modify: `Tests/TerminalUITests/AsyncFrameTailRenderingTests.swift`

- [x] **Step 1: Add a test proving prepared key commands are not live before commit**

Add this test near `blockedAsyncFrameHeadDefersAnimationCompletionUntilCommit`:

```swift
  @Test("blocked async frame head keeps draft key commands out of live dispatch")
  func blockedAsyncFrameHeadKeepsDraftKeyCommandsOutOfLiveDispatch() async throws {
    let rootIdentity = testIdentity("AsyncFrameHeadDraftKeyCommandRoot")
    let terminal = AsyncFrameTailTerminalHost()
    let recorder = AsyncFrameHeadAbortEffectRecorder()
    let renderer = DefaultRenderer()
    let inputReader = InjectedTerminalInputReader()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      renderer: renderer,
      terminalHost: terminal,
      terminalInputReader: inputReader,
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: focusTracker,
      proposal: terminal.proposal,
      viewBuilder: { value, _ in
        Panel {
          Text("value \(value)")
            .focusable(true)
        }
        .keyCommand("Initial", key: .character("i"), modifiers: .ctrl) {
          recorder.record("initial")
        }
        .modifier(AsyncFrameHeadDraftKeyCommandModifier(value: value, recorder: recorder))
      }
    )

    runLoop.scheduler.requestInvalidation(of: [rootIdentity])
    var initialFrames = 0
    try await runLoop.renderPendingFramesAsync(renderedFrames: &initialFrames)
    #expect(terminal.frames.contains { $0.contains("value 0") })
    #expect(runLoop.focusTracker.currentFocusIdentity != nil)

    let gate = AsyncFrameTailBlockingGate()
    renderer.setFrameTailRenderHooks(
      .init(beforeRaster: {
        gate.beforeRaster()
      })
    )
    defer {
      renderer.setFrameTailRenderHooks(nil)
      gate.release()
    }

    runLoop.stateContainer.mutate { value in
      value = 1
    }

    let renderTask = Task { @MainActor in
      var renderedFrames = 0
      try await runLoop.renderPendingFramesAsync(renderedFrames: &renderedFrames)
      return renderedFrames
    }

    await gate.waitUntilBlocked()

    _ = runLoop.handleKeyPress(KeyPress(.character("d"), modifiers: .ctrl))
    #expect(!recorder.events.contains("draft"))

    gate.release()
    _ = try await valueWithTimeout {
      try await renderTask.value
    }

    _ = runLoop.handleKeyPress(KeyPress(.character("d"), modifiers: .ctrl))
    #expect(recorder.events.contains("draft"))
  }
```

Add this helper near the other async frame-head scaffold helpers:

```swift
private struct AsyncFrameHeadDraftKeyCommandModifier: ViewModifier {
  var value: Int
  var recorder: AsyncFrameHeadAbortEffectRecorder

  func body(content: Content) -> some View {
    if value == 0 {
      content
    } else {
      content.keyCommand("Draft", key: .character("d"), modifiers: .ctrl) {
        recorder.record("draft")
      }
    }
  }
}
```

- [x] **Step 2: Run the focused test and confirm the current failure**

Run:

```bash
swiftly run swift test --filter TerminalUITests.AsyncFrameTailRenderingTests/blockedAsyncFrameHeadKeepsDraftKeyCommandsOutOfLiveDispatch
```

Expected before implementation: FAIL because the draft key command fires while
the frame tail is blocked.

- [x] **Step 3: Keep the failing test uncommitted until Task 3 passes**

Do not commit a red test on `main`. Keep it as the acceptance test for the
draft-registration implementation.

## Task 2: Add Runtime Registration Draft Infrastructure

**Files:**
- Create: `Sources/Core/FrameHeadRegistrationDraft.swift`
- Modify: `Sources/Core/RuntimeRegistrationSet.swift`
- Modify: `Sources/View/Environment/Environment.swift`

- [x] **Step 1: Add concrete scratch registry construction**

Add this helper to `RuntimeRegistrationSet`:

```swift
  @MainActor
  package static func scratch() -> RuntimeRegistrationSet {
    RuntimeRegistrationSet(
      actionRegistry: LocalActionRegistry(),
      keyHandlerRegistry: LocalKeyHandlerRegistry(),
      terminationRegistry: LocalTerminationRegistry(),
      pointerHandlerRegistry: LocalPointerHandlerRegistry(),
      gestureRegistry: LocalGestureRegistry(),
      gestureStateRegistry: LocalGestureStateRegistry(),
      focusBindingRegistry: LocalFocusBindingRegistry(),
      focusedValuesRegistry: LocalFocusedValuesRegistry(),
      scrollPositionRegistry: LocalScrollPositionRegistry(),
      lifecycleRegistry: LocalLifecycleRegistry(),
      taskRegistry: LocalTaskRegistry(),
      preferenceObservationRegistry: LocalPreferenceObservationRegistry(),
      commandRegistry: CommandRegistry(),
      dropDestinationRegistry: DropDestinationRegistry()
    )
  }
```

- [x] **Step 2: Add the draft object**

Create `Sources/Core/FrameHeadRegistrationDraft.swift`:

```swift
@MainActor
package final class FrameHeadRegistrationDraft {
  package enum LiveMutation: Equatable {
    case none
    case resetAll
    case removeSubtrees([Identity])
  }

  private let liveRegistrations: RuntimeRegistrationSet
  package let draftRegistrations: RuntimeRegistrationSet
  private(set) package var liveMutation: LiveMutation = .none
  private var didCommit = false
  private var didDiscard = false

  package init(liveRegistrations: RuntimeRegistrationSet) {
    self.liveRegistrations = liveRegistrations
    draftRegistrations = .scratch()
  }

  package func recordResetAll() {
    precondition(!didCommit && !didDiscard)
    liveMutation = .resetAll
  }

  package func recordRemoveSubtrees(rootedAt roots: [Identity]) {
    precondition(!didCommit && !didDiscard)
    guard !roots.isEmpty else {
      return
    }
    switch liveMutation {
    case .none:
      liveMutation = .removeSubtrees(roots)
    case .removeSubtrees(let existing):
      liveMutation = .removeSubtrees(existing + roots)
    case .resetAll:
      break
    }
  }

  package func commitRestoring(
    from viewGraph: ViewGraph,
    resolved: ResolvedNode
  ) {
    precondition(!didCommit && !didDiscard)
    switch liveMutation {
    case .none:
      break
    case .resetAll:
      liveRegistrations.resetAll()
    case .removeSubtrees(let roots):
      liveRegistrations.removeSubtrees(rootedAt: roots)
    }
    viewGraph.restoreRuntimeRegistrations(
      for: resolved,
      into: liveRegistrations
    )
    didCommit = true
  }

  package func discard() {
    precondition(!didCommit && !didDiscard)
    didDiscard = true
  }
}
```

This type intentionally does not expose a method that copies draft registry
snapshots into live registries.

- [x] **Step 3: Add context redirection**

Add this helper to `ResolveContext`:

```swift
  @MainActor
  package func replacingRuntimeRegistrations(
    _ registrations: RuntimeRegistrationSet
  ) -> Self {
    var replaced = self
    replaced.localActionRegistry = registrations.actionRegistry
    replaced.localKeyHandlerRegistry = registrations.keyHandlerRegistry
    replaced.localTerminationRegistry = registrations.terminationRegistry
    replaced.localPointerHandlerRegistry = registrations.pointerHandlerRegistry
    replaced.localGestureRegistry = registrations.gestureRegistry
    replaced.localGestureStateRegistry = registrations.gestureStateRegistry
    replaced.localFocusBindingRegistry = registrations.focusBindingRegistry
    replaced.localFocusedValuesRegistry = registrations.focusedValuesRegistry
    replaced.localScrollPositionRegistry = registrations.scrollPositionRegistry
    replaced.localLifecycleRegistry = registrations.lifecycleRegistry
    replaced.localTaskRegistry = registrations.taskRegistry
    replaced.localPreferenceObservationRegistry = registrations.preferenceObservationRegistry
    replaced.commandRegistry = registrations.commandRegistry
    replaced.dropDestinationRegistry = registrations.dropDestinationRegistry
    return replaced
  }
```

- [x] **Step 4: Build the root package**

Run:

```bash
swiftly run swift build
```

Expected: build succeeds.

- [x] **Step 5: Commit the infrastructure**

Run:

```bash
git add Sources/Core/FrameHeadRegistrationDraft.swift Sources/Core/RuntimeRegistrationSet.swift Sources/View/Environment/Environment.swift
git commit -m "Add frame-head registration draft infrastructure"
```

## Task 3: Route Async Frame Head Through Draft Registries

**Files:**
- Modify: `Sources/TerminalUI/TerminalUI.swift`
- Modify: `Tests/TerminalUITests/AsyncFrameTailRenderingTests.swift`

- [x] **Step 1: Store the draft on `FrameHeadDraft`**

Extend `FrameHeadDraft`:

```swift
private struct FrameHeadDraft {
  var clock: ContinuousClock?
  var renderGeneration: RenderGeneration
  var registrationDraft: FrameHeadRegistrationDraft
  var resolveContext: ResolveContext
  var frameContext: FrameContext
  var resolved: ResolvedNode
  var frameTailInput: FrameTailInput
  var animationTimestamp: MonotonicInstant
  var resolveDuration: Duration
  var animationCheckpoint: AnimationController.Checkpoint
}
```

- [x] **Step 2: Redirect `prepareFrameHead` to scratch registries**

Change the start of `prepareFrameHead` from live registration capture to draft
registration capture:

```swift
    var resolveContext = context
    let registrationDraft = FrameHeadRegistrationDraft(
      liveRegistrations: resolveContext.runtimeRegistrations
    )
    resolveContext = resolveContext.replacingRuntimeRegistrations(
      registrationDraft.draftRegistrations
    )
```

Replace live mutation calls inside dirty evaluation:

```swift
      if let dirtyEvaluationPlan {
        registrationDraft.recordRemoveSubtrees(
          rootedAt: dirtyEvaluationPlan.frontierIdentities
        )
      } else {
        registrationDraft.recordResetAll()
      }
```

Return the draft:

```swift
    return FrameHeadDraft(
      clock: clock,
      renderGeneration: renderGeneration,
      registrationDraft: registrationDraft,
      resolveContext: resolveContext,
      frameContext: frameContext,
      resolved: resolved,
      frameTailInput: frameTailInput,
      animationTimestamp: animationTimestamp,
      resolveDuration: resolveDuration,
      animationCheckpoint: animationCheckpoint
    )
```

- [x] **Step 3: Commit runtime registrations in `finishFrame`**

After computing `resolved` in `finishFrame`, before `viewGraph.finalizeFrame`,
commit the registration draft:

```swift
    draft.registrationDraft.commitRestoring(
      from: viewGraph,
      resolved: resolved
    )
```

The commit must happen before lifecycle/task/event planning can dispatch against
the final committed tree.

- [x] **Step 4: Run the isolation test**

Run:

```bash
swiftly run swift test --filter TerminalUITests.AsyncFrameTailRenderingTests/blockedAsyncFrameHeadKeepsDraftKeyCommandsOutOfLiveDispatch
```

Expected after implementation: PASS.

- [x] **Step 5: Run focused async renderer tests**

Run:

```bash
swiftly run swift test --filter TerminalUITests.AsyncFrameTailRenderingTests
```

Expected: all tests in `AsyncFrameTailRenderingTests` pass.

- [x] **Step 6: Commit the async draft path**

Run:

```bash
git add Sources/TerminalUI/TerminalUI.swift Tests/TerminalUITests/AsyncFrameTailRenderingTests.swift
git commit -m "Route async frame heads through draft registrations"
```

## Task 4: Apply The Same Registration Transaction To Sync Rendering

**Files:**
- Modify: `Sources/TerminalUI/TerminalUI.swift`
- Modify: `Tests/TerminalUITests/AsyncFrameTailRenderingTests.swift`

- [x] **Step 1: Add a sync/async parity assertion for draft registration commit**

Extend the existing sync/async parity test in `AsyncFrameTailRenderingTests` with
a root that conditionally installs a key command after invalidation:

```swift
    let recorder = AsyncFrameHeadAbortEffectRecorder()
    let rootIdentity = testIdentity("SyncAsyncDraftRegistrationParityRoot")

    @MainActor
    func root(_ value: Int) -> some View {
      Panel {
        Text("value \(value)").focusable(true)
      }
      .modifier(AsyncFrameHeadDraftKeyCommandModifier(value: value, recorder: recorder))
    }
```

The parity expectation remains:

```swift
    #expect(syncArtifacts == asyncArtifacts)
```

- [x] **Step 2: Update `renderView` to use `FrameHeadRegistrationDraft`**

At the start of sync `renderView`, redirect the resolve context exactly as async
does:

```swift
    var resolveContext = context
    let registrationDraft = FrameHeadRegistrationDraft(
      liveRegistrations: resolveContext.runtimeRegistrations
    )
    resolveContext = resolveContext.replacingRuntimeRegistrations(
      registrationDraft.draftRegistrations
    )
```

Replace sync live mutation calls with `registrationDraft.recordResetAll()` and
`registrationDraft.recordRemoveSubtrees(rootedAt:)`.

After layout-dependent realization has produced the final `resolved` tree, call:

```swift
    registrationDraft.commitRestoring(
      from: viewGraph,
      resolved: resolved
    )
```

- [x] **Step 3: Run parity and registration suites**

Run:

```bash
swiftly run swift test --filter TerminalUITests.AsyncFrameTailRenderingTests
swiftly run swift test --filter TerminalUITests.KeyCommandTests
swiftly run swift test --filter TerminalUITests.DropDestinationDispatchTests
```

Expected: all listed suites pass.

- [x] **Step 4: Commit sync parity**

Run:

```bash
git add Sources/TerminalUI/TerminalUI.swift Tests/TerminalUITests/AsyncFrameTailRenderingTests.swift
git commit -m "Share registration draft commits across render paths"
```

## Task 5: Cover Selective Dirty Reuse, Aliases, And Drop Destinations

**Files:**
- Modify: `Tests/TerminalUITests/AsyncFrameTailRenderingTests.swift`
- Modify: `Tests/CoreTests/Graph/ViewGraphTests.swift`

- [x] **Step 1: Add a selective-dirty runtime test with untouched sibling registrations**

Add a `RunLoop.run()` test where value `0` renders sibling A with a key command
and sibling B with another key command. Mutating only sibling B while the async
tail is blocked must keep sibling B's new command out of live dispatch until
commit, while sibling A's old command remains dispatchable.

Expected assertions:

```swift
    _ = runLoop.handleKeyPress(KeyPress(.character("a"), modifiers: .ctrl))
    #expect(recorder.events.contains("sibling-a"))

    _ = runLoop.handleKeyPress(KeyPress(.character("b"), modifiers: .ctrl))
    #expect(!recorder.events.contains("sibling-b-new"))
```

After releasing the worker gate and committing:

```swift
    _ = runLoop.handleKeyPress(KeyPress(.character("b"), modifiers: .ctrl))
    #expect(recorder.events.contains("sibling-b-new"))
```

- [x] **Step 2: Add a drop-destination version of the draft isolation test**

Use `runLoop.handlePaste(PasteEvent(content: "/tmp/draft-drop.txt"))` while the
frame tail is blocked. Expected before commit: the newly prepared drop
destination does not record. Expected after commit: the same paste records
`drop:1`.

- [x] **Step 3: Add graph alias registration rebuild coverage**

In `Tests/CoreTests/Graph/ViewGraphTests.swift`, add a test that:

1. Builds a graph with an alias registration using the existing alias helper
   used by `restoreRuntimeRegistrations` tests.
2. Calls `RuntimeRegistrationSet.scratch()`.
3. Calls `viewGraph.restoreRuntimeRegistrations(for: resolved, into: scratch)`.
4. Verifies alias-owned command and drop registrations are present in `scratch`.

The key assertion shape is:

```swift
    #expect(
      scratch.commandRegistry?.keyCommand(
        at: aliasIdentity,
        matching: KeyBinding(key: .character("a"), modifiers: .ctrl)
      ) != nil
    )
```

- [x] **Step 4: Run registration-focused tests**

Run:

```bash
swiftly run swift test --filter TerminalUITests.AsyncFrameTailRenderingTests
swiftly run swift test --filter CoreTests.ViewGraphTests
```

Expected: all listed tests pass.

- [x] **Step 5: Commit selective registration coverage**

Run:

```bash
git add Tests/TerminalUITests/AsyncFrameTailRenderingTests.swift Tests/CoreTests/Graph/ViewGraphTests.swift
git commit -m "Cover draft registration commit boundaries"
```

## Task 6: Add Graph And Node Checkpoints Without Runtime Cancellation

**Files:**
- Modify: `Sources/Core/Graph/ViewGraph.swift`
- Modify: `Sources/Core/Graph/ViewNode.swift`
- Modify: `Sources/Core/Graph/DependencyTracker.swift`
- Modify: `Tests/CoreTests/Graph/ViewGraphTests.swift`

- [x] **Step 1: Add `DependencyTracker.Checkpoint`**

Add this in `Sources/Core/Graph/DependencyTracker.swift`:

```swift
extension DependencyTracker {
  package struct Checkpoint {
    package var currentDependencies: DependencySet
  }

  package func makeCheckpoint() -> Checkpoint {
    Checkpoint(currentDependencies: currentDependencies)
  }

  package func restoreCheckpoint(_ checkpoint: Checkpoint) {
    currentDependencies = checkpoint.currentDependencies
  }
}
```

- [x] **Step 2: Add `ViewNode.Checkpoint`**

Add a package checkpoint that captures every node field mutated by dirty
evaluation, snapshot commit, lifecycle, and handler recording:

```swift
extension ViewNode {
  package struct Checkpoint {
    package var invalidator: (any Invalidating)?
    package var ownerGraph: ViewGraph?
    package var parent: ViewNode?
    package var committed: ResolvedNode
    package var isCommittedSnapshotFresh: Bool
    package var children: [ViewNode]
    package var stateSlots: [Int: AnyStateSlot]
    package var dependencies: DependencySet
    package var lifecycleState: NodeLifecycleState
    package var registeredHandlers: NodeHandlers
    package var isDirty: Bool
    package var wasPresentAtFrameStart: Bool
    package var wasVisitedThisFrame: Bool
    package var previousChildrenIdentities: [Identity]
    package var previousLifecycleMetadata: LifecycleMetadata
    package var bodyStateSlotCount: Int?
    package var currentBodyStateSlotCount: Int
    package var pendingChangeHandlerIDs: [String]
    package var dependencyTracker: DependencyTracker.Checkpoint
    package var registrationCaptureDepth: Int
    package var evaluationDepth: Int
    package var hasCommittedPresence: Bool
    package var nextChangeModifierOrdinal: Int
    package var preparedFrameID: UInt64
    package var visitedFrameID: UInt64
    package var evaluator: (@MainActor () -> Void)?
  }

  package func makeCheckpoint() -> Checkpoint {
    Checkpoint(
      invalidator: invalidator,
      ownerGraph: ownerGraph,
      parent: parent,
      committed: committed,
      isCommittedSnapshotFresh: isCommittedSnapshotFresh,
      children: children,
      stateSlots: stateSlots,
      dependencies: dependencies,
      lifecycleState: lifecycleState,
      registeredHandlers: registeredHandlers,
      isDirty: isDirty,
      wasPresentAtFrameStart: wasPresentAtFrameStart,
      wasVisitedThisFrame: wasVisitedThisFrame,
      previousChildrenIdentities: previousChildrenIdentities,
      previousLifecycleMetadata: previousLifecycleMetadata,
      bodyStateSlotCount: bodyStateSlotCount,
      currentBodyStateSlotCount: currentBodyStateSlotCount,
      pendingChangeHandlerIDs: pendingChangeHandlerIDs,
      dependencyTracker: dependencyTracker.makeCheckpoint(),
      registrationCaptureDepth: registrationCaptureDepth,
      evaluationDepth: evaluationDepth,
      hasCommittedPresence: hasCommittedPresence,
      nextChangeModifierOrdinal: nextChangeModifierOrdinal,
      preparedFrameID: preparedFrameID,
      visitedFrameID: visitedFrameID,
      evaluator: evaluator
    )
  }

  package func restoreCheckpoint(_ checkpoint: Checkpoint) {
    invalidator = checkpoint.invalidator
    ownerGraph = checkpoint.ownerGraph
    parent = checkpoint.parent
    committed = checkpoint.committed
    isCommittedSnapshotFresh = checkpoint.isCommittedSnapshotFresh
    children = checkpoint.children
    stateSlots = checkpoint.stateSlots
    dependencies = checkpoint.dependencies
    lifecycleState = checkpoint.lifecycleState
    registeredHandlers = checkpoint.registeredHandlers
    isDirty = checkpoint.isDirty
    wasPresentAtFrameStart = checkpoint.wasPresentAtFrameStart
    wasVisitedThisFrame = checkpoint.wasVisitedThisFrame
    previousChildrenIdentities = checkpoint.previousChildrenIdentities
    previousLifecycleMetadata = checkpoint.previousLifecycleMetadata
    bodyStateSlotCount = checkpoint.bodyStateSlotCount
    currentBodyStateSlotCount = checkpoint.currentBodyStateSlotCount
    pendingChangeHandlerIDs = checkpoint.pendingChangeHandlerIDs
    dependencyTracker.restoreCheckpoint(checkpoint.dependencyTracker)
    registrationCaptureDepth = checkpoint.registrationCaptureDepth
    evaluationDepth = checkpoint.evaluationDepth
    hasCommittedPresence = checkpoint.hasCommittedPresence
    nextChangeModifierOrdinal = checkpoint.nextChangeModifierOrdinal
    preparedFrameID = checkpoint.preparedFrameID
    visitedFrameID = checkpoint.visitedFrameID
    evaluator = checkpoint.evaluator
  }
}
```

Add the extension in `ViewNode.swift` so it can access the file-private node
state. If `AnyStateSlot` cannot be safely copied as a value, stop and discuss
whether graph checkpointing must move to a candidate-graph model.

- [x] **Step 3: Add `ViewGraph.Checkpoint`**

Add a package checkpoint that captures graph-owned frame-head mutable state:

```swift
extension ViewGraph {
  package struct Checkpoint {
    package var root: ViewNode?
    package var nodesByIdentity: [Identity: ViewNode]
    package var rootEvaluator: (@MainActor () -> Void)?
    package var evaluationRootIdentity: Identity?
    package var viewportLifecycleNodesByIdentity: [Identity: LifecycleStateNode]
    package var viewportLifecycleOrder: [Identity]
    package var frameOrder: [Identity]
    package var stableTaskCancelEvents: [LifecycleEvent]
    package var stableTaskStartIdentities: [Identity]
    package var structuralAppearEvents: [LifecycleEvent]
    package var structuralTaskCancelEvents: [LifecycleEvent]
    package var structuralDisappearEvents: [LifecycleEvent]
    package var invalidatedIdentities: Set<Identity>
    package var graphLocalDirtyIdentities: Set<Identity>
    package var latestLifecycleEvents: [LifecycleEvent]
    package var registrationAliasesByIdentity: [Identity: Set<Identity>]
    package var registrationAliasTargets: [Identity: Identity]
    package var registrationAliasDiagnostics: RegistrationAliasDiagnostics
    package var stateSlotDependents: [StateSlotKey: Set<Identity>]
    package var environmentDependents: [ObjectIdentifier: Set<Identity>]
    package var observableDependents: [ObjectIdentifier: Set<Identity>]
    package var currentFrameID: UInt64
    package var liveIdentities: Set<Identity>
    package var nodeCheckpoints: [Identity: ViewNode.Checkpoint]
  }
}
```

- [x] **Step 4: Add graph restore methods**

Add:

```swift
  package func makeCheckpoint() -> Checkpoint

  package func restoreCheckpoint(_ checkpoint: Checkpoint)
```

`makeCheckpoint()` should snapshot nodes with:

```swift
    let nodeCheckpoints = Dictionary(
      uniqueKeysWithValues: nodesByIdentity.map { identity, node in
        (identity, node.makeCheckpoint())
      }
    )
```

`restoreCheckpoint(_:)` should restore graph fields first, then restore each
node checkpoint keyed by identity. Do not walk the current graph to discover
nodes during restore; use `checkpoint.nodesByIdentity` and
`checkpoint.nodeCheckpoints`.

- [x] **Step 5: Add graph checkpoint tests**

Add a test that renders a graph, captures a checkpoint, performs a dirty
evaluation that changes a registered key command, restores the checkpoint, then
rebuilds registrations into a fresh scratch set. Expected: the restored graph
contains only the pre-checkpoint registration.

Add a second test that covers alias identities and verifies
`restoreRuntimeRegistrations(for:into:)` after restore still sees alias handler
state.

- [x] **Step 6: Run graph tests**

Run:

```bash
swiftly run swift test --filter CoreTests.ViewGraphTests
```

Expected: graph tests pass.

- [x] **Step 7: Commit checkpoint infrastructure**

Run:

```bash
git add Sources/Core/Graph/DependencyTracker.swift Sources/Core/Graph/ViewGraph.swift Sources/Core/Graph/ViewNode.swift Tests/CoreTests/Graph/ViewGraphTests.swift
git commit -m "Add view graph checkpoints for frame-head transactions"
```

## Task 7: Add Prepared-Frame Abort Test Hooks

**Files:**
- Modify: `Sources/TerminalUI/TerminalUI.swift`
- Modify: `Tests/TerminalUITests/AsyncFrameTailRenderingTests.swift`

- [x] **Step 1: Extend `FrameHeadDraft` with graph checkpoint state**

Add:

```swift
  var viewGraphCheckpoint: ViewGraph.Checkpoint
```

Capture it in `prepareFrameHead` immediately before `viewGraph.beginFrame()`:

```swift
    let viewGraphCheckpoint = viewGraph.makeCheckpoint()
```

Return it in the `FrameHeadDraft`.

- [x] **Step 2: Add package-internal testing hooks**

Add package methods to `DefaultRenderer`:

```swift
  @MainActor
  package func prepareFrameHeadForCancellationTesting<V: View>(
    _ root: V,
    context: ResolveContext = .init(),
    proposal: ProposedSize = .unspecified
  ) -> FrameHeadDraft {
    prepareFrameHead(
      root,
      context: context,
      proposal: proposal,
      collectsDiagnostics: true
    )
  }

  @MainActor
  package func abortPreparedFrameHeadForCancellationTesting(
    _ draft: FrameHeadDraft
  ) {
    draft.registrationDraft.discard()
    viewGraph.restoreCheckpoint(draft.viewGraphCheckpoint)
    animationController.abortFrameHeadTransaction(draft.animationCheckpoint)
  }
```

If `FrameHeadDraft` must remain private, keep the hooks package-internal by
wrapping the draft in a package testing token type. Do not make a public abort
API.

- [x] **Step 3: Add abort proof for broad reset**

Test sequence:

1. Render state `0`.
2. Prepare state `1` with a new key command, drop destination, focus binding,
   preference observer, lifecycle, and task.
3. Abort the prepared frame through the testing hook.
4. Dispatch key command and paste event.
5. Render state `0` again normally.

Expected:

```swift
    #expect(!recorder.events.contains("key-command"))
    #expect(!recorder.events.contains("drop:1"))
    #expect(!recorder.events.contains("appear:revealed"))
    #expect(!recorder.events.contains("task:revealed"))
    #expect(terminal.frames.last?.contains("value 0") == true)
```

- [x] **Step 4: Add abort proof for selective dirty reuse**

Repeat the abort test with selective evaluation enabled and only one subtree
invalidated. Expected: untouched sibling registrations remain live, aborted
subtree registrations do not become live, and a subsequent normal render
rebuilds the subtree correctly.

- [x] **Step 5: Run abort hook tests**

Run:

```bash
swiftly run swift test --filter TerminalUITests.AsyncFrameTailRenderingTests
```

Expected: all tests in `AsyncFrameTailRenderingTests` pass.

- [x] **Step 6: Commit abort proof hooks**

Run:

```bash
git add Sources/TerminalUI/TerminalUI.swift Tests/TerminalUITests/AsyncFrameTailRenderingTests.swift
git commit -m "Prove prepared frame heads can be aborted"
```

## Task 8: Gate Animation, Lifecycle, Task, And Worker Cache Effects

**Files:**
- Modify: `Sources/TerminalUI/TerminalUI.swift`
- Modify: `Tests/TerminalUITests/AsyncFrameTailRenderingTests.swift`

- [x] **Step 1: Audit `prepareFrameHead` and `renderFrameTailAsync` side effects**

Confirm each effect is either draft-only, checkpoint-restored, or commit-only:

- Runtime registrations: draft-only until `finishFrame`.
- Animation completions: held by `AnimationController.Checkpoint`.
- Placed animation snapshots: aborted through the animation checkpoint.
- Lifecycle events: produced by `viewGraph.finalizeFrame` only during finish.
- Tasks: started from committed lifecycle/task registrations only after finish.
- Worker custom-layout cache updates: held in `FrameTailLayoutOutput` and applied
  only in `finishFrame`.
- Measurement cache pruning: happens only in `finishFrame`.
- Retained committed frame: stored only after `finishFrame`.

- [x] **Step 2: Add tests for each commit-only effect**

Extend the abort proof test so it verifies:

```swift
    #expect(!recorder.events.contains("animation-completion"))
    #expect(!recorder.events.contains("appear:revealed"))
    #expect(!recorder.events.contains("task:revealed"))
```

For worker custom-layout cache, use `AsyncFrameTailWorkerCustomLayoutRecorder`
and assert:

```swift
    #expect(recorder.state.cacheApplyCount == 0)
```

after abort, then assert `cacheApplyCount == 1` after the next normal committed
render.

- [x] **Step 3: Move any leaking effect behind finish**

If an effect fires during prepare or during an aborted tail, move it into
`finishFrame` or into a checkpoint-restored transaction. If the effect cannot be
moved or restored without changing its public semantics, stop and discuss the
remaining non-draft side effect before continuing.

- [x] **Step 4: Run focused effect tests**

Run:

```bash
swiftly run swift test --filter TerminalUITests.AsyncFrameTailRenderingTests
```

Expected: all tests in `AsyncFrameTailRenderingTests` pass.

- [x] **Step 5: Commit effect gating**

Run:

```bash
git add Sources/TerminalUI/TerminalUI.swift Tests/TerminalUITests/AsyncFrameTailRenderingTests.swift
git commit -m "Gate frame-head effects behind commit"
```

## Task 9: Add Pre-Start Tail Job Cancellation

**Files:**
- Modify: `Sources/TerminalUI/TerminalUI.swift`
- Modify: `Sources/TerminalUI/RunLoop+Rendering.swift`
- Modify: `Sources/TerminalUI/FrameDiagnosticsLogger.swift`
- Modify: `Tests/TerminalUITests/AsyncFrameTailRenderingTests.swift`

- [x] **Step 1: Add tail job state**

Add an internal state enum near `FrameTailRenderer`:

```swift
private enum FrameTailJobState: Equatable, Sendable {
  case queued
  case started
  case completed
  case cancelledBeforeStart
}
```

Add a cancellable queued submission token that can transition from `queued` to
`cancelledBeforeStart` only before the worker closure begins layout.

- [x] **Step 2: Add a queued cancellation API**

Add a method shaped like:

```swift
  @MainActor
  package func renderFrameTailCancellable(
    _ draft: FrameHeadDraft
  ) async -> CancellableFrameTailResult
```

`CancellableFrameTailResult` must represent either a finished tail output or a
successful pre-start cancellation:

```swift
private enum CancellableFrameTailResult {
  case output(AsyncFrameTailDraftOutput)
  case cancelledBeforeStart
}
```

The cancellation result is legal only while no worker layout or raster closure
has begun.

- [x] **Step 3: Update the run loop policy**

In `RunLoop+Rendering.swift`, race queued tail work with input/render intent only
while the job state is `queued`. If newer desired state arrives and cancellation
succeeds:

```swift
renderer.abortPreparedFrameHeadForCancellationTesting(draft)
```

Replace the testing method name with a package production abort method in this
task:

```swift
  @MainActor
  package func abortPreparedFrameHead(_ draft: FrameHeadDraft)
```

If cancellation loses the race and the job reaches `started`, await the output
and call `finishFrame` exactly as the current ordered path does.

- [x] **Step 4: Add diagnostics**

Add TSV fields:

- `tail_job_state`
- `tail_cancel_reason`
- `cancelled_render_count`
- `newest_desired_at_tail_start`
- `newest_desired_at_tail_result`

Expected values:

- No cancellation: `tail_job_state=started` or `tail_job_state=completed`,
  `stale_frame_policy=commit_ordered`.
- Successful queued cancellation:
  `tail_job_state=cancelled_before_start`,
  `tail_cancel_reason=newer_render_intent`,
  `stale_frame_policy=cancel_pending_before_start`.

- [x] **Step 5: Add queued cancellation test**

Use a worker hook that blocks before layout start. Start a render, queue a newer
input event, and assert the first prepared frame aborts before layout begins.
Expected:

```swift
    #expect(result.finalState == 1)
    #expect(terminal.frames.last?.contains("value 1") == true)
    #expect(rows.contains { $0["tail_job_state"] == "cancelled_before_start" })
```

- [x] **Step 6: Add started-job ordered commit test**

Use a hook that blocks after layout start or before raster. Queue newer input
while the job is already started. Expected:

```swift
    #expect(terminal.frames.first?.contains("value 0") == true)
    #expect(terminal.frames.last?.contains("value 1") == true)
    #expect(rows.allSatisfy { $0["stale_frame_policy"] != "drop_completed" })
```

- [x] **Step 7: Run cancellation tests**

Run:

```bash
swiftly run swift test --filter TerminalUITests.AsyncFrameTailRenderingTests
swiftly run swift test --filter 'TerminalUITests.InteractiveRuntimeTests/(mouseClickOnScrollIndicatorJumpsToLocation|mouseDragOnScrollIndicatorTracksDraggedPosition|runLoopBatchesQueuedScrollBurstsWithLazyStacks)'
swiftly run swift test --package-path Examples/gallery --filter 'GalleryDemoViewsTests.GalleryTabSwitchTests/clickingGalleryTabSwitchesSelection'
```

Expected: all listed tests pass.

- [x] **Step 8: Commit pre-start cancellation**

Run:

```bash
git add Sources/TerminalUI/TerminalUI.swift Sources/TerminalUI/RunLoop+Rendering.swift Sources/TerminalUI/FrameDiagnosticsLogger.swift Tests/TerminalUITests/AsyncFrameTailRenderingTests.swift
git commit -m "Cancel queued frame tails before worker start"
```

## Task 10: Validate Runtime Examples And Full Gate

**Files:**
- Modify: `docs/plans/2026-05-01-006-async-frame-head-draft-transaction-plan.md`
- Modify: `docs/ASYNC_RENDERING.md`
- Modify: `docs/README.md`

- [x] **Step 1: Capture real diagnostics samples**

Run:

```bash
cd Examples/gallery
TERMUI_DIAGNOSTICS=/tmp/gallery-termui-diagnostics.tsv swiftly run swift run gallery-demo

cd ../layouts
TERMUI_DIAGNOSTICS=/tmp/layouts-termui-diagnostics.tsv swiftly run swift run layouts-demo
```

Exercise tab clicks, scroll indicator clicks, scroll indicator drags, pointer
scroll bursts, layout selection changes, and keyboard commands. Record the
observed cancellation rows in this plan's verification log.

- [x] **Step 2: Run the full repo gate**

Run from the repository root:

```bash
bun run test
```

Expected: full gate passes.

- [x] **Step 3: Update async status docs**

Update `docs/ASYNC_RENDERING.md` progress map:

- `Abortable prepared frame heads`: `Shipped`
- `Cancellable pre-start tail jobs`: `Shipped`
- `Visual-only completed-frame drops`: `Not shipped`
- `Off-main resolve`: `Not planned near-term`

Move this plan in `docs/README.md` from current planned/active plans to
implementation and post-mortem records.

- [x] **Step 4: Commit docs and verification**

Run:

```bash
git add docs/plans/2026-05-01-006-async-frame-head-draft-transaction-plan.md docs/ASYNC_RENDERING.md docs/README.md
git commit -m "Record async frame-head transaction completion"
```

## Verification Matrix

Final verification run before marking the plan shipped:

```bash
swiftly run swift test --filter TerminalUITests.AsyncFrameTailRenderingTests
swiftly run swift test --filter TerminalUITests.PreferenceSurfaceTests/resolveReuseReplaysStablePreferenceObserversForReusedSubtrees
swiftly run swift test --filter TerminalUITests.DiagnosticsAndCacheTests/resolveReuseReplaysFocusedValuePublishers
swiftly run swift test --filter TerminalUITests.ImperativeAuthoringContextDispatchTests/gestureCallbacksTargetDispatchingGraph
swiftly run swift test --filter TerminalUITests.InteractiveRuntimeTests/runLoopEmitsViewportLifecycleTransitionsForFullLazyRows
swiftly run swift test
swiftly run swift package --package-path Examples/gallery clean
swiftly run swift package --package-path Examples/layouts clean
swiftly run swift test --package-path Examples/gallery
swiftly run swift test --package-path Examples/layouts
bun run test
```

Result: PASS. Full gate log:
`/tmp/swift-terminal-ui-test-all-20260501-175403-52612.log`.

Diagnostics samples captured:

```bash
TERMUI_DIAGNOSTICS=/tmp/gallery-termui-diagnostics-20260501.tsv swiftly run swift run gallery-demo
TERMUI_DIAGNOSTICS=/tmp/layouts-termui-diagnostics-20260501.tsv swiftly run swift run layouts-demo
```

Observed diagnostics:

- Gallery produced 8 TSV rows, including cancelled queued-tail rows with
  `tail_job_state=cancelled_before_start`,
  `tail_cancel_reason=newer_render_intent`,
  `stale_frame_policy=cancel_pending_before_start`, and increasing
  `cancelled_render_count`.
- Gallery completed rows returned to `stale_frame_policy=commit_ordered` and
  `tail_job_state=completed`.
- Layouts produced 4 TSV rows, all `tail_job_state=completed` with
  `stale_frame_policy=commit_ordered`; input pressure appeared in
  `coalesced_event_batches` / `coalesced_intent_requests` without actual
  cancellation.
- Both samples retained `drop_blockers=handlerInstallations` on the committed
  rows, so completed-frame dropping remains correctly disabled.

Final behavior:

- A prepared frame can be aborted without exposing its key commands, drop
  destinations, focus bindings, lifecycle events, tasks, animation completions,
  preference observers, or worker cache updates.
- A normal committed frame rebuilds live runtime registrations from committed
  graph handlers and aliases.
- Selective dirty evaluation preserves untouched sibling registrations while
  keeping newly prepared dirty-frontier registrations draft-only until commit.
- Queued tail jobs may cancel before worker layout starts.
- Started and completed tail jobs still commit in order.
- TSV diagnostics distinguish cancellation pressure from actual cancellation.
- Completed-frame dropping remains unimplemented.

## Stop Points

Stop and discuss design before continuing if any of these happen:

- `ViewGraph.Checkpoint` cannot cover a mutable stored field without aliasing
  mutable graph state across abort.
- `ViewNode.Checkpoint` cannot restore handler or child state without breaking
  committed snapshot ownership.
- A draft registry snapshot appears necessary as the source for rebuilding live
  registries.
- Any test requires dropping a completed frame to pass.
- Any lifecycle, task, animation completion, focus, or custom-layout cache effect
  fires before `finishFrame` and cannot be made commit-only.
- Pre-start cancellation requires cancelling a worker closure after layout has
  begun.

## Execution Handoff

Complete. The plan was executed in order with a commit after each green
checkpoint. Task 1's failing test became part of the Task 3 passing commit, and
the final docs commit records the shipped state.
