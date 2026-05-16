# Changelog

Completed TODO history lives here. Keep entries concise, self-standing, and
newest first. Long-form design notes, validation records, and API details belong
in the durable docs, plans, source, or tests linked from an entry.

## Rules

- Move completed items removed from `TODO.md` into this file.
- Each entry must say what changed without requiring readers to open another
  document.
- Entries may link to long-lived repo documentation, plans, source, or tests for
  detail.
- Every link in an entry must be prefixed with the short git hash that anchors
  the linked material, for example:
  `4ee7a8f9` [TODO.md](TODO.md).
- Keep completed-work summaries out of `TODO.md`.

## 2026-05-16

- Prepared the first release-facing alpha posture for `0.1.0`: added root
  license, contribution, security, and release-policy files; restored vendored
  license/provenance files for UnixSignals and swift-figlet; added package
  license metadata; documented install, support, and product-tier guidance; and
  populated the live TODO tracker with remaining unresolved decisions.
- Repaired P0 correctness hazards around public bindings, invalid color input,
  stale SwiftUI host frames, WebHost sink backpressure, and default launcher
  error reporting.
- Restored automatic CI coverage for push and pull request traffic with
  `swiftly`-aligned Linux/macOS gates, policy checks, and an iOS package build
  check.

## 2026-05-14

- Implemented the internal `Platforms/Web` package split: `@swifttui/web` now
  owns browser runtime and WASI scene-runtime APIs, `@swifttui/build` owns
  manifest/WASI packaging helpers, WebExample consumes both packages, and public
  runtime entrypoints are tested against importing build tooling.
- Closed the local-browser WebHost v1 polish investigation and removed it from
  active TODO tracking; future work should be filed as scoped follow-up items
  instead of keeping the broad investigation open. See `c3c6459d`
  [docs/proposals/LOCAL_BROWSER_HOST_LEARNINGS.md](proposals/LOCAL_BROWSER_HOST_LEARNINGS.md).
- Formalized the semantic host-frame presentation contract: the runtime now
  produces sequenced `SemanticHostFrame` values for semantic host-frame
  consumers, retained native, WebHost, and WASI surfaces use the formal protocol
  name, and accessibility announcement publication is controlled by explicit
  host-frame capabilities instead of incidental protocol conformance.

## 2026-05-13

- Promoted presentation damage into the shared host presentation contract:
  Web/WASI, SwiftUIHost, and CLI now receive the same frame-tail damage signal,
  semantic hosts can consume raster, semantics, focus, and damage together, and
  Web/SwiftUI presentation paths use dirty-region redraws instead of repainting
  every compatible frame.

## 2026-05-12

- Shipped late preference reconciliation in the runtime frame tail: toolbar hosts
  now absorb `.toolbarItem(...)` values emitted by realized
  layout-dependent content before commit, re-run layout when toolbar chrome
  changes geometry, preserve async worker offload for unaffected trees, and expose
  toolbar item labels through Web/WASI accessibility output.
- Shipped anchored popover presentation: Boolean and item-driven `.popover`
  modifiers plus a TipKit-inspired `.popoverTip` convenience now render compact
  source-relative overlays with terminal edge fallback, Escape dismissal, modal
  gating for interactive content, non-modal read-only tips, and a gallery
  `Popovers` tab.
- Shipped the first-class terminal workspace V1 as the
  `SwiftTUITerminalWorkspace` product: apps can model tabbed split-pane
  terminal workspaces with stable pane IDs, retained sessions, pane commands,
  zoom, layout persistence, and a Zellij-style example package.
- Added a host-facing runtime issue channel and used it for unhosted
  `.toolbarItem(...)` declarations: CLI hosts forward issues to stderr, SwiftUI
  hosts log through OSLog, web hosts send typed runtime-issue records for
  browser console logging, and frame diagnostics now include the runtime issues
  observed during the frame.
- Added a gallery `Scroll Control` tab that demonstrates `ScrollViewReader`
  and `ScrollViewProxy` identity, anchor, edge, and offset commands through the
  public example app.
- `da7eab74` Implemented deeper scroll control V1: `ScrollViewReader` and
  `ScrollViewProxy` now support identity, anchor, edge, and offset scrolling
  through committed scroll-target geometry, and focused scroll views handle
  Home/End movement. Semantic `ScrollPosition` binding, target behavior,
  scrollback conventions, and host observation hooks remain deferred by the
  scope plan. See `da7eab74`
  [docs/plans/2026-05-09-003-deeper-scroll-control-scope.md](plans/2026-05-09-003-deeper-scroll-control-scope.md).
- Fixed toolbar item actions built without a construction-time authoring context:
  `.toolbarItem(config)` now supplies the attachment context instead of letting
  the config's nil snapshot clear it, so externally assembled configs can still
  mutate view-local state when fired from the rendered toolbar.
- Broadened the builder-form `.toolbarItem(...)` title extraction to resolve
  composed label views and collect text from the label subtree, covering labels
  such as small stacks of `Text` rather than only a direct `Text` value.
