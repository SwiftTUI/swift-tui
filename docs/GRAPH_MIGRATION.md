# Migration: Persistent Attribute Graph

This document plans a staged migration from the current invalidation-driven,
tree-rebuilding resolve model to a persistent attribute graph with per-node
structural diffing, ordinal state keying, and lifecycle-as-structure.

**Context:** Pre-production framework with no external consumers. Fully
breaking changes are acceptable. The goal is SwiftUI-equivalent semantics.

**Status (2026-04-02):** Ordinal state slots, graph-owned lifecycle events,
and the retained-resolve cleanup described below have landed. The migration
is not yet complete. The largest remaining gap is still the full
graph-driven dirty-node reevaluation switchover: `DefaultRenderer` still
performs a full resolve pass each frame, and `ViewGraph.evaluateDirtyNodes()`
is not yet the authoritative update path. Two additional live runtime
blockers remain under that umbrella: the interactive/runtime path still
threads `DynamicStateStore` as the authoritative `@State`/`@FocusState`
storage, and deferred builders/actions still depend on `DynamicPropertyScope`
as the authored read context.

### Remaining blockers (2026-04-02)

1. **Graph-authoritative update path**
   `ViewGraph` is still a persistence/lifecycle sidecar. The renderer does
   not yet update the graph as the source of truth and snapshot from that
   updated graph.
2. **Graph-only runtime state/focus/default-focus**
   The live runtime still injects `DynamicStateStore` into `ResolveContext`,
   so body-time `@State`, `@FocusState`, and `defaultFocus` behavior are not
   yet graph-only.
3. **Authoring-context replacement for deferred closures/builders**
   `DynamicPropertyScope` still carries more than slot access. Stored
   builders, deferred actions, and focused-value reads still depend on it,
   so `ViewNodeContext` alone is not yet a sufficient replacement.

---

## Current architecture (what we're replacing)

Each frame runs the full pipeline:

```
resolve → measure → place → semantics → draw → raster → commit
```

**Resolve** rebuilds a `ResolvedNode` tree from scratch. Subtree reuse is an
optimization: `ResolveReuseSession` checks whether an identity is in the
invalidation set and, if not, returns the previous subtree with handler
registrations replayed. Eleven registries (actions, key handlers, pointer
handlers, focus bindings, focused values, preference observations, hotkeys,
lifecycle handlers, task registrations, state store, observation bridge) are
reset at the start of each frame and repopulated during resolution.

**State** is keyed by `"{viewIdentity.path}#State[{fileID}:{line}:{column}]"`.
`DynamicPropertyScope` is set via task-local storage during body evaluation.
`@State` reads and writes go through `DynamicStateStore`, which triggers
`requestInvalidation(of:)` on the `FrameScheduler`.

**Lifecycle** is inferred after the fact: `CommitPlanner.lifecycleDiff()`
compares identity dictionaries between the previous and current
`CommittedLifecycleState`. Appear/disappear/task operations are emitted as a
`CommitPlan`.

**Downstream phases** (measure through raster) consume the `ResolvedNode`
tree and produce `MeasuredNode → PlacedNode → SemanticSnapshot → DrawNode →
RasterSurface`. These phases have their own caching (`MeasurementCache`,
`RetainedLayoutSession`) but are otherwise stateless transforms.

---

## Target architecture (what we're building)

A persistent `ViewGraph` that survives between state mutations. The graph is
the source of truth for the view hierarchy.

```
[event] → graph update → snapshot → measure → place → semantics → draw → raster
```

**Graph update** replaces resolve + commit:
1. Invalidated nodes re-evaluate their `body`.
2. New body output is structurally diffed against the node's current children.
3. Matched children (same type + identity) are updated in-place.
4. Unmatched old children are destroyed: handlers removed, disappear fired,
   tasks cancelled.
5. Unmatched new children are created: handlers installed, appear fired,
   tasks started.

