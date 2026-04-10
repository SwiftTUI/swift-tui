# refactor: Stabilize Presentation Hosting Before Coordinator Generalization

Date: 2026-04-09
Plan depth: Deep
Status: Completed
Execution posture: Characterization-first

## Problem Frame

The current presentation system successfully hoists authored presentation
surfaces to the root, but it does so through a brittle hosting seam.

Today, `DefaultRenderer` always wraps the authored root in
`PresentationHostingRoot` in `Sources/TerminalUI/TerminalUI.swift`. That host:

1. resolves the authored base content once to collect presentation declarations
2. reconciles those declarations into retained coordinator state
3. when any presentation is active, resolves the authored base content a second
   time under a `PresentationHost/base/...` identity path so the host can layer
   presentation payloads above it

That second base resolve is the architectural fault line. Deferred presentation
payloads preserve their original authored ownership through
`DeferredViewPayload`, which is why current state-owner preservation tests pass,
but the displayed base subtree is no longer the same identity space as the
authored base subtree once a presentation becomes active.

In a framework where lifecycle, focus, retained reuse, invalidation, and local
handler routing are all identity-sensitive, this split makes the system fragile.
It also matches the user report: attempted fixes in this area can easily repair
one regression while creating another.

The existing April 8, 2026 plan in
`docs/plans/2026-04-08-001-refactor-single-presentation-coordinator-plan.md`
is still directionally useful, but it tackles coordinator generalization before
stabilizing the hosting seam. This plan proposes the missing prerequisite work.

## Requirements Trace

This plan is driven directly by the April 9, 2026 request to deeply examine the
root-hoisted presentation architecture, explain why it is regressing, and
propose safer alternatives.

The work must preserve currently-shipping guarantees already covered by tests:

- hoisted surfaces render above clipped ancestors
- deferred presentation payloads preserve original state ownership and
  observation behavior
- modal-style surfaces can suppress background focus
- imperative presentation and dismissal still invalidate and rerender correctly
- command palette behavior remains intact

The work must add explicit continuity guarantees that are not currently pinned
well enough:

- opening a presentation does not remount the base subtree
- dismissing a presentation does not remount the base subtree
- base `onAppear` and `onDisappear` only fire for true base lifecycle changes
- base `.task` work is not cancelled and restarted solely because a presentation
  toggles
- focus restores predictably after modal dismissal
- transient non-modal overlays do not unnecessarily disturb base focus
- steady-state incremental rendering remains healthy after presentation
  open/close cycles

## Current Repo Grounding

No relevant upstream requirements document exists in this repo today:

- `docs/brainstorms/` is not present
- `docs/solutions/` is not present

This plan therefore uses the user request and local repo research as the source
of truth.

Relevant implementation files:

- `Sources/TerminalUI/TerminalUI.swift`
- `Sources/View/Presentation/PresentationCoordinator.swift`
- `Sources/View/Presentation/PresentationModifiers.swift`
- `Sources/View/Presentation/CommandPalette.swift`
- `Sources/View/Foundation/ViewCompositionHelpers.swift`
- `Sources/View/State/State.swift`
- `Sources/View/Environment/FrameResolveState.swift`
- `Sources/Core/Graph/ViewGraph.swift`
- `Sources/Core/CommitAndFrameTypes.swift`

Relevant tests and fixtures:

- `Tests/TerminalUITests/PresentationSurfaceTests.swift`
- `Tests/TerminalUITests/AppRuntimeTests.swift`
- `Tests/TerminalUITests/InteractiveRuntimeTests.swift`
- `Tests/TerminalUITests/Phase4ObservationAndEnvironmentTests.swift`
- `Tests/TerminalUITests/Phase1BenchmarkScenariosTests.swift`
- `Tests/TerminalUITests/Phase5ReliabilityGatesTests.swift`
- `Tests/TerminalUITests/Support/LifecycleFixtures.swift`

Important current patterns to preserve:

- authored modifiers emit presentation declarations rather than rendering inline
- `DeferredViewPayload` preserves authored ownership for deferred surfaces
- the root host, not local layout, owns hoisting above clipped ancestors
- modal-style surfaces can suppress background interaction through the semantic
  pipeline rather than ad hoc runtime hacks
- imperative presentation flows through retained coordinator state and frame
  invalidation

Important current weaknesses to fix:

- base content is re-resolved into a different display identity space whenever a
  presentation is active
- lifecycle and focus continuity across presentation toggles are under-specified
- retained reuse and incremental behavior across presentation toggles are not
  strongly characterized
- additional fixes in this seam risk compounding identity forwarding and making
  the model harder to reason about

External research is intentionally skipped for this plan. The problem is rooted
in repo-specific renderer and identity behavior, and the local implementation
patterns are the primary source of truth.

## Decisions

### 1. Treat Hosting Stabilization As A Prerequisite To Coordinator Generalization

This plan should land before the generic family/lane coordinator work proposed
on April 8.

Rationale:

- the main instability comes from the two-pass hosting seam, not from the lack
  of generic coordinator policies
- generalizing coordinator policy on top of the current host would preserve the
  most regression-prone part of the design

### 2. Keep Public Built-Ins And Current Family Stores During Phase 1

Public APIs such as `.alert`, `.confirmationDialog`, `.sheet`, `.toast`, and
`.commandPalette` remain the user-facing story. The current family-specific
coordinator storage can remain temporarily while the hosting seam changes.

Rationale:

- this reduces migration scope
- it isolates the architectural fix to hosting and frame composition first

### 3. Execute Characterization-First

Add missing continuity coverage before changing the host behavior.

Rationale:

- the target area is historically fragile
- the user explicitly reported regressions from attempted fixes
- the missing tests are exactly the behaviors most likely to drift during a
  host rewrite

### 4. Replace The Two-Pass Base Rehost With A Single-Pass Composition Seam

Resolve the authored base tree exactly once in its real identity space. Resolve
visible presentation overlays separately, then compose base and overlays for the
downstream pipeline without rebasing the base tree under `PresentationHost/base`
or an equivalent synthetic identity prefix.

Rationale:

- base identity continuity becomes stable across presentation toggles
- lifecycle and focus reasoning become simpler and more predictable
- presentation hosting stops depending on “preserve old owner identity while
  drawing somewhere else” for the base subtree

### 5. Do Not Patch The Current Rehost With More Identity Forwarding

Avoid another round of targeted fixes that attempt to preserve lifecycle,
handler routing, or focus continuity by forwarding more authored identity or
view-node ownership across the rehost seam.

Rationale:

- that path increases hidden coupling
- it makes the system harder to debug
- it preserves the core contradiction between authored identity and displayed
  identity

### 6. Defer Runtime-Managed Surface Stacks To A Future Exploration

A runtime-managed surface stack remains a plausible long-term architecture if
presentations eventually become more window-like, but it should not be the
immediate step.

Rationale:

- it is a larger rewrite than needed to fix the current regressions
- the repo can likely regain stability with a smaller single-pass composition
  refactor first

## Target Architecture

### Chosen Direction: Single-Pass Portal Composition Seam

The stabilized design should work conceptually like this:

1. resolve the authored base tree once in its real identity space
2. collect presentation declarations from that authored tree
3. reconcile declarations into retained presentation host state
4. resolve only the visible presentation payloads as overlay roots
5. compose the base root and overlay roots into one package-only frame model
   for measure, place, semantics, draw, raster, and commit

The key distinction from today is that the base tree is never cloned into a
second display namespace just because a presentation is active.

### Composition Model

The implementation should introduce a package-only composition seam, likely via
one of these shapes:

- a new package-only composed-frame model in `Sources/Core/CommitAndFrameTypes.swift`
- a new package-only presentation composition helper in
  `Sources/View/Presentation/PresentationComposition.swift`
