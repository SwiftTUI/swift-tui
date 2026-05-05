---
title: "fix: make AnyView resilient across retained view-graph updates"
type: fix
status: planned
date: 2026-05-05
depends_on:
  - "../PUBLIC_SURFACE_POLICY.md"
  - "../RUNTIME.md"
  - "../STATE_KEYING.md"
  - "../decisions/0005-anyview-anyscene-as-escape-hatches.md"
  - "../proposals/TYPE_ERASURE_DEFERRAL_PLAN.md"
  - "2026-05-04-001-terminal-embedding-plan.md"
---

# Resilient AnyView Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for
> tracking. Keep commits scoped to stages that reach a green checkpoint. This
> plan touches shared view resolution/runtime behavior, so finish with
> `bun run test` before calling the work complete.

**Goal:** Make public `AnyView` behave like a real SwiftUI-shaped type-erased
view in the retained SwiftTUI graph: the same erased static view type preserves
state, lifecycle, focus, and action continuity under the same authored identity;
a changed erased static view type destroys the old hierarchy and creates a new
one.

**Architecture:** Front-load narrow infrastructure that makes type-erasure
behavior observable, then replace the current closure-forwarding `AnyView` with
a real wrapper node and a type-stamped payload subtree. The implementation must
reuse existing `ViewGraph` structural diff, subtree removal, lifecycle, task,
registration, dependency, and state machinery instead of inventing a parallel
erasure side table.

**Tech Stack:** Swift 6.3 strict concurrency + strict memory safety, Swift
Testing, `SwiftTUIViews.AnyView`, `SwiftTUIViews.ResolveContext`,
`SwiftTUICore.ViewGraph`, `DefaultRenderer`, `LocalActionRegistry`,
`LocalLifecycleRegistry`, `LocalTaskRegistry`, and the retained graph/state
contracts documented in `RUNTIME.md` and `STATE_KEYING.md`.

---

## Problem Frame

`AnyView` is currently an escape hatch, but it is not resilient enough to be a
framework primitive that later plug-in or heterogeneous host surfaces can lean
on.

Current behavior is centered around `Sources/SwiftTUIViews/Foundation/AnyView.swift`:

- `AnyView` stores a `resolveElementsClosure`.
- Plain `AnyView(view)` resolves non-`ResolvableView` content with
  `resolveViewElements(view, in: context)`.
- `scopedAnyView(...)` restores a captured `AuthoringContext`, but still
  ultimately forwards resolved elements rather than introducing an identity
  boundary for the erased payload.
- Because the erased content can be resolved as elements at the wrapper's
  context, custom view subtrees do not reliably get the same retained graph
  shape as ordinary typed children.

The expected public contract is narrower and sharper:

1. `AnyView` erases compile-time view type at API boundaries.
2. Erasure is not permission to flatten away authored identity.
3. Under the same `AnyView` identity, an unchanged erased static payload type
   should keep the same subtree identity.
4. When the erased static payload type changes, the old payload hierarchy should
   be structurally removed. State slots, tasks, disappear handlers, focus
   registrations, action registrations, and dependency records owned by that
   hierarchy should be torn down through the existing graph path.

Apple's public SwiftUI documentation describes `AnyView` as a type-erased view
whose underlying hierarchy is destroyed and recreated when the underlying view
type changes. SwiftTUI should match that shape at the behavior level without
expanding `AnyView` into a default container policy.

Reference: <https://developer.apple.com/documentation/swiftui/anyview>

This is independent of the terminal plug-in system. A typed plug-in registry can
ship without this work, but a resilient `AnyView` gives the framework the right
general-purpose erasure primitive before later plug-in surfaces need it.

## Non-Goals

- Do not implement the plug-in registry, plug-in loading, or out-of-process
  plug-in protocol here.
- Do not make `AnyView` the preferred storage type for public APIs.
- Do not add public APIs that expose `[AnyView]`, `[AnyScene]`,
  `() -> AnyView`, or node-erasure seams.
- Do not implement the broader `TYPE_ERASURE_DEFERRAL_PLAN.md` cleanup before
  this work. Keep the scope to making existing `AnyView` correct.
- Do not preserve state across a changed erased static payload type.
- Do not add a hidden side table that manually deletes state or lifecycle
  records. Subtree removal must happen through `ViewGraph`.
- Do not flatten the wrapper away in resolved graph tests just to keep old
  snapshots stable.
