# Source Layout

Last updated: March 30, 2026

This is the current ownership map for the codebase. It documents where
subsystems live after the March 2026 source split and should stay aligned with
future file moves.

## Package Surface

- Library products:
  - `View`
  - `TerminalUI`
  - `TerminalUIScenes`
  - `TerminalUICharts`
- Internal support targets:
  - `Core`
  - `PrototypeUIComponents`
  - `UnixSignals`

`Core` remains the shared pipeline target, but it is not exposed as a separate
library product. Downstream package consumers reach those types through
`TerminalUI` re-exports.

## `TerminalUI`

- `TerminalUI.swift`: `DefaultRenderer` plus retained-frame and resolve-reuse plumbing
- `App.swift`: `App`, `Scene`, `SceneBuilder`, `WindowGroup`, and scene collection helpers
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

## `TerminalUIScenes`

- `TerminalUIScenes.swift`: product re-export surface
- `MultiSceneLauncher.swift`: public app launch path, manifest mode, hosted-session factory, and CLI routing
- `SceneManifest.swift`: `TerminalUISceneDescriptor` and `TerminalUISceneManifest`
- `HostedSceneSession.swift`: retained hosted scene runtime for GUI wrappers
- `SceneSession.swift`: shared scene-runtime bootstrap
- `SceneRuntime.swift`: per-scene runtime orchestration for multi-scene terminal apps
- `SceneLifecycle.swift`: scene session coordination
- `CLIMode.swift`: attach/list CLI argument parsing
- `SceneInfoRegistry.swift`: scene discovery snapshots for running instances
- `SocketServer.swift` and `SocketClient.swift`: Unix-domain-socket discovery and attach plumbing
- `AttachProxy.swift`: terminal attach forwarding
- `PtyPair.swift`: native pty support
- `TerminalUIScenes.docc/`: module landing page and multi-scene guidance

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

- `ViewFoundation.swift`, `ViewBaseTypes.swift`, and `ViewCompositionHelpers.swift`: `View`, `ViewBuilder`, `AnyView`, base public types, and internal composition helpers
- `State.swift` and `Observation.swift`: `@State`, repo-owned `@Bindable`, and observation plumbing
- `Environment.swift`, `ImageEnvironment.swift`, `Preference.swift`, `FocusedValue.swift`, `FocusState.swift`, and `DefaultFocus.swift`: environment, preferences, focused values, and focus bindings
- `Layout.swift`, `ContainerViews.swift`, `GeometryReader.swift`, `ScrollViewSupport.swift`, `Collections.swift`, `CollectionSupport.swift`, `OutlineViews.swift`, and `NavigationViews.swift`: layout, collection, scroll, tab, and split-navigation surfaces
- `ViewPrimitives.swift`, `TextStyles.swift`, `StylePrimitives.swift`, `StyleEnvironment.swift`, `StyleModifiers.swift`, `ShapeStyles.swift`, `Rectangle.swift`, `RoundedRectangle.swift`, and `TileBackground.swift`: primitives, styling, and shape support
- `Image.swift`: SwiftUI-shaped PNG image surface
- `Button.swift`, `ValueControls.swift`, `TextEditor.swift`, `SecureField.swift`, `AdjustableValueControls.swift`, `Picker.swift`, `PickerRendering.swift`, `Menu.swift`, `MenuRendering.swift`, `LabeledContainers.swift`, `PresentationModifiers.swift`, `Toolbar.swift`, `ProgressView.swift`, `Link.swift`, `MetricTrackSupport.swift`, and `SelectionAndValueSupport.swift`: controls, toolbar chrome, and interaction surfaces
- `ViewModifiers.swift`: public modifiers and package-only wrapper views
- `View.docc/`: module landing page and authoring guides

## `PrototypeUIComponents`

- `PrototypeModels.swift`: keybinding groups, command models, and search helpers for experimental terminal-native workflow surfaces
- `PrototypeSurfaces.swift`: repo-local command-palette views used for exploration and regression coverage

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
- `Tests/TerminalUIScenesTests`: scene launcher, hosted session, attach, pty, and manifest tests
- `Tests/PrototypeUIComponentsTests`: prototype-surface regression coverage

## Reliability Rules

- New files should belong to one subsystem only.
- Shared helpers should move into support files before they are duplicated across features.
- Source-map changes should be updated here alongside any relevant changes to [ARCHITECTURE.md](ARCHITECTURE.md), [STATUS.md](STATUS.md), and [TESTING_AND_FIXTURE_POLICY.md](TESTING_AND_FIXTURE_POLICY.md).
- The repo currently enforces public-surface guardrails through `Scripts/check_public_surface_policies.zsh`. There is not a separate checked-in source-layout hook today, so file-map drift must be caught through review and this document.