- Linked the gallery views target to `SwiftTUIAnimatedImage` and added an
  `Animated GIF` tab that decodes the embedded GIF fixture through the peer
  animated-image product and renders it with `AnimatedImage`.

## 2026-05-11

- Implemented the release-facing public product/import contract: `SwiftTUI` is
  now the one-import terminal app convenience product, `SwiftTUIRuntime` is the
  platform-neutral runtime/composition product, host products depend below the
  convenience layer, and `SwiftTUIWebHostCLI` is the explicit import
  replacement for binaries that support both terminal and `--web` launch.
- Merged first-party Swift platform integrations into the root package:
  external consumers now add one `swift-tui` package dependency and select
  products such as `SwiftTUICLI`, `SwiftTUIWASI`, `SwiftUIHost`,
  `SwiftTUIWebHost`, `SwiftTUIWebHostCLI`, `SwiftTUITerminal`, and
  `SwiftTUIPTYPrimitives`. The `Platforms/` tree remains source layout,
  `Platforms/Web` remains the Bun browser package, and examples remain
  separate mini packages.

## 2026-05-10

- Reshaped framework argument parsing around additive `SwiftTUICommand`
  conformance instead of making the argument-parsing protocol subsume `App`.
  `App.init()` is now nonisolated, runner products own the default launch path,
  WebHost-capable apps can opt into the combined runner without the
  terminal-only `--web` error, and example apps no longer need app-level
  `@preconcurrency` conformances.

## 2026-05-09

- `cf86a3a4` Shipped binding-driven navigation destination presentation:
  `NavigationStack`, `navigationDestination(isPresented:)`, and
  `navigationDestination(item:)` now render stack-owned destinations without
  `NavigationLink` or automatic Back chrome, and Escape pops destinations only
  after active modal presentations have dismissed. See `cf86a3a4`
  [docs/proposals/NAVIGATION_DESTINATION_PRESENTATION.md](proposals/NAVIGATION_DESTINATION_PRESENTATION.md),
  `cf86a3a4`
  [Sources/SwiftTUIViews/NavigationViews/NavigationStack.swift](../Sources/SwiftTUIViews/NavigationViews/NavigationStack.swift),
  and `cf86a3a4`
  [Tests/SwiftTUITests/NavigationDestinationTests.swift](../Tests/SwiftTUITests/NavigationDestinationTests.swift).
- Added cross-host clipboard writing for focused text inputs and embedded
  terminal children. `TextEditor` / `TextField` copy and cut now route through
  terminal OSC 52, hosted raster sessions, SwiftUI native pasteboards, Web/WASI
  typed clipboard records, and `TerminalView` child OSC 52 forwarding; the
  default runtime exit key moved from ctrl-c to ctrl-d so ctrl-c can copy.
- Completed the `TextEditor` V2 tranche: focused range selections now render
  through shared text-input display runs and layout-map selection rects, ctrl-a
  select-all is pinned through the runtime, and host transport,
  IME/composition, and large-document storage are recorded as explicit
  deferrals rather than active TODO work.
- Scoped the `TextEditor` V2 tranche into a dated plan and shipped the
  package-private shortcut foundation: shared word-boundary navigation,
  word-deletion, and ctrl-a select-all now flow through the reducer and the
  composed `TextEditor` runtime path. Remaining V2 work stays in `TODO.md`.
- Shipped namespace-scoped default-focus APIs and reset behavior:
  `.prefersDefaultFocus(_:in:)`, `.focusScope(_:)`, and `resetFocus` now route
  through the runtime focus tracker, while focused-object support was removed
  from planned work.
- Expanded the remaining status-stub tracker into scoped TODO items and removed
  the backlog prose from `STATUS.md`, leaving status as the high-level overview
  while live planned work lives in `TODO.md`.
- Moved the repo-owned work tracker and completed-work history into `docs/` as
  `TODO.md` and `CHANGELOG.md`, and documented the binding with `STATUS.md`:
  status remains the high-level overview, while any planned or decision-bound
  status gap must have a corresponding TODO item.
- Closed the Canvas/pointer decision work: `PointerPath` is documented as a
  complete current-gesture path, closure-backed `Canvas` authoring is public
  with identity-based equality, `.pixelExact` is hidden until a real graphics
  renderer exists, and the standalone Canvas example remains out of scope.
- Retired the remaining package-only `[AnyView]` builder traversal from
  `DeclaredChildrenView` and its structural builder conformers. Builder
  children now use the typed resolve, deferred payload, portal payload, and
  metadata-first enumeration paths, leaving `buildLimitedAvailability`, public
  `AnyView`, and explicit policy-reviewed escape hatches as the intended
  production erasure seams.