- Do not loosen the `AnyView policy:` comment requirement in
  `PUBLIC_SURFACE_POLICY.md`.

## Chosen Implementation Option

Use a real wrapper plus a type-stamped payload:

```text
AnyView identity
+-- AnyViewPayload<ErasedStaticType> identity
    +-- concrete content resolved through resolveView(...)
```

This gives the graph an ordinary structural difference when the erased static
payload type changes. The existing graph machinery then handles teardown:

- `ViewGraph.applySnapshot(...)` and structural child diffing see the payload
  identity change.
- The old payload subtree is removed.
- Runtime registrations under the old subtree are unregistered.
- `.task` cancellation and `.onDisappear` lifecycle events flow through the
  existing lifecycle path.
- State storage tied to removed identities is no longer reachable.
- Focus/action/key/pointer/drop registrations are repopulated from the new
  subtree.

The wrapper itself should be transparent to layout, drawing, and semantics
except for the identity boundary needed to make erasure observable.

### Rejected Options

- **Hidden graph nodes with a flat public resolved tree:** lower snapshot churn,
  but higher risk because the renderer and graph would disagree about which
  identities exist.
- **Type-change side table attached to current closure forwarding:** smaller
  initial patch, but incomplete for lifecycle, task, dependency, focus, and
  action cleanup.
- **Broad generic builder/type-erasure cleanup first:** useful later, but not
  necessary for this behavior and likely to increase blast radius before the
  contract is pinned.

## Success Criteria

- Same erased static payload type under the same `AnyView` identity preserves
  state across rerenders.
- Changed erased static payload type resets state by replacing the payload
  subtree.
- Changed erased static payload type emits task cancellation and disappear
  lifecycle events for removed descendants.
- Actions authored inside erased content still invalidate the owner that
  authored the action.
- Focusable descendants inside `AnyView` remain reachable after the wrapper and
  payload node are introduced.
- `scopedAnyView(...)` continues to preserve deferred authored context.
- `AnyView(ForEach(...))`, nested `AnyView`, and `AnyView(view.id(...))` have
  stable and documented identity behavior.
- `RegistrationAliasFindingsTests` still report no new non-trivial aliases for
  ordinary `AnyView` composition unless a test is intentionally updated with
  evidence.
- Public surface policy tests continue to block new public AnyView-shaped APIs.
- Full `bun run test` passes.

## Files

### Created

- `Sources/SwiftTUIViews/Foundation/ErasedViewTypeID.swift`
  - Package-private helper that derives the payload identity component and
    type discriminator from the erased static view type.
- `Tests/SwiftTUIViewsTests/ErasedViewTypeIDTests.swift`
  - Narrow tests for stable type identity strings and discriminator differences.
- `Tests/SwiftTUITests/AnyViewResilienceTests.swift`
  - Renderer-level behavior tests for state, lifecycle, tasks, focus, actions,
    nested erasure, explicit IDs, and `ForEach`.
- `Tests/SwiftTUITests/Support/AnyViewResilienceFixtures.swift`
  - Shared fixtures only if the resilience tests become too large to keep
    readable in one file.

### Modified

- `Sources/SwiftTUIViews/Foundation/AnyView.swift`
  - Replace closure-only forwarding with wrapper + payload resolution.
- `Sources/SwiftTUIViews/Foundation/ViewFoundation.swift`
  - Keep `scopedAnyView(...)` aligned with the new storage model.
- `Sources/SwiftTUI/SwiftTUI.swift`
  - Add package-only testing access to the renderer's retained view graph
    checkpoint or snapshot if the red tests need assertions beyond
    `resolvedTree` and `commitPlan`.
- `Tests/SwiftTUIViewsTests/ViewResolutionTests.swift`
  - Update shape-sensitive expectations for the new `AnyView` wrapper/payload
    graph.
- `Tests/SwiftTUITests/RegistrationAliasFindingsTests.swift`
  - Keep alias assertions current and preserve the intent of the AnyView cases.
- `docs/PUBLIC_SURFACE_POLICY.md`
  - After implementation, clarify that `AnyView` is type-aware and resilient
    while remaining an escape hatch.
- `docs/decisions/0005-anyview-anyscene-as-escape-hatches.md`
  - After implementation, record the refined runtime behavior.

## Core Invariants

