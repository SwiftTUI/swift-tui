---
title: "fix: keep lifecycle modifiers stable across selective evaluation"
type: fix
status: shipped
date: 2026-05-03
depends_on:
  - "../RUNTIME.md"
  - "../proposals/VIEW_MODIFIER_LAYER.md"
  - "2026-05-02-002-composed-presentation-primitives-plan.md"
---

# Lifecycle Modifier Selective Evaluation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for
> tracking. Keep commits scoped to each task that reaches a green checkpoint.

**Goal:** Keep `.task`, `.onAppear`, and `.onDisappear` metadata stable when a
dirty frame selectively re-evaluates content below a transparent modifier owner.

**Architecture:** Lifecycle modifiers remain identity-driven: metadata and task
descriptors stay attached to the resolved lifecycle identity, not to an
incidental wrapper. The new framework contract is that `ViewGraph` also records
which graph identity must be evaluated to re-author that lifecycle metadata; the
dirty-frontier planner promotes affected child updates back to that owner before
running selective evaluation.

**Tech Stack:** Swift 6.3, Swift Testing, `View` primitive modifiers,
`Core.ViewGraph`, `DefaultRenderer`, `RunLoop`, `PortalPrimitiveTests`, and the
`Examples/gifeditor` presentation runtime tests.

---

## Problem Frame

The current `Spinner` body is:

```swift
Group {
  Text(set.body[iteration])
}
.task(id: Pair(a: set, b: stage)) { ... }
```

`TaskLifecycleModifier.resolve` resolves the transparent `Group`, attaches task
metadata to the resolved child identity, and registers the task under that same
identity. That is the correct public lifecycle identity. The bug is that the
child identity can also have its own retained evaluator. When selective dirty
evaluation re-enters through that child evaluator, the bare child `Text` is
committed without the outer `.task` metadata. `ViewGraph` sees a stable identity
lose its task descriptor and emits `taskCancel`, stopping the spinner loop.

This plan fixes the framework seam, not `Spinner` locally.

## Non-Goals

- Do not remove `Group` from `Spinner` as the primary fix.
- Do not keep tasks alive by ignoring `taskCancel`; real descriptor removal and
  replacement must still cancel.
- Do not introduce public wrapper identities for lifecycle modifiers.
- Do not remove or redesign the existing registration alias layer.

## Files

- Modify: `Sources/Core/Graph/ViewGraph.swift`
  - Store lifecycle evaluation-owner mappings.
  - Checkpoint and restore those mappings.
  - Clear stale mappings when an owner is re-evaluated.
  - Promote dirty frontier nodes to the recorded owner.
- Modify: `Sources/View/Modifiers/ViewModifiers.swift`
  - Record lifecycle evaluation ownership from `onAppear`, `onDisappear`, and
    `task`.
- Modify: `Tests/SwiftTUITests/PortalPrimitiveTests.swift`
  - Strengthen the spinner regression so it proves continuing animation, not
    just one glyph advance.
- Create: `Tests/SwiftTUITests/LifecycleSelectiveEvaluationTests.swift`
  - Add renderer-level characterization tests for transparent lifecycle owners.
- Modify: `docs/RUNTIME.md`
  - Document lifecycle evaluation ownership in the task rules.
- Modify: `Sources/SwiftTUI/SwiftTUI.docc/Runtime.md`
  - Keep the DocC runtime article aligned with `docs/RUNTIME.md`.

## Core Invariants

- A lifecycle modifier's observable identity remains the resolved node identity.
- The graph identity that authored lifecycle metadata is recorded separately.
- If a dirty frontier node is at or below a lifecycle-owned identity, selective
  evaluation re-runs the lifecycle owner evaluator.
- Re-running the owner preserves unchanged lifecycle metadata and task
  registrations.
- Re-running the owner still allows real task replacement or removal to produce
  the existing cancel/start lifecycle deltas.
- Target nodes whose persistent lifecycle metadata is authored by a different
  graph node do not emit their own stable lifecycle deltas during evaluation or
  retained reuse. Real structural removal still fires from the removed node's
  committed lifecycle metadata.

---

## Task 1: Add Failing Regressions

**Files:**

- Create: `Tests/SwiftTUITests/LifecycleSelectiveEvaluationTests.swift`
- Modify: `Tests/SwiftTUITests/PortalPrimitiveTests.swift`

