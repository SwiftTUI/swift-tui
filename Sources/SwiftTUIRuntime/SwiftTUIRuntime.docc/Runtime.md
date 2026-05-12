# Runtime Behavior

The shipped lifecycle rules, state and observation model, input handling, and the current incremental delivery cost model.

## Overview

This article is the stable reference for how ``RunLoop`` and the surrounding runtime behave once your authored `View`, ``Scene``, and ``App`` values have been resolved into frame artifacts.

## Runtime Shape

The runtime presents one committed frame at a time through the same strict pipeline used everywhere else:

```text
resolve -> measure -> place -> semantics -> draw -> raster -> commit
```

``RunLoop`` integrates terminal I/O, invalidation scheduling, input, signals, lifecycle staging, and task reconciliation around that pure frame pipeline.

For interactive sessions, the runtime owns the terminal alternate-screen buffer while running. That gives each ``WindowGroup`` a clean full-canvas presentation surface and restores the previous shell buffer on exit.

For the underlying phases, see <doc:Architecture>.

## Root-Hoisted Presentations

Built-in presentations — `alert`, `confirmationDialog`, `sheet`, `popover`,
`popoverTip`, menus, and `toast` — are authored inside the base view tree but
displayed through root-level composition.

- Base resolution collects presentation declarations during the ordinary resolve pass
- Portal roots reconcile those declarations, then compose visible overlay
  payloads around the resolved base tree
- Presentation hosts derive visible overlay state from the current resolved
  base declarations before overlay composition; wrapper-hosted and selectively
  re-evaluated subtrees must not wait for an outer host rerender before an
  already-declared presentation appears
- The renderer composes the base root and overlay stack for downstream measure,
  place, semantics, draw, raster, and commit work
- Opening or dismissing a presentation does not re-resolve the displayed base subtree under a synthetic identity path. Presentation churn should be transparent to the currently selected tab or child owner unless the presentation action itself mutates the state that selects different content
- Dismissing a presentation prunes only the overlay-owned subtree identities for that presentation; dismissal must not run broad stale-subtree cleanup that reaches unrelated retained content
- Modal overlays can still suppress base interaction through the composed frame's semantic state

## Input, Focus, And Interaction

The runtime is keyboard-first, but it is not keyboard-only.

- Keyboard input is parsed into `KeyEvent` and `InputEvent` values
- Terminals that advertise mouse reporting feed pointer-style events into the same semantic routing layer
- Focus routing remains the authoritative target-selection system for keyboard-driven interaction
- Pointer interaction augments authored controls and collections rather than replacing the focus model

That means control activation, selection changes, scrolling, and editing can all flow through the same semantic and lifecycle system regardless of whether the initiating event came from the keyboard or the mouse-reporting stream.

Pointer input is normalized into `PointerLocation` before dispatch. Semantic
routing uses the containing integer cell, while gestures, hover handlers, and
spatial drop destinations receive continuous cell-space `Point` values. On
cell-only terminals those points are synthesized at cell centers; native, web,
and terminal-pixel hosts can provide sub-cell locations.

The runtime writes `PointerInputCapabilities` and `CellPixelMetrics` into the
environment before each render. Use those values for optional precision
indicators or direct-manipulation affordances. Layout itself remains cell-based.

Terminal-native sessions resolve mouse precision before the event pump starts.
`TerminalMouseInputResolution.preResolved` skips probing and uses the supplied
answer. Automatic resolution requires trustworthy cell metrics, then checks
SGR-Pixels 1016 with `CSI ? 1016 $ p`, then uses the documented compatibility
matrix only when the selected `TerminalMouseInputTrustPolicy` allows it.
All-motion hover reporting is enabled only while rendered views have
`onPointerHover` subscribers, then disabled again when the subscribers
disappear.

For the deeper focus model, see the `Focus` article in the `SwiftTUIViews`
module.

## Commit, Lifecycle, And Tasks

Lifecycle is identity-driven.

- An identity appears when it is present in the next committed tree but absent from the previous one
- An identity disappears when it is present in the previous committed tree but absent from the next one
- Reordering, layout movement, focus changes, clipping changes, or scroll-position changes do not count as lifecycle transitions if identity is preserved
- Off-screen or clipped nodes that remain in the tree do not disappear

The view graph finalizes each frame into explicit lifecycle events. The commit planner only packages those events into the commit plan's lifecycle slot alongside semantic handler-installation work.

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
- Selective dirty evaluation must re-run the graph node that authored lifecycle
  metadata before committing a descendant update that would otherwise drop that
  metadata. The lifecycle identity remains the resolved node identity; the
  evaluation owner is an internal graph-retention detail.

The practical rule is simple: if identity is preserved, it is not a lifecycle transition.

## State, Environment, Observation, And Isolation

