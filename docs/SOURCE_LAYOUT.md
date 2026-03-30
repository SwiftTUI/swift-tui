# Source Layout

Last updated: March 30, 2026

This is the current ownership map for the codebase. It documents where subsystems live after the source split and should stay aligned with future file moves.

## Targets

- `TerminalUI`: terminal runtime integration, rendering, host I/O, scheduling, lifecycle staging, and single-session runtime entry points
- `TerminalUIScenes`: optional multi-scene runtime integration on top of `TerminalUI`
- `View`: SwiftUI-shaped authoring surface, property wrappers, environment plumbing, layouts, and controls
- `Core`: shared geometry, layout, semantics, draw, raster, diagnostics, and commit data types
- `TerminalUICharts`: compact chart and metric views built on top of `View`
- `PrototypeUIComponents`: repo-local prototype components and exploratory UI surfaces


## `TerminalUI`

- `TerminalUI.swift`: default renderer and runtime-facing surface exports
- `App.swift`: app and scene declarations plus internal scene launch plumbing
- `RunLoop.swift`: runtime orchestration
- `LifecycleCoordinator.swift`: post-present lifecycle staging
- `TaskRunner.swift`: lifecycle-owned task execution and cancellation
- `TerminalHost.swift`: terminal host integration and presentation commit boundary
- `StreamingTerminalHost.swift`: wrapper-facing terminal host that emits presentation output to a closure instead of a file descriptor
- `TerminalGraphicsCapabilities.swift`: Kitty, Sixel, and cell-pixel capability probing helpers
- `TerminalImageRendering.swift`: image protocol emitters, fallback compositing, and dithering support
- `ImageAssetRepository.swift`: shared PNG decoding and image metadata cache, with nil-image fallback on builds where PNG support is not linked
- `TerminalPresentation.swift`: capability-aware text rendering, OSC 8 hyperlink emission, and incremental presentation planning
- `TerminalAppearanceDetection.swift`: host appearance probing
- `InputReader.swift`: keyboard and mouse input decoding
- `InjectedTerminalInputReader.swift`: wrapper-managed input stream source that shares the runtime parser and control-message contract
- `TerminalControlMessages.swift`: shared terminal control-message parsing used by fd-backed and injected input
- `LinkOpening.swift`: package-only runtime opener used by focusable links in interactive sessions
- `TerminalUI.docc/`: module landing page and runtime guides

## `TerminalUIScenes`

- `TerminalUIScenes.swift`: target re-export surface
- `MultiSceneLauncher.swift`: public app launch path for scene-based apps today
- `SceneManifest.swift`: public scene-descriptor and manifest types for wrapper tooling
- `HostedSceneSession.swift`: public wrapper-facing scene host for embedded GUI shells
- remaining files: socket discovery, scene lifecycle, pty management, and scene runtime support
- `TerminalUIScenes.docc/`: module landing page and multi-scene guidance

## `Core`

- `GeometryTypes.swift`: geometry, identity, proposal, spacing, and alignment primitives
- `EnvironmentAndNodeTypes.swift`: environment snapshots, node kinds, axis, visibility, and placement allocations
- `FocusedValues.swift`: focused-value transport types
- `PreferenceValues.swift`: preference-key protocol and reduced subtree preference storage
- `FocusPolicy.swift`: centralized focus participation defaults and focus-routing helpers
- `FocusTracker.swift`: focus ownership and traversal state
- `LayoutTypes.swift`: layout behavior, layout metadata, measured and placed node infrastructure, and custom layout handles
- `LayoutEngine.swift`: measurement and placement engine
- `RenderMetadataTypes.swift`: text style, base style, draw metadata, and collection payloads
- `RichText.swift`: rich-text runs, `LinkDestination`, payloads, and inline-link identity helpers
- `ImageTypes.swift`: image-source, resolved-image, and raster-image-attachment data types
- `RenderTreeAndSemanticsTypes.swift`: semantic metadata, lifecycle metadata, resolved tree, semantic snapshot, and draw-tree types
- `Semantics.swift`: semantic extraction and routing
- `DrawExtractor.swift`: generic draw extraction
- `DrawExtractor+Lists.swift`: list rendering and scroll-indicator helpers
- `DrawExtractor+Tables.swift`: table-specific draw extraction
- `TableSupport.swift`: table layout and formatting support
- `TableDrawSupport.swift`: shared table draw helpers
- `TextLayout.swift`: text measurement and wrapping
- `RasterTypes.swift`: raster cells, style runs, and raster surfaces
- `Rasterizer.swift`: draw-to-raster lowering
- `CommitAndFrameTypes.swift`: commit plans, lifecycle state, diagnostics, frame context, and frame artifacts
- `CommitPlanner.swift`: lifecycle diffing and commit planning
- `Pipeline.swift`: snapshot pipeline orchestration
- `Snapshots.swift`: pipeline snapshots and render helpers
- `Scheduler.swift`: invalidation and wake scheduling
- `StateContainer.swift`: runtime-owned state storage
- `SemanticRoleTypes.swift`: closed semantic roles and structured route identifiers
- `Appearance.swift`: appearance and capability-facing styling support
- `Styling.swift`: style resolution support
- `LocalActionRegistry.swift`: package-only local action registry
- `LocalFocusBindingRegistry.swift`: focus binding registry
- `LocalFocusedValuesRegistry.swift`: focused-value registry
- `LocalPreferenceObservationRegistry.swift`: package-only preference change observer registry
- `LocalKeyHandlerRegistry.swift`: package-only local key-handler registry
- `LocalLifecycleRegistry.swift`: package-only lifecycle-handler registry
- `LocalTaskRegistry.swift`: package-only task registry
- `LocalPointerHandlerRegistry.swift`: pointer event types, buttons, and scroll context for pointer input handling
- `BuiltinPointerRoutes.swift`: route component identifiers for pointer interactions with controls
- `FocusInteractionTypes.swift`: `FocusInteractions` behavior modes
- `MonotonicInstant.swift`: monotonic timestamp type for elapsed-time measurement
- `PlatformMath.swift`: platform-independent math wrappers
- `Rasterizer+CellSampling.swift`: background-color sampling for border styling
- `ScrollIndicatorSupport.swift`: scroll indicator configuration types
- `SemanticMetadataCompatibility.swift`: compatibility helpers for `SemanticMetadata`
- `StringUtilities.swift`: focused string helpers used by the runtime
- `TerminalChromeStyle.swift`: semantic chrome kinds and terminal styling support
- `Core.docc/`: module landing page and frame-pipeline guides