- `136924f3` Completed the SwiftUI host native VoiceOver focus bridge: runtime
  focus now resolves through the host overlay mappings into a host-owned
  `AccessibilityFocusState`, removed focused nodes clear the native focus
  request, and host-level tests pin the one-way runtime-to-native behavior.
  Bidirectional VoiceOver traversal back into SwiftTUI runtime focus remains a
  separate contract. See `cb94ee17`
  [docs/decisions/0015-accessibility-swiftui-host-policy.md](decisions/0015-accessibility-swiftui-host-policy.md),
  `136924f3`
  [Platforms/SwiftUI/Sources/SwiftUIHost/HostedAccessibilityOverlay.swift](../Platforms/SwiftUI/Sources/SwiftUIHost/HostedAccessibilityOverlay.swift),
  `a332e626`
  [Platforms/SwiftUI/Sources/SwiftUIHost/HostedAccessibilityFocusPolicy.swift](../Platforms/SwiftUI/Sources/SwiftUIHost/HostedAccessibilityFocusPolicy.swift),
  and `d73379a8`
  [Platforms/SwiftUI/Tests/SwiftUIHostTests/SwiftUIHostAccessibilityTests.swift](../Platforms/SwiftUI/Tests/SwiftUIHostTests/SwiftUIHostAccessibilityTests.swift).
- `2b76774e` Wired the remaining framework-owned runtime flags: `--json` /
  `SWIFTTUI_JSON=1` now emit machine-readable frame JSON, standalone
  `--linear` / `SWIFTTUI_LINEAR=1` select accessible linear output, and
  framework-owned `--start-in` / `SWIFTTUI_START_IN` was removed so launch
  routing stays app-owned. See `2b76774e`
  [Sources/SwiftTUI/Accessibility/LinearAccessibilityRenderer.swift](../Sources/SwiftTUI/Accessibility/LinearAccessibilityRenderer.swift),
  `2b76774e`
  [Sources/SwiftTUI/RunLoop/RunLoop+Rendering.swift](../Sources/SwiftTUI/RunLoop/RunLoop+Rendering.swift),
  `2b76774e`
  [Platforms/Arguments/Sources/SwiftTUIArguments/SwiftTUIOptions.swift](../Platforms/Arguments/Sources/SwiftTUIArguments/SwiftTUIOptions.swift),
  and `2b76774e`
  [Tests/SwiftTUITests/JSONFrameRendererTests.swift](../Tests/SwiftTUITests/JSONFrameRendererTests.swift).

## 2026-05-08

- `bc531320` Completed the modal accessibility focus contract for `sheet`,
  `alert`, and `confirmationDialog`: modal focus regions now carry presentation
  scope metadata, focus cycles inside active modal presentations, and dismissal
  restores the previously focused background control when it still exists. See
  `bc531320` [Sources/SwiftTUICore/Semantics/FocusTracker.swift](../Sources/SwiftTUICore/Semantics/FocusTracker.swift),
  `bc531320` [Sources/SwiftTUICore/Semantics/Semantics.swift](../Sources/SwiftTUICore/Semantics/Semantics.swift),
  and `bc531320` [Tests/SwiftTUITests/PresentationActionScopeTests.swift](../Tests/SwiftTUITests/PresentationActionScopeTests.swift).
- `964b7191` Completed reduced-motion behavior across the remaining animated
  surfaces: `PhaseAnimator` and `AnimatedImage` no longer start playback tasks
  when reduced motion is active, transition intermediates and matched geometry
  are covered by disabled animation transactions, and the accessibility docs no
  longer list reduced motion as an open gap. See
  `964b7191` [Sources/SwiftTUIViews/Animation/PhaseAnimator.swift](../Sources/SwiftTUIViews/Animation/PhaseAnimator.swift),
  `964b7191` [Sources/SwiftTUIAnimatedImage/AnimatedImage.swift](../Sources/SwiftTUIAnimatedImage/AnimatedImage.swift),
  `964b7191` [Tests/SwiftTUITests/MotionAndProgressPolicyTests.swift](../Tests/SwiftTUITests/MotionAndProgressPolicyTests.swift),
  and `964b7191` [docs/ACCESSIBILITY.md](ACCESSIBILITY.md).
- `7b32d595` Cleaned up stale historical accessibility proposal open questions:
  resolved questions now point to ADR-0011 through ADR-0015 and shipped
  behavior, while only modal-focus and native-host-focus policy remain listed
  as proposal-level questions after the reduced-motion completion. See
  `7b32d595` [docs/proposals/ACCESSIBILITY.md](proposals/ACCESSIBILITY.md)
  and `e2dc520f` [docs/ACCESSIBILITY.md](ACCESSIBILITY.md).
- `f12401cf` Replaced `.task(id:)` reflected-value descriptor identity with
  retained value comparison in the view graph, preserving the public
  `ID: Equatable` overload while making task restart decisions compare authored
  IDs directly. See
  `f12401cf` [Sources/SwiftTUIViews/Modifiers/ViewModifiers.swift](../Sources/SwiftTUIViews/Modifiers/ViewModifiers.swift),
  `f12401cf` [Sources/SwiftTUICore/Resolve/ViewGraph.swift](../Sources/SwiftTUICore/Resolve/ViewGraph.swift),
  and `f12401cf` [Tests/SwiftTUITests/LifecycleSelectiveEvaluationTests.swift](../Tests/SwiftTUITests/LifecycleSelectiveEvaluationTests.swift).
