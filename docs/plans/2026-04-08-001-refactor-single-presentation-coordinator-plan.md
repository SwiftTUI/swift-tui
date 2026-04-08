# refactor: Migrate To A Single Presentation Coordinator

Date: 2026-04-08
Plan depth: Deep
Status: Proposed

## Problem Frame

The current presentation story is split across two separate hoisting systems:

- modal-style presentation (`alert`, `confirmationDialog`, `sheet`, and
  `commandPalette`) flows through `TerminalPresentationPreferenceKey`,
  `TerminalPresentationHostingRoot`, and a kind-switched
  `TerminalPresentationSurface` in
  `Sources/View/Presentation/PresentationModifiers.swift`
- `toast` uses a second preference key, second hosting root, and its own
  overlay host in the same file
- `DefaultRenderer` nests both hosts at the root in
  `Sources/TerminalUI/TerminalUI.swift`

That shape causes three structural problems:

1. Adding a new presentation type tends to add new hoisting machinery instead of
   only adding a new authored surface.
2. Presentation coordination is partially hardcoded in view code:
   `TerminalPresentationKind`, switch-based layout and chrome, separate toast
   code paths, and root wrapper order all influence behavior.
3. Priority, exclusivity, and instance-selection behavior are implicit or
   unavailable instead of being first-class policy.

The desired end state is a single coordinator-based system that:

- hoists every presentation type through one shared path
- does not hardcode how alerts, toasts, sheets, or future surfaces are drawn
- lets presentation authors configure ordering and exclusivity across both
  families and instances
- keeps the runtime cost of adding a new presentation type as close as possible
  to “emit another request with another payload”

## Requirements Trace

This plan is driven directly by the April 8, 2026 request:

- migrate to a single presentation coordinator based system
- do not hardcode display rules for any presentation type inside the
  coordinator
- provide primitives required to author arbitrary presentation types
- allow configuration of:
  - priority order across presentation families
  - mutual exclusivity across families
  - instance-level selection such as “most recent alert only”
- make all presentation types share the same hoisting machinery
- minimize incremental runtime cost when a new presentation type is added

The migration must also preserve current repo-level guarantees already covered
by tests:

- hoisted surfaces render above clipped ancestors
- deferred builder payloads preserve original state ownership and observation
- modal-style presentation can suppress background focus
- transient surfaces can own lifecycle tasks such as toast auto-dismiss

## Current Repo Grounding

Relevant implementation files:

- `Sources/View/Presentation/PresentationModifiers.swift`
- `Sources/View/Presentation/CommandPalette.swift`
- `Sources/View/Foundation/ViewCompositionHelpers.swift`
- `Sources/TerminalUI/TerminalUI.swift`
- `Sources/TerminalUI/RunLoop+EventDispatch.swift`
- `Sources/Core/Semantics.swift`
- `Sources/Core/FocusPolicy.swift`

Relevant tests that pin current behavior:

- `Tests/TerminalUITests/PresentationSurfaceTests.swift`
- `Tests/TerminalUITests/InteractiveRuntimeTests.swift`
- `Tests/TerminalUITests/SwiftUISurfaceTests.swift`
- `Tests/TerminalUITests/Phase4ObservationAndEnvironmentTests.swift`

Important current patterns to preserve:

- deferred payload rehosting via `DeferredViewPayload` in
  `Sources/View/Foundation/ViewCompositionHelpers.swift`
- hoisting through preferences so overlays escape clipping and local layout
- root-host rewrapping in `DefaultRenderer`
- focus and hit-testing suppression driven by semantic and enabled-state rules

Important current weaknesses to fix:

- separate modal and toast hosts
- kind-switched container display logic in the host path
- no policy model for family ordering or exclusivity
- no retained activation ordering for “most recent visible instance wins”
- presentation-level dismiss behavior is fragmented instead of stack-aware

## Decisions

### 1. Replace Both Existing Hosts With One Shared Presentation Coordinator

Introduce one generic preference key, one request model, and one
`PresentationHostingRoot` that all presentation families use.

Rationale:

- one hoisting path means adding a presentation family does not require another
  root wrapper or another preference channel
- the renderer pays for shared infrastructure once per frame rather than once
  per presentation subsystem

### 2. The Coordinator Arbitrates Visibility And Base Interaction, Not Display

The coordinator should not know what an alert or a toast looks like. Each
request will carry a fully-authored deferred surface payload. The coordinator
will only:

