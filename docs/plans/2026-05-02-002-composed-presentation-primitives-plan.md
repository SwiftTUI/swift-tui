---
title: "refactor: compose presentations from primitive host layers"
type: refactor
status: shipped
date: 2026-05-02
completed: 2026-05-02
depends_on:
  - "../RUNTIME.md"
  - "../STATE_KEYING.md"
  - "../FOCUS.md"
  - "../ASYNC_RENDERING.md"
  - "2026-05-01-006-async-frame-head-draft-transaction-plan.md"
---

# Composed Presentation Primitives Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for
> tracking. Commit after every task that reaches a green checkpoint.

**Goal:** Replace presentation-specific overlay hoisting with a small set of
tested primitives that compose into sheets, alerts, menus, toasts, and future
root-level overlays without losing ordinary view-graph ownership.

**Architecture:** Keep the user-facing presentation APIs, but lower them into
general primitives: a portal registry, a root overlay stack, an interaction
gate, and a dismiss stack. A presentation may be declared anywhere, but active
presentation content must render as ordinary root-hosted child nodes with
normal state, lifecycle, task, focus, runtime-registration, and invalidation
behavior.

**Tech Stack:** Swift 6.3, SwiftPM, `TerminalUI`, `View`, `Core.ViewGraph`,
Swift Testing, `DefaultRenderer`, `RunLoop`, `FrameDiagnosticsLogger`,
`SceneSession` runtime tests, and the `Examples/gifeditor` package.

**Completion Status:** Completed on 2026-05-02. The implementation built the
primitive stack first, proved it with standalone tests, migrated each existing
hoisting-backed presentation path onto the primitive system, then removed the
old host machinery.

---

## Completion Record

Implemented primitives:

- `InteractionGate` now carries interaction availability in semantic metadata
  and suppresses focus, command, pointer, gesture, drop, text-input, and related
  interaction routes while preserving drawing, lifecycle, and tasks.
- `OverlayStack` composes root content and overlays through ordinary view
  children with deterministic `PortalOrdering` and focus-scope bridging.
- `Portal` hoists declaration payloads into graph-owned destination identities
  so hosted state, dynamic properties, tasks, lifecycle, and invalidation behave
  like normal child UI.
- `DismissStack` owns Escape dismissal ordering through the same z-order model
  used for overlay drawing.

Completed migration:

- `.sheet`, `.alert`, `.confirmationDialog`, `.menu`, `.toast`, and menu
  controls now lower through portal entries and primitive modal/non-modal
  policies.
- Menus no longer inherit sheet modal base-freezing.
- Presentation chrome remains ordinary portal content instead of owning the
  hoisting mechanism.
- The former presentation host state, overlay entry, manual graph-pruning
  teardown path, recursive base disabling, and presentation-family Escape
  ordering were removed from production runtime paths.

Verification completed:

```bash
swift format format -i --recursive --configuration .swift-format.json Sources Tests Examples/gifeditor/Tests/GIFEditorUITests/PresentationRuntimeTests.swift
swiftly run swift test --filter 'SwiftTUITests\.(InteractionGateTests|OverlayStackTests|DismissStackTests|PortalPrimitiveTests|PresentationEscapeDismissTests|PresentationActionScopeTests|PresentationSurfaceTests|PresentationContinuityTests|MenuSurfaceTests|AppRuntimeTests|AsyncFrameTailRenderingTests|Phase4ObservationAndEnvironmentTests|Phase4StateReliabilityTests|DiagnosticsAndCacheTests|ImperativeAuthoringContextDispatchTests|TerminationRequestTests|AnimationRepeatForeverGrowthTests|SwiftUISurfaceTests|InteractiveRuntimeTests|RegistrationAliasFindingsTests)'
swiftly run swift test --package-path Examples/gifeditor
swiftly run swift run --package-path Examples/gifeditor gifeditor
git diff --check
bun run test
```

The manual gifeditor PTY smoke opened the help sheet with `?`, observed the
spinner advance, dismissed with Escape, confirmed editor responsiveness with
`]`, and exited with Ctrl+Q.

Stale-host search:

```bash
rg -n "PresentationOverlayEntry|PresentationHostState|PresentationHostingRoot|composePresentationHostTree|__TerminalUIPresentationHost|PresentationHost|overlay host|disablesBaseInteractionWhenActive|presentation-family|lifecycleEntriesFromFocusSyncRerenders|setEnabledRecursively" Sources Tests docs -g '!docs/plans/2026-05-02-002-composed-presentation-primitives-plan.md'
```

