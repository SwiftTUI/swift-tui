# Changelog

Completed active-work history lives here. Keep entries concise, self-standing,
and newest first. Long-form design notes, validation records, and API details
belong in the durable docs, plans, source, or tests linked from an entry.

## Rules

- Move completed items removed from `active_work.md` into this file.
- Each entry must say what changed without requiring readers to open another
  document.
- Entries may link to long-lived repo documentation, plans, source, or tests for
  detail.
- Every link in an entry must be prefixed with the short git hash that anchors
  the linked material, for example:
  `4ee7a8f9` [active_work.md](active_work.md).
- Keep completed-work summaries out of `active_work.md`.

## 2026-05-08

- `e3178a74` Reconciled the terminal-embedding tracker state by marking the
  implementation plan shipped, pointing the docs index at it as an
  implementation record, and removing the stale active-work item. See
  `e3178a74` [docs/plans/2026-05-04-001-terminal-embedding-plan.md](docs/plans/2026-05-04-001-terminal-embedding-plan.md).
- `0c8b73f2` Refreshed shipped-tooling docs so the CPU latency evaluation
  proposal describes the delivered `Tools/TermUIPerf` harness and the argument
  parsing proposal no longer marks accessibility/WebHost runtime configuration
  fields as parsed-but-unwired. See
  `0c8b73f2` [docs/proposals/CPU_LATENCY_EVALUATION_PIPELINE.md](docs/proposals/CPU_LATENCY_EVALUATION_PIPELINE.md)
  and `4278c485` [docs/proposals/ARGUMENT_PARSING.md](docs/proposals/ARGUMENT_PARSING.md).
- `0c8b73f2` Reconciled the docs index with shipped plan front matter so CPU
  latency evaluation, composed-presentation primitives, and the gallery
  animation regression record live with implementation/post-mortem records
  instead of current planned/active work. See
  `0c8b73f2` [docs/plans/2026-05-02-001-cpu-latency-evaluation-pipeline-plan.md](docs/plans/2026-05-02-001-cpu-latency-evaluation-pipeline-plan.md),
  `e9ab33a5` [docs/plans/2026-05-02-002-composed-presentation-primitives-plan.md](docs/plans/2026-05-02-002-composed-presentation-primitives-plan.md),
  and `16e38b42` [docs/plans/2026-05-01-007-gallery-animation-regression-notes.md](docs/plans/2026-05-01-007-gallery-animation-regression-notes.md).
- `41ed1600` Added the changelog workflow and documented that completed
  active-work items move out of `active_work.md` into concise, self-standing
  changelog entries. See `41ed1600` [CHANGELOG.md](CHANGELOG.md) and
  `41ed1600` [active_work.md](active_work.md).
- `4ee7a8f9` Re-audited remaining repo work and expanded the active-work queue
  with documentation hygiene, runtime/public-surface, Canvas/pointer, and
  accessibility follow-ups. See `4ee7a8f9` [active_work.md](active_work.md).
- `8fcb8710` Added the repo-root active-work tracker and pointed the README
  and agent guide at it as the first place to check incomplete work. See
  `8fcb8710` [active_work.md](active_work.md).
- `e2dc520f` Published the durable shipped accessibility guide covering the
  semantic substrate, runtime policy, target bridges, guardrails, and remaining
  gaps. See `e2dc520f` [docs/ACCESSIBILITY.md](docs/ACCESSIBILITY.md).
- `271473ad` Added the public reduced-motion environment API with SwiftUI-style
  naming through `EnvironmentValues.accessibilityReduceMotion`. See
  `271473ad` [Sources/SwiftTUIViews/Environment/RuntimePolicyEnvironment.swift](Sources/SwiftTUIViews/Environment/RuntimePolicyEnvironment.swift).

## 2026-05-06

- `3e465e7f` Shipped the compile-time opt-in embedded WebHost stack: package
  boundary guardrails, shared web-surface adapters, HTTP/WebSocket server,
  browser runtime bundle, combined CLI runner, and gallery verification. See
  `3e465e7f` [docs/plans/2026-05-06-002-embedded-web-host-compile-time-plan.md](docs/plans/2026-05-06-002-embedded-web-host-compile-time-plan.md)
  and `3e465e7f` [Platforms/WebHost](Platforms/WebHost).
- `7b8c3280` Shipped text input model v1 for `TextField`, `SecureField`, and
  `TextEditor`, including value/selection storage, reducer behavior, paste
  routing, gallery coverage, caret anchoring, and accessibility status. See
  `7b8c3280` [docs/plans/2026-05-06-001-text-input-model-v1-plan.md](docs/plans/2026-05-06-001-text-input-model-v1-plan.md).
