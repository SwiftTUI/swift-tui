# Source Layout

Last updated: April 5, 2026

This is the current ownership map for the codebase. It documents where
subsystems live after the March 2026 source split and should stay aligned with
future file moves.

## Repository Layout

- `Sources/`: root Swift package targets (`Core`, `View`, `PrototypeUIComponents`, `TerminalUICharts`, `TerminalUI`, and the vendored `UnixSignals` support target)
- `Tests/`: root Swift package tests for the package products plus prototype regressions
- `Runners/`: peer SwiftPM runner packages for terminal-native CLI launch and WASI launch
- `GUI/`: peer wrapper packages for SwiftUI hosting and Bun/browser hosting
- `Examples/`: sibling example apps and example-specific package manifests
- `Fixtures/`: shared transport fixtures consumed by both Swift and web tests
- `Scripts/`: repository policy scripts and hook helpers
- `docs/`: reference docs, plans, and historical implementation records

## Package Surface

- Library products:
  - `View`
  - `TerminalUI`
  - `TerminalUICharts`
- Internal support targets:
  - `Core`
  - `PrototypeUIComponents`
  - `UnixSignals`

- Peer runner and wrapper packages:
  - `Runners/TerminalUICLI`
  - `Runners/TerminalUIWASI`
  - `GUI/SwiftUITUIGUI`
  - `GUI/WebTUIGUI`

`Core` remains the shared pipeline target, but it is not exposed as a separate
library product. Downstream package consumers reach those types through
`TerminalUI` re-exports.

## `TerminalUI`

- `TerminalUI.swift`: `DefaultRenderer` plus retained-frame and resolve-reuse plumbing
- `App.swift`: `App`, `Scene`, `SceneBuilder`, `WindowGroup`, and scene collection helpers
- `SceneManifest.swift`: `TerminalUISceneDescriptor`, `TerminalUISceneManifest`, and manifest generation from authored scenes
- `HostedSceneSession.swift`: retained hosted scene runtime for GUI wrappers and other non-terminal hosts
- `SceneSession.swift`: shared scene-session bootstrap used by hosted sessions and compatibility launch paths
- `RunLoop.swift`: runtime coordinator and shared runtime state
- `RunLoop+EventDispatch.swift`: keyboard, signal, focus, action, and scroll dispatch
- `RunLoop+PointerHandling.swift`: pointer routing, activation, capture, and scroll-wheel handling
- `RunLoop+EventPump.swift`: event buffering and coalescing
- `RunLoop+Rendering.swift`: render scheduling, resolve-context assembly, and focus application
- `LifecycleCoordinator.swift`: post-present lifecycle staging
- `TaskRunner.swift`: lifecycle-owned task execution and cancellation
- `TerminalHost.swift`: fd-backed terminal host plus the WASI-facing `WebTerminalHost`
- `StreamingTerminalHost.swift`: wrapper-facing terminal host that emits presentation output through a closure
- `TerminalPresentation.swift`: capability-aware surface diffing and text presentation
- `TerminalAppearanceDetection.swift`: appearance probing
- `TerminalGraphicsCapabilities.swift`: Kitty, Sixel, and cell-pixel capability detection
- `TerminalImageRendering.swift`: image protocol emitters and cell fallback rendering
- `ImageAssetRepository.swift`: shared PNG decode and metadata cache
- `InputReader.swift`: keyboard and mouse input decoding
- `InjectedTerminalInputReader.swift`: wrapper-managed input stream source that shares control-message parsing
- `SignalReader.swift`: native and in-process signal readers
- `TerminalControlMessages.swift`: shared resize/control-message parsing
- `LinkOpening.swift`: runtime link opener
- `TerminalUI.docc/`: module landing page and runtime guides

## `Runners/TerminalUICLI`