- collect requests
- compute visible requests from policy
- order them
- determine background interaction behavior
- host the selected payloads above the base tree

Rationale:

- this makes presentation display a normal authored `View` concern
- built-in families and future families can reuse the same machinery

### 3. Use A Two-Level Policy Model: Families And Lanes

Introduce:

- `PresentationFamilyID`: logical family such as `alert`, `sheet`, `toast`, or
  `commandPalette`
- `PresentationLaneID`: hosted stratum such as `modal` or `notification`

Policy is applied in two passes:

1. family pass:
   - deduplicate or select instances within a family
   - examples: `.all`, `.latest(1)`, `.highestPriority(2)`
2. lane pass:
   - combine surviving family candidates into visible hosted requests
   - apply cross-family ordering or exclusivity within the lane
   - examples: `.all`, `.single(.highestPriorityThenMostRecent)`, `.limit(3)`

Rationale:

- family rules handle “most recent alert only”
- lane rules handle “alerts render above toasts” and “only one modal visible”
- this avoids pairwise type-specific logic inside the coordinator

### 4. Track Activation Order Explicitly Instead Of Using Tree Order

The coordinator must maintain retained activation order for each request ID so
instance-selection policies can mean true presentation recency rather than view
declaration order.

Rationale:

- “most recent alert wins” is not derivable from `PreferenceKey.reduce` order
- recency must survive across frames and state toggles

### 5. Keep The Generic Emitter Package-Only During The Migration

The generic request-emission primitive should land as a package-only seam first.
Existing public modifiers remain the canonical public API while they are
reimplemented on top of the new coordinator.

Rationale:

- this repo’s public-surface policy favors package-only internals during
  migrations
- the coordinator architecture should support future public graduation without
  forcing that API commitment in the same refactor

If the repo later wants a public generic primitive, the same internal request
model can be surfaced as a narrow `.presentation(...)` authoring API in a
follow-up change.

### 6. Coordinator-Level Key Handling Should Be Stack-Aware

Add a coordinator-owned active-presentation key path for focus-independent
presentation handlers, especially dismiss behavior such as `Esc`.

Rationale:

- dismissal is a coordinator concern when visibility is coordinator-owned
- active presentation handlers should not depend on the container itself being a
  focus region

## Target Architecture

### Generic Request Shape

The unified request model should look conceptually like this:

- stable request ID
- attachment identity
- family ID
- optional instance priority override
- deferred surface payload for the entire presentation surface
- dismiss closure
- optional presentation-scoped key handlers

The request should not contain family-specific fields such as:

- `alert` versus `sheet` enum kinds
- separate action/message/content payload arrays
- toast-only style fields
- modal-only alignment or backdrop knobs

Those concerns move into authored surface views built by the family wrapper.

### Coordinator Configuration

Introduce a package-level coordinator profile with:

- family policies:
  - lane
  - default family priority
  - instance selection policy
- lane policies:
  - z-order
  - cross-family visibility policy
  - background interaction policy

Recommended built-in default profile after the migration stabilizes:

| Family | Lane | Family selection | Default priority |
| --- | --- | --- | --- |
| `commandPalette` | `modal` | latest(1) | 300 |
| `alert` | `modal` | latest(1) | 260 |
| `confirmationDialog` | `modal` | latest(1) | 240 |
| `sheet` | `modal` | latest(1) | 200 |
| `toast` | `notification` | all | 100 |

| Lane | Visibility policy | Base interaction |
| --- | --- | --- |
| `modal` | single(highestPriorityThenMostRecent) | disable base focus and hit-testing |
| `notification` | all | passthrough |

This default profile is a product decision, not a coordinator limitation. The
coordinator should allow alternate profiles.

### Arbitration Pipeline

For each frame:

1. collect all requests from the unified preference key
2. normalize each request with family and lane defaults
3. assign activation ordinals from retained coordinator state
4. run family-level selection
5. run lane-level selection
6. sort visible requests by lane order, family priority, instance priority, and
   activation order
7. derive base interaction policy from the visible requests
8. host visible payloads in one overlay tree

### Shared Hoisting Path

`DefaultRenderer` should wrap the root once:

- old:
  - `ToastHostingRoot(TerminalPresentationHostingRoot(root))`
- new:
  - `PresentationHostingRoot(root)`

The hosted overlay container renders generic payloads only. Each built-in family
is responsible for its own alignment, backdrop, chrome, scroll bounds, and
focus scope.

### Built-In Families Become Thin Adapters

Public built-ins remain:

- `.alert(...)`
- `.confirmationDialog(...)`
- `.sheet(...)`
- `.toast(...)`
- `.commandPalette(...)`

Each one becomes:

1. a family-specific surface view
2. a package-only request emitter that registers that surface with the unified
   coordinator

That means:

- `AlertPresentationSurface` owns alert header, buttons, and bounded content
- `ToastPresentationSurface` owns toast border, icon, alignment, and lifecycle
  task
- `CommandPalettePresentationSurface` owns backdrop, search UI, and execution
  behavior

The coordinator stays unaware of all of that display logic.

## File Plan

### New Files

- `Sources/View/Presentation/PresentationCoordinator.swift`
  - unified request model
  - unified preference key
  - retained activation ordering state
  - arbitration engine
  - hosting root and overlay host
- `Sources/View/Presentation/PresentationPolicies.swift`
  - family IDs
  - lane IDs
  - family and lane policy types
  - selection and interaction policy enums

Optional split if `PresentationModifiers.swift` remains too large:

- `Sources/View/Presentation/BuiltinPresentationSurfaces.swift`
  - alert, confirmation dialog, sheet, and toast surface views

### Files To Modify

- `Sources/View/Presentation/PresentationModifiers.swift`
  - remove `TerminalPresentationKind`
  - remove type-specific request structs and toast-specific preference key
  - convert built-in modifiers to generic request emission
  - move alert, confirmation dialog, sheet, and toast chrome into family-owned
    surface views
- `Sources/View/Presentation/CommandPalette.swift`
  - emit unified presentation requests instead of modal-specific requests
  - register family metadata and modal-lane defaults
- `Sources/TerminalUI/TerminalUI.swift`
  - replace nested toast/modal hosting roots with one `PresentationHostingRoot`
- `Sources/View/Foundation/ViewCompositionHelpers.swift`
  - keep `DeferredViewPayload`
  - add any small helper needed for single-surface deferred payload emission
- `Sources/TerminalUI/RunLoop+EventDispatch.swift`
  - dispatch active presentation key handlers before focused-identity handlers
    when the coordinator has visible requests with coordinator-scoped handlers
- `Sources/Core/LocalKeyHandlerRegistry.swift`
  - extend or complement current key-dispatch infrastructure if a separate
    presentation-level registry is cleaner than reusing identity-only dispatch
- `docs/ARCHITECTURE.md`
- `docs/RUNTIME.md`
- `docs/SOURCE_LAYOUT.md`
- `docs/STATUS.md`

### Tests To Add Or Update

- `Tests/ViewTests/PresentationCoordinatorTests.swift`
  - family arbitration
  - lane arbitration
  - ordering stability
  - activation recency
- `Tests/TerminalUITests/PresentationSurfaceTests.swift`
  - one shared host path for modal and notification families
  - modal lane above notification lane
  - modal base suppression versus notification passthrough
  - clipped-ancestor hoisting still works
- `Tests/TerminalUITests/InteractiveRuntimeTests.swift`
  - `Esc` dismiss uses active presentation stack order
  - toast auto-dismiss still rerenders without input
  - command palette still opens, filters, dismisses, and executes correctly
- `Tests/TerminalUITests/SwiftUISurfaceTests.swift`
  - built-in modifiers still render expected authored surfaces through the
    unified coordinator
- `Tests/TerminalUITests/Phase4ObservationAndEnvironmentTests.swift`
  - generic deferred surface payloads still preserve original state owner and
    observation behavior

## Migration Phases

### Phase 1: Extract Shared Coordinator Infrastructure Without Changing Product Defaults

Goal:

- land one unified request and hosting pipeline
- keep built-in behavior as close as possible to current behavior while the
  plumbing changes

Steps:

- add the generic coordinator types and single hosting root
- convert modal requests and toast requests to the unified preference key
- keep current built-in wrappers but have them emit full-surface payloads
- keep the existing default ordering behavior temporarily if needed to reduce
  migration risk
- update tests to assert that all families now share one hoisting path

Exit criteria:

- `DefaultRenderer` uses one hosting root
- `toast`, `alert`, `confirmationDialog`, `sheet`, and `commandPalette` all
  flow through one preference key and one overlay host
- no built-in family depends on type-switched coordinator display code

### Phase 2: Add Family And Lane Policy Engine

Goal:

- make ordering and exclusivity declarative instead of wrapper-order driven

Steps:

- introduce family and lane policy types
- add retained activation ordering state
- implement family-level instance selection and lane-level visibility rules
- keep compatibility defaults first if the repo wants a no-behavior-change
  intermediate step

Exit criteria:

- family selection can express `latest(1)` and similar instance rules
- lane selection can express `single(...)` or `all`
- visible request order no longer depends on which root wrapper happened to run
  last

### Phase 3: Move Built-In Families Onto Recommended Defaults

Goal:

- adopt a cleaner built-in coordinator profile

Steps:

- map alert-like families into a `modal` lane
- map toasts into a `notification` lane
- make modal lane exclusive by default
- make alert-like families latest-instance-only by default
- confirm command palette behavior remains correct under modal-lane arbitration

Exit criteria:

- alerts can be configured above toasts through lane order rather than custom
  host code
- the repo can express “latest alert only” without custom alert logic
- the coordinator remains display-agnostic

### Phase 4: Unify Presentation-Level Key Handling

Goal:

- make active presentation dismissal and other stack-owned shortcuts reliable

Steps:

- add coordinator-visible key-handler registration
- dispatch from topmost visible presentation downward before normal focused
  dispatch
- move alert or sheet `Esc` dismissal off identity-local container handlers

Exit criteria:

- active modal dismissal does not depend on the modal container being focusable
- topmost visible presentation gets first shot at coordinator-level shortcuts

### Phase 5: Cleanup And Documentation

Goal:

- remove obsolete presentation machinery and document the new model

Steps:

- delete the old toast-specific preference key and host
- delete modal kind-switch coordination code
- document how to add a new family using the generic coordinator
- update architecture and runtime docs to describe family and lane arbitration

Exit criteria:

- the codebase has one canonical presentation hoisting path
- docs describe coordinator-driven presentation rather than alert-versus-toast
  special cases

## Verification Strategy

### Behavioral Scenarios

- alert, confirmation dialog, sheet, toast, and command palette still render
  through authored surfaces
- presentation surfaces still hoist above clipped ancestors
- modal presentations still suppress background focus and interaction when the
  lane policy requires it
- notification presentations leave background interaction intact when the lane
  policy requires it
- command palette retains search, focus, and execute behavior
- toast auto-dismiss remains lifecycle-task driven

### Coordinator Scenarios

- two alerts present at once with family policy `latest(1)` only show the newest
- an alert and toast present at once with modal lane above notification lane
  show both with the alert on top
- two modal families present at once with modal lane `single(...)` only show the
  winning request
- changing policy changes visibility without requiring any family-specific host
  code

### Regression Scenarios

- deferred surface payloads still preserve the original state owner
- observed models inside hosted presentation payloads still rerender correctly
- background focus suppression still comes from semantic and enabled-state rules,
  not from family-specific hacks
- the single shared coordinator does not reintroduce `AnyView`-style public
  storage seams

## Risks And Mitigations

### Risk: Recency Semantics Drift Into Tree-Order Semantics

Mitigation:

- make activation order retained coordinator state, not a byproduct of
  `PreferenceKey.reduce`
- add pure coordinator tests for “latest instance wins”

### Risk: Public API Churn While The Policy Model Is Still Settling

Mitigation:

- keep the generic emitter package-only during the migration
- preserve existing public built-in modifiers as the canonical story

### Risk: Modal Exclusivity Changes Product Behavior

Mitigation:

- stage the migration so the policy engine lands before the default profile
  changes
- if needed, carry a temporary compatibility profile in early PRs

### Risk: Coordinator Key Handling Conflicts With Focused Control Input

Mitigation:

- scope coordinator-level handlers to visible requests only
- dispatch topmost-first and stop after the first handled result
- cover command palette, editing controls, and modal dismissal in runtime tests

## Recommended PR Breakdown

1. Shared coordinator infrastructure plus single hosting root, no intentional
   default behavior changes.
2. Built-in families converted to full-surface payload emission.
3. Family and lane policy engine with coordinator arbitration tests.
4. Active-presentation key handling and `Esc` dismissal cleanup.
5. Built-in default profile switch, docs refresh, and old-code removal.

## Done Looks Like

The migration is complete when:

- the renderer hosts presentation through one root coordinator
- adding a new presentation family only requires:
  - defining a family policy entry
  - authoring a surface view
  - emitting a generic request
- the coordinator itself contains no alert-specific, sheet-specific, or
  toast-specific display branching
- priority and exclusivity behavior is expressed by policies, not wrapper order
- instance-level recency policies work independently of tree declaration order
