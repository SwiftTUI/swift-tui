# State, Environment, And Focus

## Overview

SwiftTUI keeps state, observation, environment, and focus on one runtime
invalidation path.

That gives the framework a few important properties:

- local `@State` changes rerender the same way observable writes do
- focus changes feed the same semantic system that keyboard interaction uses
- environment reads stay in authored view composition, not out-of-band
  configuration

## State

Use ``State`` for local value ownership. Use ``Binding`` to project a value
into child views.

`@State` storage is owned by a runtime `ViewNodeID` and a source-location
ordinal, scoped to the active view graph. Unkeyed owners follow their
`StructuralPath` in the resolved tree. Explicit `.id(...)` values and
`ForEach` data keys produce an `EntityIdentity`. This identity can route the
same owner across structural moves. A change to the explicit id creates a new
owner.

Interactive runtime callbacks are additionally scoped to the view graph that
registered them. Projected bindings, button actions, key commands, dismiss
closures, and gesture updates continue to mutate their original runtime graph.
They do so even when another graph reuses the same view value. No-invalidator
`DefaultRenderer` snapshots preserve test ergonomics by letting a reused view
instance carry imperative writes into a later snapshot of that same instance.

## Observation

Use repository-owned ``Bindable`` with `Observation` models for editable
bindings into observable reference types.

SwiftTUI tracks observable reads through the runtime invalidation bridge.
Observable writes invalidate the exact identities that observed them. They do
not use a second rendering system.

Observable model writes may happen off the main actor, as in SwiftUI's
background-task model writes. The bridge accepts the change from any
executor, wakes the scheduler, and applies the invalidation on the main actor
at the next frame head. `@State` and `Binding` writes remain main-actor-only,
enforced at compile time.

## Environment

Use ``Environment`` or ``EnvironmentReader`` with ``EnvironmentValues`` for
values that descend through the tree. Use ``GeometryReader`` for authored
content that responds to geometry from layout. A reader at the root receives
the root terminal geometry.

Environment updates can affect:

- styling and appearance
- focus affordances
- enabled or disabled state
- terminal-specific presentation details

Environment writes are part of authored structure. They are not a late-stage
rendering override.

Runtime-injected environment actions expose host-owned verbs without putting
host mechanics in views. ``EnvironmentValues/requestTermination`` asks the
active session to end through the same ``View/onTerminationRequest(perform:)``
policy used for exit keys and signals. For example:

```swift
struct QuitButton: View {
  @Environment(\.requestTermination) private var requestTermination

  var body: some View {
    Button("Quit") { _ = requestTermination() }
  }
}
```

``EnvironmentValues/terminalHandoff`` temporarily restores the user's terminal
while an asynchronous external operation runs. The “Terminal Handoffs” guide
in `SwiftTUIRuntime` describes the ownership and restoration contract.

## Focus

Use ``FocusState`` to model authored focus ownership. Use ``FocusedValue`` or
``FocusedBinding`` to export context from the focused subtree.

The runtime is keyboard-first, but focus also matters for:

- selecting the control that reacts to key events
- routing focused-value data to tool panels or status bars
- coordinating editable controls with selection or activation behavior

## Related Symbols

- ``State``
- ``Binding``
- ``Bindable``
- ``Environment``
- ``EnvironmentValues``
- ``EnvironmentReader``
- ``GeometryReader``
- ``FocusState``
- ``FocusedValue``
- ``FocusedBinding``
- ``RequestTerminationAction``
- ``TerminalHandoffAction``
