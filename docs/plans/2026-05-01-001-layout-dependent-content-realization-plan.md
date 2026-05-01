---
title: "refactor: add layout-dependent content realization"
type: refactor
status: shipped
date: 2026-05-01
proposal: "../../LAYOUT-RESOLVE-SPLIT.md"
---

# refactor: add layout-dependent content realization

## Overview

Remove the framework-level layout/resolve limitation that makes local geometry
available only when resolve-time environment shims happen to mirror later layout
proposals.

The target design is a generalized layout-time content realization seam:

```
resolve -> static resolved nodes plus layout-dependent boundaries
measure/place -> realize boundary content with actual layout geometry when needed
semantics/draw/raster -> consume the fully realized placed tree
commit -> publish runtime side effects exactly once
```

`GeometryReader` should be the first public adopter, but it must not be the
architecture. The same seam should be able to support geometry-bound
preferences, coordinate-space anchors, decoration content that depends on
primary geometry, and future terminal-native geometry APIs.

This is a pre-release hard migration. Source compatibility and migration size
are not decision constraints. The final state should be coherent and
SwiftUI-shaped, not a larger collection of special-case terminal geometry
bridges.

## Source Inputs

Primary local source:

- [`../../LAYOUT-RESOLVE-SPLIT.md`](../../LAYOUT-RESOLVE-SPLIT.md)

Related architecture records:

- [`../ASYNC_RENDERING.md`](../ASYNC_RENDERING.md)
- [`../proposals/OFF_MAIN_PIPELINE_RENDERING.md`](../proposals/OFF_MAIN_PIPELINE_RENDERING.md)
- [`../proposals/CUSTOM_LAYOUT_OFF_MAIN_ISOLATION.md`](../proposals/CUSTOM_LAYOUT_OFF_MAIN_ISOLATION.md)
- [`2026-04-26-002-frame-head-abort-plan.md`](2026-04-26-002-frame-head-abort-plan.md)
- [`../proposals/FRACTIONAL_COORDINATE_SPACE.md`](../proposals/FRACTIONAL_COORDINATE_SPACE.md)
- [`../SWIFTUI_LAYOUT.md`](../SWIFTUI_LAYOUT.md)
- [`../proposals/layout/BEHAVIOUR_FINDINGS.md`](../proposals/layout/BEHAVIOUR_FINDINGS.md)

SwiftUI reference points:

- [`GeometryReader`](https://developer.apple.com/documentation/swiftui/geometryreader)
  is documented as content defined from the reader's own size and coordinate
  space.
- [`GeometryProxy`](https://developer.apple.com/documentation/swiftui/geometryproxy)
  exposes size, safe-area insets, frames, coordinate-space conversion, and
  anchor resolution.
- [`Layout`](https://developer.apple.com/documentation/swiftui/layout) and
  [`LayoutSubview.place(at:anchor:proposal:)`](https://developer.apple.com/documentation/swiftui/layoutsubview/place%28at%3Aanchor%3Aproposal%3A%29)
  make proposal and placement a layout-owned conversation through subview
  proxies.
- [`anchorPreference(key:value:transform:)`](https://developer.apple.com/documentation/swiftui/view/anchorpreference%28key%3Avalue%3Atransform%3A%29)
  is explicitly geometry-bound and resolved through later coordinate-space
  conversion.
- [`visualEffect(_:)`](https://developer.apple.com/documentation/SwiftUI/View/visualEffect%28_%3A%29)
  and [`onGeometryChange(for:of:action:)`](https://developer.apple.com/documentation/swiftui/view/ongeometrychange%28for%3Aof%3Aaction%3A%29)
  are examples of geometry-aware APIs that do not ask ordinary body evaluation
  to guess layout results during initial resolve.
- [WWDC22 "Compose custom layouts with SwiftUI"](https://developer.apple.com/videos/play/wwdc2022/10056/)
  distinguishes downward geometry flow from upward measurement-driven layout.

The Apple sources do not expose SwiftUI's private implementation phases. The
plan therefore targets the public semantic model rather than claiming to clone
SwiftUI internals.

## Implementation Status

Shipped implementation:

- Core carries `ResolvedNode.layoutDependentContent` as a sibling field rather
  than a new `LayoutBehavior` case.
- Measurement uses an explicit sizing policy and does not realize authored
  content. Placement realizes content from final bounds, safe-area insets, cell
  metrics, and pointer capabilities.
- `GeometryReader` is the first public adopter. It uses a `10x10` ideal for
  unspecified dimensions, remains flexible in stacks, and reports placement
  geometry rather than a resolve-time `EnvironmentValues.terminalSize` shim.
- Runtime registration restoration now includes command and drop handlers, and
  graph restoration can publish the finalized realized subtree instead of a
  partial draft snapshot.
- Frame diagnostics expose layout-dependent realization counts, cache hits, and
  main-actor fallback counts. Async frame-tail layout falls back to the main
  actor when arbitrary authored content realization is present, while static
  and `SendableLayout` worker paths remain eligible.
- Static proposal-transforming modifiers no longer rewrite `terminalSize`;
  that environment value is host/root surface metadata. Local geometry comes
  from layout proposals and placed bounds.
- `ViewThatFits` commits only the selected candidate's realized geometry
  content; unselected geometry candidates may be measured without publishing
  lifecycle, task, gesture, semantic, command, or drop side effects.
- Ordinary preferences remain resolve-time. Public anchor and geometry-bound
  preference APIs remain deferred until coordinate-space resolution is ready.

Verification:

- Focused layout-dependent geometry, safe-area, `ViewThatFits`, async fallback,
  graph registration restoration, gallery physics, and layout example tests
  passed.
- `bun run test` passed after implementation.

## Problem Frame

Today `GeometryReader` is resolved before layout. It builds `GeometryProxy.size`
from `EnvironmentValues.terminalSize`, then resolves its authored content
immediately. Later, `LayoutEngine` computes the actual child proposal.

The recent static fixes improved the common cases where a wrapper can know its
child proposal during resolve. They do not remove the structural gap:

- `EnvironmentValues.terminalSize` still acts as both root host-surface size and
  local geometry proposal.
- Every deterministic proposal-transforming modifier must remember to rewrite
  that environment field.
- Measurement-dependent containers cannot always know the child proposal during
  resolve.
- Geometry-bound content that is built during layout needs identity, state,
  dependency tracking, runtime registrations, retained reuse, and async
  frame-tail ownership rules.

The full fix is to stop treating environment as the source of local layout
truth. The source of local layout truth is the proposal, bounds, placement,
safe-area, and coordinate-space information known during measurement and
placement.

## Requirements Trace

- R1. Remove the hidden contract that local geometry requires resolve-time
  `terminalSize` mutation by every proposal-transforming wrapper.
- R2. Preserve a SwiftUI-shaped authoring model: `View.body` stays ordinary
  view evaluation; layout-owned APIs expose geometry through proxies and
  controlled callbacks.
- R3. Keep `GeometryReader` flexible and downward-flowing: its content may adapt
  to the reader's final container geometry, but should not be the mechanism for
  measuring children to influence ancestors.
- R4. Provide one reusable internal seam for all layout-dependent content, not a
  one-off `GeometryReader` fix.
- R5. Keep `@State`, dynamic properties, observation dependencies, lifecycle,
  tasks, gestures, focus, commands, and other runtime registrations stable and
  committed exactly once per frame.
- R6. Preserve current layout correctness for static containers, measurement-
  dependent containers, custom `Layout`, and worker-safe `SendableLayout`.
- R7. Preserve ordered async frame commit. Do not reintroduce the reverted
  frame-head abort failure mode.
- R8. Make worker fallback visible in diagnostics when layout-dependent content
  forces main-actor layout.
- R9. Remove or rename the overloaded local-geometry use of
  `EnvironmentValues.terminalSize`.
- R10. Update docs, examples, fixtures, and tests to assert layout-time geometry
  rather than resolve-time geometry.

## Scope

In scope:

- `Sources/View/GeometryReading/GeometryReader.swift`
- `Sources/View/Environment/StyleEnvironment.swift`
- `Sources/View/ViewModifiers.swift`
- `Sources/View/Modifiers/Preference.swift`
- `Sources/View/Layout/Layout.swift`
- `Sources/Core/LayoutTypes.swift`
- `Sources/Core/LayoutEngine.swift`
- `Sources/Core/LayoutEngine+Placement.swift`
- `Sources/Core/RenderTreeAndSemanticsTypes.swift`
- `Sources/Core/Graph/ViewGraph.swift`
- `Sources/Core/Graph/ViewNode.swift`
- `Sources/Core/RuntimeRegistrationSet.swift`
- `Sources/TerminalUI/TerminalUI.swift`
- `Sources/TerminalUI/RunLoop+Rendering.swift`
- layout, geometry, async-rendering, and interactive runtime tests under
  `Tests/CoreTests/`, `Tests/ViewTests/`, and `Tests/TerminalUITests/`

Out of scope for the first implementation pass:

- moving arbitrary `View.body` evaluation off-main,
- making every public `Layout` automatically worker-safe,
- adding complete public anchor-preference APIs before the coordinate-space
  foundation is ready,
- adding frame dropping or completed-worker cancellation,
- preserving source compatibility for the old `terminalSize` local geometry
  behavior.

## Architecture Direction

Introduce an internal value that resolve can emit but layout owns:

```
LayoutDependentContentBoundary
```

The exact names can change, but the model should have these parts:

- stable boundary identity,
- an authored content evaluator captured during resolve,
- an environment and transaction snapshot,
- a geometry input contract,
- a sizing policy,
- a realization cache keyed by identity, environment dependencies, state
  dependencies, and geometry signature,
- draft runtime-registration and lifecycle staging,
- explicit worker eligibility.

The boundary appears in the resolved tree as a normal layout participant. Its
children are not fully known until the layout phase provides the required
geometry.

For `GeometryReader`, the sizing policy should be independent of realized
content:

```
measure GeometryReader boundary:
  return proposed size, replacing unspecified dimensions with terminal-native
  defaults consistent with current flexible-reader behavior

place GeometryReader boundary:
  build GeometryProxy from final bounds/proposal/safe-area/coordinate-space data
  realize content(proxy)
  measure/place realized content inside the reader's bounds
```

For future geometry-bound APIs, other sizing policies may be needed:

- realize on measurement when content size contributes to the parent,
- realize on placement when content only adapts to assigned geometry,
- realize after placement for effect-only or preference-only APIs,
- publish a geometry change to next-frame state rather than changing the current
  layout.

These policies must be explicit. Hidden re-entry into body evaluation from
arbitrary layout code should not become the default.

## Key Decisions

### Decision 1: Generalized boundary, not `GeometryReader` special casing

`GeometryReader` is only one symptom. The same structural gap exists anywhere a
view closure needs geometry that layout has not computed yet. A generalized
boundary lets the framework solve the class of problem once.

### Decision 2: Main-actor realization first

Arbitrary authored content realization must run on the main actor because
`View.body`, dynamic properties, observation, state slots, focus, lifecycle,
tasks, gestures, commands, and runtime registrations are main-actor-owned today.

Worker layout can remain available for pure static trees and explicit
`SendableLayout` cases. A boundary that requires arbitrary view realization
should force main-actor fallback until there is a separate, proven snapshot
model.

### Decision 3: Draft side effects are mandatory

Layout may measure a child multiple times, place it more than once, or discard a
candidate. Realizing view content during those operations must not mutate live
runtime registries directly.

The implementation needs a draft transaction that records new registrations and
graph effects, then installs only the committed result. The frame-head abort
post-mortem shows that draft data cannot become the source of truth for live
registries; commit must restore from the finalized graph plus new committed
registrations.

### Decision 4: `terminalSize` stops being local proposal

`EnvironmentValues.terminalSize` should represent the host/root terminal
surface, or be renamed to make that role explicit. Local geometry should come
from layout geometry. Static proposal shims may remain temporarily during
migration, but the final design should delete the hidden dual meaning.

### Decision 5: Anchor and coordinate-space work becomes part of the same seam

SwiftUI's anchor preferences and geometry proxy are tied to coordinate spaces.
TerminalUI already defers anchor-based preference APIs until local coordinate
spaces and anchor resolution ship. The layout-dependent boundary should be
designed with coordinate-space conversion in mind even if public anchors ship in
a later phase.

## Implementation Strategy

Do the work in vertical phases that compile and test at each boundary. Start
with infrastructure and one adopter, then remove the old bridge only after the
new seam has enough coverage to carry the framework.

## Phase 0: Baseline And Characterization

### Objective

Record the current behavior and pin the desired SwiftUI-shaped behavior before
changing architecture.

### Work

- Confirm the full test baseline with `bun run test`.
- Add or preserve focused characterization tests for:
  - root `GeometryReader` reports terminal surface geometry,
  - `GeometryReader` inside exact frame,
  - `GeometryReader` inside flexible finite frame,
  - `GeometryReader` inside padding and safe-area padding,
  - `GeometryReader` inside `safeAreaInset`,
  - `GeometryReader` inside `ViewThatFits`,
  - `GeometryReader` inside custom `Layout` that measures under one proposal and
    places under another,
  - repeated measurement of the same geometry boundary does not duplicate tasks
    or lifecycle registrations.
- Add a small SwiftUI comparison note to this plan or a companion test comment
  for the custom-layout measure/place case. Treat it as semantic evidence, not
  as a conformance oracle.

### Likely files

- `Tests/TerminalUITests/GeometryReaderSurfaceTests.swift`
- `Tests/TerminalUITests/SafeAreaSurfaceTests.swift`
- `Tests/TerminalUITests/ViewThatFitsSurfaceTests.swift`
- `Tests/ViewTests/LayoutProtocolTests.swift`
- `Tests/TerminalUITests/AsyncFrameTailRenderingTests.swift`
- `docs/proposals/layout/BEHAVIOUR_FINDINGS.md`

### Acceptance

- Baseline pass/fail status is known.
- Current static bridge behavior is pinned.
- At least one failing or skipped characterization exists for a
  measurement-dependent case that the full fix intends to make pass.

## Phase 1: Frame Draft And Runtime Registration Staging

### Objective

Create the safety layer that allows view content to be realized during layout
without duplicating or prematurely committing runtime side effects.

### Work

- Introduce a draft registration channel for layout-time realization.
- Ensure draft registration captures:
  - action handlers,
  - key commands,
  - pointer handlers,
  - gesture handlers and gesture-state bindings,
  - focus registrations,
  - scroll registrations,
  - lifecycle handlers,
  - tasks,
  - commands,
  - drop destinations,
  - preference observations.
- At frame finish, apply live mutations and restore committed registrations
  from the finalized graph, not from a partial draft snapshot.
- Keep synchronous rendering behavior unchanged.
- Add diagnostics to distinguish:
  - no layout realization,
  - layout realization on main actor,
  - worker fallback caused by layout realization,
  - repeated realization count for a boundary.

### Likely files

- `Sources/Core/RuntimeRegistrationSet.swift`
- `Sources/Core/Graph/ViewGraph.swift`
- `Sources/Core/Graph/ViewNode.swift`
- `Sources/TerminalUI/TerminalUI.swift`
- `Sources/TerminalUI/RunLoop+Rendering.swift`
- `Sources/TerminalUI/FrameDiagnosticsLogger.swift`

### Tests

- `Tests/TerminalUITests/GestureTeardownTests.swift`
- `Tests/TerminalUITests/InteractiveRuntimeTests.swift`
- `Tests/TerminalUITests/AsyncFrameTailRenderingTests.swift`
- new focused tests for draft registration install/rollback behavior

### Acceptance

- Runtime registrations remain equivalent to the finalized committed graph.
- Repeated draft realization does not duplicate lifecycle or task effects.
- Interactive scroll/click/drag behavior is manually checked in the gallery demo
  before this phase is considered complete.

## Phase 2: Add Layout-Dependent Boundary Infrastructure

### Objective

Teach the resolved tree and layout engine to carry a placeholder boundary that
can produce children during layout using concrete geometry.

### Work

- Add a boundary representation to Core:
  - `LayoutBehavior.layoutDependentContent(...)`, or
  - a sibling field on `ResolvedNode` if that keeps layout behavior cleaner.
- Add a View-layer handle that can realize authored content on the main actor.
- Add a `LayoutRealizationContext` carrying:
  - boundary identity,
  - environment snapshot,
  - transaction snapshot,
  - proposed size,
  - final bounds,
  - safe-area insets,
  - cell pixel metrics,
  - pointer input capabilities,
  - coordinate-space transform data as it becomes available.
- Add realization cache invalidation keyed by:
  - boundary identity,
  - geometry signature,
  - environment dependencies,
  - observed object dependencies,
  - state-slot dependencies,
  - transaction properties that affect layout or drawing.
- Mark retained-reuse support conservatively until the realized shape is stable.
- Make layout measurement and placement able to request realization through the
  boundary handle.

### Likely files

- `Sources/Core/LayoutTypes.swift`
- `Sources/Core/LayoutEngine.swift`
- `Sources/Core/LayoutEngine+Placement.swift`
- `Sources/Core/RenderTreeAndSemanticsTypes.swift`
- `Sources/View/Environment/ResolveContext.swift`
- `Sources/View/Layout/Layout.swift`
- new package-internal file under `Sources/View/GeometryReading/` or
  `Sources/View/Layout/`

### Tests

- `Tests/CoreTests/LayoutEngineTests.swift`
- `Tests/CoreTests/RetainedLayoutReuseTests.swift`
- `Tests/ViewTests/ObservationDependencyTests.swift`
- new tests for boundary identity and cache invalidation

### Acceptance

- Static trees are unaffected.
- A package-internal test boundary can realize content during placement.
- State under the boundary persists across geometry changes.
- Changing geometry invalidates only the boundary subtree that depends on it.
- Worker layout falls back with a diagnostic when arbitrary realization is
  required.

## Phase 3: Move `GeometryReader` Onto The Boundary

### Objective

Make `GeometryReader` report layout-time geometry rather than resolve-time
environment geometry.

### Work

- Change `GeometryReader.resolveElements(in:)` to emit a layout-dependent
  boundary instead of immediately calling `content(proxy)`.
- Define `GeometryReader` sizing semantics:
  - finite proposal: occupy that proposal,
  - unspecified dimension: use existing terminal-native flexible default,
  - final placement: realize content with final reader size and safe-area data.
- Build `GeometryProxy` from layout geometry:
  - `size`,
  - `safeAreaInsets`,
  - `cellPixelMetrics`,
  - `pointerInputCapabilities`,
  - future coordinate-space and anchor access.
- Preserve the existing top-leading flexible content placement unless a
  deliberate SwiftUI-shape correction is chosen and documented.
- Remove `GeometryReader` dependency on local `terminalSize` proposal rewriting.

### Likely files

- `Sources/View/GeometryReading/GeometryReader.swift`
- `Sources/Core/LayoutEngine.swift`
- `Sources/Core/LayoutEngine+Placement.swift`
- `Sources/View/Environment/StyleEnvironment.swift`
- `Tests/TerminalUITests/GeometryReaderSurfaceTests.swift`

### Tests

- Root geometry still reports terminal surface size.
- Exact and flexible frames report the actual placed reader size.
- Padding and safe-area padding report the actual placed reader size.
- `safeAreaInset` reports the measured/placed local geometry.
- A custom `Layout` that measures under one proposal and places under another
  causes `GeometryReader` content to see the placement proposal.
- Measuring the reader multiple times does not evaluate content multiple times
  unless the sizing policy explicitly requires it.
- State inside `GeometryReader` content persists across resize.

### Acceptance

- The spinner-style bug is fixed without any static environment shim.
- Measurement-dependent containers no longer need bespoke `terminalSize`
  forwarding for `GeometryReader`.
- The old geometry bridge can be deleted for `GeometryReader` without regressing
  root geometry behavior.

## Phase 4: Convert Geometry-Bound Preferences And Decorations

### Objective

Move geometry-bound preference and decoration surfaces toward the same layout
realization model, so overlays and backgrounds can depend on measured/placed
primary geometry without resolve-time guessing.

### Work

- Keep ordinary value preferences resolve-time for now.
- Add internal support for geometry-bound preferences whose values are produced
  from anchors or layout geometry.
- Split preference reduction into:
  - resolve-time value preferences,
  - layout/post-layout geometry preferences.
- Change `overlayPreferenceValue` and `backgroundPreferenceValue` only where
  necessary to avoid reading geometry-dependent values before placement.
- Prepare the storage model needed for future public `anchorPreference` and
  `transformAnchorPreference`.
- Ensure decoration children that depend on primary measured size or placement
  can be realized after primary geometry is known.

### Likely files

- `Sources/View/Modifiers/Preference.swift`
- `Sources/Core/PreferenceValues.swift`
- `Sources/Core/LayoutEngine.swift`
- `Sources/Core/LayoutEngine+Placement.swift`
- `Sources/Core/RenderTreeAndSemanticsTypes.swift`
- new anchor/coordinate-space support files if Phase 4 includes public API

### Tests

- `Tests/ViewTests/PreferenceTests.swift`
- `Tests/TerminalUITests/OverlayPreferenceTests.swift`
- new tests for geometry-dependent overlay/background placement
- future anchor tests once local coordinate spaces exist

### Acceptance

- Ordinary preferences retain current behavior.
- Geometry-bound preferences are not reduced from stale resolve-time geometry.
- Overlay/background content can depend on placed primary geometry without
  duplicate registration effects.

## Phase 5: Audit And Convert Measurement-Dependent Containers

### Objective

Remove remaining framework assumptions that layout-dependent local geometry must
be represented by environment mutation.

### Work

- Audit all `LayoutBehavior` cases:
  - `.padding`,
  - `.safeAreaIgnoring`,
  - `.safeAreaInset`,
  - `.border`,
  - `.frame`,
  - `.flexibleFrame`,
  - `.decoration`,
  - `.viewThatFits`,
  - `.custom`.
- For each case, decide whether it:
  - only transforms child proposal deterministically,
  - needs measurement before child geometry is known,
  - needs placement before child geometry is known,
  - can remain purely static.
- Update `safeAreaInset` so base and inset content see the geometry that layout
  actually computes.
- Update decorations so secondary content can use primary size/placement through
  the boundary seam.
- Update `ViewThatFits` selection semantics:
  - selected candidate should determine committed semantic/draw output,
  - unselected candidates should not leak committed lifecycle or registrations,
  - behavior for state retention in unselected candidates must be documented.
- Update custom `Layout` interaction:
  - ordinary public `Layout` may trigger main-actor boundary realization,
  - `SendableLayout` remains worker-safe only when its subtrees do not require
    arbitrary main-actor realization or when a future snapshot contract permits
    it.

### Likely files

- `Sources/Core/LayoutEngine.swift`
- `Sources/Core/LayoutEngine+Placement.swift`
- `Sources/Core/LayoutEngine+Stack.swift`
- `Sources/View/Layout/Layout.swift`
- `Sources/View/ViewModifiers.swift`
- `Sources/View/Containers/ViewThatFits.swift`
- `Sources/View/SafeArea/`
- `Sources/View/Containers/ScrollView/`

### Tests

- `Tests/TerminalUITests/SafeAreaSurfaceTests.swift`
- `Tests/TerminalUITests/ViewThatFitsSurfaceTests.swift`
- `Tests/ViewTests/LayoutProtocolTests.swift`
- `Tests/TerminalUITests/ScrollViewSurfaceTests.swift`
- focused tests for unselected `ViewThatFits` side effects
- focused tests for custom `Layout` measure/place proposal divergence

### Acceptance

- No measurement-dependent container relies on local geometry through
  `terminalSize`.
- Selected/unselected candidate behavior is explicit and tested.
- Worker fallback is predictable and recorded in diagnostics.

## Phase 6: Remove The Resolve-Time Geometry Bridge

### Objective

Delete the old local proposal bridge and make host surface size distinct from
local layout geometry.

### Work

- Rename or narrow `EnvironmentValues.terminalSize` so it means root host
  surface only.
- Remove helper code that tightens `terminalSize` for static proposal
  transforms, unless kept temporarily behind migration-only tests.
- Update environment docs to distinguish:
  - host/root terminal surface,
  - local layout proposal,
  - placed bounds,
  - safe-area insets,
  - cell pixel metrics.
- Update public docs for `GeometryProxy.size`.
- Update all tests that manually set `terminalSize` as local geometry input.

### Likely files

- `Sources/View/Environment/StyleEnvironment.swift`
- `Sources/View/ViewModifiers.swift`
- `Sources/TerminalUI/RunLoop+Rendering.swift`
- `docs/RUNTIME.md`
- `docs/SWIFTUI_LAYOUT.md`
- `docs/PUBLIC_API_BASELINE.md`
- `LAYOUT-RESOLVE-SPLIT.md`

### Tests

- full geometry reader surface suite,
- environment invalidation tests,
- interactive runtime tests that set terminal size,
- public API baseline regeneration if public names change.

### Acceptance

- `GeometryReader` never reads local geometry from `terminalSize`.
- Static proposal wrappers no longer need environment bridge tests.
- `terminalSize` naming and documentation no longer imply local proposal.

## Phase 7: Async And Worker Eligibility Hardening

### Objective

Keep async rendering correct after layout can realize content.

### Work

- Ensure frame-tail input records whether unresolved layout-dependent boundaries
  are present.
- Ensure worker layout rejects or falls back for frames that require main-actor
  realization.
- Preserve ordered commit.
- Add diagnostics for:
  - layout realization count,
  - realization duration,
  - worker fallback reason,
  - boundary cache hit/miss,
  - committed vs discarded candidate count.
- Revisit stale-frame cancellation only after draft-only side effects are proven
  under layout realization. Do not revive the reverted frame-head abort design
  unchanged.

### Likely files

- `Sources/TerminalUI/TerminalUI.swift`
- `Sources/TerminalUI/RunLoop+Rendering.swift`
- `Sources/TerminalUI/FrameDiagnosticsLogger.swift`
- `Sources/Core/FrameDropEligibility.swift`
- `Tests/TerminalUITests/AsyncFrameTailRenderingTests.swift`

### Tests

- sync/async parity for geometry reader,
- worker fallback when geometry realization is present,
- worker path still used for static/sendable layouts,
- retained reuse remains correct across resize,
- manual gallery validation for scrolling, clicking, and dragging.

### Acceptance

- Geometry realization does not regress async ordered commit.
- Worker diagnostics clearly explain why a frame did or did not offload layout.
- `bun run test` passes.

## Phase 8: Documentation, Examples, And Migration Notes

### Objective

Make the new contract clear and remove guidance that normalizes the old
structural limitation.

### Work

- Update `LAYOUT-RESOLVE-SPLIT.md` from issue note to implementation history.
- Update `docs/SWIFTUI_LAYOUT.md` with the final geometry contract.
- Update `docs/RUNTIME.md` phase ownership.
- Update `docs/ASYNC_RENDERING.md` if worker fallback or diagnostics change.
- Update examples that used `GeometryReader` defensively around static frames.
- Add migration notes:
  - `terminalSize` is root/host surface, not local geometry,
  - use `GeometryReader` for downward geometry adaptation,
  - use `Layout` for child measurement that affects ancestors,
  - use future anchor/geometry preferences for post-layout coordinate reporting.

### Acceptance

- Docs describe the final model, not the transitional bridge.
- Examples demonstrate correct terminal-native geometry usage.
- Public API baseline and source-layout docs are updated where needed.

## Open Questions

### OQ1: GeometryReader unspecified-size default

SwiftUI `GeometryReader` has flexible preferred size. TerminalUI needs a
terminal-native rule for unspecified dimensions. The implementation should
preserve current useful behavior unless characterization shows it is already
non-SwiftUI-shaped in a user-visible way.

### OQ2: Evaluation timing for `GeometryReader` content

Empirical SwiftUI probes suggest content is evaluated with placement geometry,
not every measurement proposal. Apple docs do not state this as an implementation
phase guarantee. TerminalUI should adopt the semantic result: reader content
adapts downward to its container geometry and does not drive the reader's own
parent measurement.

### OQ3: `ViewThatFits` side effects

The desired behavior for unselected candidates needs care. The likely contract
is that unselected candidates may be measured but should not commit lifecycle,
tasks, gestures, or semantics. Whether state should be retained for candidates
across selection changes should be investigated and documented before Phase 5
lands.

### OQ4: Anchor preferences before coordinate spaces

The boundary should be designed for anchor resolution, but public anchor APIs can
remain deferred until local coordinate spaces exist. Avoid baking a geometry
preference model that cannot support anchors later.

### OQ5: Cache granularity

Realized subtree caching should be conservative at first. Over-caching can
produce stale geometry; under-caching costs performance but is easier to reason
about. Start with correctness and add diagnostics before optimizing.

### OQ6: Interaction with retained tree reuse

`ResolvedNode.supportsRetainedReuse` currently assumes children are known after
resolve except for a few special cases. Layout-dependent boundaries need their
own reuse rule and tests, especially when geometry changes but identity and
state should persist.

## Verification Matrix

Focused checks by phase:

- `swiftly run swift test --filter TerminalUITests.GeometryReaderSurfaceTests`
- `swiftly run swift test --filter TerminalUITests.SafeAreaSurfaceTests`
- `swiftly run swift test --filter TerminalUITests.ViewThatFitsSurfaceTests`
- `swiftly run swift test --filter TerminalUITests.AsyncFrameTailRenderingTests`
- `swiftly run swift test --filter TerminalUITests.InteractiveRuntimeTests`
- `swiftly run swift test --filter ViewTests`
- `swiftly run swift test --filter CoreTests`

Final gate:

```bash
bun run test
```

Manual validation required before completion:

- Run the gallery demo in a real terminal.
- Scroll a tab.
- Click buttons.
- Drag sliders or scroll indicators.
- Resize the terminal around a `GeometryReader` demo.
- Compare sync and async runtime behavior where diagnostics show worker fallback.

## Completion Criteria

This plan is complete when:

- `GeometryReader` reports layout-time local geometry in static and
  measurement-dependent containers.
- Local geometry no longer depends on mutating `EnvironmentValues.terminalSize`
  before resolve.
- Runtime side effects from layout-realized content are staged and committed
  exactly once.
- Worker layout eligibility remains explicit and diagnostics-backed.
- Geometry-bound preference and decoration foundations use the same seam or are
  explicitly deferred with compatible storage.
- Docs and tests describe the final model.
- `bun run test` passes.