- [ ] **Step 1: Add a renderer-level transparent owner regression**

Create `Tests/SwiftTUITests/LifecycleSelectiveEvaluationTests.swift` with this
test. It uses observation to trigger a selective child invalidation below a
transparent `Group` that owns a `.task`.

```swift
import Observation
import Testing

@_spi(Testing) @testable import Core
@_spi(Runners) @testable import SwiftTUI
@testable import View

@MainActor
@Suite(.serialized)
struct LifecycleSelectiveEvaluationTests {
  @Test("selective child invalidation under transparent task owner preserves the task")
  func selectiveChildInvalidationUnderTransparentTaskOwnerPreservesTask() throws {
    let model = LifecycleSelectiveCounter()
    let invalidator = LifecycleSelectiveRecordingInvalidator()
    let bridge = ObservationBridge()
    bridge.attachInvalidator(invalidator)

    let taskRegistry = LocalTaskRegistry()
    let renderer = DefaultRenderer()
    var initialContext = ResolveContext(
      identity: testIdentity("Root"),
      localTaskRegistry: taskRegistry,
      applyEnvironmentValues: true
    )
    initialContext.observationBridge = bridge

    let initialArtifacts = renderer.render(
      LifecycleSelectiveTransparentTaskProbe(model: model),
      context: initialContext
    )
    let initialNode = try #require(
      initialArtifacts.resolvedTree.descendant(withText: "Count 0")
    )
    let expectedTask = TaskDescriptor(
      id: "\(initialNode.identity)#task[\"stable\"]",
      priority: .medium
    )
    #expect(initialNode.lifecycleMetadata.task == expectedTask)
    #expect(taskRegistry.registration(for: initialNode.identity)?.descriptor == expectedTask)

    invalidator.clear()
    model.count = 1
    let invalidated = invalidator.requests.reduce(into: Set<Identity>()) { partial, request in
      partial.formUnion(request)
    }
    #expect(!invalidated.isEmpty)

    var updatedContext = ResolveContext(
      identity: testIdentity("Root"),
      invalidatedIdentities: invalidated,
      localTaskRegistry: taskRegistry,
      applyEnvironmentValues: true
    )
    updatedContext.observationBridge = bridge

    let updatedArtifacts = renderer.render(
      LifecycleSelectiveTransparentTaskProbe(model: model),
      context: updatedContext
    )
    let updatedNode = try #require(
      updatedArtifacts.resolvedTree.descendant(withText: "Count 1")
    )

    #expect(updatedNode.identity == initialNode.identity)
    #expect(updatedNode.lifecycleMetadata.task == expectedTask)
    #expect(taskRegistry.registration(for: updatedNode.identity)?.descriptor == expectedTask)
    #expect(updatedArtifacts.commitPlan.lifecycle.isEmpty)
  }
}

@Observable
private final class LifecycleSelectiveCounter {
  var count = 0
}

private struct LifecycleSelectiveTransparentTaskProbe: View {
  let model: LifecycleSelectiveCounter

  var body: some View {
    Group {
      Text("Count \(model.count)")
    }
    .task(id: "stable") {}
  }
}

private final class LifecycleSelectiveRecordingInvalidator: Invalidating {
  var requests: [Set<Identity>] = []

  func requestInvalidation(of identities: Set<Identity>) {
    requests.append(identities)
  }

  func clear() {
    requests.removeAll(keepingCapacity: true)
  }
}

extension ResolvedNode {
  fileprivate func descendant(withText text: String) -> ResolvedNode? {
    if drawPayload == .text(text) {
      return self
    }
    for child in children {
      if let match = child.descendant(withText: text) {
        return match
      }
    }
    return nil
  }
}
```

- [ ] **Step 2: Add appear/disappear coverage for the same owner seam**

Add a second test inside `LifecycleSelectiveEvaluationTests`, before the closing
brace from Step 1. This proves the owner map covers all persistent lifecycle
metadata, not just task metadata.

