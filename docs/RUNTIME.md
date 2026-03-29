# Runtime

Last updated: March 29, 2026

This document is the stable reference for runtime behavior. It captures the shipped lifecycle rules, state and observation model, input handling, and the current incremental delivery cost model.

## Runtime Shape

The runtime presents one committed frame at a time through the same strict pipeline used everywhere else:

```text
resolve -> measure -> place -> semantics -> draw -> raster -> commit
```

`RunLoop` integrates terminal I/O, invalidation scheduling, input, signals, lifecycle staging, and task reconciliation around that pure frame pipeline.

For interactive sessions, the runtime owns the terminal alternate-screen buffer while running. That gives each `WindowGroup` a clean full-canvas presentation surface and restores the previous shell buffer on exit.

## Input, Focus, And Interaction

The runtime is keyboard-first, but it is not keyboard-only.

- Keyboard input is parsed into `KeyEvent` and `InputEvent` values
- Terminals that advertise mouse reporting feed pointer-style events into the same semantic routing layer
- Focus routing remains the authoritative target-selection system for keyboard-driven interaction
- Pointer interaction augments authored controls and collections rather than replacing the focus model

That means control activation, selection changes, scrolling, and editing can all flow through the same semantic and lifecycle system regardless of whether the initiating event came from the keyboard or the mouse-reporting stream.

## Commit, Lifecycle, And Tasks

Lifecycle is identity-driven.

- An identity appears when it is present in the next committed tree but absent from the previous one
- An identity disappears when it is present in the previous committed tree but absent from the next one
- Reordering, layout movement, focus changes, clipping changes, or scroll-position changes do not count as lifecycle transitions if identity is preserved
- Off-screen or clipped nodes that remain in the tree do not disappear

`CommitPlanner` flattens lifecycle metadata from the resolved tree into `CommittedLifecycleState`, diffs that state against the previous committed frame, and emits explicit lifecycle work in `CommitPlan.lifecycle`.

### Ordering Rules

- Removal cancels any owned task before running disappear handlers
- Insertion runs appear handlers before starting any owned task
- Task replacement on a stable identity cancels the old task before starting the new one

### Task Rules

- A task starts when an identity appears with a task descriptor
- A task also starts when a stable identity gains a task descriptor
- A task survives ordinary frame updates when the identity and task descriptor are unchanged
- A task restarts when the descriptor changes on the same identity
- A task cancels when its identity disappears, when its descriptor is replaced, or when the runtime shuts down

The practical rule is simple: if identity is preserved, it is not a lifecycle transition.

## State, Environment, Observation, And Isolation

The package still uses `.defaultIsolation(.none)` in `Package.swift`. That is deliberate. The shipped model now matches SwiftUI-style authoring isolation through explicit `@MainActor` annotations rather than through blanket target isolation.

The shipped ownership model is split into three categories:

- Main-actor authoring and body evaluation:
  - `View`, `Scene`, and `App`
  - `Resolver.resolve(...)`
  - `DefaultRenderer.render(...)`
  - scene collection helpers and `WindowGroup` root-view construction
  - action-bearing authoring APIs such as `Binding.init(get:set:)`, button actions, `OpenLinkAction`, `.onAppear`, `.onDisappear`, and `.task(...)`
- Main-actor runtime coordination and ownership:
  - `RunLoop`
  - `StateContainer`
  - local action, focused-value, key, lifecycle, task, and pointer registries
  - retained frame and resolve-reuse stores
  - focus, pressed identity, lifecycle staging, and task reconciliation
  - terminal presentation commit boundaries
- Pure nonisolated frame products:
  - `ResolveContext`
  - `EnvironmentSnapshot`
  - resolved, measured, placed, semantic, draw, raster, and commit artifacts
- Genuinely concurrent I/O and host plumbing:
  - input readers
  - signal readers
  - terminal-host I/O
  - graphics or image transport support

### State Model

- `@State` persistence is keyed by view identity path plus source location
- Rebinding the same view instance into a different identity path creates a different state slot
- `StateContainer` invalidates only when an `Equatable` state change actually changes value
- Projected bindings and local actions route through the same invalidation path
- Direct local actions restore the dynamic-property scope they were registered under so mutations remain bound to the right runtime scope

### Environment Model

- `EnvironmentKey.Value` is `Sendable`
- `EnvironmentValues` stores typed sendable boxes rather than raw erased payloads
- `EnvironmentSnapshot` uses immutable value-style replacement semantics
- Style-affecting environment updates can change presentation without implying layout changes

Regression coverage exists for nested overrides, `transformEnvironment`, wrapper propagation, terminal-appearance updates, and style-only changes that preserve text layout.

### Observation Model

Observation is built on the same invalidation path as `@State`, not on a parallel runtime.

- `resolveBody` and `EnvironmentReader` track observable reads through `ObservationBridge`
- observable callbacks invalidate the exact observed identity on the main actor
- generation tracking suppresses stale callbacks from older frames
- committed-frame pruning stops removed identities from continuing to invalidate hidden subtrees
- the package provides its own `@Bindable`

Supported scenarios include body-driven reads, environment-driven observable reads, bindable editing, and rerenders after observable edits.

## Current Incremental Cost Model

The runtime is materially incremental in common steady-state paths, but it is not uniformly incremental in every case.

### Resolve

- Invalidated identities are visible in `ResolveContext`, `FrameContext`, and `FrameDiagnostics`
- Localized dirty frames can reuse clean resolved subtrees when subtree identity, environment, and transaction still match
- Resolve reuse is conservative: root-invalidated frames and fully cold frames still resolve normally

### Measure And Place

- `MeasurementCache` survives across frames
- Cache reuse is guarded by a structural input snapshot, not just identity and proposal
- `RetainedLayoutSession` can reuse clean measured and placed subtrees when the invalidation set, subtree equality, proposals, bounds, and layout behavior all allow it

### Presentation

- `WindowGroup` roots render through a full-canvas window host that sizes itself to the current terminal proposal and clips drawing to terminal bounds
- `TerminalHost` keeps the previous `RasterSurface`
- `TerminalPresentationPlanner` emits cursor-addressed incremental span updates when the previous and current surfaces are compatible
- Span updates are normalized around continuation cells to keep wide-glyph behavior safe
- `SIGWINCH` schedules a fresh frame and re-reads terminal size without exiting the run loop

### Deterministic Scenario Checks

The standing runtime checks are deterministic scenario tests rather than wall-clock benchmarks.

- Idle rerender: the second frame reuses measured and placed work and writes no bytes
- Localized subtree update: work stays concentrated on the dirty path and reused siblings stay clean
- Focused button press: the second frame remains incremental and smaller than the initial full repaint
- Single-character text input: the second frame remains incremental, though a cursor-bearing insertion can still widen to a 2-cell span
- Single-step scroll movement: still a documented conservative path and not yet a guaranteed incremental case

### Known Full-Repaint Fallbacks

- First frame, when there is no previous surface
- Surface size changes, including terminal resize
- Raster attachment changes
- Raster metadata changes
- Any host that relies on the default `TerminalHosting.present(_:)` implementation instead of `TerminalHost`
- The current `ScrollView` viewport-shift benchmark path

## Coverage Anchors

Key suites that pin this document:

- `InteractiveRuntimeTests`
- `DiagnosticsAndCacheTests`
- `Phase1BenchmarkScenariosTests`
- `Phase2CommitPlannerTests`
- `Phase2LifecycleFixtureTests`
- `Phase4ObservationAndEnvironmentTests`
- `Phase4StateReliabilityTests`