- `TerminalUICLI.swift`: re-export surface for the CLI runner package
- `TerminalCLIAppRunner.swift`: terminal-native app launch, CLI-mode routing, and single-scene test helper
- `SceneRuntime.swift`: per-scene runtime orchestration for multi-scene terminal apps
- `SceneLifecycle.swift`: scene session coordination
- `CLIMode.swift`: attach/list CLI argument parsing
- `SceneInfoRegistry.swift`: scene discovery snapshots for running instances
- `SocketServer.swift` and `SocketClient.swift`: Unix-domain-socket discovery and attach plumbing
- `AttachProxy.swift`: terminal attach forwarding
- `PtyPair.swift`: native pty support

## `Runners/TerminalUIWASI`

- `TerminalUIWASI.swift`: re-export surface for the WASI runner package
- `TerminalWASIAppRunner.swift`: manifest mode plus WASI scene selection and launch

## Wrapper Packages

- `GUI/SwiftUITUIGUI`: SwiftUI host package built on `TerminalUISceneManifest` and `HostedSceneSession`
- `GUI/WebTUIGUI`: Bun-based web host that consumes a `TerminalUIWASI` build and manifest

## `Core`

- `GeometryTypes.swift`, `EnvironmentAndNodeTypes.swift`, and `LayoutTypes.swift`: geometry, proposals, placement, layout metadata, and node infrastructure
- `RenderTreeAndSemanticsTypes.swift`: resolved-tree, semantic snapshot, and draw-tree data types
- `CommitAndFrameTypes.swift`: commit plans, diagnostics, retained resolve frames, and frame artifacts
- `NodeMetadata.swift`: grouped node metadata used by measurement and refactor follow-up work
- `LayoutEngine.swift` plus `LayoutEngine+Alignment.swift`, `LayoutEngine+List.swift`, `LayoutEngine+Placement.swift`, `LayoutEngine+Stack.swift`, `LayoutEngine+Table.swift`, and `LayoutEngine+Utility.swift`: decomposed measurement and placement engine
- `Semantics.swift`: semantic extraction and route generation
- `DrawExtractor.swift`, `DrawExtractor+Lists.swift`, and `DrawExtractor+Tables.swift`: draw extraction
- `Rasterizer.swift` and `Rasterizer+CellSampling.swift`: raster lowering
- `Pipeline.swift` and `Snapshots.swift`: snapshot pipeline orchestration
- `CommitPlanner.swift`: lifecycle diffing and commit packaging
- `Scheduler.swift`: invalidation and wake scheduling
- `StateContainer.swift`: runtime-owned state storage
- `FocusTracker.swift`, `FocusPolicy.swift`, `FocusInteractionTypes.swift`, and `FocusedValues.swift`: focus state and focus-value transport
- `PreferenceValues.swift`: preference storage
- `SemanticRoleTypes.swift` and `BuiltinPointerRoutes.swift`: closed semantic roles and structured pointer routes
- `Appearance.swift`, `Styling.swift`, `TerminalChromeStyle.swift`, and `ViewStyleTypes.swift`: styling and appearance support
- `TextLayout.swift`, `RichText.swift`, `ImageTypes.swift`, `RasterTypes.swift`, `ScrollIndicatorSupport.swift`, `TableSupport.swift`, and `TableDrawSupport.swift`: supporting model types
- `LocalActionRegistry.swift`, `LocalFocusBindingRegistry.swift`, `LocalFocusedValuesRegistry.swift`, `LocalKeyHandlerRegistry.swift`, `LocalLifecycleRegistry.swift`, `LocalPointerHandlerRegistry.swift`, `LocalPreferenceObservationRegistry.swift`, and `LocalTaskRegistry.swift`: package-only runtime registries
- `MonotonicInstant.swift`, `PlatformLock.swift`, `PlatformMath.swift`, and `StringUtilities.swift`: low-level support helpers
- `Core.docc/`: target-level pipeline guides

## `View`