Only the unrelated `FallbackPresentationHost` terminal-host test fixture
remained.

## Problem Frame

The current presentation system is standardized inside `PresentationCoordinator`,
but special-cased at the framework level:

- Presentation declarations travel upward as preferences.
- `PresentationHostState` reconciles hardcoded presentation families.
- `composePresentationHostTree(...)` synthesizes a root-level overlay sibling.
- The base subtree is disabled by mutating a resolved copy with
  `setEnabledRecursively(false)`.
- Escape precedence is hardcoded by presentation family.
- Overlay teardown manually removes runtime registrations and prunes graph
  subtrees.
- Presented content is carried through `DeferredViewPayload`, which was designed
  for resolving content in a different tree location.

That design succeeds at global layering, but it has repeatedly made
state/lifecycle/runtime behavior depend on special host paths. The desired
replacement is not "remove hoisting"; hoisting is still necessary. The desired
replacement is "make hoisting a primitive with the same graph semantics as
ordinary child composition."

## Target Confidence Bar

The migration is not complete until the composed primitives meet all of these
conditions:

- A state mutation inside hoisted content recomputes that hoisted content on the
  next committed frame in sync, async, async-no-cancel, and async-no-drop modes.
- A `.task` started inside hoisted content starts exactly once on activation,
  keeps running across unrelated base rerenders, visibly rerenders state changes,
  and cancels exactly once on dismissal or source removal.
- `onAppear`, `onDisappear`, and `.onChange` in hoisted content commit exactly
  once per lifecycle transition, including focus-sync rerenders and async
  frame-tail cancellation.
- Base interaction freezing suppresses focus, pointer, gesture, key-command,
  focused-value, scroll, text-input, and drop routes through one tested primitive.
- Escape/dismiss routing uses the same overlay ordering model as drawing.
- Menus no longer inherit sheet modal base-freezing by accident.
- Existing sheet/alert/confirmation-dialog/toast behavior is either preserved by
  test or intentionally changed by a named migration test.
- The `Examples/gifeditor` help-sheet spinner advances in the composed runtime
  path and does not make the app non-responsive.

This is the "failure chance <= 10%" bar: each primitive owns one policy surface,
and the migration is blocked until the composition tests prove the surfaces work
together.

## Migration Boundary

Build and prove the primitives before replacing any existing presentation
modifier execution path. Stages 1 through 4 are allowed to add parallel
package-internal primitives, tests, and temporary bridge points, but they must
not partially convert `.sheet`, `.alert`, `.confirmationDialog`, `.menu`, or
`.toast` while the primitive stack is incomplete.

Once `InteractionGate`, `OverlayStack`, `Portal`, and `DismissStack` are green
as standalone primitives, Stage 5 must migrate every current hoisting-backed
view modifier and presentation declaration path onto the new system. A mixed
end state where some presentation families still execute through
`PresentationHostState`, `PresentationOverlayHost`, or presentation-family
Escape ordering is not acceptable. Temporary compatibility shims are allowed
only inside the Stage 5 migration and must be deleted in Stage 6 after the
adapter parity tests pass.

## Primitive Set

### Primitive 1: `InteractionGate`

`InteractionGate` is a semantic/event primitive for "render this subtree, but
make it unavailable for interaction." It must not be implemented as a late
mutation of a resolved copy. It should be represented in resolved metadata and
honored by semantic extraction and event routing.

Required behavior:

- Focus regions under a disabled gate are omitted from traversal and focus-sync
  desired-focus resolution.
- Pointer regions, gesture recognizers, hover routes, and drop destinations under
  a disabled gate are omitted from runtime dispatch.
- Key handlers, palette commands, toolbar commands, and termination handlers
  under a disabled gate are omitted from command dispatch.
- Text input focus presentation under a disabled gate resolves to no edit target.
- Lifecycle and `.task` are not affected by the gate; disabled content is still
  mounted.

### Primitive 2: `OverlayStack`

`OverlayStack` is a root-local ordinary view composition primitive. It draws a
base child and zero or more overlay children with deterministic ordering.

Required behavior:

- The base child remains a normal graph child with stable identity.
- Each overlay child remains a normal graph child with stable identity.
- Ordering is by `(zIndex, activationOrdinal, stableID)`.
- The stack owns focus-scope bridging, so scene-level action scopes remain
  visible from overlay content.