```swift
  @Test("selective child invalidation under transparent appear disappear owner preserves handlers")
  func selectiveChildInvalidationUnderTransparentAppearDisappearOwnerPreservesHandlers() throws {
    let model = LifecycleSelectiveCounter()
    let invalidator = LifecycleSelectiveRecordingInvalidator()
    let bridge = ObservationBridge()
    bridge.attachInvalidator(invalidator)

    let lifecycleRegistry = LocalLifecycleRegistry()
    let renderer = DefaultRenderer()
    var initialContext = ResolveContext(
      identity: testIdentity("Root"),
      localLifecycleRegistry: lifecycleRegistry,
      applyEnvironmentValues: true
    )
    initialContext.observationBridge = bridge

    let initialArtifacts = renderer.render(
      LifecycleSelectiveTransparentAppearProbe(model: model),
      context: initialContext
    )
    let initialNode = try #require(
      initialArtifacts.resolvedTree.descendant(withText: "Count 0")
    )
    #expect(initialNode.lifecycleMetadata.appearHandlerIDs.count == 1)
    #expect(initialNode.lifecycleMetadata.disappearHandlerIDs.count == 1)

    invalidator.clear()
    model.count = 1
    let invalidated = invalidator.requests.reduce(into: Set<Identity>()) { partial, request in
      partial.formUnion(request)
    }

    var updatedContext = ResolveContext(
      identity: testIdentity("Root"),
      invalidatedIdentities: invalidated,
      localLifecycleRegistry: lifecycleRegistry,
      applyEnvironmentValues: true
    )
    updatedContext.observationBridge = bridge

    let updatedArtifacts = renderer.render(
      LifecycleSelectiveTransparentAppearProbe(model: model),
      context: updatedContext
    )
    let updatedNode = try #require(
      updatedArtifacts.resolvedTree.descendant(withText: "Count 1")
    )

    #expect(updatedNode.identity == initialNode.identity)
    #expect(updatedNode.lifecycleMetadata.appearHandlerIDs == initialNode.lifecycleMetadata.appearHandlerIDs)
    #expect(updatedNode.lifecycleMetadata.disappearHandlerIDs == initialNode.lifecycleMetadata.disappearHandlerIDs)
    #expect(updatedArtifacts.commitPlan.lifecycle.isEmpty)
  }

private struct LifecycleSelectiveTransparentAppearProbe: View {
  let model: LifecycleSelectiveCounter

  var body: some View {
    Group {
      Text("Count \(model.count)")
    }
    .onAppear {}
    .onDisappear {}
  }
}
```

- [ ] **Step 3: Strengthen the portal spinner test**

In `Tests/SwiftTUITests/PortalPrimitiveTests.swift`, replace the weak "any
advanced glyph" assertion in
`singleRootHoistedSpinnerAdvancesAcrossAsyncFrames` with a distinct-glyph
minimum. Keep the existing startup/dismiss flow.

```swift
    let expectedGlyphs = Set(["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"])

    let inputReader = PortalPrimitiveAwaitedInputReader(steps: [
      .press(KeyPress(.return)),
      .waitUntil(timeoutNanoseconds: 3_000_000_000) {
        observedSpinnerGlyphs(
          in: terminal.frames,
          expectedGlyphs: expectedGlyphs
        ).count >= 7
      },
      .press(KeyPress(.character("c"), modifiers: .ctrl)),
    ])
```

Add the helper near the existing test helpers:

```swift
private func observedSpinnerGlyphs(
  in frames: [String],
  expectedGlyphs: Set<String>
) -> Set<String> {
  frames.reduce(into: Set<String>()) { partial, frame in
    for glyph in expectedGlyphs where frame.contains(glyph) {
      partial.insert(glyph)
    }
  }
}
```

- [ ] **Step 4: Run the new tests and confirm the red failure**

Run:

```bash
swiftly run swift test --filter SwiftTUITests.LifecycleSelectiveEvaluationTests
swiftly run swift test --filter SwiftTUITests.PortalPrimitiveTests/singleRootHoistedSpinnerAdvancesAcrossAsyncFrames
```

Expected before the fix:

- The lifecycle selective test either emits a `taskCancel` or loses task
  metadata after the observed child update.
- The strengthened spinner test times out or observes fewer than seven spinner
  glyphs.

---

## Task 2: Record Lifecycle Evaluation Owners

**Files:**

- Modify: `Sources/Core/Graph/ViewGraph.swift`

- [ ] **Step 1: Add owner maps to `ViewGraph.Checkpoint`**

Add these stored properties to `ViewGraph.Checkpoint`:

```swift
    package var lifecycleEvaluationOwnersByIdentity: [Identity: Identity]
    package var lifecycleEvaluationTargetsByOwner: [Identity: Set<Identity>]
    package var lifecycleEvaluationTargetsRecordedByOwner: [Identity: Set<Identity>]
```

Thread them through `makeCheckpoint()` and `restoreCheckpoint(_:)`.

- [ ] **Step 2: Add owner maps to `ViewGraph`**

Add private storage beside the registration alias maps:

```swift
  private var lifecycleEvaluationOwnersByIdentity: [Identity: Identity]
  private var lifecycleEvaluationTargetsByOwner: [Identity: Set<Identity>]
  private var lifecycleEvaluationTargetsRecordedByOwner: [Identity: Set<Identity>]
```

Initialize all three to `[:]` in `init()`.

- [ ] **Step 3: Add the public package recording API**

Add this method near `recordRegistrationAlias(from:to:resolvedKind:)`:

```swift
  package func recordLifecycleEvaluationOwner(
    target targetIdentity: Identity,
    owner ownerIdentity: Identity
  ) {
    if let previousOwner = lifecycleEvaluationOwnersByIdentity[targetIdentity],
      previousOwner != ownerIdentity
    {
      lifecycleEvaluationTargetsByOwner[previousOwner]?.remove(targetIdentity)
      if lifecycleEvaluationTargetsByOwner[previousOwner]?.isEmpty == true {
        lifecycleEvaluationTargetsByOwner.removeValue(forKey: previousOwner)
      }
    }

    lifecycleEvaluationOwnersByIdentity[targetIdentity] = ownerIdentity
    lifecycleEvaluationTargetsByOwner[ownerIdentity, default: []].insert(targetIdentity)
    if lifecycleEvaluationTargetsRecordedByOwner[ownerIdentity] != nil {
      lifecycleEvaluationTargetsRecordedByOwner[ownerIdentity, default: []].insert(targetIdentity)
    }
  }
```

- [ ] **Step 4: Track and prune stale mappings after an owner re-evaluates**

Add a private helper:

```swift
  private func pruneLifecycleEvaluationOwners(
    ownedBy ownerIdentity: Identity
  ) {
    guard
      let recordedTargets = lifecycleEvaluationTargetsRecordedByOwner.removeValue(
        forKey: ownerIdentity
      )
    else {
      return
    }
    guard let targets = lifecycleEvaluationTargetsByOwner[ownerIdentity] else {
      return
    }
    let staleTargets = targets.subtracting(recordedTargets)
    for target in staleTargets {
      lifecycleEvaluationOwnersByIdentity.removeValue(forKey: target)
    }
    if recordedTargets.isEmpty {
      lifecycleEvaluationTargetsByOwner.removeValue(forKey: ownerIdentity)
    } else {
      lifecycleEvaluationTargetsByOwner[ownerIdentity] = recordedTargets
    }
  }
```

In `beginEvaluation(identity:invalidator:suppressesStructuralLifecycle:)`, clear
only the per-evaluation recording set when the node has just entered its
outermost evaluation depth:

```swift
    node.beginEvaluation(
      frameID: currentFrameID,
      invalidator: invalidator,
      suppressesStructuralLifecycle: suppressesStructuralLifecycle
    )
    if node.isAtOutermostEvaluationDepth {
      lifecycleEvaluationTargetsRecordedByOwner[identity] = []
    }
    return node
```

Do not clear the existing owner map at this point. It must remain available
while child content is evaluated, otherwise a transparent child can emit a
spurious `taskCancel` before the owner reapplies metadata. After the owner
finishes, prune any previously owned targets that were not re-recorded.

- [ ] **Step 5: Remove mappings when nodes are removed**

In `removeSubtree(rootedAt:committedSnapshot:)`, remove both directions before
dropping the node from `nodesByIdentity`:

```swift
    if let owner = lifecycleEvaluationOwnersByIdentity.removeValue(forKey: node.identity) {
      lifecycleEvaluationTargetsByOwner[owner]?.remove(node.identity)
      if lifecycleEvaluationTargetsByOwner[owner]?.isEmpty == true {
        lifecycleEvaluationTargetsByOwner.removeValue(forKey: owner)
      }
    }
    if let targets = lifecycleEvaluationTargetsByOwner.removeValue(forKey: node.identity) {
      for target in targets {
        lifecycleEvaluationOwnersByIdentity.removeValue(forKey: target)
      }
    }
```