- multi-root support in `Sources/Core/Graph/ViewGraph.swift`, if that produces a
  cleaner lifecycle story than wrapping overlay roots into a synthetic composed
  node after resolution

Whichever shape is chosen, the requirements are:

- base authored identity remains authoritative
- overlay roots can participate in layout, semantics, draw, and commit
  alongside the base tree
- base interaction suppression remains derived from visible modal families
- overlay z-order remains explicit and deterministic

### Coordinator Responsibilities In The Stabilized Model

For this prerequisite refactor, the presentation host should keep a narrow job:

- collect declarations
- retain imperative and declarative presentation family state
- determine which overlay roots are active
- determine whether active overlays suppress base interaction
- hand base plus overlay roots to the composition seam

It should not:

- re-resolve the base tree under a new identity namespace
- become a family-agnostic policy engine yet
- take ownership of family-specific rendering chrome

### Alternative Architectures Considered

#### A. Keep Patching The Two-Pass Rehost

Rejected.

Why:

- this preserves the authored/displayed identity split
- each additional fix would likely be local and fragile
- it does not improve conceptual clarity

#### B. Jump Directly To The Generic Family/Lane Coordinator

Rejected as the next step, but retained as a follow-on plan.

Why:

- it solves extensibility, not the base identity split
- it risks large-scope churn without reducing the core hosting fragility

#### C. Runtime-Managed Surface Stack

Deferred.

Why:

- it could ultimately be the cleanest model for truly window-like surfaces
- it is a larger architectural step than this bug class requires right now

## File Plan

### New Files

- `docs/plans/2026-04-09-001-stabilize-presentation-hosting-plan.md`
- `Tests/TerminalUITests/PresentationContinuityTests.swift`

Possible new package-only support file if it clarifies the implementation:

- `Sources/View/Presentation/PresentationComposition.swift`

### Files To Modify

- `Sources/TerminalUI/TerminalUI.swift`
  - stop relying on a two-pass hosted base re-resolve
  - switch the renderer to the new composition seam
- `Sources/View/Presentation/PresentationCoordinator.swift`
  - extract declaration collection and visible overlay resolution from the
    current rehost implementation
  - remove `hostedBasePayload` or equivalent second-pass base hosting machinery
- `Sources/View/Presentation/PresentationModifiers.swift`
  - adapt built-in presentation emitters only as needed for the new hosting seam
- `Sources/View/Presentation/CommandPalette.swift`
  - confirm command palette presentation uses the new composition seam without
    regressing input and dismissal behavior
- `Sources/View/Foundation/ViewCompositionHelpers.swift`
  - preserve deferred authored ownership for overlay payloads only where still
    needed
- `Sources/View/State/State.swift`
  - verify dynamic property ownership assumptions after base rehost removal
- `Sources/Core/Graph/ViewGraph.swift`
  - add any lifecycle or multi-root support needed by the composition seam
- `Sources/Core/CommitAndFrameTypes.swift`
  - add any package-only composed frame representation needed by the pipeline
- `docs/ARCHITECTURE.md`
- `docs/RUNTIME.md`
- `docs/SOURCE_LAYOUT.md`

### Tests To Add Or Update

- `Tests/TerminalUITests/PresentationContinuityTests.swift`
  - base lifecycle continuity across presentation open/close
  - base task continuity across presentation open/close
  - overlay lifecycle correctness
  - focus restoration expectations
- `Tests/TerminalUITests/PresentationSurfaceTests.swift`
  - keep hoisting and base-suppression coverage
  - add assertions that modal and non-modal overlays do not require base rehost
- `Tests/TerminalUITests/AppRuntimeTests.swift`
  - add focus restoration and focus continuity scenarios around modal dismissal
- `Tests/TerminalUITests/InteractiveRuntimeTests.swift`
  - extend lifecycle recorder coverage for presentation transitions
  - confirm imperative present/dismiss still invalidates correctly
- `Tests/TerminalUITests/Phase4ObservationAndEnvironmentTests.swift`
  - preserve state-owner and observation guarantees for hosted overlay payloads