- The stack does not know about sheets, alerts, menus, or toasts.

### Primitive 3: `Portal`

`Portal` is the general hoisting primitive. It lets a deep source declare an
entry that renders under the nearest compatible root portal host.

Required behavior:

- Portal declarations are data: `id`, `role`, `zIndex`, `activationOrdinal`,
  `modalPolicy`, `dismissPolicy`, and a typed content payload.
- The source identity determines declaration ownership and stale-source pruning.
- The hosted content identity is rooted under the portal host, not under the
  source subtree.
- Hosted content gets destination `ViewNode` ownership for its own dynamic
  properties. Captured parent `Binding` values still mutate their original
  owner through the captured binding.
- Portal content invalidation dirties the hosted content frontier and cannot be
  dropped as "outside the base subtree."
- Portal teardown uses ordinary child removal and normal runtime-registration
  pruning through the committed frame path.

### Primitive 4: `DismissStack`

`DismissStack` is the topmost-dismiss route. It is not presentation-specific.

Required behavior:

- Entries register a dismiss action, an escape eligibility flag, z-order data,
  and activation ordinal.
- Escape dispatch chooses the same topmost eligible entry that drawing places on
  top.
- Non-dismissible overlays, such as passive toasts, do not register escape
  actions.
- Nested overlays and imperative presentation handles use the same route.

### Primitive 5: Presentation Lowering

The existing public presentation APIs become adapters:

- `.sheet(...)` declares a modal portal entry with surface chrome.
- `.alert(...)` declares a modal portal entry with alert chrome and action
  content.
- `.confirmationDialog(...)` declares a modal portal entry with dialog chrome
  and default cancel action.
- `.menu(...)` declares a non-modal portal entry with menu chrome.
- `.toast(...)` declares a non-modal portal entry with toast chrome and optional
  timed dismissal.

The presentation adapters may keep the existing item models while migrating, but
the final runtime behavior must come from the primitives above.

## File Map

Create:

- `Sources/Core/InteractionGateTypes.swift`
  - Gate metadata carried in resolved nodes and consulted by semantic/event
    extraction.
- `Sources/Core/PortalTypes.swift`
  - Stable portal entry data, ordering keys, modal policy, dismiss policy, and
    diagnostics structures.
- `Sources/View/Presentation/Portal.swift`
  - View-layer portal declaration modifier and root host view.
- `Sources/View/Presentation/OverlayStack.swift`
  - View-layer root overlay composition primitive.
- `Sources/View/Presentation/InteractionGate.swift`
  - View modifier or primitive view that emits gate metadata.
- `Sources/View/Presentation/DismissStack.swift`
  - Root-level dismiss action registry and environment handle.
- `Tests/SwiftTUITests/InteractionGateTests.swift`
  - Gate behavior for focus, pointer, gestures, commands, focused values, and
    lifecycle preservation.
- `Tests/SwiftTUITests/OverlayStackTests.swift`
  - Ordering, focus-scope bridging, identity stability, and non-presentation
    composition.
- `Tests/SwiftTUITests/PortalPrimitiveTests.swift`
  - Graph ownership, state, task, lifecycle, invalidation, async rendering, and
    stale-source pruning for hoisted content.
- `Tests/SwiftTUITests/DismissStackTests.swift`
  - Topmost dismiss ordering and escape eligibility independent of presentation
    families.
- `Examples/gifeditor/Tests/GIFEditorUITests/PresentationRuntimeTests.swift`
  - Composed gifeditor help-sheet spinner and responsiveness regression.

Modify:

- `Sources/Core/RenderTreeAndSemanticsTypes.swift`
  - Add interaction-gate metadata to resolved/semantic structures.
- `Sources/Core/Semantics.swift`
  - Omit gated interaction/focus/command routes while preserving lifecycle.
- `Sources/Core/DrawExtractor.swift`
  - Preserve drawing through gates and overlay-stack children.
- `Sources/Core/LayoutEngine.swift`
  - Ensure overlay stack layout is ordinary overlay layout, not presentation
    special case.
- `Sources/Core/Graph/ViewGraph.swift`
  - Support portal host child ownership and stale declaration pruning without
    manual presentation-only graph surgery.
- `Sources/View/Presentation/PresentationCoordinator.swift`
  - Convert from host implementation to presentation adapter and remove
    hardcoded overlay host execution after parity.