---

## Task 3: Promote Dirty Evaluation To Lifecycle Owners

**Files:**

- Modify: `Sources/Core/Graph/ViewGraph.swift`

- [ ] **Step 1: Add a resolver for lifecycle owner ancestors**

Add this helper near `nearestEvaluatorAncestor(of:)`:

```swift
  private func lifecycleEvaluationOwnerAncestor(
    of node: ViewNode
  ) -> ViewNode? {
    var current: ViewNode? = node
    var visited: Set<ObjectIdentifier> = []

    while let candidate = current {
      let candidateID = ObjectIdentifier(candidate)
      guard visited.insert(candidateID).inserted else {
        return nil
      }
      if let ownerIdentity = lifecycleEvaluationOwnersByIdentity[candidate.identity],
        let ownerNode = nodesByIdentity[ownerIdentity]
      {
        return ownerNode
      }
      current = candidate.parent
    }

    return nil
  }
```

- [ ] **Step 2: Centralize evaluator promotion**

Add:

```swift
  private func evaluatorTarget(
    for dirtyNode: ViewNode
  ) -> ViewNode? {
    if let lifecycleOwner = lifecycleEvaluationOwnerAncestor(of: dirtyNode) {
      return lifecycleOwner.hasEvaluator ? lifecycleOwner : nearestEvaluatorAncestor(of: lifecycleOwner)
    }
    return dirtyNode.hasEvaluator ? dirtyNode : nearestEvaluatorAncestor(of: dirtyNode)
  }
```

- [ ] **Step 3: Use the lifecycle-aware target in `selectiveDirtyEvaluationPlan()`**

Replace the current target selection:

```swift
      let target = node.hasEvaluator ? node : nearestEvaluatorAncestor(of: node)
```

with:

```swift
      let target = evaluatorTarget(for: node)
```

Keep the existing `target.markDirty()`, dedupe, and `allSatisfy(\.hasEvaluator)`
behavior. This makes the dirty plan fall back to the existing full-root path if
the owner mapping is stale or points at a node without any evaluator chain.

- [ ] **Step 4: Suppress target-owned stable lifecycle deltas**

Add a helper used by `finishEvaluation` and `recordReusedSubtree`:

```swift
  private func nodeEmitsOwnLifecycleEvents(
    _ node: ViewNode
  ) -> Bool {
    guard node.participatesInStructuralLifecycle else {
      return false
    }
    guard let ownerIdentity = lifecycleEvaluationOwnersByIdentity[node.identity],
      ownerIdentity != node.identity,
      nodesByIdentity[ownerIdentity] != nil
    else {
      return true
    }
    return false
  }
```

Use this helper instead of `node.participatesInStructuralLifecycle` for stable
task start/cancel, structural task cancel, and appear/disappear emission. The
lifecycle owner emits those events; the target child must not duplicate or
pre-empt them.

- [ ] **Step 5: Run focused graph/runtime tests**

Run:

```bash
swiftly run swift test --filter SwiftTUITests.LifecycleSelectiveEvaluationTests
swiftly run swift test --filter SwiftTUITests.PortalPrimitiveTests/singleRootHoistedSpinnerAdvancesAcrossAsyncFrames
```

Expected after Task 3:

- The code compiles.
- The lifecycle and spinner tests may still fail until the modifiers record
  ownership in Task 4.

---

## Task 4: Record Owners From Lifecycle Modifiers

**Files:**

- Modify: `Sources/View/Modifiers/ViewModifiers.swift`

- [ ] **Step 1: Add a small helper near `lifecycleHandlerID`**

```swift
private func recordLifecycleEvaluationOwner(
  for lifecycleIdentity: Identity,
  in context: ResolveContext
) {
  context.viewGraph?.recordLifecycleEvaluationOwner(
    target: lifecycleIdentity,
    owner: context.identity
  )
}
```

- [ ] **Step 2: Record ownership in `AppearLifecycleModifier`**

After `var node = content.resolve(in: context)`:

```swift
    recordLifecycleEvaluationOwner(
      for: node.identity,
      in: context
    )
```

