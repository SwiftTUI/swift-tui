# Architecture Refactor Status

**Date:** 2026-03-30
**Ref:** [ARCHITECTURE_AUDIT.md](./ARCHITECTURE_AUDIT.md)
**Purpose:** Track the remaining follow-up work after the March 2026 architecture audit

This document is no longer a speculative full rewrite plan. It is the current
status ledger for the refactor work that the March 26 audit kicked off.

## Already Landed

### 1. Typed semantic roles and structured routes

The old open-ended semantic token model has been replaced by the closed role
and route types in `Sources/Core/SemanticRoleTypes.swift`, with the pointer and
semantic systems now using `RouteID`, `RouteKind`, and typed roles directly.

### 2. `LayoutEngine` decomposition

The monolithic layout engine work is landed through:

- `LayoutEngine+Alignment.swift`
- `LayoutEngine+List.swift`
- `LayoutEngine+Placement.swift`
- `LayoutEngine+Stack.swift`
- `LayoutEngine+Table.swift`
- `LayoutEngine+Utility.swift`

`LayoutEngine.swift` remains the main public entry point rather than a catch-all
implementation bucket.

### 3. `RunLoop` decomposition

The runtime split landed, although the final filenames differ slightly from the
first draft:

- `RunLoop+EventDispatch.swift`
- `RunLoop+PointerHandling.swift`
- `RunLoop+EventPump.swift`
- `RunLoop+Rendering.swift`

That is the shipped shape and should now be treated as canonical.

### 4. Test-target split

The repo now has dedicated test targets for:

- `CoreTests`
- `ViewTests`
- `TerminalUITests`
- `TerminalUIScenesTests`
- `PrototypeUIComponentsTests`

This part of the original plan is complete.

### 5. Incremental resolve reuse

Incremental resolve is landed through retained resolve frames and
`ResolveReuseSession`, wired through `ResolveContext` and `DefaultRenderer`.

### 6. Grouped node metadata for measurement

`Sources/Core/NodeMetadata.swift` now provides grouped node metadata types used
for measurement and refactor follow-up work. This addressed the most urgent
cache-comparison problem even though the deeper physical `ResolvedNode` split is
still a separate question.

## Remaining Follow-Ups

### 1. Audit `@unchecked Sendable` sites

Why this is still open:

- the repo still contains a large number of `@unchecked Sendable` annotations
- several are probably justified because of closure storage or host bridges
- others still need either stronger synchronization or explicit `// SAFETY:`
  rationale

Recommended approach:

1. inventory the current sites
2. classify each as replaceable or justified
3. prioritize runtime registries, retained replay structures, and host bridges
4. avoid public API churn unless the safety win is material

### 2. Decide whether to fully split `ResolvedNode`

Current state:

- grouped accessors exist through `NodeLayoutInfo`, `NodeDrawInfo`,
  `NodeSemanticInfo`, and `NodeLifecycleInfo`
- `ResolvedNode` storage in `RenderTreeAndSemanticsTypes.swift` remains mostly
  flat

Decision needed:

- finish the physical split, or
- declare the grouped-accessor model sufficient and remove this from the active
  refactor queue

### 3. Keep docs and guardrails aligned with the shipped file map

The March 30 doc audit found stale references to:

- nonexistent source files in `docs/SOURCE_LAYOUT.md`
- nonexistent repository hooks in `docs/TESTING_AND_FIXTURE_POLICY.md`
- future-tense work that has already shipped in `README.md`, `TUIGUI.md`, and
  this plan set

That drift is corrected in the current working tree, but future refactors
should update the doc set in the same change as file moves.

## Verification Anchors

- `swiftly run swift test`
- `Tests/CoreTests`
- `Tests/ViewTests`
- `Tests/TerminalUITests`
- `Tests/TerminalUIScenesTests`

If a future refactor touches package boundaries, also re-check
[SOURCE_LAYOUT.md](SOURCE_LAYOUT.md), [STATUS.md](STATUS.md), and
[PUBLIC_API_INVENTORY.md](PUBLIC_API_INVENTORY.md) in the same pass.