- `Tests/TerminalUITests/Phase1BenchmarkScenariosTests.swift`
  - add or extend scenarios that detect degraded steady-state reuse after
    presentation toggles
- `Tests/TerminalUITests/Phase5ReliabilityGatesTests.swift`
  - ensure no reliability gate regresses when toggling presentations repeatedly

## Characterization Test Plan

Before any host refactor, add explicit tests for the following behaviors.

### Base Lifecycle Continuity

- opening a sheet does not re-fire base `onAppear`
- opening a sheet does not trigger base `onDisappear`
- dismissing a sheet does not re-fire base `onAppear`
- opening an alert over a focused base control does not remount the base control

These scenarios likely fit best in
`Tests/TerminalUITests/PresentationContinuityTests.swift` with helper reuse from
`Tests/TerminalUITests/Support/LifecycleFixtures.swift`.

### Base Task Continuity

- a base `.task(id:)` does not cancel and restart when a sheet opens
- a base `.task(id:)` does not cancel and restart when an alert opens
- a base `.task(id:)` does not cancel and restart when a toast appears

These scenarios should reuse `RuntimeLifecycleRecorder` patterns already present
in `Tests/TerminalUITests/InteractiveRuntimeTests.swift`.

### Overlay Lifecycle Correctness

- overlay `onAppear` fires once for an actual open transition
- overlay `onDisappear` fires once for an actual dismiss transition
- toast auto-dismiss task cancellation happens once per true dismissal

### Focus Continuity

- modal dismissal restores the previously-focused base control when still
  present
- modal dismissal falls back predictably when the previously-focused control no
  longer exists
- non-modal overlays such as toasts do not steal or reset base focus unless
  explicitly designed to

These scenarios should extend
`Tests/TerminalUITests/AppRuntimeTests.swift` and
`Tests/TerminalUITests/PresentationSurfaceTests.swift`.

### Incremental Rendering Continuity

- repeated present/dismiss cycles still settle back to expected retained-layout
  and retained-render reuse behavior
- presentation toggles do not permanently increase invalidation scope once the
  tree returns to steady state

These scenarios belong in
`Tests/TerminalUITests/Phase1BenchmarkScenariosTests.swift` and
`Tests/TerminalUITests/Phase5ReliabilityGatesTests.swift`.

## Migration Phases

### Phase 1: Add Characterization Coverage

Goal:

- pin lifecycle, focus, and task continuity before changing host behavior

Exit criteria:

- the missing continuity scenarios are covered by dedicated tests
- the tests fail if the base subtree remounts across presentation toggles

### Phase 2: Extract Presentation Snapshot And Composition Seams

Goal:

- separate declaration collection and visible-overlay snapshotting from the
  current rehost implementation without yet changing pipeline behavior

Steps:

- isolate the logic that gathers visible presentations from
  `PresentationHostingRoot`
- introduce a package-only representation for “base root plus overlay roots”
- keep public APIs and family stores unchanged

Exit criteria:

- presentation collection logic is no longer entangled with “resolve base again
  for display”
- the code clearly exposes the seam where composition will replace rehost

### Phase 3: Switch To Single-Pass Base Hosting

Goal:

- resolve the base content once and compose overlay roots around it

Steps:

- update `DefaultRenderer` and the presentation host to stop producing a second
  base payload
- feed the composed frame into the existing downstream pipeline
- keep current product behavior as close as possible during the transition

Exit criteria:

- no code path re-resolves the base content under a `PresentationHost/base`
  namespace
- presentation open/close no longer changes base display identity

### Phase 4: Adapt Lifecycle, Focus, And Commit Integration

Goal:

- ensure the composed frame participates correctly in commit planning and
  runtime interaction

Steps:

- add any needed multi-root or synthetic-composition support in `ViewGraph`
- verify semantic extraction still applies base-interaction suppression from
  visible modal overlays
- verify local handlers and focus restoration behave correctly through the new
  seam

Exit criteria:

- lifecycle continuity characterization tests pass
- focus continuity characterization tests pass
- imperative present/dismiss flows still invalidate correctly

### Phase 5: Remove Dead Rehost Machinery And Refresh Docs

Goal:

- delete obsolete host code and document the new mental model

Steps:

- remove second-pass base hosting helpers and dead state
- document single-pass hosting in `docs/ARCHITECTURE.md` and `docs/RUNTIME.md`
- update `docs/SOURCE_LAYOUT.md` for any file moves or new support files

Exit criteria:

- the codebase has one clear presentation hosting story
- docs describe composition rather than base rehost

### Phase 6: Resume Coordinator Generalization As A Follow-On

Goal:

- return to the generic family/lane coordinator refactor on a stable foundation

Scope:

- use the April 8 plan as the follow-on plan after this prerequisite lands
- family/lane policy work should build on the stabilized composition seam rather
  than the old rehost path

## Verification Strategy

### Required Test Passes

- `swift test --filter TerminalUITests.PresentationContinuityTests`
- `swift test --filter TerminalUITests.PresentationSurfaceTests`
- `swift test --filter TerminalUITests.AppRuntimeTests`
- `swift test --filter TerminalUITests.InteractiveRuntimeTests`
- `swift test --filter TerminalUITests.Phase4ObservationAndEnvironmentTests`
- `swift test`

### Key Behavioral Outcomes

- the base subtree keeps the same effective identity across presentation toggles
- base lifecycle and task semantics do not churn when overlays appear
- overlays still hoist above clipped ancestors
- modal overlays still suppress background interaction correctly
- command palette and imperative presentation behavior remain intact
- the renderer returns to healthy steady-state incremental behavior after
  presentation dismissal

## Risks And Mitigations

### Risk: Multi-Root Composition Complicates Lifecycle Finalization

Mitigation:

- keep the first version package-only
- adapt `ViewGraph` only as much as needed to support lifecycle continuity
- use characterization tests to guard commit behavior before deleting the old
  path

### Risk: Focus Restoration Semantics Drift During The Host Rewrite

Mitigation:

- add explicit modal-dismiss focus restoration tests before the refactor
- keep modal base-suppression logic derived from visible overlay state rather
  than scattered per-family conditions

### Risk: Incremental Rendering Regresses Even If Behavior Looks Correct

Mitigation:

- include benchmark and reliability-gate scenarios that exercise repeated
  presentation toggles
- do not treat “surface output still looks right” as sufficient verification

### Risk: Scope Creep Into The Generic Coordinator Refactor

Mitigation:

- keep family/lane policy generalization out of this work
- treat the April 8 plan as a distinct follow-on effort

## Recommended PR Breakdown

1. Characterization tests only: add presentation continuity coverage without
   changing runtime behavior.
2. Composition seam extraction: isolate presentation snapshotting and add any
   package-only composition types.
3. Single-pass host switch: remove the second base resolve and wire the new
   composition path into the renderer.
4. Cleanup and docs: delete dead rehost machinery and refresh architecture
   docs.
5. Follow-on coordinator generalization: resume the April 8 plan on the stable
   host foundation.

## Relationship To Existing Plan

`docs/plans/2026-04-08-001-refactor-single-presentation-coordinator-plan.md`
should remain in place. It becomes the follow-on plan once this hosting
stabilization work lands.

If implementation discovers that some family/lane policy primitives are needed
earlier to make the composition seam tractable, add only the minimum package-only
surface needed to complete this prerequisite. Do not broaden scope into a full
generic public or package-level coordinator redesign during the hosting fix.

## Done Looks Like

This prerequisite refactor is complete when:

- the base authored tree is resolved once per frame, not once for collection and
  again for display
- presentation open/close no longer remaps the displayed base subtree into a
  synthetic identity namespace
- lifecycle, focus, and base task continuity tests pass
- existing hoisting and observation guarantees still pass
- the repo can safely resume coordinator generalization work without depending
  on the current brittle rehost seam