- `8f113e73` Removed the stale modifier-layer active item because the public
  `ViewModifier` / `ModifiedContent` migration has already shipped with
  primitive modifier lowering, modifier algebra tests, transition probing, and
  tab metadata peeking. See
  `8f113e73` [docs/proposals/VIEW_MODIFIER_LAYER.md](proposals/VIEW_MODIFIER_LAYER.md),
  `8f113e73` [Sources/SwiftTUIViews/Foundation/ViewModifier.swift](../Sources/SwiftTUIViews/Foundation/ViewModifier.swift),
  and `8f113e73` [Tests/SwiftTUIViewsTests/ViewModifierAlgebraTests.swift](../Tests/SwiftTUIViewsTests/ViewModifierAlgebraTests.swift).
- `4278c485` Wired `RuntimeConfiguration.debug` into the CLI runtime by enabling
  the existing frame diagnostics logger for `--debug` / `SWIFTTUI_DEBUG=1`, and
  narrowed the remaining runtime-configuration active item to the fields whose
  behavior still needs a fresh scope decision. See
  `4278c485` [Platforms/CLI/Sources/SwiftTUICLI/SceneRuntime.swift](../Platforms/CLI/Sources/SwiftTUICLI/SceneRuntime.swift),
  `4278c485` [Platforms/CLI/Tests/SwiftTUICLITests/SceneRuntimeTests.swift](../Platforms/CLI/Tests/SwiftTUICLITests/SceneRuntimeTests.swift),
  and `4278c485` [docs/proposals/ARGUMENT_PARSING.md](proposals/ARGUMENT_PARSING.md).
- `5cc2d3a4` Closed the stale plan-status tracker by retaining the shipped
  border/stroke and Canvas rendering plans as implementation records, and by
  moving the fractional-coordinate uncertainty into the Canvas/pointer active
  task for a fresh phase inventory. See
  `5cc2d3a4` [docs/plans/2026-04-26-003-border-stroke-simplification-plan.md](plans/2026-04-26-003-border-stroke-simplification-plan.md),
  `81d11ad8` [docs/plans/2026-04-28-001-canvas-adaptation-plan.md](plans/2026-04-28-001-canvas-adaptation-plan.md),
  and `0d3ba0b5` [docs/plans/FRACTIONAL_COORDINATE_SPACE_PLAN.md](plans/FRACTIONAL_COORDINATE_SPACE_PLAN.md).
- `7a8d9542` Reconciled the historical animation proposal docs with the shipped
  controller surface: completion callbacks, custom animation evaluation,
  repeat behavior, padding/border/flexible-frame animation, placed-level
  removal overlays, and matched-geometry translation are no longer listed as
  active gaps. See
  `7a8d9542` [docs/proposals/ANIMATION_PLAN.md](proposals/ANIMATION_PLAN.md)
  and `c2e74728` [docs/proposals/ANIMATABLE_PROTOCOL_MIGRATION.md](proposals/ANIMATABLE_PROTOCOL_MIGRATION.md).
- `5cc2d3a4` Refreshed the public API inventory for the shipped border/stroke
  simplification: placement now lives on `StrokeStyle`, removed stroke sugar
  presets are no longer documented as public, and the generated API baseline is
  current. See
  `5cc2d3a4` [docs/PUBLIC_API_INVENTORY.md](PUBLIC_API_INVENTORY.md)
  and `5cc2d3a4` [Sources/SwiftTUICore/Styling/Styling.swift](../Sources/SwiftTUICore/Styling/Styling.swift).
- `e3178a74` Reconciled the terminal-embedding tracker state by marking the
  implementation plan shipped, pointing the docs index at it as an
  implementation record, and removing the stale active-work item. See
  `e3178a74` [docs/plans/2026-05-04-001-terminal-embedding-plan.md](plans/2026-05-04-001-terminal-embedding-plan.md).
- `0c8b73f2` Refreshed shipped-tooling docs so the CPU latency evaluation
  proposal describes the delivered `Tools/TermUIPerf` harness and the argument
  parsing proposal no longer marks accessibility/WebHost runtime configuration
  fields as parsed-but-unwired. See
  `0c8b73f2` [docs/proposals/CPU_LATENCY_EVALUATION_PIPELINE.md](proposals/CPU_LATENCY_EVALUATION_PIPELINE.md)
  and `4278c485` [docs/proposals/ARGUMENT_PARSING.md](proposals/ARGUMENT_PARSING.md).