- Public `AnyView` remains a `View` and `ResolvableView`.
- `AnyView` is a real retained graph identity.
- Payload identity includes an `ErasedViewTypeID` component derived from the
  erased static type.
- The concrete content is resolved through `resolveView(...)`, not directly via
  `resolveViewElements(...)`, so custom views receive normal retained
  `ViewNode` ownership.
- Captured authored context is restored while resolving the erased payload, so
  dynamic properties and action closures keep the owner they were authored
  under.
- Payload type changes are represented as ordinary structural child
  replacement, not manual cleanup.
- `AnyView` wrapper and payload nodes must not add visible layout spacing,
  semantic regions, draw commands, or raster output.
- The implementation must stay package-private except for the existing public
  `AnyView` initializer behavior.

## Staging

### Stage 0: Baseline Inventory

- [ ] Confirm the worktree is clean or record unrelated dirty files:

  ```bash
  git status --short
  ```

- [ ] Read the current implementation and policy anchors:

  ```bash
  sed -n '1,220p' Sources/SwiftTUIViews/Foundation/AnyView.swift
  sed -n '90,170p' Sources/SwiftTUIViews/Foundation/ViewFoundation.swift
  sed -n '1,180p' docs/PUBLIC_SURFACE_POLICY.md
  sed -n '1,180p' docs/decisions/0005-anyview-anyscene-as-escape-hatches.md
  sed -n '1,220p' docs/proposals/TYPE_ERASURE_DEFERRAL_PLAN.md
  ```

- [ ] Run the current focused baseline before adding red tests:

  ```bash
  swiftly run swift test --filter SwiftTUIViewsTests.ViewResolutionTests
  swiftly run swift test --filter SwiftTUITests.RegistrationAliasFindingsTests
  swiftly run swift test --filter SwiftTUITests.StatePersistenceTests
  swiftly run swift test --filter SwiftTUITests.LifecycleSelectiveEvaluationTests
  ```

Expected result: these pass before any behavior change. Any unrelated failure
should be captured in the implementation notes before proceeding.

### Stage 1: Add Targeted Infrastructure

This stage should be behavior-neutral.

- [ ] Create `Sources/SwiftTUIViews/Foundation/ErasedViewTypeID.swift`.

  Shape:

  ```swift
  package import SwiftTUICore

  package struct ErasedViewTypeID: Hashable, Sendable, CustomStringConvertible {
    package let identityComponent: IdentityComponent
    package let typeDiscriminator: ObjectIdentifier
    package let displayName: String

    package init<V: View>(_ type: V.Type) {
      let reflectedName = String(reflecting: type)
      displayName = reflectedName
      typeDiscriminator = ObjectIdentifier(type)
      identityComponent = .init(rawValue: "AnyViewPayload<\(reflectedName)>")
    }

    package var description: String {
      displayName
    }
  }
  ```

  If strict concurrency rejects `ObjectIdentifier` in a `Sendable` struct, make
  the sendability issue explicit instead of papering over it with
  `@unchecked Sendable`.

- [ ] Create `Tests/SwiftTUIViewsTests/ErasedViewTypeIDTests.swift`.

  Required assertions:

  - The same static type produces equal `ErasedViewTypeID` values.
  - Different static types produce different `identityComponent` values.
  - Different static types produce different `typeDiscriminator` values.
  - The display name is deterministic enough for readable test failures.

- [ ] Add a package-only renderer graph inspection hook only if the resilience
  tests need direct graph access beyond `resolvedTree` and `commitPlan`.

  Preferred minimal shape in `Sources/SwiftTUI/SwiftTUI.swift`:

  ```swift
  @MainActor
  package var debugViewGraphCheckpoint: ViewGraph.Checkpoint {
    viewGraph.makeCheckpoint()
  }
  ```

  Do not expose this publicly. Do not add a broader graph debugging API unless
  a specific test requires it.

- [ ] Add small test-only helpers in
  `Tests/SwiftTUITests/AnyViewResilienceTests.swift` or
  `Tests/SwiftTUITests/Support/AnyViewResilienceFixtures.swift`:

  - `descendantIdentities(matching:)`
  - `firstDescendant(withKind:)`
  - a boxed event recorder for lifecycle/task tests
  - fixtures that can render the same content as typed content, `Group`, and
    `AnyView`

