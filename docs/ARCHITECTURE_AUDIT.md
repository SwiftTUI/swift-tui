# Architecture Audit

**Date:** 2026-03-30
**Scope:** Current working tree, including `Core`, `View`, `TerminalUI`, `TerminalUIScenes`, wrapper packages, and the top-level docs that describe them

## Executive Summary

The March 26 architecture audit is no longer accurate as a future-looking
punch list. The codebase has since landed most of the structural work that
audit called for:

- `LayoutEngine` is decomposed into focused extension files
- `RunLoop` is split across event-dispatch, pointer, event-pump, and rendering
  files
- typed semantic roles and structured route identifiers replaced the old
  string-token model
- test coverage is now split across `CoreTests`, `ViewTests`,
  `TerminalUITests`, `TerminalUIScenesTests`, and
  `PrototypeUIComponentsTests`
- retained resolve reuse is present and wired into `DefaultRenderer`

The remaining debt is narrower. It is now mostly about concurrency annotation
cleanup, deciding how far to push the `ResolvedNode` metadata split, and
keeping docs and guardrails aligned with the file map that already shipped.

This refreshed audit intentionally avoids hard-coded line counts and file-count
tables. Those numbers drift too quickly to stay useful.

## What Landed Since The Original Audit

### `LayoutEngine` decomposition

The old monolithic `LayoutEngine.swift` has been split into:

- `LayoutEngine+Alignment.swift`
- `LayoutEngine+List.swift`
- `LayoutEngine+Placement.swift`
- `LayoutEngine+Stack.swift`
- `LayoutEngine+Table.swift`
- `LayoutEngine+Utility.swift`

That keeps the main file focused on the public engine surface while moving
algorithm groups into targeted extensions.

### `RunLoop` decomposition

The runtime coordinator still centers on `RunLoop.swift`, but the heavy logic
is now split into:

- `RunLoop+EventDispatch.swift`
- `RunLoop+PointerHandling.swift`
- `RunLoop+EventPump.swift`
- `RunLoop+Rendering.swift`

The final shape differs slightly from the original proposed filenames, but the
structural goal is clearly landed.

### Typed semantic roles and routes

`Sources/Core/SemanticRoleTypes.swift` now carries the closed semantic-role and
route model. The old string-style compatibility layer described in the March 26
audit is no longer the active architecture story.

### Test-target split

The repo no longer relies on a single `TerminalUITests` bucket for everything.
`CoreTests`, `ViewTests`, and `TerminalUIScenesTests` now exist and materially
improve subsystem-local verification.

### Incremental resolve

Incremental resolve reuse is present through `ResolveReuseSession` and retained
resolve frames. That part of the original audit already resolved itself during
the first pass and remains landed.

## Still Open Or Partial

### 1. `@unchecked Sendable` still needs a deliberate sweep

This remains the highest-value follow-up. A current search shows 52
`@unchecked Sendable` sites across `Sources/` and `Tests/`.

Some are expected because the repo stores closures or bridges mutable host
state, but the remaining sites still deserve one of two outcomes:

- replace with stronger isolation or synchronization where practical
- keep them, but add explicit `// SAFETY:` invariants so future changes do not
  silently widen the unsoundness boundary

The local registries, host bridges, and retained replay structures remain the
best places to start.

### 2. `ResolvedNode` splitting is only partially landed

`Sources/Core/NodeMetadata.swift` now provides grouped metadata views such as
`NodeLayoutInfo`, `NodeDrawInfo`, `NodeSemanticInfo`, and `NodeLifecycleInfo`.
That improves measurement comparisons and lowers some coupling.

But the physical `ResolvedNode` storage in
`Sources/Core/RenderTreeAndSemanticsTypes.swift` is still mostly flat. The repo
should make an explicit choice:

- finish the deeper storage split, or
- decide the grouped accessors are sufficient and stop treating a full split as
  pending work

Leaving this in an implied half-state is harder to reason about than either
clear direction.

### 3. Docs and guardrails had drifted behind the shipped file map

This audit pass found doc drift in:

- `docs/SOURCE_LAYOUT.md`
- `docs/TESTING_AND_FIXTURE_POLICY.md`
- `README.md`
- `TUIGUI.md`
- `docs/REFACTOR_PLAN.md`

Those docs were describing nonexistent files, missing products, or future work
that has already shipped. They should now be treated as part of the same
reliability surface as the code split itself.

## Recommended Near-Term Plan

1. Run a focused `@unchecked Sendable` audit, starting with runtime registries and host bridges.
2. Decide whether `ResolvedNode` should be physically split further or formally left as grouped-accessor storage.
3. If the repo wants source-layout rules enforced mechanically again, add a real checked-in hook and document that hook in the same change.