- `0c8b73f2` Reconciled the docs index with shipped plan front matter so CPU
  latency evaluation, composed-presentation primitives, and the gallery
  animation regression record live with implementation/post-mortem records
  instead of current planned/active work. See
  `0c8b73f2` [docs/plans/2026-05-02-001-cpu-latency-evaluation-pipeline-plan.md](plans/2026-05-02-001-cpu-latency-evaluation-pipeline-plan.md),
  `e9ab33a5` [docs/plans/2026-05-02-002-composed-presentation-primitives-plan.md](plans/2026-05-02-002-composed-presentation-primitives-plan.md),
  and `16e38b42` [docs/plans/2026-05-01-007-gallery-animation-regression-notes.md](plans/2026-05-01-007-gallery-animation-regression-notes.md).
- `41ed1600` Added the changelog workflow and documented that completed
  active-work items move out of `TODO.md` into concise, self-standing
  changelog entries. See `41ed1600` [CHANGELOG.md](CHANGELOG.md) and
  `41ed1600` [TODO.md](TODO.md).
- `4ee7a8f9` Re-audited remaining repo work and expanded the active-work queue
  with documentation hygiene, runtime/public-surface, Canvas/pointer, and
  accessibility follow-ups. See `4ee7a8f9` [TODO.md](TODO.md).
- `8fcb8710` Added the repo-root active-work tracker and pointed the README
  and agent guide at it as the first place to check incomplete work. See
  `8fcb8710` [TODO.md](TODO.md).
- `e2dc520f` Published the durable shipped accessibility guide covering the
  semantic substrate, runtime policy, target bridges, guardrails, and remaining
  gaps. See `e2dc520f` [docs/ACCESSIBILITY.md](ACCESSIBILITY.md).
- `271473ad` Added the public reduced-motion environment API with SwiftUI-style
  naming through `EnvironmentValues.accessibilityReduceMotion`. See
  `271473ad` [Sources/SwiftTUIViews/Environment/RuntimePolicyEnvironment.swift](../Sources/SwiftTUIViews/Environment/RuntimePolicyEnvironment.swift).

## 2026-05-06

- `3e465e7f` Shipped the compile-time opt-in embedded WebHost stack: package
  boundary guardrails, shared web-surface adapters, HTTP/WebSocket server,
  browser runtime bundle, combined CLI runner, and gallery verification. See
  `3e465e7f` [docs/plans/2026-05-06-002-embedded-web-host-compile-time-plan.md](plans/2026-05-06-002-embedded-web-host-compile-time-plan.md)
  and `3e465e7f` [Platforms/WebHost](../Platforms/WebHost).
- `7b8c3280` Shipped text input model v1 for `TextField`, `SecureField`, and
  `TextEditor`, including value/selection storage, reducer behavior, paste
  routing, gallery coverage, caret anchoring, and accessibility status. See
  `7b8c3280` [docs/plans/2026-05-06-001-text-input-model-v1-plan.md](plans/2026-05-06-001-text-input-model-v1-plan.md).
- `690d5269` Added accessibility guardrails for raw glyphs, color-state
  styling, visual-only content, and manual listening evidence. See
  `690d5269` [docs/ACCESSIBILITY.md](ACCESSIBILITY.md),
  `690d5269` [Scripts/check_accessibility_guardrails.sh](../Scripts/check_accessibility_guardrails.sh),
  and `690d5269` [prek.toml](../prek.toml).

## 2026-05-05

- `79df823b` Completed the accessibility runtime and host bridge rollout across
  terminal, Web/WASI, and SwiftUI hosting: semantic nodes, cursor-as-focus,
  linear output, motion/progress policy, live regions, ARIA transport, and a
  SwiftUI accessibility overlay.
- `e71f7cd5` Made `AnyView` resilient across retained graph updates by adding
  type-aware payload identity, preserving explicit authored IDs, and documenting
  consumer and maintainer policy. See
  `e71f7cd5` [docs/ANYVIEW_INTERNALS.md](ANYVIEW_INTERNALS.md) and
  `e71f7cd5` [Sources/SwiftTUIViews/SwiftTUIViews.docc/AnyView.md](../Sources/SwiftTUIViews/SwiftTUIViews.docc/AnyView.md).
- `4278c485` Shipped the `SwiftTUIArguments` peer package with standard
  framework flags, env-var resolution, `SwiftTUIApp` easy mode, CLIMode
  subcommands, and completion script printing/install helpers. See
  `4278c485` [docs/plans/2026-05-04-002-argument-parsing-plan.md](plans/2026-05-04-002-argument-parsing-plan.md)
  and `4278c485` [Platforms/Arguments](../Platforms/Arguments).
- `e3178a74` Shipped terminal-program embedding through `TerminalView`,
  `TerminalSession`, `TerminalProcessSession`, PTY process integration, input
  mode handling, render-diff validation, and the file-previewer example. See
  `e3178a74` [docs/plans/2026-05-04-001-terminal-embedding-plan.md](plans/2026-05-04-001-terminal-embedding-plan.md),
  `e3178a74` [Platforms/Embedding](../Platforms/Embedding), and
  `e3178a74` [Examples/file-previewer](../Examples/file-previewer).
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
  docs. See `e2fe0d9b` [docs/SOURCE_LAYOUT.md](SOURCE_LAYOUT.md).