The package uses `.defaultIsolation(.none)` in its package settings. That is deliberate. The shipped model now matches SwiftUI-style authoring isolation through explicit `@MainActor` annotations rather than through blanket target isolation.

The shipped ownership model is split into three categories:

- Main-actor authoring and body evaluation:
  - `View`, ``Scene``, and ``App``
  - `Resolver.resolve(...)`
  - ``DefaultRenderer/render(_:context:proposal:collectsDiagnostics:)``
  - scene collection helpers, typed ``WindowIdentifier`` values, and ``WindowGroup`` root-view construction
  - action-bearing authoring APIs such as `Binding.init(get:set:)`, button actions, `OpenLinkAction` over typed `LinkDestination` values, `.onAppear`, `.onDisappear`, `.onChange(of:initial:_:)`, and `.task(...)`
- Main-actor runtime coordination and ownership:
  - ``RunLoop``
  - the state container
  - local action, focused-value, key, lifecycle, task, and pointer registries
  - retained frame and resolve-reuse stores
  - focus, pressed identity, lifecycle staging, and task reconciliation
  - terminal presentation commit boundaries
- Pure nonisolated frame products:
  - resolve context, environment snapshots, and resolved, measured, placed, semantic, draw, raster, and commit artifacts
- Genuinely concurrent I/O and host plumbing:
  - input readers
  - signal readers
  - terminal-host I/O
  - graphics or image transport support

### State Model

- `@State` persistence is keyed by view identity path plus source location
- Live runtime writes are additionally scoped to the view graph that registered
  the callback, so the same stateful view instance can be mounted in another
  live graph without inheriting the first graph's imperative writes
- Rebinding the same view instance into a different identity path creates a different state slot
- Keying only preserves state while the owning identity survives. State that must outlive active-tab bodies, deferred content, or presentation churn should be owned above those lazy seams and threaded down through bindings or explicit model state
- Active-tab local state may still be intentionally ephemeral across tab selection changes because `TabView` resolves only the selected body. Hoist only the state that must survive that tab churn; presentation open and close alone should not force the same reset
- The state container invalidates only when an `Equatable` state change actually changes value
- Projected bindings and local actions route through the same invalidation path
- Direct local actions restore the dynamic-property scope they were registered
  under so mutations remain bound to the right runtime graph
- Button actions, key-command handlers, dismiss closures, projected bindings, and other imperative paths must preserve that same authoring and dynamic-property scope so each path invalidates the same owner
- `@GestureState` follows the same graph-scoped binding lookup for imperative
  gesture updates, while still resetting to its construction-time seed when
  the gesture ends
- No-invalidator `DefaultRenderer` snapshots preserve same-instance test and
  preview ergonomics: if a reused view instance receives an imperative write,
  a later snapshot of that same instance can observe it even when no live
  invalidator exists

For the deeper keying tradeoffs, see the `State-Keying` article in the
`SwiftTUIViews` module.

### Environment Model

- An environment key's `Value` is `Sendable`
- Environment storage uses typed sendable boxes rather than raw erased payloads
- Environment snapshots use immutable value-style replacement semantics
- Style-affecting environment updates can change presentation without implying layout changes

Regression coverage exists for nested overrides, `transformEnvironment`, wrapper propagation, terminal-appearance updates, and style-only changes that preserve text layout.

### Observation Model

Observation is built on the same invalidation path as `@State`, not on a separate runtime.

- `resolveBody` and `EnvironmentReader` track observable reads through an internal observation bridge
- observable callbacks invalidate the exact observed identity on the main actor
- generation tracking suppresses stale callbacks from older frames
- committed-frame pruning stops removed identities from continuing to invalidate hidden subtrees
- the package provides its own `Bindable`

Supported scenarios include body-driven reads, environment-driven observable reads, bindable editing, and rerenders after observable edits.

## Incremental Delivery

The runtime is materially incremental in common steady-state paths: idle
rerenders reuse measured and placed work and write no bytes, localized subtree
updates keep work concentrated on the dirty path, and focused-button or
single-character-text-input frames remain incremental relative to the initial
paint. Full repaints still occur on first frame, surface resize, raster
attachment changes, and raster metadata changes. Terminal text and OSC 8
hyperlink destinations are sanitized at the presentation boundary before bytes
are written to the host. `SIGWINCH` schedules a fresh frame and re-reads
terminal size without exiting the run loop.

## Crash Recovery

The CLI runner installs a crash guard before the session enters raw mode. If the process crashes from `fatalError`, segmentation fault, or another fatal signal, the guard resets the terminal (disables mouse reporting, shows the cursor, resets style, exits the alternate screen, restores termios) before re-raising the signal. The terminal is left usable instead of stuck in raw mode.

## See Also

- <doc:Architecture>
- <doc:Vision>
- <doc:Host-Integration>
- <doc:Running-Apps>
- [Runtime details](https://github.com/adamz/swift-tui/blob/main/docs/RUNTIME.md)