- `Sources/View/Presentation/PresentationModifiers.swift`
  - Lower `.sheet`, `.alert`, `.confirmationDialog`, `.menu`, and `.toast` into
    portal entries.
- `Sources/SwiftTUI/RunLoop+EventDispatch.swift`
  - Route Escape through `DismissStack`.
- `Sources/SwiftTUI/RunLoop+Rendering.swift`
  - Remove presentation-specific lifecycle carry-forward once portal content is
    ordinary graph-owned UI.
- `Sources/SwiftTUI/SwiftTUI.swift`
  - Remove completed-frame preview lifecycle merging that exists only to rescue
    special presentation-host side effects.
- `Tests/SwiftTUITests/PresentationSurfaceTests.swift`
  - Keep visible behavior tests, update expected resolved kind names only after
    primitive tests are green.
- `Tests/SwiftTUITests/PresentationActionScopeTests.swift`
  - Assert the new overlay stack owns scene/presentation scope ordering.
- `Tests/SwiftTUITests/PresentationEscapeDismissTests.swift`
  - Migrate from family-specific registry tests to dismiss-stack ordering tests.
- `Tests/SwiftTUITests/AppRuntimeTests.swift`
  - Keep runtime sheet task/spinner regressions until gifeditor coverage lands.
- `docs/ARCHITECTURE.md`
  - Document portal/overlay/gate/dismiss as runtime primitives.
- `docs/RUNTIME.md`
  - Document portal content state, lifecycle, task, and invalidation contracts.
- `docs/FOCUS.md`
  - Document interaction gates and overlay scope ordering.
- `docs/README.md`
  - Link this plan while active.

## Stage 0: Lock The Current Failure Class

**Goal:** Establish red tests that fail for the right reason before refactoring.

- [x] Add `PortalPrimitiveTests.hoistedTaskStateRerendersHostedContent`.

  Test shape:

  ```swift
  private struct PortalTaskProbe: View {
    @State private var isPresented = true

    var body: some View {
      Text("Base")
        .sheet("Inspector", isPresented: $isPresented) {
          PortalTaskContent()
        }
    }
  }

  private struct PortalTaskContent: View {
    @State private var tick = 0

    var body: some View {
      Text("Tick \(tick)")
        .task(id: "advance") {
          try? await Task.sleep(for: .milliseconds(20))
          tick = 1
        }
    }
  }
  ```

  Run:

  ```bash
  swiftly run swift test --filter SwiftTUITests.PortalPrimitiveTests/hoistedTaskStateRerendersHostedContent
  ```

  Expected before the primitive migration: fail on the current branch if the
  overlay content starts but later state invalidation reuses a stale overlay
  subtree.

- [x] Add `PortalPrimitiveTests.hoistedSpinnerAdvancesAcrossAsyncFrames`.

  Use `runTestSceneSession` with a key-opened sheet containing `Spinner()`.
  Assert that frames contain `Inspector`, `⠋`, and at least one of
  `["⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]`.

  Run:

  ```bash
  swiftly run swift test --filter SwiftTUITests.PortalPrimitiveTests/hoistedSpinnerAdvancesAcrossAsyncFrames
  ```

  Expected before the primitive migration: fail in the composed gifeditor-like
  path if the hosted content is not graph-owned.

- [x] Add a diagnostics assertion for the failure mode.

  The test should install `FrameDiagnosticsLogger` and assert that a state tick
  frame after activation has non-zero resolved work for a portal-hosted content
  identity. This prevents a false green where the task runs but the overlay
  subtree is reused stale.

- [x] Run the existing presentation runtime surface.

  ```bash
  swiftly run swift test --filter 'SwiftTUITests\.(PresentationSurfaceTests|PresentationContinuityTests|PresentationActionScopeTests|PresentationEscapeDismissTests|AppRuntimeTests)'
  ```

  Expected: current behavior is documented. New red tests identify the failure
  class being fixed.

## Stage 1: Build `InteractionGate`

**Goal:** Replace late recursive disabling with an ordinary semantic primitive.

- [x] Add `InteractionGateMetadata` to resolved node metadata.

  The resolved metadata should distinguish at least:

  ```swift
  package enum InteractionAvailability: Equatable, Sendable {
    case enabled
    case disabled(reason: InteractionDisabledReason)
  }

  package enum InteractionDisabledReason: String, Equatable, Sendable {
    case modalOverlay
    case authorRequested
  }
  ```