- [ ] Verify infrastructure before behavior changes:

  ```bash
  swiftly run swift test --filter SwiftTUIViewsTests.ErasedViewTypeIDTests
  swiftly run swift test --filter SwiftTUITests.RegistrationAliasFindingsTests
  ```

### Stage 2: Add Red AnyView Resilience Tests

Add `Tests/SwiftTUITests/AnyViewResilienceTests.swift`. These tests should fail
against the current closure-forwarding implementation where the current
behavior is deficient.

- [ ] `sameErasedTypePreservesStateAcrossRerenders`

  Render `AnyView(AnyViewStateCounter(kind: .text))`, dispatch an increment
  action, rerender with the same erased static type, and assert the count
  remains incremented.

- [ ] `erasedTypeSwapDestroysOldStateAndStartsNewState`

  Render an erased stateful `Text`-backed fixture, mutate state through an
  action, then render an erased stateful `VStack`-backed fixture under the same
  `AnyView` identity. Assert the old state is absent and the new fixture starts
  from its initial state.

- [ ] `erasedTypeSwapCancelsTaskAndFiresDisappear`

  Render an erased fixture with `.task(id:)`, `.onAppear`, and `.onDisappear`.
  Swap to a different erased static type under the same `AnyView` identity.
  Assert the update commit plan contains `taskCancel` and `disappear` for the
  removed descendant identity.

- [ ] `actionInsideAnyViewInvalidatesOriginalOwner`

  Store erased content through `scopedAnyView(...)` in a deferred or captured
  path. Dispatch a `Button` action inside the erased subtree. Assert the
  original owner invalidates and the next render observes the mutation.

- [ ] `focusableDescendantInsideAnyViewRemainsReachable`

  Render focusable/button content inside `AnyView`. Assert a focus region exists
  for the descendant, dispatching the focused action works, and the action still
  works after a rerender with the same erased static type.

- [ ] `nestedAnyViewUsesEachErasedTypeBoundary`

  Render `AnyView(AnyView(StatefulLeaf()))`, mutate the leaf, rerender the same
  nested erased type, then swap only the inner erased type. Assert the outer
  wrapper remains stable while the inner payload subtree is replaced.

- [ ] `explicitIDInsideAnyViewDoesNotDefeatTypeSwapTeardown`

  Render `AnyView(StatefulLeaf().id("stable"))`, mutate it, then swap the erased
  static type while keeping the same explicit ID string inside the new payload.
  Assert type-swap teardown wins; the explicit ID must not keep incompatible
  state alive across different erased static payload types.

- [ ] `forEachInsideAnyViewKeepsElementIdentities`

  Render `AnyView(ForEach(items, id: \.self) { ... })`, mutate per-row state or
  dispatch row actions, reorder stable IDs, and assert row identity behavior is
  unchanged except for the new wrapper/payload ancestors.

- [ ] Run the red suite and record which tests fail before implementation:

  ```bash
  swiftly run swift test --filter SwiftTUITests.AnyViewResilienceTests
  ```

Expected result: at least the type-swap teardown and authored-context/action
tests fail on the current implementation. If every test passes, pause and add a
more precise graph/lifecycle assertion before changing production code.

### Stage 3: Implement Wrapper + Type-Stamped Payload

- [ ] Replace `AnyView`'s closure-only storage with typed payload storage in
  `Sources/SwiftTUIViews/Foundation/AnyView.swift`.

  Required storage behavior:

  ```swift
  private struct AnyViewStorage {
    let typeID: ErasedViewTypeID
    let authoringContext: AuthoringContext?
    let resolve: @MainActor (ResolveContext) -> ResolvedNode
  }
  ```

  The `resolve` closure must capture the static type `V` and call
  `resolveView(view, in: context)` inside the captured authored context when
  one exists.

- [ ] Introduce a package-private payload view in `AnyView.swift`.

  Shape:

  ```swift
  private struct AnyViewPayload: View, ResolvableView {
    let storage: AnyViewStorage

    var body: Never {
      fatalError("AnyViewPayload is resolved directly.")
    }

    func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
      [storage.resolve(context.child(component: .named("Content")))]
    }
  }
  ```

  Use a non-public component for the concrete content child if `.named("Content")`
  is too collision-prone for readable identity output. Keep it stable.

