# Documentation Index

This directory is the current-state documentation set for the repository.
Landed work that no longer changes decisions has been folded into the
surviving source-of-truth docs rather than kept around as historical roadmaps
or superseded plans.

Per-target API reference lives in the `*.docc` catalogs under `Sources/`:

```bash
swiftly run swift package generate-documentation --target TerminalUI
```

The repository [README.md](../README.md) is the public landing page.
[AGENTS.md](../AGENTS.md) is the short guide for agentic assistants.

## Start Here

- [STATUS.md](STATUS.md) — shipped surface, current constraints, and short-term gaps
- [ARCHITECTURE.md](ARCHITECTURE.md) — package boundaries and the frame pipeline
- [RUNTIME.md](RUNTIME.md) — lifecycle, state, observation, and incremental rendering
- [ASYNC_RENDERING.md](ASYNC_RENDERING.md) — async presentation and frame-tail offload
- [VISION.md](VISION.md) — philosophy, scope, and deferred work
- [TOOLCHAINS.md](TOOLCHAINS.md) — Swift, wasm, Bun, Xcode, Android toolchain story

## Reference

- [SOURCE_LAYOUT.md](SOURCE_LAYOUT.md) — ownership map across targets and key files
- [PUBLIC_API_INVENTORY.md](PUBLIC_API_INVENTORY.md) — canonical public surface, removed surface, and package-only seams
- [PUBLIC_SURFACE_POLICY.md](PUBLIC_SURFACE_POLICY.md) — guardrails for public API additions, `AnyView` / `AnyScene` policy
- [TESTING_AND_FIXTURE_POLICY.md](TESTING_AND_FIXTURE_POLICY.md) — fixture, determinism, regression, and test-topology rules
- [FOCUS.md](FOCUS.md) — focus traversal, focused values, default-focus behavior
- [STATE_KEYING.md](STATE_KEYING.md) — retained-graph state-keying rules and authored-view identity

## Platform Packaging

- [HOST_PACKAGES.md](HOST_PACKAGES.md) — runner-package and embedded-host packaging model
- [ANDROID.md](ANDROID.md) — Android cross-compilation
- [../Examples/README.md](../Examples/README.md) — maintained example apps and packages

## Product Direction

- [TERMINAL_NATIVE_DOCTRINE.md](TERMINAL_NATIVE_DOCTRINE.md) — terminal-native design principles

## Proposals and Plans

Active design proposals that are still shaping decisions:

- [proposals/ASYNC_FRAME_STALE_POLICY.md](proposals/ASYNC_FRAME_STALE_POLICY.md) — future cancellation and dropping policy
- [proposals/ASYNC_RENDER_GENERATION_SCHEDULER.md](proposals/ASYNC_RENDER_GENERATION_SCHEDULER.md) — pre-start frame-tail cancellation design
- [proposals/TYPE_ERASURE_DEFERRAL_PLAN.md](proposals/TYPE_ERASURE_DEFERRAL_PLAN.md) — remaining `AnyView` reduction work
- [proposals/layout/BEHAVIOUR_FINDINGS.md](proposals/layout/BEHAVIOUR_FINDINGS.md) — behaviour-test findings from the layouts example

Dated, agent-executable implementation plans live in [`plans/`](plans/), front-matter-tagged with `status:` (`planned`, `active`, `design-approved`, or `shipped`). Current planned/active plans:

- [plans/2026-04-28-001-canvas-adaptation-plan.md](plans/2026-04-28-001-canvas-adaptation-plan.md) — extending Canvas for dense pixel grids, half-block rendering, and optional sub-cell pointer precision

Implementation and post-mortem records retained for context:

- [plans/2026-05-01-005-async-rendering-r0-inventory.md](plans/2026-05-01-005-async-rendering-r0-inventory.md) — R0 diagnostics and composed-runtime coverage checkpoint for restarting async cancellation work
- [plans/2026-05-01-004-layout-dependent-container-hardening-plan.md](plans/2026-05-01-004-layout-dependent-container-hardening-plan.md) — shipped hardening record for layout-dependent container geometry tests and docs
- [plans/2026-05-01-003-layout-dependent-container-audit.md](plans/2026-05-01-003-layout-dependent-container-audit.md) — audit of `safeAreaInset`, `ScrollView`, `ViewThatFits`, lazy stacks, and custom `Layout` for remaining resolve-time local-geometry assumptions
- [plans/2026-05-01-002-public-anchor-geometry-preferences-plan.md](plans/2026-05-01-002-public-anchor-geometry-preferences-plan.md) — shipped public anchor tokens, anchor preferences, `GeometryProxy` anchor resolution, and geometry-bound preference overlays
- [plans/2026-05-01-001-layout-dependent-content-realization-plan.md](plans/2026-05-01-001-layout-dependent-content-realization-plan.md) — shipped generalized layout-time content realization for `GeometryReader`, geometry preferences, and measurement-dependent containers
- [proposals/ASYNC_PRESENTATION.md](proposals/ASYNC_PRESENTATION.md) — POSIX terminal writer offload
- [proposals/OFF_MAIN_PIPELINE_RENDERING.md](proposals/OFF_MAIN_PIPELINE_RENDERING.md) — guarded frame-tail worker implementation record
- [proposals/CUSTOM_LAYOUT_OFF_MAIN_ISOLATION.md](proposals/CUSTOM_LAYOUT_OFF_MAIN_ISOLATION.md) — `SendableLayout` worker migration
- [plans/2026-04-26-001-off-main-frame-tail-rendering-plan.md](plans/2026-04-26-001-off-main-frame-tail-rendering-plan.md) — shipped frame-tail worker plan
- [plans/2026-04-26-002-frame-head-abort-plan.md](plans/2026-04-26-002-frame-head-abort-plan.md) — reverted frame-head abort attempt and post-mortem
- [proposals/ACTION_SCOPES_AND_COMMANDS.md](proposals/ACTION_SCOPES_AND_COMMANDS.md) — scope-based command, keybinding, and toolbar design
- [proposals/ACTION_SCOPES_AND_COMMANDS_IMPLEMENTATION.md](proposals/ACTION_SCOPES_AND_COMMANDS_IMPLEMENTATION.md) — phase-by-phase implementation record
- [proposals/ANIMATION_PLAN.md](proposals/ANIMATION_PLAN.md) — original animation rollout
- [proposals/ANIMATABLE_PROTOCOL_MIGRATION.md](proposals/ANIMATABLE_PROTOCOL_MIGRATION.md) — follow-up migration to SwiftUI-shaped `Animatable`
- [proposals/ARCHITECTURE_NOTES.md](proposals/ARCHITECTURE_NOTES.md) — view-graph and diffing improvements
- [proposals/CELL_PIXEL_METRICS.md](proposals/CELL_PIXEL_METRICS.md) — public `CellPixelMetrics` on `GeometryProxy`/`EnvironmentValues` plus Braille-shape aspect correction
- [proposals/GESTURES_IMPLEMENTATION.md](proposals/GESTURES_IMPLEMENTATION.md) — SwiftUI-shaped gesture API
- [proposals/SHAPE_AND_BORDER_APIS.md](proposals/SHAPE_AND_BORDER_APIS.md) — shape and border API redesign
- [proposals/VIEW_MODIFIER_LAYER.md](proposals/VIEW_MODIFIER_LAYER.md) — public `ViewModifier` / `ModifiedContent` migration

## Background Material

- [SWIFTUI_LAYOUT.md](SWIFTUI_LAYOUT.md) — the SwiftUI layout model this package targets
- [LIPGLOSS_SWIFTUI_EQUIVALENTS.md](LIPGLOSS_SWIFTUI_EQUIVALENTS.md) — Lip Gloss / TUI ↔ SwiftUI concept mapping
- [TERMINAL_NATIVE_UI_RESEARCH.md](TERMINAL_NATIVE_UI_RESEARCH.md) — UI-side research that informed the design
- [TERMINAL_NATIVE_UX_RESEARCH.md](TERMINAL_NATIVE_UX_RESEARCH.md) — UX/workflow research
- [CELL_PIXEL_GEOMETRY_RESEARCH.md](CELL_PIXEL_GEOMETRY_RESEARCH.md) — motivations and trade-offs for exposing pixel-level geometry on a cell-based API