- [x] Add a view-layer primitive.

  Provide a package-internal primitive first:

  ```swift
  extension View {
    package func interactionGate(
      _ availability: InteractionAvailability
    ) -> some View
  }
  ```

  Do not make this public until the presentation migration proves the contract.

- [x] Update semantic extraction to carry an inherited disabled state.

  Drawing still walks gated children. Semantic extraction omits interaction
  surfaces that would route input into a disabled subtree.

- [x] Update command and input registries to respect gated route omission.

  The gate should not add new dispatch-time conditionals in every caller.
  Instead, gated descendants should not publish active routes in the semantic
  snapshot or command registry for that frame.

- [x] Add `InteractionGateTests`.

  Required tests:

  - gated focusable button is absent from focus regions;
  - ungated overlay button remains focusable while gated base button is absent;
  - gated pointer handler does not fire through the full run loop;
  - gated key command does not fire;
  - gated drop destination does not fire;
  - gated child `.task` still starts and cancels normally;
  - gated child `onAppear` and `onDisappear` still fire normally.

- [x] Verify Stage 1.

  ```bash
  swiftly run swift test --filter SwiftTUITests.InteractionGateTests
  swiftly run swift test --filter 'SwiftTUITests\.(FocusTransitionTests|KeyCommandTests|GestureRunLoopDispatchTests|DropDestinationDispatchTests|PresentationSurfaceTests)'
  git diff --check
  ```

## Stage 2: Build `OverlayStack`

**Goal:** Make root-level overlay composition an ordinary reusable view instead
of presentation-specific tree synthesis.

- [x] Add `OverlayStackEntry`.

  Required fields:

  ```swift
  package struct OverlayStackEntry<ID: Hashable & Sendable>: Sendable {
    package var id: ID
    package var zIndex: Int
    package var activationOrdinal: Int
    package var kindName: String
  }
  ```

  The content builder can be stored in a view-layer wrapper; keep Core data
  payloads free of view closures.

- [x] Add `OverlayStack`.

  The primitive should lower to a resolved node with ordinary children:

  ```text
  OverlayStack
    base
    overlays
      overlay[id:...]
      overlay[id:...]
  ```

  It may use existing `.overlay(alignment: .topLeading)` layout behavior, but
  the root kind should be explicit for diagnostics and tests.

- [x] Move scene focus-scope bridging into `OverlayStack`.

  The current presentation host manually clears and lifts focus-scope metadata.
  `OverlayStack` should own that rule so presentations do not need custom scope
  repair.

- [x] Add `OverlayStackTests`.

  Required tests:

  - overlays paint above clipped/nested base content;
  - overlay ordering follows z-index, then activation ordinal, then stable id;
  - base identity remains stable when overlay appears and disappears;
  - overlay identity remains stable across unrelated base invalidations;
  - scene scope appears before overlay scope in descendant focus-region paths;
  - `OverlayStack` with no overlays has the same rendered surface as base-only
    content and does not introduce focus regions.

- [x] Verify Stage 2.

  ```bash
  swiftly run swift test --filter SwiftTUITests.OverlayStackTests
  swiftly run swift test --filter 'SwiftTUITests\.(PresentationActionScopeTests|PresentationSurfaceTests|SwiftUISurfaceTests)'
  git diff --check
  ```

## Stage 3: Build `Portal`

**Goal:** Generalize hoisting while preserving ordinary graph ownership for
hosted content.

- [x] Add portal entry data and host state.

  Required entry model:

  ```swift
  package struct PortalEntryID: Hashable, Sendable {
    package var sourceIdentity: Identity
    package var token: String
  }

  package enum PortalModalPolicy: Equatable, Sendable {
    case nonModal
    case disablesBaseInteraction
  }

  package struct PortalOrdering: Equatable, Sendable {
    package var zIndex: Int
    package var activationOrdinal: Int
    package var stableTieBreaker: String
  }
  ```

- [x] Add a typed portal content payload that does not capture destination
  `ViewNode`.

  The payload may preserve authoring context for closures and captured bindings,
  but when resolved under the portal host it must bind dynamic properties to the
  destination graph nodes. This is the core invariant that prevents the current
  bug class.