- [ ] Make `AnyView.resolveElements(in:)` return the wrapper node with one
  payload child.

  Required properties:

  - wrapper identity: `context.identity`
  - wrapper kind: `.view("AnyView")`
  - wrapper type discriminator: `ObjectIdentifier(AnyView.self)`
  - payload identity: `context.child(component: storage.typeID.identityComponent)`
  - payload kind: `.view("AnyViewPayload")`
  - payload type discriminator: `storage.typeID.typeDiscriminator`
  - payload child: concrete content resolved through `resolveView(...)`

- [ ] Preserve specialized package initializers:

  - `package init<V: View & ResolvableView>(resolving view: V)`
  - `package init<V: View>(scoped view: V, authoringContext: AuthoringContext?)`
  - `package init(erasing view: some ViewNode)`

  The `ViewNode` initializer may need its own storage path because it erases an
  already-node-shaped value. It still needs a stable payload type key.

- [ ] Ensure all paths that store authored content for later still use
  `scopedAnyView(...)`, not plain `AnyView(...)`.

  Search before and after:

  ```bash
  rg -n "AnyView\\(|scopedAnyView|\\[AnyView\\]|-> AnyView|\\(\\) -> AnyView" Sources Tests
  ```

- [ ] Run the red suite:

  ```bash
  swiftly run swift test --filter SwiftTUITests.AnyViewResilienceTests
  ```

Expected result: resilience tests should turn green or expose exact follow-up
shape changes in `ViewFoundation.swift`.

### Stage 4: Align Resolution, Alias, and Shape-Sensitive Tests

- [ ] Update `Tests/SwiftTUIViewsTests/ViewResolutionTests.swift` for the new
  wrapper/payload resolved tree.

  Expected shape for `Resolver().resolve(AnyView(Text("A")), in: rootContext)`:

  ```text
  Root: view(AnyView)
  +-- Root/AnyViewPayload<SwiftTUIViews.Text>: view(AnyViewPayload)
      +-- Root/AnyViewPayload<SwiftTUIViews.Text>/Content: view(Text)
  ```

  The exact reflected type name may include module-qualified generic detail.
  Assert stable behavior without overfitting to incidental generic spelling
  unless `ErasedViewTypeIDTests` deliberately pins that spelling.

- [ ] Update `Tests/SwiftTUITests/RegistrationAliasFindingsTests.swift`.

  The ordinary AnyView cases should still report zero non-trivial aliases. If a
  non-trivial alias appears, investigate whether wrapper/payload resolution is
  bypassing normal `resolveView(...)` before changing the expected count.

- [ ] Run related focused suites:

  ```bash
  swiftly run swift test --filter SwiftTUIViewsTests.ViewResolutionTests
  swiftly run swift test --filter SwiftTUITests.RegistrationAliasFindingsTests
  swiftly run swift test --filter SwiftTUITests.AnyViewResilienceTests
  ```

### Stage 5: Prove Runtime Interactions

Run focused suites that exercise the risk surface around retained graph
ownership, state slots, lifecycle events, actions, and focus.

- [ ] State and lifecycle:

  ```bash
  swiftly run swift test --filter SwiftTUITests.StatePersistenceTests
  swiftly run swift test --filter SwiftTUITests.LifecycleSelectiveEvaluationTests
  swiftly run swift test --filter SwiftTUITests.Phase4StateReliabilityTests
  ```

- [ ] Focus and command/action routing:

  ```bash
  swiftly run swift test --filter SwiftTUITests.FocusTransitionTests
  swiftly run swift test --filter SwiftTUITests.KeyCommandTests
  ```

- [ ] Core graph behavior:

  ```bash
  swiftly run swift test --filter SwiftTUICoreTests.ViewGraphTests
  swiftly run swift test --filter SwiftTUICoreTests.RegistrationAliasDiagnosticsTests
  ```

- [ ] If any failure shows a real wrapper/payload regression, fix production
  code rather than weakening the test. If a failure is only an intentional
  resolved-tree shape change, update the shape-sensitive assertion with a
  comment that names this plan.

### Stage 6: Documentation and Policy Update

- [ ] Update `docs/PUBLIC_SURFACE_POLICY.md`.

  Add a short note under the `AnyView` policy:

  - `AnyView` is type-aware and graph-resilient.
  - Same erased static payload type preserves the retained subtree.
  - Changed erased static payload type replaces the payload subtree.
  - The API remains an escape hatch; public collection/builder APIs should stay
    generic unless a policy exception is documented.