**State** is keyed by `(node_identity, slot_ordinal)`. Each node maintains a
fixed-size slot array. Slots are allocated during the first body evaluation
and reused on subsequent evaluations.

**Lifecycle** is structural: `onAppear` fires when a node is inserted into
the graph. `onDisappear` fires when a node is removed. No separate diff pass.

**Dependency tracking:** Each node records which state slots and environment
values its body read. On mutation, only nodes with edges to the mutated
dependency re-evaluate.

**Snapshot bridge:** After graph update, the graph produces a `ResolvedNode`
tree for consumption by the existing downstream phases. This is the
compatibility layer that lets measure/place/semantics/draw/raster work
unchanged during migration.

---

## Principles

1. **Downstream phases do not change during migration.** Measure through
   raster continue to consume `ResolvedNode` trees. The snapshot bridge
   insulates them.

2. **Tests run at every milestone.** Each milestone has a "green gate" — the
   full test suite passes before proceeding.

3. **No Foundation.** The codebase currently has zero Foundation imports in
   source files. This must remain true.

4. **Terminal-first, cross-platform-last.** Intermediate milestones test on
   macOS terminal only. The final milestone validates all platforms.

5. **Delete aggressively.** Once a milestone is green, dead code from the
   previous model is removed in that milestone's cleanup step. No
   deprecation shims.

---

## Milestone 0: Regression baseline

**Goal:** Capture current pipeline behavior as tests. These tests survive the
entire migration and are the safety net.

### Deliverables

**0.1 — Pipeline snapshot tests**

Create `Tests/CoreTests/PipelineRegressionTests.swift`. For each of the
following view configurations, run the full pipeline and snapshot the output
at each phase boundary:

- Single `Text` node
- `VStack` with three children
- `ForEach` with explicit IDs
- Conditional branch (`if/else` with `@State` toggle)
- Nested `ScrollView` with `LazyVStack`
- `NavigationSplitView` with sidebar + detail
- `Button` with action handler
- `TextField` with `@Binding`
- `onAppear` + `onDisappear` + `.task` lifecycle
- `onKeyPress` handler registration
- `.environment()` modifier propagation
- `.preference(key:value:)` upward flow

For each, assert:
- `ResolvedNode` structure (identity paths, child counts, metadata)
- `CommitPlan` lifecycle operations (appear/disappear/task entries)
- `SemanticSnapshot` interaction and focus regions
- Handler registration counts in each registry

**0.2 — Lifecycle sequence tests**

Create `Tests/CoreTests/LifecycleSequenceTests.swift`. Test explicit
lifecycle ordering:

- Insert → appear fires before task starts
- Remove → task cancels before disappear fires
- Branch flip → old branch disappears, new branch appears
- `ForEach` reorder with stable IDs → no lifecycle transitions
- `ForEach` element removal → disappear for removed identity only
- `.task(id:)` descriptor change → old task cancels, new task starts

**0.3 — State persistence tests**

Create `Tests/ViewTests/StatePersistenceTests.swift`. Test state keying
behavior that will change during migration (source-location → ordinal):

- Two `@State` properties in one view maintain independent values
- State survives body re-evaluation when identity is stable
- State resets when identity changes (conditional branch flip)
- `@FocusState` persistence follows same rules
- `@Binding` reads track through to source `@State`

Mark these tests with a `// MIGRATION: keying behavior changes` comment so
they can be updated at Milestone 4.

### Green gate

All existing tests pass. All new tests pass. No source changes outside
`Tests/`.

---

## Milestone 1: Graph data structure

**Goal:** Implement the persistent graph in isolation. No integration with
the existing pipeline. Fully tested on its own.

### Deliverables

**1.1 — `ViewGraph` and `ViewNode`**

Create `Sources/Core/Graph/ViewGraph.swift`:

```swift
@MainActor
package final class ViewGraph {
    private(set) var root: ViewNode?
    private var nodesByIdentity: [Identity: ViewNode]

    package func updateRoot<V: View>(_ view: V, environment: EnvironmentSnapshot)
    package func invalidate(_ identities: Set<Identity>)
    package func evaluateDirtyNodes()
}
```