- `690d5269` Added accessibility guardrails for raw glyphs, color-state
  styling, visual-only content, and manual listening evidence. See
  `690d5269` [docs/ACCESSIBILITY.md](docs/ACCESSIBILITY.md),
  `690d5269` [Scripts/check_accessibility_guardrails.sh](Scripts/check_accessibility_guardrails.sh),
  and `690d5269` [prek.toml](prek.toml).

## 2026-05-05

- `79df823b` Completed the accessibility runtime and host bridge rollout across
  terminal, Web/WASI, and SwiftUI hosting: semantic nodes, cursor-as-focus,
  linear output, motion/progress policy, live regions, ARIA transport, and a
  SwiftUI accessibility overlay.
- `e71f7cd5` Made `AnyView` resilient across retained graph updates by adding
  type-aware payload identity, preserving explicit authored IDs, and documenting
  consumer and maintainer policy. See
  `e71f7cd5` [docs/ANYVIEW_INTERNALS.md](docs/ANYVIEW_INTERNALS.md) and
  `e71f7cd5` [Sources/SwiftTUIViews/SwiftTUIViews.docc/AnyView.md](Sources/SwiftTUIViews/SwiftTUIViews.docc/AnyView.md).
- `4278c485` Shipped the `SwiftTUIArguments` peer package with standard
  framework flags, env-var resolution, `SwiftTUIApp` easy mode, CLIMode
  subcommands, and completion script printing/install helpers. See
  `4278c485` [docs/plans/2026-05-04-002-argument-parsing-plan.md](docs/plans/2026-05-04-002-argument-parsing-plan.md)
  and `4278c485` [Platforms/Arguments](Platforms/Arguments).
- `e3178a74` Shipped terminal-program embedding through `TerminalView`,
  `TerminalSession`, `TerminalProcessSession`, PTY process integration, input
  mode handling, render-diff validation, and the file-previewer example. See
  `e3178a74` [docs/plans/2026-05-04-001-terminal-embedding-plan.md](docs/plans/2026-05-04-001-terminal-embedding-plan.md),
  `e3178a74` [Platforms/Embedding](Platforms/Embedding), and
  `e3178a74` [Examples/file-previewer](Examples/file-previewer).
- `0c075e1f` Migrated `gifcat` and `gifeditor` to the `SwiftTUIApp` easy-mode
  argument-parsing path, proving the framework-owned command surface in real
  example packages.
- `1b07047f` Hardened terminal text rendering against control-sequence
  injection, and `2446ae08` hardened OSC 8 hyperlink destinations against
  unsafe terminal output.
- `0d80debd` Fixed a PNG decoder memory-safety issue, `ed86470e` bounded the
  TextFigure metrics cache, and `cb8d07e6` fixed a state-session vulnerability.

## 2026-05-04

- `e2fe0d9b` Reorganized the source tree around the package boundaries and
  seven-phase rendering pipeline so subsystem ownership is visible in paths and
  docs. See `e2fe0d9b` [docs/SOURCE_LAYOUT.md](docs/SOURCE_LAYOUT.md).
- `64e2a480` Finished TermUIPerf bundled-file splits, repaired the performance
  tool after the source reorganization, and put perf tests behind the repo gate.
  See `64e2a480` [Tools/TermUIPerf](Tools/TermUIPerf).

## 2026-05-03

- `47672b9c` Split finite pre-composed animated image and GIF behavior into the
  `SwiftTUIAnimatedImage` peer product, updated `gifcat` to consume it, and
  documented the media boundary. See
  `47672b9c` [Sources/SwiftTUIAnimatedImage](Sources/SwiftTUIAnimatedImage) and
  `47672b9c` [docs/VISION.md](docs/VISION.md).

## 2026-05-02

- `0c8b73f2` Shipped the CPU-versus-latency evaluation pipeline with runtime
  render-mode selection, deterministic scenarios, process CPU sampling,
  artifacts, comparison commands, CI archiving, and workflow docs. See
  `0c8b73f2` [docs/plans/2026-05-02-001-cpu-latency-evaluation-pipeline-plan.md](docs/plans/2026-05-02-001-cpu-latency-evaluation-pipeline-plan.md),
  `0c8b73f2` [docs/PERFORMANCE_EVALUATION.md](docs/PERFORMANCE_EVALUATION.md),
  and `0c8b73f2` [Tools/TermUIPerf](Tools/TermUIPerf).