- [x] Add root portal host reconciliation.

  Reconciliation should:

  - begin a sync pass;
  - apply source declarations;
  - keep active imperative entries;
  - remove stale declarative entries whose source did not appear in the current
    committed base snapshot;
  - assign activation ordinals once per logical entry activation;
  - expose overlay entries to `OverlayStack`;
  - expose modal state to `InteractionGate`;
  - expose dismiss entries to `DismissStack`.

- [x] Make portal-hosted identities descendants of the host overlay identity.

  Required identity shape:

  ```text
  <scene-root>/PortalHost/overlays/<portal-id>/body/...
  ```

  State changes inside the body must invalidate identities in that subtree, not
  identities under the original source modifier.

- [x] Add stale-source teardown through ordinary child removal.

  Removing a declarative source should remove its portal entry and let the next
  committed tree removal cancel tasks and fire disappear handlers. Do not add a
  presentation-specific runtime-registration removal path.

- [x] Add `PortalPrimitiveTests`.

  Required tests:

  - portal content declared under a clipped ancestor renders above scene base;
  - portal content `@State` changes rerender only hosted content when possible;
  - portal content `.task` starts once, updates visible text, and cancels once;
  - portal content `onAppear` and `onDisappear` fire exactly once;
  - parent state captured through a `Binding` still mutates the parent owner;
  - state declared inside portal content belongs to the hosted content identity;
  - source subtree removal tears down the portal and cancels hosted tasks;
  - unrelated base rerender does not restart hosted portal tasks;
  - async frame-tail cancellation and completed-frame dropping do not publish
    duplicate lifecycle events for portal content;
  - frame diagnostics for a portal-content state tick show non-zero resolved
    work for the hosted content frontier.

- [x] Verify Stage 3.

  ```bash
  swiftly run swift test --filter SwiftTUITests.PortalPrimitiveTests
  swiftly run swift test --filter 'SwiftTUITests\.(AsyncFrameTailRenderingTests|PresentationContinuityTests|Phase4ObservationAndEnvironmentTests)'
  git diff --check
  ```

## Stage 4: Build `DismissStack`

**Goal:** Route topmost dismissal through overlay entries instead of hardcoded
presentation-family order.

- [x] Add `DismissStackEntry`.

  Required fields:

  ```swift
  package struct DismissStackEntry<ID: Hashable & Sendable>: Sendable {
    package var id: ID
    package var ordering: PortalOrdering
    package var acceptsEscape: Bool
    package var dismiss: @MainActor @Sendable () -> Void
  }
  ```

- [x] Add a root `DismissStack` environment handle.

  The run loop should query a single topmost escape action after each committed
  frame. Presentation families must not be named in the run-loop Escape path.

- [x] Migrate `PresentationEscapeDismissTests`.

  Required tests:

  - no entries yields no Escape action;
  - topmost z-index wins;
  - higher activation ordinal wins for equal z-index;
  - non-Escape entries are skipped;
  - dismiss action invalidates the portal host identity;
  - toast-like non-dismissible entries do not shadow sheet-like entries.

- [x] Verify Stage 4.

  ```bash
  swiftly run swift test --filter SwiftTUITests.DismissStackTests
  swiftly run swift test --filter 'SwiftTUITests\.(PresentationEscapeDismissTests|AppRuntimeTests)'
  git diff --check
  ```

## Stage 5: Lower Existing Presentation APIs Into Primitives

**Goal:** Keep public API behavior while replacing the execution model for every
existing hoisting-backed modifier.

- [x] Audit every existing hoisting-backed presentation entry point.

  Search for all callers and declarations that feed
  `PresentationCoordinatorDeclarationPreferenceKey`, `PresentationOverlayEntry`,
  `PresentationHostState`, or `composePresentationHostTree(...)`. The migration
  scope includes `.sheet`, `.alert`, `.confirmationDialog`, `.menu`, `.toast`,
  `Menu` controls that currently lower through sheet presentation machinery,
  and any other modifier or control that uses the same hoisted presentation
  path. Do not start replacing individual public modifiers until
  `InteractionGate`, `OverlayStack`, `Portal`, and `DismissStack` have passed
  their standalone primitive suites.

- [x] Convert `.sheet(...)`.

  `.sheet` should declare a portal entry with:

  - role: sheet;
  - z-index: 200;
  - modal policy: disables base interaction;
  - Escape dismiss: yes;
  - chrome: existing surface chrome;
  - content sizing: existing sheet sizing defaults.

