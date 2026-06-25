# State Keying

How `@State` storage is keyed across re-evaluations, and what owner placement to choose when state must survive lazy seams.

## Overview

SwiftTUI separates the pieces that SwiftUI developers usually call "identity":

- `StructuralPath` records an authored position in the resolved tree.
- `EntityIdentity` records an explicit `.id(...)` value or a `ForEach` data key.
- `ViewNodeID` is the runtime lifetime that owns local state, lifecycle, focus,
  and other graph registrations.
- Each `@State` declaration reconnects through a graph-scoped state slot:
  owner `ViewNodeID` plus the declaration's source-location ordinal.

For an unkeyed view, the owner lifetime follows structural position. Move the
owner to a different structural slot and SwiftTUI creates a fresh state slot.
For an explicitly keyed view, the entity identity can route the same
`ViewNodeID` across structural moves such as wrapper toggles or moving a row
between containers. Changing the explicit id is a new entity and therefore a new
state owner.

Live runtime callbacks add one more internal scope: the view graph that
registered the callback. Button actions, key-command handlers, projected
bindings, and gesture updates mutate the graph-scoped state location captured
when the handler was authored. Reusing the same stateful view value in another
live graph therefore starts with that graph's own storage instead of leaking
writes through a last-bound global fallback.

`DefaultRenderer` remains snapshot-friendly when there is no invalidating
runtime graph. If a test or preview reuses the same stateful view instance
across no-invalidator snapshots, imperative writes can still feed a later
snapshot of that same instance.

Keying only protects the reconnection step. It does not recover state when the
owning runtime lifetime is genuinely removed and no entity route preserves it.

## Practical Owner Placement Guidance

Keying is only about how a surviving or entity-routed owner reconnects to its
persisted state slot. It does **not** protect state when the owner itself is
removed.

That distinction matters because several runtime features intentionally resolve children lazily or out of line:

- active-tab content in `TabView`
- scoped content payloads captured for later evaluation
- root-hoisted presentation overlays
- wrapper-hosted and scene-hosted compositions that can re-resolve only part of the tree on a given frame

If a piece of state must survive churn across one of those seams, the durable
rule is to own it above the seam, or give the moving child a stable explicit
entity id when it is genuinely the same logical value. Keying cannot recover
state from an owner that disappeared without a route.

Practical consequences:

- Diagnose "tab switch" or "presentation dismiss" resets as owner-placement problems first, not keying problems.
- Do not over-hoist by default. Tab-local state can be allowed to reset when a tab is genuinely deselected if that is the intended product behavior.
- Distinguish transient visual flicker from true state loss. Flicker can come from composition or host-sync issues even when state ownership is correct.
- Root-hoisted presentation churn should be transparent to the currently selected tab. If opening or dismissing a palette resets the active tab's local state without the palette changing selection, that is a presentation bug rather than an expected lazy-tab reset.
- When a child is resolved lazily, prefer parent-owned state plus explicit bindings over child-local `@State` for data that must persist across activation changes.
- In a `ForEach`, the collection slot and each element's positional
  `StructuralPath` are separate from the element's data identity. Row-local
  state follows the element's routed `ViewNodeID`; state captured by the row
  closure stays owned by the view that authored the closure.

## See Also

- <doc:State-Environment-And-Focus>
- <doc:Focus>
- <doc:Authoring-Views>