- `e9ab33a5` Replaced presentation-specific overlay hoisting with composed
  primitives for portals, overlay stacks, interaction gates, and dismiss stacks,
  with runtime and gifeditor coverage. See
  `e9ab33a5` [docs/plans/2026-05-02-002-composed-presentation-primitives-plan.md](docs/plans/2026-05-02-002-composed-presentation-primitives-plan.md).
- `bfa989cf` Rebranded the repo and public documentation around SwiftTUI. See
  `bfa989cf` [README.md](README.md) and
  `bfa989cf` [docs/README.md](docs/README.md).

## 2026-05-01

- `16e38b42` Fixed the gallery one-shot animation regression by replaying
  cancelled animation intent into the replacement frame after pre-start async
  tail cancellation. See
  `16e38b42` [docs/plans/2026-05-01-007-gallery-animation-regression-notes.md](docs/plans/2026-05-01-007-gallery-animation-regression-notes.md).
- `4e848eae` Completed the async frame-head draft-transaction path with
  prepared-frame abort proof, retained-state checkpoints, and queued-tail
  cancellation behavior. See
  `4e848eae` [docs/plans/2026-05-01-006-async-frame-head-draft-transaction-plan.md](docs/plans/2026-05-01-006-async-frame-head-draft-transaction-plan.md)
  and `4e848eae` [docs/ASYNC_RENDERING.md](docs/ASYNC_RENDERING.md).
- `d99719a1` Shipped layout-dependent content realization for
  `GeometryReader`, geometry preferences, and measurement-dependent containers.
  See
  `d99719a1` [docs/plans/2026-05-01-001-layout-dependent-content-realization-plan.md](docs/plans/2026-05-01-001-layout-dependent-content-realization-plan.md).
- `88d8a898` Shipped public anchor tokens, anchor preferences,
  `GeometryProxy` anchor resolution, and geometry-bound preference overlays. See
  `88d8a898` [docs/plans/2026-05-01-002-public-anchor-geometry-preferences-plan.md](docs/plans/2026-05-01-002-public-anchor-geometry-preferences-plan.md).
- `9c56edf8` Hardened layout-dependent container geometry with focused
  regression tests and docs for `safeAreaInset`, `ScrollView`, `ViewThatFits`,
  lazy stacks, and custom `Layout`. See
  `9c56edf8` [docs/plans/2026-05-01-004-layout-dependent-container-hardening-plan.md](docs/plans/2026-05-01-004-layout-dependent-container-hardening-plan.md).

## 2026-04-29

- `af34396d` Added an auto-generated public API inventory, a diff-checkable
  baseline, and metadata needed to police package-only seams. See
  `af34396d` [docs/PUBLIC_API_INVENTORY.md](docs/PUBLIC_API_INVENTORY.md) and
  `af34396d` [docs/PUBLIC_API_BASELINE.md](docs/PUBLIC_API_BASELINE.md).
- `9f3ee3f8` Wired checked-in plans and proposals into the website/documentation
  surface so implementation plans can be browsed from generated docs.

## 2026-04-28

- `81d11ad8` Extended `Canvas` for dense pixel-grid rendering with direct cell
  writes, full-cell and vertical half-block pixel grids, styled Braille cells,
  a Canvas example, and a Canvas-backed gifeditor migration. See
  `81d11ad8` [docs/plans/2026-04-28-001-canvas-adaptation-plan.md](docs/plans/2026-04-28-001-canvas-adaptation-plan.md),
  `81d11ad8` [Sources/SwiftTUIViews/Canvas.swift](Sources/SwiftTUIViews/Canvas.swift), and
  `81d11ad8` [Examples/gifeditor](Examples/gifeditor).
- `1d035917` Added JPEG and GIF codec integration, decoded-image dispatch, and
  terminal graphics verification groundwork for richer image and animation
  surfaces.

## 2026-04-26

- `2063bdca` Shipped off-main frame-tail rendering: extracted the synchronous
  frame tail, isolated retained tail state, staged animation overlays across the
  tail boundary, added a worker renderer, and recorded runtime results. See
  `2063bdca` [docs/plans/2026-04-26-001-off-main-frame-tail-rendering-plan.md](docs/plans/2026-04-26-001-off-main-frame-tail-rendering-plan.md)
  and `2063bdca` [docs/ASYNC_RENDERING.md](docs/ASYNC_RENDERING.md).