- `64e2a480` Finished TermUIPerf bundled-file splits, repaired the performance
  tool after the source reorganization, and put perf tests behind the repo gate.
  See `64e2a480` [Tools/TermUIPerf](../Tools/TermUIPerf).

## 2026-05-03

- `47672b9c` Split finite pre-composed animated image and GIF behavior into the
  `SwiftTUIAnimatedImage` peer product, updated `gifcat` to consume it, and
  documented the media boundary. See
  `47672b9c` [Sources/SwiftTUIAnimatedImage](../Sources/SwiftTUIAnimatedImage) and
  `47672b9c` [docs/VISION.md](VISION.md).

## 2026-05-02

- `0c8b73f2` Shipped the CPU-versus-latency evaluation pipeline with runtime
  render-mode selection, deterministic scenarios, process CPU sampling,
  artifacts, comparison commands, CI archiving, and workflow docs. See
  `0c8b73f2` [docs/plans/2026-05-02-001-cpu-latency-evaluation-pipeline-plan.md](plans/2026-05-02-001-cpu-latency-evaluation-pipeline-plan.md),
  `0c8b73f2` [docs/PERFORMANCE_EVALUATION.md](PERFORMANCE_EVALUATION.md),
  and `0c8b73f2` [Tools/TermUIPerf](../Tools/TermUIPerf).
- `e9ab33a5` Replaced presentation-specific overlay hoisting with composed
  primitives for portals, overlay stacks, interaction gates, and dismiss stacks,
  with runtime and gifeditor coverage. See
  `e9ab33a5` [docs/plans/2026-05-02-002-composed-presentation-primitives-plan.md](plans/2026-05-02-002-composed-presentation-primitives-plan.md).
- `bfa989cf` Rebranded the repo and public documentation around SwiftTUI. See
  `bfa989cf` [README.md](../README.md) and
  `bfa989cf` [docs/README.md](README.md).

## 2026-05-01

- `16e38b42` Fixed the gallery one-shot animation regression by replaying
  cancelled animation intent into the replacement frame after pre-start async
  tail cancellation. See
  `16e38b42` [docs/plans/2026-05-01-007-gallery-animation-regression-notes.md](plans/2026-05-01-007-gallery-animation-regression-notes.md).
- `4e848eae` Completed the async frame-head draft-transaction path with
  prepared-frame abort proof, retained-state checkpoints, and queued-tail
  cancellation behavior. See
  `4e848eae` [docs/plans/2026-05-01-006-async-frame-head-draft-transaction-plan.md](plans/2026-05-01-006-async-frame-head-draft-transaction-plan.md)
  and `4e848eae` [docs/ASYNC_RENDERING.md](ASYNC_RENDERING.md).
- `d99719a1` Shipped layout-dependent content realization for
  `GeometryReader`, geometry preferences, and measurement-dependent containers.
  See
  `d99719a1` [docs/plans/2026-05-01-001-layout-dependent-content-realization-plan.md](plans/2026-05-01-001-layout-dependent-content-realization-plan.md).
- `88d8a898` Shipped public anchor tokens, anchor preferences,
  `GeometryProxy` anchor resolution, and geometry-bound preference overlays. See
  `88d8a898` [docs/plans/2026-05-01-002-public-anchor-geometry-preferences-plan.md](plans/2026-05-01-002-public-anchor-geometry-preferences-plan.md).
- `9c56edf8` Hardened layout-dependent container geometry with focused
  regression tests and docs for `safeAreaInset`, `ScrollView`, `ViewThatFits`,
  lazy stacks, and custom `Layout`. See
  `9c56edf8` [docs/plans/2026-05-01-004-layout-dependent-container-hardening-plan.md](plans/2026-05-01-004-layout-dependent-container-hardening-plan.md).

## 2026-04-29

- `af34396d` Added an auto-generated public API inventory, a diff-checkable
  baseline, and metadata needed to police package-only seams. See
  `af34396d` [docs/PUBLIC_API_INVENTORY.md](PUBLIC_API_INVENTORY.md) and
  `af34396d` [docs/PUBLIC_API_BASELINE.md](PUBLIC_API_BASELINE.md).
- `9f3ee3f8` Wired checked-in plans and proposals into the website/documentation
  surface so implementation plans can be browsed from generated docs.

## 2026-04-28

- `81d11ad8` Extended `Canvas` for dense pixel-grid rendering with direct cell
  writes, full-cell and vertical half-block pixel grids, styled Braille cells,
  a Canvas example, and a Canvas-backed gifeditor migration. See
  `81d11ad8` [docs/plans/2026-04-28-001-canvas-adaptation-plan.md](plans/2026-04-28-001-canvas-adaptation-plan.md),
  `81d11ad8` [Sources/SwiftTUIViews/Canvas.swift](../Sources/SwiftTUIViews/Canvas.swift), and
  `81d11ad8` [Examples/gifeditor](../Examples/gifeditor).