- [x] Convert `.alert(...)`.

  `.alert` should declare:

  - z-index: 260;
  - modal policy: disables base interaction;
  - Escape dismiss: yes;
  - action/message body mode;
  - existing default dismiss/cancel behavior.

- [x] Convert `.confirmationDialog(...)`.

  `.confirmationDialog` should declare:

  - z-index: 240;
  - modal policy: disables base interaction;
  - Escape dismiss: yes;
  - default cancel action when no explicit cancel exists.

- [x] Convert `.menu(...)`.

  `.menu` should declare:

  - z-index: 180 unless a stronger local policy is chosen;
  - modal policy: non-modal;
  - Escape dismiss: yes;
  - no backdrop;
  - intrinsic content sizing;
  - no inherited sheet base-freezing.

- [x] Convert `.toast(...)`.

  `.toast` should declare:

  - z-index: 100;
  - modal policy: non-modal;
  - Escape dismiss: no;
  - auto-dismiss timer behavior preserved.

- [x] Keep presentation chrome views as ordinary portal content.

  `HostedPromptPresentation`, `PromptPresentationSurface`, menu chrome, and
  toast chrome may remain, but they should no longer own hoisting mechanics.

- [x] Update presentation tests.

  Keep or update tests for:

  - alert surface rendering;
  - confirmation dialog default cancel;
  - sheet chrome background sampling;
  - toast and alert ordering;
  - menu overlay intrinsic sizing;
  - menu item focus without accidental base freeze;
  - sheet focus restoration;
  - Escape dismissal from text-input focus inside a sheet.

- [x] Confirm no presentation family remains on the old hoisting execution path.

  After the adapters are converted, every active presentation surface should be
  produced by portal entries, composed by `OverlayStack`, interaction-gated by
  `InteractionGate`, and dismissed through `DismissStack`. Existing public
  functions may remain as adapters, but none should call the old hoisting host
  as their runtime implementation.

- [x] Verify Stage 5.

  ```bash
  swiftly run swift test --filter 'SwiftTUITests\.(PresentationSurfaceTests|PresentationContinuityTests|PresentationActionScopeTests|PresentationEscapeDismissTests|MenuSurfaceTests|AppRuntimeTests)'
  swiftly run swift test --package-path Examples/gifeditor
  git diff --check
  ```

## Stage 6: Remove Presentation-Specific Host Machinery

**Goal:** Delete the old special paths after primitive parity and full adapter
migration are proven.

- [x] Remove `PresentationOverlayEntry` and `PresentationOverlayHost` if they
  have no non-test callers.
- [x] Remove hardcoded `PresentationCoordinatorRegistry.topmostEscapeDismissAction`
  and route through `DismissStack`.
- [x] Remove `PresentationHostState.disablesBaseInteraction` and replace callers
  with `InteractionGate`.
- [x] Remove manual overlay teardown:
  `runtimeRegistrations.removeSubtrees(rootedAt:)` and
  `viewGraph.pruneDetachedIdentitySubtree(rootedAt:)` should not be presentation
  adapter code.
- [x] Remove lifecycle carry-forward logic that only exists to preserve side
  effects from presentation preview/focus-sync frames.
- [x] Search for stale special-case strings.

  ```bash
  rg -n "PresentationHost|topmostEscapeDismissAction|disablesBaseInteraction|removeSubtrees\\(rootedAt: \\[overlayContext|lifecycleEntriesFromFocusSyncRerenders" Sources Tests
  ```

  Expected: remaining matches are either primitive names, migration comments
  with active tests, or deleted.

- [x] Treat any remaining old-host caller as a blocker.

  Stage 6 is not complete while a production source path can still present UI
  through `PresentationHostState`, `PresentationOverlayHost`,
  `PresentationCoordinatorRegistry.overlayEntries()`, or
  presentation-family-specific Escape ordering. If a shim remains temporarily
  necessary, document the exact blocker in this plan and keep the status
  `active`.

- [x] Verify Stage 6.

  ```bash
  swiftly run swift test --filter 'SwiftTUITests\.(PortalPrimitiveTests|OverlayStackTests|InteractionGateTests|DismissStackTests|PresentationSurfaceTests|PresentationContinuityTests|PresentationActionScopeTests|PresentationEscapeDismissTests|MenuSurfaceTests|AppRuntimeTests|AsyncFrameTailRenderingTests)'
  swiftly run swift test --package-path Examples/gifeditor
  git diff --check
  ```

## Stage 7: Full Runtime And Example Validation