- [ ] **Step 3: Record ownership in `DisappearLifecycleModifier`**

After `var node = content.resolve(in: context)`:

```swift
    recordLifecycleEvaluationOwner(
      for: node.identity,
      in: context
    )
```

- [ ] **Step 4: Record ownership in `TaskLifecycleModifier`**

After `let lifecycleIdentity = node.identity`:

```swift
    recordLifecycleEvaluationOwner(
      for: lifecycleIdentity,
      in: context
    )
```

- [ ] **Step 5: Do not record ownership from `ChangeLifecycleModifier` in this pass**

`onChange` does not persist in `LifecycleMetadata`; it queues per-frame change
handlers on the owner node. Keep this fix scoped to persistent lifecycle
metadata (`appearHandlerIDs`, `disappearHandlerIDs`, and `task`). If a later
test proves `onChange` has a similar selective-evaluation owner issue, address
it with a dedicated plan because its state-slot ordinal behavior is separate.

- [ ] **Step 6: Run the focused tests again**

Run:

```bash
swiftly run swift test --filter SwiftTUITests.LifecycleSelectiveEvaluationTests
swiftly run swift test --filter SwiftTUITests.PortalPrimitiveTests/singleRootHoistedSpinnerAdvancesAcrossAsyncFrames
swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/conditionalLifecycleOwnershipFollowsResolvedBranchIdentity
swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests/publicLifecycleAndTaskModifiersDriveCommitDeltas
```

Expected:

- The new lifecycle and spinner tests pass.
- Existing lifecycle identity tests still show branch/resolved identities, not
  wrapper identities.
- Task replacement still emits cancel then start.

---

## Task 5: Prove Real Cancellation Still Works

**Files:**

- Modify: `Tests/SwiftTUITests/LifecycleSelectiveEvaluationTests.swift`

- [ ] **Step 1: Add task replacement coverage under a transparent owner**

Add:

```swift
  @Test("transparent task owner still cancels and restarts when descriptor changes")
  func transparentTaskOwnerStillCancelsAndRestartsWhenDescriptorChanges() {
    let renderer = DefaultRenderer()

    _ = renderer.render(
      LifecycleSelectiveTaskReplacementProbe(label: "A", taskID: "first"),
      context: .init(identity: testIdentity("Root"))
    )
    let updated = renderer.render(
      LifecycleSelectiveTaskReplacementProbe(label: "A", taskID: "second"),
      context: .init(identity: testIdentity("Root"))
    )

    #expect(
      updated.commitPlan.lifecycle == [
        .init(
          identity: testIdentity("Root", "Group[0]"),
          operation: .taskCancel(
            .init(id: "Root/Group[0]#task[\"first\"]", priority: .medium)
          )
        ),
        .init(
          identity: testIdentity("Root", "Group[0]"),
          operation: .taskStart(
            .init(id: "Root/Group[0]#task[\"second\"]", priority: .medium)
          )
        ),
      ]
    )
  }

private struct LifecycleSelectiveTaskReplacementProbe: View {
  let label: String
  let taskID: String

  var body: some View {
    Group {
      Text(label)
    }
    .task(id: taskID) {}
  }
}
```

- [ ] **Step 2: Add task removal coverage under a transparent owner**

Add:

```swift
  @Test("transparent task owner still cancels when the task modifier is removed")
  func transparentTaskOwnerStillCancelsWhenTaskModifierIsRemoved() {
    let renderer = DefaultRenderer()

    _ = renderer.render(
      LifecycleSelectiveOptionalTaskProbe(label: "A", hasTask: true),
      context: .init(identity: testIdentity("Root"))
    )
    let updated = renderer.render(
      LifecycleSelectiveOptionalTaskProbe(label: "A", hasTask: false),
      context: .init(identity: testIdentity("Root"))
    )

    #expect(
      updated.commitPlan.lifecycle == [
        .init(
          identity: testIdentity("Root", "true", "Group[0]"),
          operation: .taskCancel(
            .init(id: "Root/true/Group[0]#task[\"optional\"]", priority: .medium)
          )
        )
      ]
    )
  }

private struct LifecycleSelectiveOptionalTaskProbe: View {
  let label: String
  let hasTask: Bool

  var body: some View {
    if hasTask {
      Group {
        Text(label)
      }
      .task(id: "optional") {}
    } else {
      Group {
        Text(label)
      }
    }
  }
}
```

