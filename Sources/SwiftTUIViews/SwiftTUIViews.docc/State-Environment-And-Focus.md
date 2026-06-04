# State, Environment, And Focus

## Overview

SwiftTUI keeps state, observation, environment, and focus on one runtime invalidation path.

That gives the framework a few important properties:

- local `@State` changes rerender the same way observable writes do
- focus changes feed the same semantic system that keyboard interaction uses
- environment reads stay part of authored view composition instead of becoming out-of-band configuration

## State

Use ``State`` for local value ownership and ``Binding`` for projection into child views.

`@State` storage is owned by a runtime `ViewNodeID` and a source-location
ordinal, scoped to the active view graph. Unkeyed owners follow their
`StructuralPath` in the resolved tree. Explicit `.id(...)` values and
`ForEach` data keys produce an `EntityIdentity` that can route the same owner
across structural moves, while changing the explicit id creates a new owner.

Interactive runtime callbacks are additionally scoped to the view graph that
registered them. Projected bindings, button actions, key commands, dismiss
closures, and gesture updates therefore keep mutating the runtime graph they
came from even when the same view value is reused elsewhere. No-invalidator
`DefaultRenderer` snapshots preserve test ergonomics by letting a reused view
instance carry imperative writes into a later snapshot of that same instance.

## Observation

Use repo-owned ``Bindable`` with `Observation` models when you want editable bindings into observable reference types.

SwiftTUI tracks observable reads through the same invalidation bridge used by the rest of the runtime. Observable writes therefore invalidate the exact identities that observed them, rather than relying on a second rendering system.

## Environment

Use ``Environment`` or ``EnvironmentReader`` with ``EnvironmentValues`` when values should be inherited structurally through the tree. Use ``GeometryReader`` when authored content should react to the geometry assigned by layout, including the root terminal surface when the reader is placed at the root.

Environment updates can affect:

- styling and appearance
- focus affordances
- enabled or disabled state
- terminal-specific presentation details

Environment writes are part of authored structure. They are not a late-stage rendering override.

## Focus

Use ``FocusState`` to model authored focus ownership, and use ``FocusedValue`` or ``FocusedBinding`` when the currently focused subtree should export context upward.

The runtime is keyboard-first, but focus also matters for:

- determining which control should react to key events
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
