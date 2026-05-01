# State, Environment, And Focus

## Overview

TerminalUI keeps state, observation, environment, and focus on one runtime invalidation path.

That gives the framework a few important properties:

- local `@State` changes rerender the same way observable writes do
- focus changes feed the same semantic system that keyboard interaction uses
- environment reads stay part of authored view composition instead of becoming out-of-band configuration

## State

Use ``State`` for local value ownership and ``Binding`` for projection into child views.

`@State` storage is keyed by view identity path plus source location, not by reference identity. That means moving a stateful view to a different identity path creates a distinct state slot, which matches SwiftUI-style expectations.

## Observation

Use repo-owned ``Bindable`` with `Observation` models when you want editable bindings into observable reference types.

TerminalUI tracks observable reads through the same invalidation bridge used by the rest of the runtime. Observable writes therefore invalidate the exact identities that observed them, rather than relying on a second rendering system.

## Environment

Use ``EnvironmentValues`` and ``EnvironmentReader`` when values should be inherited structurally through the tree. Use ``GeometryReader`` when authored content should react to the geometry assigned by layout, including the root terminal surface when the reader is placed at the root.

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
- ``EnvironmentValues``
- ``EnvironmentReader``
- ``GeometryReader``
- ``FocusState``
- ``FocusedValue``
- ``FocusedBinding``