- `1d035917` Added JPEG and GIF codec integration, decoded-image dispatch, and
  terminal graphics verification groundwork for richer image and animation
  surfaces.

## 2026-04-26

- `2063bdca` Shipped off-main frame-tail rendering: extracted the synchronous
  frame tail, isolated retained tail state, staged animation overlays across the
  tail boundary, added a worker renderer, and recorded runtime results. See
  `2063bdca` [docs/plans/2026-04-26-001-off-main-frame-tail-rendering-plan.md](plans/2026-04-26-001-off-main-frame-tail-rendering-plan.md)
  and `2063bdca` [docs/ASYNC_RENDERING.md](ASYNC_RENDERING.md).
- `084ab185` Recorded the prepared frame-head abort experiment as reverted,
  preserving the post-mortem and constraints that shaped the later async
  draft-transaction approach. See
  `084ab185` [docs/plans/2026-04-26-002-frame-head-abort-plan.md](plans/2026-04-26-002-frame-head-abort-plan.md).

## 2026-04-24

- `32ecec01` Shipped the layouts example and behavior-test suite, giving the
  repo a broad SwiftUI comparison surface for layout, focus, presentation,
  canvas, matched geometry, list, table, and custom layout cases. See
  `32ecec01` [docs/plans/2026-04-24-001-layouts-example-plan.md](plans/2026-04-24-001-layouts-example-plan.md)
  and `32ecec01` [Examples/layouts](../Examples/layouts).

## 2026-04-20

- `6c41a052` Shipped `CellPixelMetrics` through geometry, environment, hosted
  resize, runtime refresh, draw-time style snapshots, and aspect-correct shape
  rendering. See
  `6c41a052` [docs/plans/2026-04-20-001-cell-pixel-metrics-plan.md](plans/2026-04-20-001-cell-pixel-metrics-plan.md)
  and `6c41a052` [docs/proposals/CELL_PIXEL_METRICS.md](proposals/CELL_PIXEL_METRICS.md).
- `be28568a` Shipped drop destinations scoped to `ActionScope`, including
  dropped-path parsing, paste-event dispatch, leafmost-first runtime routing,
  and a gallery file-drop demo. See
  `be28568a` [docs/plans/2026-04-20-002-drop-destination-plan.md](plans/2026-04-20-002-drop-destination-plan.md).

## 2026-04-18

- `a4c0b3f3` Shipped the terminal gesture model: coordinate spaces,
  `@GestureState`, tap, spatial tap, drag, long press, exclusive gestures,
  gesture masks, content shapes, pointer capture, and subtree teardown cleanup.
  See `a4c0b3f3` [docs/proposals/GESTURES_IMPLEMENTATION.md](proposals/GESTURES_IMPLEMENTATION.md)
  and `a4c0b3f3` [Sources/SwiftTUIViews/Gestures](../Sources/SwiftTUIViews/Gestures).
- `fe30d65b` Hardened terminal repaint behavior with range-aware presentation
  damage, incremental row writes, full-repaint synchronization, separate Kitty
  graphics replay, and steady-state paint-path tests. See
  `fe30d65b` [docs/RUNTIME.md](RUNTIME.md) and
  `fe30d65b` [Sources/SwiftTUI/Terminal/TerminalPresentation.swift](../Sources/SwiftTUI/Terminal/TerminalPresentation.swift).

## 2026-04-17

- `5fb8b634` Shipped the ActionScope command surface: `ActionScope`, scoped
  `CommandRegistry`, `Panel`, focus containment, `.keyCommand`,
  `.paletteCommand`, `.toolbar`, `.toolbarItem`, and scene/presentation scope
  boundaries. See
  `5fb8b634` [docs/proposals/ACTION_SCOPES_AND_COMMANDS.md](proposals/ACTION_SCOPES_AND_COMMANDS.md)
  and `5fb8b634` [Sources/SwiftTUIViews/ActionScopes](../Sources/SwiftTUIViews/ActionScopes).

## 2026-04-14

- `4765881a` Added host-package and graphics foundations around SwiftTerm,
  SwiftUI hosting, XTerm.js/Web hosting experiments, and Kitty image rendering
  for the `Image` surface. See `4765881a` [docs/HOST_PACKAGES.md](HOST_PACKAGES.md),
  `4765881a` [Platforms/SwiftUI](../Platforms/SwiftUI), and
  `4765881a` [Sources/SwiftTUI/Terminal/TerminalImageRendering.swift](../Sources/SwiftTUI/Terminal/TerminalImageRendering.swift).

## 2026-04-13

- `c2e74728` Landed the animatable-value migration path and richer animation
  model, including `Animatable` conformances, unit-point gradients, compound
  interpolation, unified animation side channels, and `PhaseAnimator` polish.
  See `c2e74728` [docs/proposals/ANIMATABLE_PROTOCOL_MIGRATION.md](proposals/ANIMATABLE_PROTOCOL_MIGRATION.md)
  and `c2e74728` [Sources/SwiftTUIViews/Animation](../Sources/SwiftTUIViews/Animation).