**Goal:** Prove the primitives compose under the real app/runtime paths.

- [x] Add gifeditor composed-runtime regression.

  Add `Examples/gifeditor/Tests/GIFEditorUITests/PresentationRuntimeTests.swift`
  with a `RunLoop` or `SceneSession` test that:

  - opens the help sheet through the same `?` binding path;
  - waits for `Keyboard help`;
  - waits for at least two distinct spinner glyphs;
  - sends Escape and confirms the editor is responsive again;
  - sends a normal editor key after dismissal and observes the expected status
    or model change.

- [x] Run gifeditor manually through the PTY path.

  ```bash
  swiftly run swift run --package-path Examples/gifeditor gifeditor
  ```

  Manual verification:

  - press `?`;
  - confirm the spinner advances;
  - press Escape;
  - confirm the sheet dismisses;
  - press an editor key such as `]` or `[`;
  - confirm the UI responds;
  - exit with the configured quit binding.

- [x] Run root focused suites.

  ```bash
  swiftly run swift test --filter 'SwiftTUITests\.(PortalPrimitiveTests|OverlayStackTests|InteractionGateTests|DismissStackTests|PresentationSurfaceTests|PresentationContinuityTests|PresentationActionScopeTests|PresentationEscapeDismissTests|MenuSurfaceTests|AppRuntimeTests|AsyncFrameTailRenderingTests|InteractiveRuntimeTests|GalleryStyleDispatchTests|Phase4ObservationAndEnvironmentTests)'
  ```

- [x] Run full repo gate.

  ```bash
  bun run test
  ```

  Expected: pass. If unrelated suites fail, record exact failing commands and
  keep the primitive-focused suites green before deciding whether to split the
  fix.

## Stage 8: Documentation And Contract Cleanup

**Goal:** Make the new primitives the source of truth.

- [x] Update `docs/ARCHITECTURE.md`.

  Add portal/overlay/gate/dismiss to the runtime architecture section and show
  how they sit in the frame pipeline:

  ```text
  resolve declarations -> reconcile portal host -> overlay stack composition
  -> measure/place -> semantics honoring interaction gates -> draw/raster
  -> commit lifecycle/tasks/dismiss routes exactly once
  ```

- [x] Update `docs/RUNTIME.md`.

  Document:

  - portal content identity ownership;
  - dynamic property ownership rules;
  - task/lifecycle commit rules;
  - stale-source pruning;
  - async frame-tail behavior.

- [x] Update `docs/FOCUS.md`.

  Document:

  - interaction gates;
  - overlay stack focus-scope bridging;
  - scene scope ordering for presentation content.

- [x] Update `docs/SOURCE_LAYOUT.md`.

  Add the new files and responsibilities.

- [x] Update this plan's progress and verification logs.

  Mark shipped only after `bun run test` and gifeditor runtime verification pass.

## Design Guardrails

- Do not add public API until the package-internal primitives are green.
- Do not preserve current kind names in tests if doing so keeps old special-case
  architecture alive; update tests to assert semantic behavior instead.
- Do not fix portal invalidation by forcing root evaluation on every portal
  state change. That may mask the bug but fails the primitive bar.
- Do not let menus remain sheet entries. Menu modal behavior must be a policy
  choice, not an inherited registry accident.
- Do not merge lifecycle entries from abandoned preview or focus-sync frames as
  a general solution. Lifecycle side effects must come from the committed frame.
- Do not couple Escape routing to presentation family names.
- Do not make interaction gating cancel lifecycle or tasks. Visual presence and
  input availability are separate contracts.

## Completion Criteria

The plan is complete when all of the following are true:

- `InteractionGateTests`, `OverlayStackTests`, `PortalPrimitiveTests`, and
  `DismissStackTests` exist and pass.
- Existing presentation behavior passes through adapters built on those
  primitives.
- `Examples/gifeditor` has a runtime regression proving the help-sheet spinner
  advances and the app remains responsive.
- Presentation code no longer needs manual overlay graph pruning, hardcoded
  Escape family precedence, or lifecycle carry-forward for hoisted content.
- Every existing hoisting-backed view modifier and presentation control has
  been migrated to the primitive system; no public presentation API remains on
  the old host implementation.
- Documentation names portal, overlay stack, interaction gate, and dismiss stack
  as framework primitives.
- `bun run test` passes, or any unrelated failures are documented with focused
  primitive and presentation suites green.