Create `Sources/Core/Graph/ViewNode.swift`:

```swift
@MainActor
package final class ViewNode {
    let identity: Identity
    private(set) var children: [ViewNode]
    private(set) var stateSlots: [AnyStateSlot]
    private(set) var dependencies: DependencySet
    private(set) var lifecycleState: NodeLifecycleState
    private(set) var registeredHandlers: NodeHandlers

    // Metadata for downstream phases
    var environmentSnapshot: EnvironmentSnapshot
    var layoutBehavior: LayoutBehavior
    var layoutMetadata: LayoutMetadata
    var drawMetadata: DrawMetadata
    var semanticMetadata: SemanticMetadata
    var drawPayload: DrawPayload

    var isDirty: Bool
}
```

**1.2 — State slots (ordinal keying)**

Create `Sources/Core/Graph/StateSlot.swift`:

```swift
package struct AnyStateSlot {
    private var storage: Any
    private let equals: (Any, Any) -> Bool

    package func value<T>(as type: T.Type) -> T
    package mutating func set<T>(_ value: T) -> Bool  // returns true if changed
}
```

Slot allocation contract:
- First evaluation: slots are appended in order as `@State` properties are
  accessed. The ordinal is the append index.
- Subsequent evaluations: slots are accessed by ordinal. The count must
  match. A count mismatch is a fatal error (same as SwiftUI).

**1.3 — Dependency tracking**

Create `Sources/Core/Graph/DependencySet.swift`:

```swift
package struct DependencySet: Equatable, Sendable {
    var stateSlotReads: Set<StateSlotKey>     // (nodeIdentity, slotOrdinal)
    var environmentReads: Set<ObjectIdentifier>  // EnvironmentKey metatypes
    var observableReads: Set<ObjectIdentifier>   // Observable object identities
}
```

Create `Sources/Core/Graph/DependencyTracker.swift`:

```swift
@MainActor
package final class DependencyTracker {
    private(set) var currentDependencies = DependencySet()

    package func recordStateRead(_ key: StateSlotKey)
    package func recordEnvironmentRead(_ key: ObjectIdentifier)
    package func recordObservableRead(_ id: ObjectIdentifier)
    package func reset() -> DependencySet
}
```

The tracker is set as task-local storage during body evaluation (same
pattern as `DynamicPropertyScopeStorage.current`). After evaluation, the
recorded set replaces the node's `dependencies`.

**1.4 — Structural diff algorithm**

Create `Sources/Core/Graph/StructuralDiff.swift`:

```swift
package enum ChildDiffOp {
    case matched(oldIndex: Int, newIndex: Int)
    case inserted(newIndex: Int)
    case removed(oldIndex: Int)
}

package func diffChildren(
    old: [ChildDescriptor],
    new: [ChildDescriptor]
) -> [ChildDiffOp]
```

`ChildDescriptor` carries the view's type identity (metatype) and explicit
ID if present. The diff algorithm:

1. Build a map of `(typeIdentity, explicitID?) → oldIndex` from old children.
2. Walk new children. For each, look up a match in the map.
3. Matched: emit `.matched`. Remove from map.
4. Unmatched: emit `.inserted`.
5. Remaining map entries: emit `.removed`.

This is O(n) — no longest-common-subsequence needed because identity
matching is exact, not positional.

**1.5 — Lifecycle operations**

Lifecycle is a direct consequence of diff ops:

- `.inserted` → create `ViewNode`, set `lifecycleState = .appeared`,
  fire `onAppear` handlers, start `.task` if present.
- `.removed` → cancel `.task` if running, fire `onDisappear` handlers,
  deallocate `ViewNode` and its subtree.
- `.matched` → no lifecycle transition. Update metadata, re-evaluate body
  if dirty.

Create `Sources/Core/Graph/NodeLifecycle.swift`:

```swift
package enum NodeLifecycleState: Equatable, Sendable {
    case appearing   // onAppear pending
    case alive       // stable
    case disappearing // onDisappear pending
}

package struct LifecycleEvent: Equatable, Sendable {
    var identity: Identity
    var operation: LifecycleOperation
}

package enum LifecycleOperation: Equatable, Sendable {
    case appear(handlerIDs: [String])
    case disappear(handlerIDs: [String])
    case taskStart(TaskDescriptor)
    case taskCancel(TaskDescriptor)
}
```

**1.6 — Graph-level tests**

Create `Tests/CoreTests/Graph/`:

- `ViewGraphTests.swift` — insert root, update root, verify node structure
- `StateSlotTests.swift` — ordinal allocation, value persistence, mutation
  detection
- `DependencyTrackingTests.swift` — record reads, verify dependency set
- `StructuralDiffTests.swift` — matched/inserted/removed for various child
  configurations (reorder, type change, ID change, count change)
- `NodeLifecycleTests.swift` — appear on insert, disappear on remove, no
  transition on match, task start/cancel ordering

### Files created

```
Sources/Core/Graph/
  ViewGraph.swift
  ViewNode.swift
  StateSlot.swift
  DependencySet.swift
  DependencyTracker.swift
  StructuralDiff.swift
  NodeLifecycle.swift
  NodeHandlers.swift
  ChildDescriptor.swift

Tests/CoreTests/Graph/
  ViewGraphTests.swift
  StateSlotTests.swift
  DependencyTrackingTests.swift
  StructuralDiffTests.swift
  NodeLifecycleTests.swift
```

### Green gate

All Milestone 0 tests still pass (no existing code changed). All new graph
tests pass.

---

## Milestone 2: Snapshot bridge

**Goal:** The graph can produce a `ResolvedNode` tree that is structurally
equivalent to what the current resolve phase produces. This proves the graph
is correct before we wire it into the pipeline.

### Deliverables

**2.1 — `ViewGraph.snapshot() → ResolvedNode`**

Add to `ViewGraph`:

```swift
package func snapshot() -> ResolvedNode {
    guard let root else { fatalError("graph has no root") }
    return root.toResolvedNode()
}
```

`ViewNode.toResolvedNode()` recursively constructs `ResolvedNode` from the
graph's current state:

- `identity` → node's identity
- `children` → `children.map { $0.toResolvedNode() }`
- `environmentSnapshot` → node's environment
- `layoutBehavior`, `layoutMetadata`, `drawMetadata`, `semanticMetadata`,
  `drawPayload` → copied from node
- `lifecycleMetadata` → derived from node's registered lifecycle handlers
- `supportsRetainedReuse` → always `true` (graph handles its own reuse)

**2.2 — Snapshot equivalence tests**

Create `Tests/CoreTests/Graph/SnapshotBridgeTests.swift`. For each view
configuration from Milestone 0.1, render through both paths:

1. Current resolve path: `Resolver().resolve(view, in: context)`
2. Graph path: build graph, evaluate, `graph.snapshot()`

Assert structural equivalence:
- Same identity paths
- Same child counts at each level
- Same `layoutBehavior`, `drawPayload` values
- Same `lifecycleMetadata` handler ID counts

Lifecycle handler closures and action closures cannot be compared for
equality — assert only that the correct number exist at each identity.

**2.3 — Lifecycle event equivalence tests**

For each lifecycle scenario from Milestone 0.2, run through both paths.
Assert the same lifecycle operations are produced in the same order.

### Green gate

All previous tests pass. Snapshot bridge tests demonstrate structural
equivalence with the current resolve output for all test configurations.

---

## Milestone 3: Pipeline integration

**Goal:** Replace the resolve phase with graph-update-then-snapshot. The rest
of the pipeline is unchanged. This is the critical switchover.

### Deliverables

**3.1 — Wire graph into `DefaultRenderer`**

In `Sources/TerminalUI/TerminalUI.swift`, replace the resolve call:

Before:
```swift
let resolved = resolver.resolve(root, in: resolveContext)
```

After:
```swift
viewGraph.update(root, environment: resolveContext.environment,
                 invalidatedIdentities: scheduledFrame.invalidatedIdentities)
viewGraph.evaluateDirtyNodes()
let resolved = viewGraph.snapshot()
```

The `viewGraph` is a new stored property on `DefaultRenderer`, initialized
once and persistent across frames.

**3.2 — Move registries to graph nodes**

Currently, 11 registries are reset each frame and repopulated during resolve.
In the graph model, handlers persist on their owning `ViewNode`:

- `NodeHandlers` on each `ViewNode` stores: action handlers, key handlers,
  pointer handlers, hotkey bindings, lifecycle handlers, task registrations.
- During body evaluation, handlers are registered on the current node (not
  in a frame-global registry).
- When a node is destroyed, its handlers are removed.
- When a node is re-evaluated, its handlers are replaced (old cleared, new
  installed).

The frame-global registries (`LocalActionRegistry`, `HotkeyRegistry`, etc.)
become **read-only views** that aggregate handlers from the graph. They are
rebuilt (not repopulated) from the graph after update:

```swift
viewGraph.evaluateDirtyNodes()
localActionRegistry.rebuild(from: viewGraph)
hotkeyRegistry.rebuild(from: viewGraph)
// ... etc
```

This preserves the downstream contract: the rest of the pipeline reads from
the same registry types.

**3.3 — Remove `ResolveReuseSession` and `RetainedResolveFrame`**

These types exist to optimize the tree-rebuild model. The graph replaces
them entirely:

- Delete `ResolveReuseSession` (in `Environment.swift`, lines 400-619)
- Delete `RetainedResolveFrame` (in `CommitAndFrameTypes.swift`)
- Delete `RetainedFrameStore.resolveSession()` and related methods
- Remove the `resolveReuseSession` field from `ResolveContext`
- Remove handler replay logic

**3.4 — Replace `CommitPlanner.lifecycleDiff()`**

Lifecycle events are now produced during graph update (Milestone 1.5), not
after the fact. The commit planner no longer needs to diff lifecycle state:

- Remove `lifecycleDiff()` from `CommitPlanner`
- Remove `CommittedLifecycleState` (the graph is the lifecycle state)
- `CommitPlan.lifecycle` is populated directly from graph update events
- `CommitPlan.nextLifecycleState` is removed (the graph persists it)

**3.5 — Update `RunLoop+Rendering.swift`**

The frame loop simplifies:

Before:
```
1. Reset all registries
2. Build ResolveContext with registries + invalidation set
3. Resolve (rebuild tree)
4. Store retained frame
5. Measure → place → semantics → draw → raster
6. Commit plan (lifecycle diff)
7. Apply commit plan
```

After:
```
1. Graph update (evaluate dirty nodes, structural diff, lifecycle events)
2. Rebuild registry aggregates from graph
3. Snapshot graph → ResolvedNode
4. Measure → place → semantics → draw → raster
5. Apply lifecycle events
```

**3.6 — Update `ObservationBridge` integration**

The bridge currently uses generation-based tracking with identity-scoped
invalidation. In the graph model, observable tracking attaches to the node's
dependency set:

- During body evaluation, `withObservationTracking` records which observable
  properties were read.
- These are stored in the node's `dependencies.observableReads`.
- On change, the node is marked dirty (not the identity in a global set).

The `ObservationBridge` type can be simplified or removed. Its pruning logic
(`prune(keeping:)`) is replaced by graph node destruction.

### Files modified

