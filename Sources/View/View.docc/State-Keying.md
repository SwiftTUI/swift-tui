# State Keying

How `@State` storage is keyed across re-evaluations, and what owner placement to choose when state must survive lazy seams.

## Overview

SwiftTUI keys `@State` storage by view identity path plus source location. As long as the owning view's identity path is stable, each `@State` declaration reconnects to the same persisted slot across re-evaluations. Move a stateful view to a different identity path and you get a fresh state slot; the old slot is orphaned and reclaimed.

Keying only protects the reconnection step. It does not recover state when the owning view *itself* is recreated under a different identity path.

## Practical Owner Placement Guidance

Keying is only about how a surviving owner reconnects to its persisted state slot. It does **not** protect state when the owning view identity itself is recreated.

That distinction matters because several runtime features intentionally resolve children lazily or out of line:

- active-tab content in `TabView`
- deferred view payloads captured for later evaluation
- root-hoisted presentation overlays
- wrapper-hosted and scene-hosted compositions that can re-resolve only part of the tree on a given frame

If a piece of state must survive churn across one of those seams, the durable rule is to own it above the seam and pass bindings or model references into the lazy child. Keying cannot recover state from an owner that disappeared and was recreated somewhere else.

Practical consequences:

- Diagnose "tab switch" or "presentation dismiss" resets as owner-placement problems first, not keying problems.
- Do not over-hoist by default. Tab-local state can be allowed to reset when a tab is genuinely deselected if that is the intended product behavior.
- Distinguish transient visual flicker from true state loss. Flicker can come from composition or host-sync issues even when state ownership is correct.
- Root-hoisted presentation churn should be transparent to the currently selected tab. If opening or dismissing a palette resets the active tab's local state without the palette changing selection, that is a presentation bug rather than an expected lazy-tab reset.
- When a child is resolved lazily, prefer parent-owned state plus explicit bindings over child-local `@State` for data that must persist across activation changes.

## See Also

- <doc:State-Environment-And-Focus>
- <doc:Focus>
- <doc:Authoring-Views>
- [State Keying: Ordinal vs Source-Location](https://github.com/adamz/swift-tui/blob/main/docs/STATE_KEYING.md)