- `084ab185` Recorded the prepared frame-head abort experiment as reverted,
  preserving the post-mortem and constraints that shaped the later async
  draft-transaction approach. See
  `084ab185` [docs/plans/2026-04-26-002-frame-head-abort-plan.md](docs/plans/2026-04-26-002-frame-head-abort-plan.md).

## 2026-04-24

- `32ecec01` Shipped the layouts example and behavior-test suite, giving the
  repo a broad SwiftUI comparison surface for layout, focus, presentation,
  canvas, matched geometry, list, table, and custom layout cases. See
  `32ecec01` [docs/plans/2026-04-24-001-layouts-example-plan.md](docs/plans/2026-04-24-001-layouts-example-plan.md)
  and `32ecec01` [Examples/layouts](Examples/layouts).

## 2026-04-20

- `6c41a052` Shipped `CellPixelMetrics` through geometry, environment, hosted
  resize, runtime refresh, draw-time style snapshots, and aspect-correct shape
  rendering. See
  `6c41a052` [docs/plans/2026-04-20-001-cell-pixel-metrics-plan.md](docs/plans/2026-04-20-001-cell-pixel-metrics-plan.md)
  and `6c41a052` [docs/proposals/CELL_PIXEL_METRICS.md](docs/proposals/CELL_PIXEL_METRICS.md).
- `be28568a` Shipped drop destinations scoped to `ActionScope`, including
  dropped-path parsing, paste-event dispatch, leafmost-first runtime routing,
  and a gallery file-drop demo. See
  `be28568a` [docs/plans/2026-04-20-002-drop-destination-plan.md](docs/plans/2026-04-20-002-drop-destination-plan.md).

## 2026-04-18

- `a4c0b3f3` Shipped the terminal gesture model: coordinate spaces,
  `@GestureState`, tap, spatial tap, drag, long press, exclusive gestures,
  gesture masks, content shapes, pointer capture, and subtree teardown cleanup.
  See `a4c0b3f3` [docs/proposals/GESTURES_IMPLEMENTATION.md](docs/proposals/GESTURES_IMPLEMENTATION.md)
  and `a4c0b3f3` [Sources/SwiftTUIViews/Gestures](Sources/SwiftTUIViews/Gestures).
- `fe30d65b` Hardened terminal repaint behavior with range-aware presentation
  damage, incremental row writes, full-repaint synchronization, separate Kitty
  graphics replay, and steady-state paint-path tests. See
  `fe30d65b` [docs/RUNTIME.md](docs/RUNTIME.md) and
  `fe30d65b` [Sources/SwiftTUI/Terminal/TerminalPresentation.swift](Sources/SwiftTUI/Terminal/TerminalPresentation.swift).

## 2026-04-17

- `5fb8b634` Shipped the ActionScope command surface: `ActionScope`, scoped
  `CommandRegistry`, `Panel`, focus containment, `.keyCommand`,
  `.paletteCommand`, `.toolbar`, `.toolbarItem`, and scene/presentation scope
  boundaries. See
  `5fb8b634` [docs/proposals/ACTION_SCOPES_AND_COMMANDS.md](docs/proposals/ACTION_SCOPES_AND_COMMANDS.md)
  and `5fb8b634` [Sources/SwiftTUIViews/ActionScopes](Sources/SwiftTUIViews/ActionScopes).

## 2026-04-14

- `4765881a` Added host-package and graphics foundations around SwiftTerm,
  SwiftUI hosting, XTerm.js/Web hosting experiments, and Kitty image rendering
  for the `Image` surface. See `4765881a` [docs/HOST_PACKAGES.md](docs/HOST_PACKAGES.md),
  `4765881a` [Platforms/SwiftUI](Platforms/SwiftUI), and
  `4765881a` [Sources/SwiftTUI/Terminal/TerminalImageRendering.swift](Sources/SwiftTUI/Terminal/TerminalImageRendering.swift).

## 2026-04-13

- `c2e74728` Landed the animatable-value migration path and richer animation
  model, including `Animatable` conformances, unit-point gradients, compound
  interpolation, unified animation side channels, and `PhaseAnimator` polish.
  See `c2e74728` [docs/proposals/ANIMATABLE_PROTOCOL_MIGRATION.md](docs/proposals/ANIMATABLE_PROTOCOL_MIGRATION.md)
  and `c2e74728` [Sources/SwiftTUIViews/Animation](Sources/SwiftTUIViews/Animation).

## 2026-04-11