## `View`

- `ViewBaseTypes.swift`: shared public base types such as `Binding`, `Bindable`, `Axis`, `ScrollPosition`, and `ViewSpacing`
- `ViewFoundation.swift`: `View`, `ViewBuilder`, `AnyView`, resolver entry points, and typed builder plumbing
- `State.swift`: `@State` and binding-facing state support
- `Observation.swift`: observable bridging and repo-owned `@Bindable`
- `Environment.swift`: environment keys, typed `OpenLinkAction`, public `ResolveContext` configuration, and package-only runtime plumbing
- `ImageEnvironment.swift`: image resource-root and terminal cell-pixel environment values
- `FocusedValue.swift`: focused-value property wrappers and modifiers
- `Preference.swift`: `PreferenceKey`-driven modifiers, subtree readers, and preference change observers
- `FocusState.swift`: `@FocusState` and focus-binding surface
- `Layout.swift`: `Layout` protocol support, layout modifiers, stack layouts, and alignment helpers
- `ViewPrimitives.swift`: `EmptyView`, rich-interpolated `Text`, `Spacer`, and `Divider`
- `Image.swift`: SwiftUI-shaped PNG image surface
- `GeometryReader.swift`: terminal-surface geometry proxy and reader
- `ContainerViews.swift`: `Group`, `ForEach`, `ViewThatFits`, `ScrollView`, `VStack`, `HStack`, and `ZStack`
- `NavigationViews.swift`: terminal-native `TabView`, `NavigationSplitView`, and related shell composition support
- `OutlineViews.swift`: outline and hierarchical collection views
- `ViewModifiers.swift`: public modifiers and package-only wrapper views such as padding, frame, overlay, and background
- `PresentationModifiers.swift`: terminal-native `alert` and `confirmationDialog` presentation
- `StylePrimitives.swift`: style enums and primitive style values
- `StyleEnvironment.swift`: style-related environment keys and accessors
- `StyleModifiers.swift`: `foregroundStyle`, `tint`, `disabled`, and row-styling helpers
- `LabeledContainers.swift`: `Label`, `LabeledContent`, `ControlGroup`, and `GroupBox`
- `ProgressView.swift`: determinate and indeterminate progress-bar surface
- `ValueControls.swift`: `Toggle`, `TextField`, and `DisclosureGroup`
- `TextEditor.swift`: multiline text editing surface
- `SecureField.swift`: masked string-entry control built on the text-entry helpers
- `AdjustableValueControls.swift`: `Stepper` and `Slider`
- `Collections.swift`: `Section`, `List`, `TableRow`, and `Table`
- `CollectionSupport.swift`: shared selection, table-formatting, and collection-text helpers
- `Picker.swift`: `Picker` and picker body builders
- `Menu.swift` and `MenuRendering.swift`: standalone menu control and inline expansion rendering
- `Button.swift`: `Button` and button chrome helpers
- `Link.swift`: text-backed `Link` plus rich-text lowering helpers for inline hyperlinks
- `MetricTrackSupport.swift`: shared compact metric-track helpers used by core progress surfaces and charts
- `ViewCompositionHelpers.swift`: shared group composition helpers and internal lowering support
- `ShapesAndTextStyle.swift`: shapes plus `Text` styling extensions
- `DefaultFocus.swift`: default-focus modifiers using `FocusState` bindings
- `PickerRendering.swift`: rendering logic for picker styles
- `ScrollViewSupport.swift`: scroll key handling and indicator visibility logic
- `SelectionAndValueSupport.swift`: selection helpers and pointer interaction support
- `TileBackground.swift`: tiled background-pattern view
- `View.docc/`: module landing page and authoring guides

## `PrototypeUIComponents`

- `PrototypeModels.swift`: key-binding groups, command models, and search helpers for experimental terminal-native workflow surfaces
- `PrototypeSurfaces.swift`: repo-local help-strip and command-palette views used for exploration and regression coverage

## `TerminalUICharts`

- chart files such as `BarChart.swift`, `Sparkline.swift`, and `Timeline.swift`: compact chart and metric views
- `ChartModels.swift`: shared data models for chart families
- `ChartSupport.swift` and `ChartChromeSupport.swift`: shared chart rendering helpers
- `TerminalUICharts.docc/`: module landing page and charting guide

## Reliability Rules

- New files should belong to one subsystem only
- Shared helpers should move into support files before they are duplicated across features
- Source-map changes should be updated here alongside any relevant changes to [ARCHITECTURE.md](ARCHITECTURE.md), [STATUS.md](STATUS.md), and [TESTING_AND_FIXTURE_POLICY.md](TESTING_AND_FIXTURE_POLICY.md)