```
Sources/TerminalUI/TerminalUI.swift          — graph wiring, remove old resolve
Sources/TerminalUI/RunLoop+Rendering.swift   — simplified frame loop
Sources/View/Environment/Environment.swift   — remove ResolveReuseSession
Sources/Core/CommitAndFrameTypes.swift       — remove RetainedResolveFrame,
                                               CommittedLifecycleState
Sources/Core/CommitPlanner.swift             — remove lifecycleDiff
Sources/View/Foundation/ViewFoundation.swift — Resolver becomes thin wrapper
                                               or is removed
Sources/View/Environment/Observation.swift   — simplify or remove bridge
```

### Files deleted

```
(No files deleted — code is removed from existing files)
```

### Green gate

All Milestone 0 regression tests pass (they test pipeline output, not
internals). Lifecycle sequence tests pass. State persistence tests pass
(source-location keying is still active — that changes in Milestone 4).

---

## Milestone 4: State keying migration

**Goal:** Switch from source-location keying to ordinal keying. This is the
semantic change.

### Deliverables

**4.1 — Update `@State` property wrapper**

In `Sources/View/State/State.swift`:

Remove source-location capture:
```swift
// REMOVE
public init(
    wrappedValue: Value,
    fileID: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column
) {
    box = StateBox(seedValue: wrappedValue,
                   sourceLocation: "\(fileID):\(line):\(column)")
}
```

Replace with ordinal-based access:
```swift
public init(wrappedValue: Value) {
    box = StateBox(seedValue: wrappedValue)
}
```

The `wrappedValue` getter/setter no longer builds a source-location key.
Instead, it accesses the current node's next state slot ordinal via
task-local storage:

```swift
public var wrappedValue: Value {
    get {
        guard let node = ViewNodeContext.current else {
            return box.seedValue
        }
        return node.stateSlot(ordinal: box.ordinal, seed: box.seedValue)
    }
    nonmutating set {
        guard let node = ViewNodeContext.current else {
            box.seedValue = newValue
            return
        }
        node.setStateSlot(ordinal: box.ordinal, value: newValue)
    }
}
```

**4.2 — Update `@FocusState` property wrapper**