- `050bd529` Shipped the shape and border revamp: `BorderSet`, per-side border
  styling, outset/inset border layout, gradients and pattern fills, Braille
  curved shapes, `Circle`, `Ellipse`, `Capsule`, `BorderBlend`, and the initial
  `Canvas` draw pipeline. See
  `050bd529` [docs/proposals/SHAPE_AND_BORDER_APIS.md](docs/proposals/SHAPE_AND_BORDER_APIS.md),
  `050bd529` [Sources/SwiftTUIViews/Shapes](Sources/SwiftTUIViews/Shapes), and
  `050bd529` [Sources/SwiftTUIViews/Canvas.swift](Sources/SwiftTUIViews/Canvas.swift).

## 2026-04-10

- `7a8d9542` Closed the first animation audit by wiring transition overlays,
  opacity compositing, custom animation evaluation, repeat/autoreverse behavior,
  completion callbacks, independent padding/frame animation, matched geometry,
  `PhaseAnimator`, and gallery regression probes. See
  `7a8d9542` [docs/proposals/ANIMATION_PLAN.md](docs/proposals/ANIMATION_PLAN.md)
  and `7a8d9542` [Examples/gallery](Examples/gallery).

## 2026-04-09

- `57f6f756` Rebuilt the gallery as a focused integration app with counter,
  todo, calculator, command-palette, animation, image, physics, life, and
  border/shape tabs plus package-level tests. See
  `57f6f756` [Examples/gallery](Examples/gallery).
- `cb4727ba` Stabilized presentation behavior around sheets, alerts, toasts,
  command palettes, overlay resolution, and deferred-content state identity.
  See `cb4727ba` [docs/proposals/ASYNC_PRESENTATION.md](docs/proposals/ASYNC_PRESENTATION.md)
  and `cb4727ba` [Sources/SwiftTUIViews/Presentation](Sources/SwiftTUIViews/Presentation).

## 2026-04-08

- `5a04e706` Added the `TextFigure` / embedded FIGlet surface and supporting
  vendored font package integration for terminal-native large text. See
  `5a04e706` [Sources/SwiftTUIViews/Primitives/TextFigure.swift](Sources/SwiftTUIViews/Primitives/TextFigure.swift)
  and `5a04e706` [Vendor/swift-figlet](Vendor/swift-figlet).

## 2026-04-03

- `d7e41bcd` Established the scene and runner split with `App`, `Scene`,
  scene manifests, hosted scene sessions, CLI runner separation, and WASI
  runner groundwork. See `d7e41bcd` [Sources/SwiftTUI/Scenes](Sources/SwiftTUI/Scenes),
  `d7e41bcd` [Platforms/CLI](Platforms/CLI), and `d7e41bcd` [Platforms/WASI](Platforms/WASI).

## 2026-04-02

- `7e335623` Documented state keying and graph ownership while the runtime
  moved toward retained graph evaluation, async presentation boundaries, and
  off-main terminal presentation writes. See
  `7e335623` [docs/STATE_KEYING.md](docs/STATE_KEYING.md),
  `7e335623` [docs/proposals/ASYNC_PRESENTATION.md](docs/proposals/ASYNC_PRESENTATION.md),
  and `7e335623` [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## 2026-03-31

- `5e4a3f03` Added viewport-lazy `LazyVStack` and `LazyHStack` behavior, then
  extended laziness through single-`ForEach` rows. See
  `5e4a3f03` [Sources/SwiftTUIViews/Stacks/LazyVStack.swift](Sources/SwiftTUIViews/Stacks/LazyVStack.swift)
  and `5e4a3f03` [Sources/SwiftTUIViews/Stacks/LazyHStack.swift](Sources/SwiftTUIViews/Stacks/LazyHStack.swift).
- `690d373d` Brought up the first WASM/Web example path with WASI build/run
  fixes and browser-side scene transport groundwork. See
  `690d373d` [Examples/WebExample](Examples/WebExample) and
  `690d373d` [Platforms/Web](Platforms/Web).

## 2026-03-30

- `46f294f0` Turned the prototype into documented SwiftUI-shaped architecture,
  including the early retained graph, `AnyView`, preferences, presentations,
  TabView, segmented picker, color gallery, and SwiftUI/Web example shells. See
  `46f294f0` [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md),
  `46f294f0` [Sources/SwiftTUIViews](Sources/SwiftTUIViews), and
  `46f294f0` [Examples/README.md](Examples/README.md).

## 2026-03-28

- `8830fb6d` Started the repository as a SwiftUI-inspired terminal UI
  prototype with a terminal-native render pipeline and demo application path.
  See `8830fb6d` [README.md](README.md) and
  `8830fb6d` [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