- [ ] **Step 3: Adjust expected identities only if the red run shows a different existing identity**

Use the identities emitted by the current resolved tree. The assertion must stay
strict: it should prove cancellation is still emitted for actual descriptor
replacement and actual descriptor removal.

- [ ] **Step 4: Run lifecycle-focused tests**

Run:

```bash
swiftly run swift test --filter SwiftTUITests.LifecycleSelectiveEvaluationTests
swiftly run swift test --filter SwiftTUITests.Phase2CommitPlannerTests
swiftly run swift test --filter SwiftTUITests.Phase2LifecycleFixtureTests
```

Expected:

- New preservation tests pass.
- New replacement/removal tests pass.
- Existing commit planner ordering remains unchanged.

---

## Task 6: Update Runtime Documentation

**Files:**

- Modify: `docs/RUNTIME.md`
- Modify: `Sources/SwiftTUI/SwiftTUI.docc/Runtime.md`

- [ ] **Step 1: Update task rules in `docs/RUNTIME.md`**

In the "Task Rules" section, add:

```markdown
- Selective dirty evaluation must re-run the graph node that authored a lifecycle
  modifier before committing any descendant update that would otherwise drop that
  modifier's lifecycle metadata. The lifecycle identity remains the resolved
  node identity; the evaluation owner is an internal graph-retention detail.
```

- [ ] **Step 2: Mirror the same rule in DocC**

Add the same bullet to
`Sources/SwiftTUI/SwiftTUI.docc/Runtime.md` in its "Task Rules" section.

- [ ] **Step 3: Format and diff-check docs**

Run:

```bash
git diff -- docs/RUNTIME.md Sources/SwiftTUI/SwiftTUI.docc/Runtime.md
git diff --check
```

Expected:

- The docs explain the new owner/evaluation distinction.
- `git diff --check` reports no whitespace errors.

---

## Task 7: Full Verification

**Files:**

- No new edits unless verification exposes a failure.

- [ ] **Step 1: Format Swift files**

Run:

```bash
swift format format -i --configuration .swift-format.json \
  Sources/Core/Graph/ViewGraph.swift \
  Sources/View/Modifiers/ViewModifiers.swift \
  Tests/SwiftTUITests/LifecycleSelectiveEvaluationTests.swift \
  Tests/SwiftTUITests/PortalPrimitiveTests.swift
```

- [ ] **Step 2: Run targeted framework tests**

Run:

```bash
swiftly run swift test --filter SwiftTUITests.LifecycleSelectiveEvaluationTests
swiftly run swift test --filter SwiftTUITests.PortalPrimitiveTests
swiftly run swift test --filter SwiftTUITests.SwiftUISurfaceTests
swiftly run swift test --filter SwiftTUITests.DiagnosticsAndCacheTests
swiftly run swift test --filter SwiftTUITests.Phase4ObservationAndEnvironmentTests
```

- [ ] **Step 3: Run presentation and gifeditor coverage**

Run:

```bash
swiftly run swift test --filter SwiftTUITests.PresentationContinuityTests
swiftly run swift test --filter SwiftTUITests.PresentationSurfaceTests
swiftly run swift test --package-path Examples/gifeditor --filter GIFEditorUITests.PresentationRuntimeTests/helpSheetSpinnerAdvancesAndEditorRespondsAfterDismissal
```

- [ ] **Step 4: Run repo gate**

Run:

```bash
bun run test
```

Expected:

- Focused tests pass.
- Gifeditor presentation test passes.
- Repo gate passes.

---

## Review Checklist

- The implementation never changes the public lifecycle identity chosen by
  `TaskLifecycleModifier`, `AppearLifecycleModifier`, or
  `DisappearLifecycleModifier`.
- Dirty-frontier promotion happens before registration draft subtree removal so
  runtime registration cleanup uses the promoted owner frontier, not the child
  identity that would have dropped metadata.
- Stale owner mappings are cleared when an owner re-evaluates and when either
  the owner or target node is removed.
- Full-root fallback remains available when the owner mapping cannot produce a
  valid evaluator.
- The strengthened spinner test proves continuing animation across several task
  ticks.
- The replacement/removal tests prove real task cancellation still happens.