- `Foundation/AnyView.swift`, `Foundation/StylePrimitives.swift`, `Foundation/ViewBaseTypes.swift`, `Foundation/ViewCompositionHelpers.swift`, and `Foundation/ViewFoundation.swift`: `View`, `Resolver`, `AnyView`, style primitives, and internal composition helpers
- `ViewBuilder/ViewBuilder.swift`, `ViewBuilder/TupleView.swift`, `ViewBuilder/ConditionalContentView.swift`, `ViewBuilder/VariadicView.swift`, and `ViewBuilder/EmptyView.swift`: typed builder artifacts and builder machinery
- `State/State.swift`, `State/FocusState.swift`, and `State/FocusedValue.swift`: `@State`, focus bindings, and focused-value projections
- `Environment/Environment.swift`, `Environment/ImageEnvironment.swift`, `Environment/Observation.swift`, and `Environment/StyleEnvironment.swift`: environment storage, repo-owned `@Bindable`, image resource roots, and style environment plumbing
- `Focus/DefaultFocus.swift`: default-focus modifiers and focus defaults
- `Layout/Layout.swift`, `Stacks/*.swift`, `ScrollView/*.swift`, `GeometryReading/*.swift`, `Collections/*.swift`, and `NavigationViews/*.swift`: layout, stack, scroll, geometry, collection, and navigation surfaces
- `Primitives/*.swift` and `Shapes/*.swift`: text/image primitives, labeled containers, tile backgrounds, and basic shapes
- `Controls/*.swift`: control surfaces, rendering helpers, and shared control support
- `Presentation/PresentationModifiers.swift`, `Presentation/Toolbar.swift`, and `Presentation/CommandPalette.swift`: alerts, confirmation dialogs, sheets, toasts, toolbar chrome, command registration, and the canonical command-palette surface
- `Modifiers/Preference.swift`, `Modifiers/StyleModifiers.swift`, `Modifiers/ViewModifiers.swift`, and `Modifiers/OnKeyPress.swift`: public modifiers and the package-only wrapper views that back them
- `View.docc/`: module landing page and authoring guides

## `PrototypeUIComponents`

- `PrototypeModels.swift`: keybinding groups, prototype command models, and search helpers for experimental terminal-native workflow surfaces
- `PrototypeSurfaces.swift`: repo-local help-strip and simplified command-surface views used for exploration and regression coverage

## `TerminalUICharts`

- chart files such as `BarChart.swift`, `BulletChart.swift`, `ColumnChart.swift`, `ComparisonChart.swift`, `HeatStrip.swift`, `Legend.swift`, `Meter.swift`, `Sparkline.swift`, `StackedBarChart.swift`, `ThresholdGauge.swift`, and `Timeline.swift`: compact chart and metric views
- `ChartModels.swift`: shared data models for chart families
- `ChartSupport.swift` and `ChartChromeSupport.swift`: shared chart rendering helpers
- `Exports.swift`: product-facing export glue
- `TerminalUICharts.docc/`: module landing page and charting guide

## Tests

- `Tests/CoreTests`: pipeline, layout, raster, and focus infrastructure tests
- `Tests/ViewTests`: authoring-layer and environment-level tests
- `Tests/TerminalUITests`: runtime, rendering, fixture, and end-to-end behavioral tests
- `Runners/TerminalUICLI/Tests/TerminalUICLITests`: terminal-native runner, attach, pty, and CLI-scene-management tests
- `Runners/TerminalUIWASI/Tests/TerminalUIWASITests`: WASI runner and manifest-mode tests
- `Tests/PrototypeUIComponentsTests`: prototype-surface regression coverage
- `Fixtures/Transport`: shared transport fixtures for terminal render-style encoding/decoding tests across Swift and web hosts

## Reliability Rules

- New files should belong to one subsystem only.
- Shared helpers should move into support files before they are duplicated across features.
- Source-map changes should be updated here alongside any relevant changes to [ARCHITECTURE.md](ARCHITECTURE.md), [STATUS.md](STATUS.md), and [TESTING_AND_FIXTURE_POLICY.md](TESTING_AND_FIXTURE_POLICY.md).
- The repo currently enforces public-surface guardrails through `Scripts/check_public_surface_policies.zsh`. There is not a separate checked-in source-layout hook today, so file-map drift must be caught through review and this document.