Same pattern as `@State`. Remove source-location capture. Use ordinal slots.
`@FocusState` slots are interleaved with `@State` slots in the same ordinal
sequence (matching SwiftUI's behavior).

**4.3 — Remove `DynamicStateStore` and `DynamicPropertyScope`**

These types exist to support the source-location-keyed dictionary model:

- `DynamicStateStore` (dictionary of `String → DynamicStateEntry`) is
  replaced by the node's `stateSlots: [AnyStateSlot]` array.
- `DynamicPropertyScope` is replaced by `ViewNodeContext` (task-local
  reference to the current `ViewNode`).
- `DynamicPropertyScopeStorage` is replaced by `ViewNodeContext.current`.

**4.4 — Update state persistence tests**

The tests marked `// MIGRATION: keying behavior changes` in Milestone 0.3
are updated to reflect ordinal semantics:

- Two `@State` properties are distinguished by ordinal, not source location.
- Reordering declarations in source swaps values (ordinal semantics).
- Moving a declaration to a different line has no effect (ordinal semantics).

**4.5 — Remove `StateBox.sourceLocation`**

Delete the `sourceLocation` stored property and all code paths that
reference it. Delete `DynamicPropertyScope.stateKey(for:)`.

### Files modified

```
Sources/View/State/State.swift          — ordinal access, remove source location
Sources/View/State/FocusState.swift     — ordinal access, remove source location
Sources/View/Foundation/ViewFoundation.swift — remove DynamicPropertyScope wiring
```

### Files deleted or gutted

```
DynamicStateStore   — removed (replaced by node slot arrays)
DynamicPropertyScope — removed (replaced by ViewNodeContext)
```

### Green gate

All regression tests pass. Updated state persistence tests pass with ordinal
semantics.

---

## Milestone 5: Dead code removal and cleanup

**Goal:** Remove all vestiges of the tree-rebuild model. The codebase should
read as if the graph model was always the design.

### Deliverables

**5.1 — Remove orphaned types**

Audit and remove:
- `ResolveReuseSession` (if not already removed in M3)
- `RetainedResolveFrame` (if not already removed in M3)
- `RetainedFrameStore.resolveSession()`
- `CommittedLifecycleState`
- `CommitPlanner.lifecycleDiff()`
- `ResolveContext.resolveReuseSession`
- `ResolvedNode.supportsRetainedReuse` (graph handles reuse)
- `ResolveWorkMetrics` (replaced by graph metrics)
- `DynamicStateEntry`, `DynamicStateEntryBox`
- `StateBox.sourceLocation`
- Any `resolvedTreeIndex` used only for reuse lookups

**5.2 — Simplify `ResolveContext`**

`ResolveContext` currently carries 11 registries, a reuse session, and an
invalidation set. In the graph model, most of this is unnecessary — the graph
node is the context. Reduce `ResolveContext` to:

```swift
package struct ResolveContext {
    var identity: Identity
    var environment: EnvironmentSnapshot
    var transaction: TransactionSnapshot
}
```

Registry access goes through the `ViewNode`, not the context.

**5.3 — Simplify `CommitPlan`**

Remove `nextLifecycleState` (the graph is the state). Remove lifecycle
diffing artifacts. The plan becomes:

```swift
public struct CommitPlan {
    var transaction: TransactionSnapshot
    var semanticSnapshot: SemanticSnapshot
    var lifecycleEvents: [LifecycleEvent]  // from graph update
    var handlerInstallations: [HandlerInstallation]
}
```

**5.4 — Audit `@unchecked Sendable`**

The architecture audit documented 52 `@unchecked Sendable` sites. The graph
migration changes many of them. Audit each:
- Graph types are `@MainActor` — they don't need `Sendable`.
- Snapshot types flowing to downstream phases remain `Sendable`.
- Remove `@unchecked Sendable` from any type that no longer crosses
  isolation boundaries.

**5.5 — Update documentation**

- `docs/ARCHITECTURE.md` — document the graph model, updated pipeline
- `docs/RUNTIME.md` — update lifecycle semantics, state keying, incremental
  cost model
- `docs/STATE_KEYING.md` — note that TerminalUI now uses ordinal keying
- Remove references to `ResolveReuseSession`, `RetainedResolveFrame`,
  source-location keying throughout docs

### Green gate

All tests pass. No dead code. `grep` for removed type names returns zero
hits outside of git history and docs changelog.

---

## Milestone 6: Optimization

**Goal:** Improve graph performance now that correctness is established.

### Deliverables

**6.1 — Layout cache integration**

`MeasurementCache` and `RetainedLayoutSession` currently key by identity.
The graph provides a more direct signal: a node's "layout-relevant hash"
(layout behavior + metadata + child structure). Cache entries can be
invalidated precisely when this hash changes, rather than conservatively by
identity set membership.

**6.2 — Incremental snapshot**

The snapshot bridge (`ViewGraph.snapshot()`) currently rebuilds the full
`ResolvedNode` tree. Optimize to rebuild only the subtree rooted at dirty
nodes. Clean subtrees return a cached `ResolvedNode`.

**6.3 — Skip re-evaluation for environment-only changes**

The current model conservatively re-resolves when the environment changes.
With dependency tracking, the graph knows exactly which nodes read which
environment keys. Environment changes only dirty nodes that read the changed
key.

**6.4 — Benchmark suite**

Create `Tests/CoreTests/Graph/GraphBenchmarks.swift`:

- 100-node tree, single leaf state change → measure graph update time
- 1000-node tree, root environment change → measure selective re-evaluation
- Idle frame (no changes) → verify zero graph work
- ForEach with 100 elements, one element removed → measure structural diff

### Green gate

All tests pass. Benchmarks establish baseline numbers. No performance
regressions in existing tests.

---

## Milestone 7: Cross-platform validation

**Goal:** Validate the migration on all supported platforms.

### Deliverables

**7.1 — macOS terminal**

Full test suite. Interactive smoke test with the example apps.

**7.2 — Linux**

Full test suite on Ubuntu (the CI configuration). Verify no Darwin-specific
code leaked into `Sources/Core/Graph/`.

**7.3 — WASI (WebAssembly)**

Build and run the WebExample. Verify the graph types compile under
`swift-wasm` toolchain. Verify `ViewNode` and `ViewGraph` do not use
`PlatformLock` or other platform-conditional types (they shouldn't — they're
`@MainActor`).

**7.4 — iOS**

Build the HostedSceneSession path. Verify `TerminalUIScenes` compiles and
the graph integrates with the SwiftUI host wrapper.

**7.5 — Android**

Cross-compile and run the test suite. Verify no regressions.

**7.6 — Foundation audit**

```bash
grep -r 'import Foundation' Sources/
```

Must return zero results.

### Green gate

Full test suite passes on all five platforms. No Foundation imports. The
WebExample runs in the browser. Interactive terminal apps work on macOS and
Linux.

---

## Milestone summary

| # | Name | Scope | Risk |
|---|------|-------|------|
| 0 | Regression baseline | Tests only | None |
| 1 | Graph data structure | New code in Core/Graph/ | Low (isolated) |
| 2 | Snapshot bridge | New code + tests | Low (no pipeline changes) |
| 3 | Pipeline integration | **Critical switchover** | **High** |
| 4 | State keying migration | Semantic change | Medium |
| 5 | Dead code removal | Cleanup | Low |
| 6 | Optimization | Performance | Low |
| 7 | Cross-platform validation | Testing | Low |

Milestones 0–2 are additive — no existing code changes. The risk is
concentrated in Milestone 3, where the resolve phase is replaced. The
regression baseline from Milestone 0 is the safety net.

---

## Types created (complete list)

```
Sources/Core/Graph/
  ViewGraph.swift           — persistent graph, root management, dirty evaluation
  ViewNode.swift            — per-node state: slots, deps, handlers, children, metadata
  ViewNodeContext.swift     — task-local storage for current node during body eval
  StateSlot.swift           — type-erased ordinal state slot
  DependencySet.swift       — recorded reads (state, environment, observable)
  DependencyTracker.swift   — recording context set during body evaluation
  StructuralDiff.swift      — O(n) child diff by type + identity
  ChildDescriptor.swift     — (metatype, explicitID?) pair for diff input
  NodeLifecycle.swift       — lifecycle state enum and event types
  NodeHandlers.swift        — per-node handler storage (actions, keys, etc.)
```

## Types removed (complete list)

```
ResolveReuseSession         — graph handles reuse
RetainedResolveFrame        — graph is the retained state
RetainedFrameStore (partial)— resolveSession() and related methods
CommittedLifecycleState     — graph is the lifecycle state
DynamicStateStore           — replaced by node slot arrays
DynamicStateEntry           — replaced by AnyStateSlot
DynamicStateEntryBox        — replaced by AnyStateSlot
DynamicPropertyScope        — replaced by ViewNodeContext
DynamicPropertyScopeStorage — replaced by ViewNodeContext
StateBox.sourceLocation     — ordinal keying, no source location
ResolveWorkMetrics          — replaced by graph update metrics
```

## Types modified (significant changes)

```
ResolveContext              — reduced to identity + environment + transaction
CommitPlan                  — remove nextLifecycleState, lifecycle from graph
CommitPlanner               — remove lifecycleDiff, receive events from graph
@State                      — ordinal access, remove source-location init params
@FocusState                 — ordinal access, remove source-location init params
@Binding                    — unchanged (pass-through, no keying)
ObservationBridge           — simplified or removed, tracking moves to graph
DefaultRenderer             — owns ViewGraph, snapshot bridge
RunLoop+Rendering           — simplified frame loop
FrameScheduler              — unchanged (still coalesces invalidations)
LayoutEngine                — unchanged (consumes ResolvedNode via snapshot)
SemanticExtractor           — unchanged
DrawExtractor               — unchanged
Rasterizer                  — unchanged
```
