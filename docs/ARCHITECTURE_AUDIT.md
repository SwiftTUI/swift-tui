# Architecture Audit

**Date:** 2026-03-26
**Scope:** Full framework audit — Core, View, TerminalUI, TerminalUIScenes

## Codebase Summary

| Module | Lines | Files | Purpose |
|--------|-------|-------|---------|
| Core | 13,509 | 35 | Rendering pipeline, layout, semantics |
| View | 8,816 | 28 | SwiftUI-shaped view authoring surface |
| TerminalUI | 4,076 | 9 | Terminal host integration, app entry |
| TerminalUIScenes | — | — | Multi-scene runtime layer |
| TerminalUICharts | — | — | Chart/metric components |

## Strengths

### 1. Pipeline Design
The 7-phase rendering pipeline (Resolve → Measure → Place → Semantics → Draw → Raster → Commit) in `Core/Pipeline.swift` is clean, composable, and testable. Each phase has a single responsibility with well-defined input/output types. The generic `Renderer<Root>` with closure-based phases allows the pipeline to be assembled differently for testing vs production.

### 2. Immutable Intermediate Trees
`ResolvedNode`, `MeasuredNode`, `PlacedNode`, and `DrawNode` are all value types (`Equatable, Sendable`). This makes the pipeline inherently safe for concurrency and easy to reason about — each phase produces a fresh tree from the previous.

### 3. Identity-Based Invalidation
The `Identity`-keyed invalidation system (`StateContainer.invalidationIdentities`, `FrameContext.invalidatedIdentities`) enables incremental rendering without a full virtual-DOM diff. Combined with `MeasurementCache`, this is a smart performance strategy for terminal UIs where layout is simpler but redraw latency matters.

### 4. Separation of View Authoring from Rendering
The `View` module knows nothing about terminals. It defines the declarative API and resolution to `ResolvedNode`. The `TerminalUI` module handles terminal I/O. This separation means the core View DSL could target other backends.

### 5. Swift 6 Concurrency
`.swiftLanguageMode(.v6)`, `.strictMemorySafety()`, `Sendable` throughout. The `StateContainer` uses `Mutex` from `Synchronization` correctly — copy-on-read, compare-before-write. Well ahead of most Swift projects.

## Issues Found

### HIGH Priority

#### H1: `LayoutEngine.swift` at 1,922 Lines
Handles measurement for every `LayoutBehavior` variant — stacks, overlays, padding, frames, decorations, `viewThatFits`, and custom layouts — all in one file. Hardest file to modify safely.

**Fix:** Extract measurement strategies into separate files by layout kind (e.g., `StackMeasurement.swift`, `FrameMeasurement.swift`). The `LayoutBehavior` enum provides natural seams.

#### H2: `RunLoop.swift` Mixes Too Many Concerns (1,136 Lines)
Handles event polling, signal handling, state mutation, frame scheduling, focus management, key dispatch, pointer dispatch, scroll handling, action dispatch, and lifecycle coordination.

**Fix:** Extract `EventDispatcher` (takes `InputEvent` + `SemanticSnapshot` + `FocusTracker`, returns mutations) and `FrameScheduler` (decides when to render). RunLoop becomes a thin coordinator.

#### H3: String-Typed Semantic Roles
The old semantic/token layer used open-ended strings for roles and routes. That made routing and styling fragile and forced extra compatibility code.

**Fix:** Keep semantic roles and routes closed-typed: enums for roles, structured `RouteID`, typed identities for built-in child routes, and no string-token fallback layer.

### MEDIUM Priority

#### M1: `ResolvedNode` is a God Struct (12 Fields)
Carries identity, layout, drawing, semantics, lifecycle, and environment. Every phase reads different subsets but receives everything. Changes to any metadata type force recompilation of all phases. Also degrades `MeasurementCache` — the cache compares *all* fields when only layout-relevant fields matter.

**Fix:** Split into composable metadata bags (`NodeLayout`, `NodeDraw`, `NodeSemantics`, `NodeLifecycle`) alongside a slimmed `ResolvedNode`.

#### M2: `@unchecked Sendable` Proliferation (24 Instances)
Heaviest concentration in local registries (`LocalActionRegistry`, `LocalKeyHandlerRegistry`, `LocalFocusBindingRegistry`, etc.). Each is a potential soundness hole. Several store closures capturing mutable state.

**Fix:** Audit each instance. Replace with `Mutex`-protected struct or actor where possible. Add `// SAFETY:` comments documenting thread-access invariants where `@unchecked` must remain.

#### M3: Single Test Target for Core + View + TerminalUI
All ~37 test files are in `TerminalUITests`. No dedicated `CoreTests` or `ViewTests`. Can't run layout engine tests without compiling the terminal host. Test failures don't localize to a module.

**Fix:** Add `CoreTests` and `ViewTests` test targets to `Package.swift`.

#### ~~M4: No Incremental Resolve Phase~~ (ALREADY IMPLEMENTED)
Upon closer inspection, incremental resolve already exists via `ResolveReuseSession` (`View/Environment.swift:308`). It stores the previous frame's resolved tree and reuses subtrees when:
- The subtree's identity is not in `invalidatedIdentities`
- No descendant identities are invalidated
- The environment and transaction snapshots match
Handler registrations are replayed from the retained frame for reused subtrees. Fully wired in `TerminalUI.swift:125`.

### LOW Priority (Not Addressed in This Refactor)

- **L1:** Full-surface rasterization (allocates entire `[[RasterCell]]` every frame)
- **L2:** Module naming (`TerminalUI` is opaque, `View` collides with `SwiftUI.View`)
- **L3:** No accessibility / screen reader story (OSC escape sequences)