## 2026-04-11

- `050bd529` Shipped the shape and border revamp: `BorderSet`, per-side border
  styling, outset/inset border layout, gradients and pattern fills, Braille
  curved shapes, `Circle`, `Ellipse`, `Capsule`, `BorderBlend`, and the initial
  `Canvas` draw pipeline. See
  `050bd529` [docs/proposals/SHAPE_AND_BORDER_APIS.md](proposals/SHAPE_AND_BORDER_APIS.md),
  `050bd529` [Sources/SwiftTUIViews/Shapes](../Sources/SwiftTUIViews/Shapes), and
  `050bd529` [Sources/SwiftTUIViews/Canvas.swift](../Sources/SwiftTUIViews/Canvas.swift).

## 2026-04-10

- `7a8d9542` Closed the first animation audit by wiring transition overlays,
  opacity compositing, custom animation evaluation, repeat/autoreverse behavior,
  completion callbacks, independent padding/frame animation, matched geometry,
  `PhaseAnimator`, and gallery regression probes. See
  `7a8d9542` [docs/proposals/ANIMATION_PLAN.md](proposals/ANIMATION_PLAN.md)
  and `7a8d9542` [Examples/gallery](../Examples/gallery).

## 2026-04-09

- `57f6f756` Rebuilt the gallery as a focused integration app with counter,
  todo, calculator, command-palette, animation, image, physics, life, and
  border/shape tabs plus package-level tests. See
  `57f6f756` [Examples/gallery](../Examples/gallery).
- `cb4727ba` Stabilized presentation behavior around sheets, alerts, toasts,
  command palettes, overlay resolution, and deferred-content state identity.
  See `cb4727ba` [docs/proposals/ASYNC_PRESENTATION.md](proposals/ASYNC_PRESENTATION.md)
  and `cb4727ba` [Sources/SwiftTUIViews/Presentation](../Sources/SwiftTUIViews/Presentation).

## 2026-04-08

- `5a04e706` Added the `TextFigure` / embedded FIGlet surface and supporting
  vendored font package integration for terminal-native large text. See
  `5a04e706` [Sources/SwiftTUIViews/Primitives/TextFigure.swift](../Sources/SwiftTUIViews/Primitives/TextFigure.swift)
  and `5a04e706` [Vendor/swift-figlet](../Vendor/swift-figlet).

## 2026-04-03

- `d7e41bcd` Established the scene and runner split with `App`, `Scene`,
  scene manifests, hosted scene sessions, CLI runner separation, and WASI
  runner groundwork. See `d7e41bcd` [Sources/SwiftTUI/Scenes](../Sources/SwiftTUI/Scenes),
  `d7e41bcd` [Platforms/CLI](../Platforms/CLI), and `d7e41bcd` [Platforms/WASI](../Platforms/WASI).

## 2026-04-02

- `7e335623` Documented state keying and graph ownership while the runtime
  moved toward retained graph evaluation, async presentation boundaries, and
  off-main terminal presentation writes. See
  `7e335623` [docs/STATE_KEYING.md](STATE_KEYING.md),
  `7e335623` [docs/proposals/ASYNC_PRESENTATION.md](proposals/ASYNC_PRESENTATION.md),
  and `7e335623` [docs/ARCHITECTURE.md](ARCHITECTURE.md).

## 2026-03-31

- `5e4a3f03` Added viewport-lazy `LazyVStack` and `LazyHStack` behavior, then
  extended laziness through single-`ForEach` rows. See
  `5e4a3f03` [Sources/SwiftTUIViews/Stacks/LazyVStack.swift](../Sources/SwiftTUIViews/Stacks/LazyVStack.swift)
  and `5e4a3f03` [Sources/SwiftTUIViews/Stacks/LazyHStack.swift](../Sources/SwiftTUIViews/Stacks/LazyHStack.swift).
- `690d373d` Brought up the first WASM/Web example path with WASI build/run
  fixes and browser-side scene transport groundwork. See
  `690d373d` [Examples/WebExample](../Examples/WebExample) and
  `690d373d` [Platforms/Web](../Platforms/Web).

## 2026-03-30

- `46f294f0` Turned the prototype into documented SwiftUI-shaped architecture,
  including the early retained graph, `AnyView`, preferences, presentations,
  TabView, segmented picker, color gallery, and SwiftUI/Web example shells. See
  `46f294f0` [docs/ARCHITECTURE.md](ARCHITECTURE.md),
  `46f294f0` [Sources/SwiftTUIViews](../Sources/SwiftTUIViews), and
  `46f294f0` [Examples/README.md](../Examples/README.md).

## 2026-03-28

- `8830fb6d` Started the repository as a SwiftUI-inspired terminal UI
  prototype with a terminal-native render pipeline and demo application path.
  See `8830fb6d` [README.md](../README.md) and
  `8830fb6d` [docs/ARCHITECTURE.md](ARCHITECTURE.md).
