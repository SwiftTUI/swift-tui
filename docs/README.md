# Documentation Index

This directory is the current-state documentation set for the repository.
Landed work that no longer changes decisions has been folded into the
surviving source-of-truth docs rather than kept around as historical roadmaps
or superseded plans.

Per-target API reference lives in the `*.docc` catalogs under `Sources/`:

```bash
swiftly run swift package generate-documentation --target SwiftTUI
```

The repository [README.md](../README.md) is the public landing page.
[AGENTS.md](../AGENTS.md) is the short guide for agentic assistants.
[`TODO.md`](TODO.md) tracks planned work and unresolved decisions, and
[`CHANGELOG.md`](CHANGELOG.md) records completed TODO history.

## Start Here

- [STATUS.md](STATUS.md) — shipped surface, current constraints, goals, and
  explicit deferrals; planned or decision-bound gaps are tracked in
  [`TODO.md`](TODO.md)
- [ARCHITECTURE.md](ARCHITECTURE.md) — product/target boundaries and the frame pipeline
- [RUNTIME.md](RUNTIME.md) — lifecycle, graph-scoped state, observation,
  presentation safety, and incremental rendering
- [ASYNC_RENDERING.md](ASYNC_RENDERING.md) — async presentation and frame-tail offload
- [VISION.md](VISION.md) — philosophy, scope, and deferred work
- [TOOLCHAINS.md](TOOLCHAINS.md) — Swift, wasm, Bun, Xcode, Android toolchain story

## Reference

- [SOURCE_LAYOUT.md](SOURCE_LAYOUT.md) — ownership map across targets and key files
- [TERMINOLOGY.md](TERMINOLOGY.md) — runner, host, presentation-surface, and
  hosted-session vocabulary for public docs and package integration
- [ACCESSIBILITY.md](ACCESSIBILITY.md) — shipped accessibility semantics,
  runtime policy, target bridges, guardrails, and remaining gaps
- [PUBLIC_API_INVENTORY.md](PUBLIC_API_INVENTORY.md) — canonical public surface, removed surface, and package-only seams
- [PUBLIC_SURFACE_POLICY.md](PUBLIC_SURFACE_POLICY.md) — guardrails for public API additions, `AnyView` / `AnyScene` policy
- [ANYVIEW_INTERNALS.md](ANYVIEW_INTERNALS.md) — maintainer guide for
  `AnyView` graph behavior, acceptable internal erasure, and dangerous patterns
- [TESTING_AND_FIXTURE_POLICY.md](TESTING_AND_FIXTURE_POLICY.md) — fixture, determinism, regression, and test-topology rules
- [PERFORMANCE_EVALUATION.md](PERFORMANCE_EVALUATION.md) — local CPU-versus-latency scenario runs, artifacts, and comparison workflow
- [EMBEDDING.md](EMBEDDING.md) — terminal-program embedding through `TerminalView` and `TerminalProcessSession`
- [proposals/TERMINAL_WORKSPACE.md](proposals/TERMINAL_WORKSPACE.md) — shipped first-class terminal workspace surface above `TerminalView`
- [FOCUS.md](FOCUS.md) — focus traversal, focused values, default-focus behavior
- [STATE_KEYING.md](STATE_KEYING.md) — graph-scoped state-keying rules,
  snapshot fallback behavior, and authored-view identity

## Platform Products

- [HOST_PACKAGES.md](HOST_PACKAGES.md) — root-package platform products for
  executable runners, embedded hosts, and terminal-program embedding
- [HOST_RENDERING_PIPELINES.md](HOST_RENDERING_PIPELINES.md) — detailed
  rendering, input, resize, and presentation data flow for CLI, SwiftUIHost,
  WebHost, and `Platforms/Web`
- [ANDROID.md](ANDROID.md) — Android cross-compilation
- [../Examples/README.md](../Examples/README.md) — maintained example apps and packages

## Product Direction

- [TERMINAL_NATIVE_DOCTRINE.md](TERMINAL_NATIVE_DOCTRINE.md) — terminal-native design principles

## Proposals and Plans

Active design proposals that are still shaping decisions:

- [proposals/TEXT_INPUT_MODEL.md](proposals/TEXT_INPUT_MODEL.md) — shipped text input value, selection, reducer, layout-map, caret-anchor, shortcut, and selection-rendering foundation for `TextField`, `SecureField`, and `TextEditor`
- [proposals/ACCESSIBILITY.md](proposals/ACCESSIBILITY.md) — historical research record and remaining accessibility behavior questions; current shipped behavior lives in [ACCESSIBILITY.md](ACCESSIBILITY.md)
- [proposals/EMBEDDED_WEB_HOST.md](proposals/EMBEDDED_WEB_HOST.md) — shipped compile-time opt-in `SwiftTUIWebHost` / `SwiftTUIWebHostCLI` products for serving SwiftTUI apps through localhost HTTP/WebSocket using the shared `web-surface` browser runtime
- [proposals/LOCAL_BROWSER_HOST_LEARNINGS.md](proposals/LOCAL_BROWSER_HOST_LEARNINGS.md) — investigation draft capturing external-consumer and open-source-pattern
  learnings for the native local-browser host story
- [proposals/PLATFORMS_WEB_CONSUMABLE_PACKAGES.md](proposals/PLATFORMS_WEB_CONSUMABLE_PACKAGES.md) — investigation draft for making `Platforms/Web`
  consumable as browser/runtime and build packages such as `@swifttui/web` and
  `@swifttui/build`
- [proposals/PUBLIC_PRODUCTS_DRAFT.md](proposals/PUBLIC_PRODUCTS_DRAFT.md) — implemented release-facing product/import contract for one-import terminal apps, `SwiftTUIRuntime` composition, explicit host products, and first-class domain utility targets
- [proposals/ARGUMENT_PARSING.md](proposals/ARGUMENT_PARSING.md) — standard framework flags/env vars, including the WebHost `--web` / `--open` configuration surface
- [proposals/TERMINAL_WORKSPACE.md](proposals/TERMINAL_WORKSPACE.md) — scoped design work for a first-class Zellij-style terminal workspace surface above `TerminalView`
- [proposals/POPOVER_PRESENTATION_API.md](proposals/POPOVER_PRESENTATION_API.md) — draft anchored popover and TipKit-inspired `popoverTip` API proposal
- [proposals/ASYNC_FRAME_STALE_POLICY.md](proposals/ASYNC_FRAME_STALE_POLICY.md) — completed-frame stale policy
- [proposals/CPU_LATENCY_EVALUATION_PIPELINE.md](proposals/CPU_LATENCY_EVALUATION_PIPELINE.md) — CPU-versus-latency measurement system for async rendering and future runtime optimizations
- [proposals/TYPE_ERASURE_DEFERRAL_PLAN.md](proposals/TYPE_ERASURE_DEFERRAL_PLAN.md) — remaining `AnyView` reduction work
- [proposals/NAVIGATION_DESTINATION_PRESENTATION.md](proposals/NAVIGATION_DESTINATION_PRESENTATION.md) — shipped binding-driven `NavigationStack` destination presentation surface that intentionally excludes
  `NavigationLink`
- [proposals/layout/BEHAVIOUR_FINDINGS.md](proposals/layout/BEHAVIOUR_FINDINGS.md) — behaviour-test findings from the layouts example

Dated, agent-executable implementation plans live in [`plans/`](plans/), front-matter-tagged with `status:` (`planned`, `active`, `design-approved`, or `shipped`). Current planned/active plans:

- [plans/2026-05-09-003-deeper-scroll-control-scope.md](plans/2026-05-09-003-deeper-scroll-control-scope.md) — planned first-class scroll control scope, recommending `ScrollViewReader` / `ScrollViewProxy` identity and anchor scrolling before semantic `ScrollPosition` bindings or host observation hooks

Implementation and post-mortem records retained for context:

- [proposals/SEMANTIC_HOST_FRAME_API.md](proposals/SEMANTIC_HOST_FRAME_API.md) — implemented semantic host-frame producer/consumer contract that carries producer sequence, raster output, semantic snapshots, focus, host-frame capabilities, and raster damage together
- [plans/2026-05-13-001-host-presentation-damage-plan.md](plans/2026-05-13-001-host-presentation-damage-plan.md) — shipped host presentation damage promotion: `PresentationDamage` is an optional public host hint, semantic host-frame presentation preserves accessibility data and damage, SwiftUIHost redraws dirty native rects, and WebHost/WASI redraw dirty browser-canvas regions while still sending complete frame records
- [plans/2026-05-12-002-late-preference-reconciliation-plan.md](plans/2026-05-12-002-late-preference-reconciliation-plan.md) — shipped runtime late preference reconciliation seam, with toolbar hosts absorbing `.toolbarItem(...)` values emitted by realized `GeometryReader` content before commit
- [plans/2026-05-12-001-popover-presentation-plan.md](plans/2026-05-12-001-popover-presentation-plan.md) — shipped anchored popover presentation implementation record for Boolean and item-driven `.popover`, TipKit-inspired `.popoverTip`, source-relative terminal placement, Escape dismissal, and the gallery `Popovers` tab
- [proposals/POPOVER_PRESENTATION_API.md](proposals/POPOVER_PRESENTATION_API.md) — shipped anchored popover and TipKit-inspired `popoverTip` API proposal
- [plans/2026-05-09-002-text-editor-v2-plan.md](plans/2026-05-09-002-text-editor-v2-plan.md) — shipped `TextEditor` V2 shortcut, selection-rendering, clipboard copy/cut, and default-exit record; host value/selection transport, IME/composition, and large-document storage are explicit deferrals
- [plans/FRACTIONAL_COORDINATE_SPACE_PLAN.md](plans/FRACTIONAL_COORDINATE_SPACE_PLAN.md) — shipped fractional pointer, coordinate-space, Canvas-grid, terminal-pixel, host-precision, and gesture implementation record; the remaining Canvas/pointer API decisions are resolved in the plan status section
- [plans/2026-05-09-001-swiftui-native-voiceover-focus-plan.md](plans/2026-05-09-001-swiftui-native-voiceover-focus-plan.md) — shipped SwiftUI host native VoiceOver focus bridge, making runtime focus move native accessibility focus by default while leaving native-to-runtime focus for a later interaction contract
- [plans/2026-04-28-001-canvas-adaptation-plan.md](plans/2026-04-28-001-canvas-adaptation-plan.md) — shipped Canvas pixel-grid rendering, direct cell writes, styled Braille, half-block grids, gifeditor migration, and documentation; the standalone `Examples/canvas` package named by the historical record is not currently maintained
- [plans/2026-04-26-003-border-stroke-simplification-plan.md](plans/2026-04-26-003-border-stroke-simplification-plan.md) — shipped border/stroke cleanup record; landed behavior keeps `.rounded` as the canonical default while placement lives on `StrokeStyle`
- [plans/2026-05-06-002-embedded-web-host-compile-time-plan.md](plans/2026-05-06-002-embedded-web-host-compile-time-plan.md) — implementation record for the compile-time opt-in embedded WebHost runner, browser bundle, WebSocket transport, package-boundary guardrails, and example package
- [plans/2026-05-06-001-text-input-model-v1-plan.md](plans/2026-05-06-001-text-input-model-v1-plan.md) — shipped V1 text input value, reducer, layout map, paste routing, and caret-anchor semantics
- [plans/2026-05-04-001-terminal-embedding-plan.md](plans/2026-05-04-001-terminal-embedding-plan.md) — shipped terminal-program embedding through `TerminalView`, `TerminalProcessSession`, PTY process integration, render-diff validation, and the file-previewer example
- [plans/2026-05-02-001-cpu-latency-evaluation-pipeline-plan.md](plans/2026-05-02-001-cpu-latency-evaluation-pipeline-plan.md) — shipped same-binary CPU and input-latency evaluation tooling for async rendering and future runtime optimization work
- [plans/2026-05-02-002-composed-presentation-primitives-plan.md](plans/2026-05-02-002-composed-presentation-primitives-plan.md) — shipped migration from presentation-specific overlay hoisting to portal, overlay-stack, interaction-gate, and dismiss-stack primitives
- [plans/2026-05-01-007-gallery-animation-regression-notes.md](plans/2026-05-01-007-gallery-animation-regression-notes.md) — shipped regression guard and fix record for gallery one-shot animation transactions snapping after async Option 3
- [plans/2026-05-05-003-accessibility-cli-runtime-plan.md](plans/2026-05-05-003-accessibility-cli-runtime-plan.md) — shipped CLI accessibility runtime behavior: cursor-as-focus, linear output, motion/progress policy, and live regions
- [plans/2026-05-05-004-accessibility-web-aria-plan.md](plans/2026-05-05-004-accessibility-web-aria-plan.md) — shipped Web/WASI accessibility tree encoding and browser ARIA mounting
- [plans/2026-05-05-005-accessibility-swiftui-host-plan.md](plans/2026-05-05-005-accessibility-swiftui-host-plan.md) — shipped SwiftUI host accessibility overlay and live-region bridging
- [plans/2026-05-05-001-resilient-anyview-plan.md](plans/2026-05-05-001-resilient-anyview-plan.md) — shipped resilient `AnyView` implementation with targeted graph, lifecycle, and runtime verification
- [plans/2026-05-01-006-async-frame-head-draft-transaction-plan.md](plans/2026-05-01-006-async-frame-head-draft-transaction-plan.md) — shipped Option 3 implementation for draft frame-head transactions, prepared-frame abort proof, and queued-tail cancellation
- [plans/2026-05-01-005-async-rendering-r0-inventory.md](plans/2026-05-01-005-async-rendering-r0-inventory.md) — R0 diagnostics and composed-runtime coverage checkpoint for restarting async cancellation work
- [plans/2026-05-01-004-layout-dependent-container-hardening-plan.md](plans/2026-05-01-004-layout-dependent-container-hardening-plan.md) — shipped hardening record for layout-dependent container geometry tests and docs
- [plans/2026-05-01-003-layout-dependent-container-audit.md](plans/2026-05-01-003-layout-dependent-container-audit.md) — audit of `safeAreaInset`, `ScrollView`, `ViewThatFits`, lazy stacks, and custom `Layout` for remaining resolve-time local-geometry assumptions
- [plans/2026-05-01-002-public-anchor-geometry-preferences-plan.md](plans/2026-05-01-002-public-anchor-geometry-preferences-plan.md) — shipped public anchor tokens, anchor preferences, `GeometryProxy` anchor resolution, and geometry-bound preference overlays
- [plans/2026-05-01-001-layout-dependent-content-realization-plan.md](plans/2026-05-01-001-layout-dependent-content-realization-plan.md) — shipped generalized layout-time content realization for `GeometryReader`, geometry preferences, and measurement-dependent containers
- [proposals/ASYNC_PRESENTATION.md](proposals/ASYNC_PRESENTATION.md) — POSIX terminal writer offload
- [proposals/OFF_MAIN_PIPELINE_RENDERING.md](proposals/OFF_MAIN_PIPELINE_RENDERING.md) — guarded frame-tail worker implementation record
- [proposals/CUSTOM_LAYOUT_OFF_MAIN_ISOLATION.md](proposals/CUSTOM_LAYOUT_OFF_MAIN_ISOLATION.md) — `SendableLayout` worker migration
- [proposals/ASYNC_RENDER_GENERATION_SCHEDULER.md](proposals/ASYNC_RENDER_GENERATION_SCHEDULER.md) — shipped render-generation and pre-start frame-tail cancellation design
- [plans/2026-04-26-001-off-main-frame-tail-rendering-plan.md](plans/2026-04-26-001-off-main-frame-tail-rendering-plan.md) — shipped frame-tail worker plan
- [plans/2026-04-26-002-frame-head-abort-plan.md](plans/2026-04-26-002-frame-head-abort-plan.md) — reverted frame-head abort attempt and post-mortem
- [proposals/ACTION_SCOPES_AND_COMMANDS.md](proposals/ACTION_SCOPES_AND_COMMANDS.md) — scope-based command, keybinding, and toolbar design
- [proposals/ACTION_SCOPES_AND_COMMANDS_IMPLEMENTATION.md](proposals/ACTION_SCOPES_AND_COMMANDS_IMPLEMENTATION.md) — phase-by-phase implementation record
- [proposals/ANIMATION_PLAN.md](proposals/ANIMATION_PLAN.md) — shipped original animation rollout plus current limitations
- [proposals/ANIMATABLE_PROTOCOL_MIGRATION.md](proposals/ANIMATABLE_PROTOCOL_MIGRATION.md) — shipped follow-up migration to SwiftUI-shaped `Animatable`
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