- [ ] Update
  `docs/decisions/0005-anyview-anyscene-as-escape-hatches.md`.

  Record the implementation decision: `AnyView` uses wrapper + type-stamped
  payload rather than hidden graph erasure or manual state cleanup.

- [ ] If implementation changes package or public API inventory output, refresh
  it with the repo script and commit the resulting baseline:

  ```bash
  ./Scripts/generate_public_api_inventory.sh
  ```

  This should not be necessary for a purely package-private helper and behavior
  change. Run it if the compiler forces a public/package surface adjustment.

### Stage 7: Full Validation

- [ ] Format Swift changes:

  ```bash
  swift format format -i --configuration .swift-format.json Sources/ Tests/
  ```

- [ ] Build:

  ```bash
  swiftly run swift build
  ```

- [ ] Run the root Swift test suite:

  ```bash
  swiftly run swift test
  ```

- [ ] Run the authoritative repo gate:

  ```bash
  bun run test
  ```

- [ ] Inspect the final diff:

  ```bash
  git diff --check
  git status --short
  ```

## Implementation Notes

### Authoring Context

The subtle requirement is not just state preservation. Controls and dynamic
properties may capture the authored owner at construction time. The new
`AnyView` storage must restore the captured `AuthoringContext` while resolving
the erased payload so that actions inside stored erased content still invalidate
the owner that authored them.

This is why the implementation should not simply call `resolveView(payload, in:
context)` under the ambient parent context and call it done. It must keep the
captured context restoration currently provided by `scopedAnyView(...)`.

### Payload Type Identity

`ErasedViewTypeID` should be derived from the erased static type `V`, not from a
runtime value inspection. This lets `if condition { AnyView(Text(...)) } else {
AnyView(VStack { ... }) }` become a structural payload replacement while
`AnyView(Text(dynamicString))` remains the same payload type and preserves
stateful descendants under that payload.

### Explicit IDs

Explicit `.id(...)` inside the erased payload should continue to work within the
payload subtree. It must not bridge incompatible erased static payload types.
The payload type component sits above any inner explicit ID, so type changes
replace the subtree first.

### ForEach

`AnyView(ForEach(...))` should add wrapper/payload ancestors but should not
change element-level stable ID behavior. Existing `ForEach` identity rules
continue inside the payload content child.

### Testing Strategy

Prefer renderer-level tests over resolver-only tests for behavior. Resolver
tests are useful for pinning the new graph shape, but the real proof is in:

- action dispatch through `LocalActionRegistry`
- lifecycle/task commit entries
- semantic focus regions
- state persistence across repeated `DefaultRenderer.render(...)` calls
- retained graph snapshots only when the above artifacts are insufficient

## Risk Assessment

Expected chance of success is high if the infrastructure stages land first:
roughly 75-85%. The core graph already has the hard primitives needed for this:
structural child diffing, subtree removal, checkpoint/restore, lifecycle event
generation, dependency indexing, and registration cleanup.

The main risks are:

- **Authoring-context regression:** actions or dynamic properties inside stored
  erased content invalidate the wrong owner. Mitigation: red action test before
  production changes.
- **Shape-sensitive test churn:** introducing wrapper/payload nodes changes
  resolver snapshots. Mitigation: update only tests that assert resolved graph
  shape; do not hide the new identity boundary.
- **Alias diagnostics regression:** wrapper resolution might accidentally create
  non-trivial aliases. Mitigation: keep the AnyView alias tests focused and
  investigate any count increase before accepting it.
- **Over-preserving state:** explicit IDs inside different erased static types
  could keep incompatible state alive if the payload type component is placed
  too low. Mitigation: explicit-ID type-swap test.
- **Under-preserving state:** if the payload type ID is unstable across renders,
  same-type `AnyView` will reset state. Mitigation: `ErasedViewTypeIDTests` and
  same-type state test.

## Commit Checkpoints

Recommended commit boundaries:

1. `test: add AnyView type-erasure inspection infrastructure`
2. `test: characterize resilient AnyView behavior`
3. `fix: resolve AnyView through type-stamped payload subtrees`
4. `test: align AnyView graph shape and alias expectations`
5. `docs: record resilient AnyView policy`

Do not combine the red characterization tests and the implementation in a
single commit unless the branch workflow explicitly requires it. The red tests
are the proof that the implementation is fixing the intended framework seam.
