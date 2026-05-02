# Source Layout

This is the current ownership map for the codebase. It documents where
subsystems live after the March 2026 source split and should stay aligned with
future file moves.

## Repository Layout

- `Sources/`: root Swift package targets (`Core`, `View`, `SwiftTUICharts`, and `SwiftTUI`)
- `Tests/`: root Swift package tests for the package products
- `Runners/`: peer SwiftPM executable runner packages for terminal-native CLI launch and WASI launch
- `GUI/`: peer embedded host packages for SwiftUI hosting and Bun/browser hosting
- `Examples/`: sibling example apps and example-specific package manifests
- `Vendor/`: sibling vendored Swift packages such as `UnixSignals`, `swift-figlet`,
  `swift-hash`, `swift-png`, `swift-jpeg`, and `swift-gif`
- `Fixtures/`: shared transport fixtures consumed by both Swift and web tests
- `Scripts/`: repository policy scripts and hook helpers
- `docs/`: reference docs, plans, and historical implementation records

## Package Surface

- Library products:
  - `View`
  - `SwiftTUI`
  - `SwiftTUICharts`
- Internal support targets:
  - `Core`

- Peer platform integration packages:
  - executable runner packages:
    - `Runners/SwiftTUICLI`
    - `Runners/SwiftTUIWASI`
  - embedded host packages:
    - `GUI/SwiftUIHost`
    - `GUI/WebHost`

- Vendored local packages:
  - `Vendor/UnixSignals`
  - `Vendor/swift-figlet`
  - `Vendor/swift-hash`
  - `Vendor/swift-png`
  - `Vendor/swift-jpeg` — pure-Swift baseline JPEG decoder, mirrors the
    `PNG.Image` / `BytestreamSource` / `RGBA<T>` shape of swift-png
  - `Vendor/swift-gif` — pure-Swift GIF decoder (LZW + frame compositor),
    mirrors the same shape; static-frame `unpack(as:)` plus a `frames`
    accessor for future animation support

`Core` remains the shared pipeline target, but it is not exposed as a separate
library product. Downstream package consumers reach those types through
`SwiftTUI` re-exports.

## `SwiftTUI`

- `SwiftTUI.swift`: `DefaultRenderer` plus retained-frame, resolve-reuse, and post-resolve presentation composition plumbing
- `App.swift`: `App`, `Scene`, `SceneBuilder`, `WindowGroup`, `AnyScene`, and typed scene builder artifacts
- `SceneTraversal.swift`: typed scene traversal, descriptor collection, and window-scene selection helpers
- `SceneManifest.swift`: `SceneDescriptor`, `SceneManifest`, and manifest generation from authored scenes
- `HostedSceneSession.swift`: retained hosted scene runtime for GUI host packages and other non-terminal hosts
- `SceneSession.swift`: shared scene-session bootstrap used by hosted sessions and compatibility launch paths
- `RunLoop.swift`: runtime coordinator and shared runtime state
- `RunLoop+EventDispatch.swift`: keyboard, signal, focus, action, and scroll dispatch
- `RunLoop+PointerHandling.swift`: pointer routing, activation, hover, capture, and scroll-wheel handling
- `RunLoop+EventPump.swift`: event buffering and coalescing
- `RunLoop+Rendering.swift`: render scheduling, resolve-context assembly, and focus application
- `LifecycleCoordinator.swift`: post-present lifecycle staging
- `TaskRunner.swift`: lifecycle-owned task execution and cancellation
- `TerminalHost.swift`: fd-backed terminal host plus the WASI-facing `WebTerminalHost`, including
  final paint metrics for synchronized framing, graphics replay scope, and terminal edit-op
  lowering
- `StreamingTerminalHost.swift`: host-facing terminal host that emits presentation output through a closure
- `FrameDiagnosticsLogger.swift`: tab-separated per-frame diagnostics sink that joins pipeline
  counters with presentation metrics
- `TerminalPresentation.swift`: capability-aware surface diffing and text presentation
- `TerminalAppearanceDetection.swift`: appearance probing
- `TerminalGraphicsCapabilities.swift`: Kitty, Sixel, and cell-pixel capability detection
- `TerminalImageRendering.swift`: image protocol emitters and cell fallback rendering
- `ImageAssetRepository.swift`: shared decode + metadata cache for PNG,
  baseline JPEG, and GIF (format dispatched on the leading magic bytes)
- `InputReader.swift`: keyboard, mouse, pointer, paste, and drop input decoding
- `InjectedTerminalInputReader.swift`: wrapper-managed input stream source that shares control-message parsing
- `SignalReader.swift`: native and in-process signal readers
- `TerminalControlMessages.swift`: shared resize/control-message parsing
- `LinkOpening.swift`: runtime link opener
- `SwiftTUI.docc/`: module landing page and runtime guides

## `Runners/SwiftTUICLI`

- `SwiftTUICLI.swift`: re-export surface for the CLI runner package
- `TerminalRunner.swift`: terminal-native app launch, CLI-mode routing, and single-scene test helper
- `SceneRuntime.swift`: per-scene runtime orchestration for multi-scene terminal apps
- `SceneLifecycle.swift`: scene session coordination
- `CLIMode.swift`: attach/list CLI argument parsing
- `SceneInfoRegistry.swift`: scene discovery snapshots for running instances
- `SocketServer.swift` and `SocketClient.swift`: Unix-domain-socket discovery and attach plumbing
- `AttachProxy.swift`: terminal attach forwarding
- `PtyPair.swift`: native pty support

## `Runners/SwiftTUIWASI`

- `SwiftTUIWASI.swift`: re-export surface for the WASI runner package
- `WASIRunner.swift`: manifest mode plus WASI scene selection and launch

## Embedded Host Packages

- `GUI/SwiftUIHost`: native SwiftUI host package built on `SceneManifest` and `HostedSceneSession`
- `GUI/WebHost`: Bun-based web host that consumes a `SwiftTUIWASI` build and manifest, using the `web-surface` transport to draw raster output onto a canvas

## `Core`

- `Geometry/Point.swift`, `Geometry/CellGeometry.swift`,
  `Geometry/PixelGeometry.swift`, `Geometry/Path.swift`, `GeometryTypes.swift`,
  `EnvironmentAndNodeTypes.swift`, and `LayoutTypes.swift`: continuous
  authored geometry, integer terminal-cell geometry, pixel geometry, proposals,
  path hit-testing geometry, placement, layout metadata, and node infrastructure
- `Pointer/PointerLocation.swift`, `Pointer/PointerPrecisionPolicy.swift`, and
  `Pointer/HoverPhase.swift`: normalized pointer locations, public runtime
  capability metadata, precision policy, and hover phases
- `RenderTreeAndSemanticsTypes.swift`: resolved-tree, semantic snapshot, and draw-tree data types, including `TextFigure` draw payload support
- `CommitAndFrameTypes.swift`: commit plans, refined presentation-damage diagnostics, retained
  resolve frames, and frame artifacts
- `NodeMetadata.swift`: grouped node metadata used by measurement and refactor follow-up work
- `LayoutEngine.swift` plus `LayoutEngine+Alignment.swift`, `LayoutEngine+List.swift`, `LayoutEngine+Placement.swift`, `LayoutEngine+Stack.swift`, `LayoutEngine+Table.swift`, and `LayoutEngine+Utility.swift`: decomposed measurement and placement engine
- `Semantics.swift`: semantic extraction and route generation
- `DrawExtractor.swift`, `DrawExtractor+Lists.swift`, and `DrawExtractor+Tables.swift`: draw extraction
- `Rasterizer.swift` and `Rasterizer+CellSampling.swift`: raster lowering
- `Pipeline.swift` and `Snapshots.swift`: snapshot pipeline orchestration
- `CommitPlanner.swift`: lifecycle diffing and commit packaging
- `Scheduler.swift`: invalidation and wake scheduling
- `StateContainer.swift`: runtime-owned state storage
- `TextFigureSupport.swift`: embedded-FIGlet font lookup, layout metrics, caching, and rendering support used by proposal-aware figure text
- `FocusTracker.swift`, `FocusPolicy.swift`, `FocusInteractionTypes.swift`, `FocusPresentation.swift`, and `FocusedValues.swift`: focus state and focus-value transport
- `PreferenceValues.swift`: preference storage
- `SemanticRoleTypes.swift` and `BuiltinPointerRoutes.swift`: closed semantic roles and structured pointer routes
- `Appearance.swift`, `Styling.swift`, `TerminalChromeStyle.swift`, and `ViewStyleTypes.swift`: styling and appearance support
- `TextLayout.swift`, `RichText.swift`, `ImageTypes.swift`, `RasterTypes.swift`, `ScrollIndicatorSupport.swift`, `TableSupport.swift`, and `TableDrawSupport.swift`: supporting model types
- `LocalActionRegistry.swift`, `LocalFocusBindingRegistry.swift`, `LocalFocusedValuesRegistry.swift`, `LocalKeyHandlerRegistry.swift`, `LocalLifecycleRegistry.swift`, `LocalPointerHandlerRegistry.swift`, `LocalPreferenceObservationRegistry.swift`, and `LocalTaskRegistry.swift`: package-only runtime registries
- `DropDestinationRegistry.swift`: action-scope drop routing plus optional
  spatial drop context
- `ActionScope.swift` and `CommandRegistry.swift`: ActionScope scaffolding and the scope-identity-keyed command registry wired into the runtime (see [proposals/ACTION_SCOPES_AND_COMMANDS.md](proposals/ACTION_SCOPES_AND_COMMANDS.md))
- `MonotonicInstant.swift`, `PlatformLock.swift`, `PlatformMath.swift`, and `StringUtilities.swift`: low-level support helpers
- `Core.docc/`: target-level pipeline guides

## `View`

- `Foundation/AnyView.swift`, `Foundation/StylePrimitives.swift`, `Foundation/ViewBaseTypes.swift`, `Foundation/ViewCompositionHelpers.swift`, `Foundation/ViewFoundation.swift`, and `Foundation/ViewModifier.swift`: `View`, `ViewModifier`, `ModifiedContent`, `Resolver`, `AnyView`, style primitives, and internal composition helpers
- `ViewBuilder/ViewBuilder.swift`, `ViewBuilder/TupleView.swift`, `ViewBuilder/ConditionalContentView.swift`, `ViewBuilder/VariadicView.swift`, and `ViewBuilder/EmptyView.swift`: typed builder artifacts and builder machinery
- `State/State.swift`, `State/FocusState.swift`, and `State/FocusedValue.swift`: `@State`, focus bindings, and focused-value projections
- `Environment/Environment.swift`, `Environment/ImageEnvironment.swift`, `Environment/Observation.swift`, and `Environment/StyleEnvironment.swift`: environment storage, repo-owned `@Bindable`, image resource roots, and style environment plumbing
- `Focus/DefaultFocus.swift`: default-focus modifiers and focus defaults
- `Layout/Layout.swift`, `Stacks/*.swift`, `ScrollView/*.swift`, `GeometryReading/*.swift`, `Collections/*.swift`, and `NavigationViews/*.swift`: layout, stack, scroll, geometry, collection, and navigation surfaces
- `Canvas.swift`: public Canvas view construction over `CanvasDrawing` and dense
  pixel-grid drawings
- `Gestures/*.swift`: gestures, pointer paths, coordinate-space resolution,
  content shapes, and hover modifiers
- `ActionScopes/Panel.swift`, `ActionScopes/DropDestinationModifier.swift`, `ActionScopes/KeyCommandModifier.swift`, `ActionScopes/PaletteCommandModifier.swift`, `ActionScopes/Toolbar.swift`, and `ActionScopes/ToolbarItem.swift`: the `Panel` primitive with `.panel(id:)` / `.panel()` / `FocusContainment`; `.dropDestination(...)` scoped path drops with optional spatial context; the `.keyCommand(...)` modifier for shallowest-wins keybindings; the `.paletteCommand(...)` modifier plus `ActivePaletteCommand` + `EnvironmentValues.activePaletteCommands` for consumer-queryable palette surfaces; and the `.toolbar(style:)` absorber, `.toolbarItem(...)` hoisting contribution, `ToolbarStyle` protocol, and `DefaultTopToolbarStyle` / `DefaultBottomToolbarStyle` defaults. See [proposals/ACTION_SCOPES_AND_COMMANDS.md](proposals/ACTION_SCOPES_AND_COMMANDS.md).
- `Primitives/*.swift` and `Shapes/*.swift`: text/image primitives including `TextFigure`, labeled containers, and basic shapes
- `Controls/*.swift`: control surfaces, rendering helpers, and shared control support
- `Presentation/PresentationCoordinator.swift` and `Presentation/PresentationModifiers.swift`: shared presentation host, single-pass overlay composition, family coordinators, package-only declaration reconciliation, and built-in alert/confirmation-dialog/sheet/toast surfaces
- `Modifiers/Preference.swift`, `Modifiers/StyleModifiers.swift`, `Modifiers/ViewModifiers.swift`, and `Modifiers/OnKeyPress.swift`: public modifiers plus the package-only modifier-value lowering hooks that back them
- `View.docc/`: module landing page and authoring guides

## `SwiftTUICharts`

- chart files such as `BarChart.swift`, `BulletChart.swift`, `ColumnChart.swift`, `ComparisonChart.swift`, `HeatStrip.swift`, `Legend.swift`, `Meter.swift`, `Sparkline.swift`, `StackedBarChart.swift`, `ThresholdGauge.swift`, and `Timeline.swift`: compact chart and metric views
- `ChartModels.swift`: shared data models for chart families
- `ChartSupport.swift` and `ChartChromeSupport.swift`: shared chart rendering helpers
- `Exports.swift`: product-facing export glue
- `SwiftTUICharts.docc/`: module landing page and charting guide

## Tests

- `Tests/CoreTests`: pipeline, layout, raster, and focus infrastructure tests
- `Tests/ViewTests`: authoring-layer and environment-level tests
- `Tests/SwiftTUITests`: runtime, rendering, fixture, and end-to-end behavioral tests
- `Runners/SwiftTUICLI/Tests/SwiftTUICLITests`: terminal-native runner, attach, pty, and CLI-scene-management tests
- `Runners/SwiftTUIWASI/Tests/SwiftTUIWASITests`: WASI runner and manifest-mode tests
- `Fixtures/Transport`: shared transport fixtures for terminal render-style encoding/decoding tests across Swift and web hosts

## Reliability Rules

- New files should belong to one subsystem only.
- Shared helpers should move into support files before they are duplicated across features.
- Source-map changes should be updated here alongside any relevant changes to [ARCHITECTURE.md](ARCHITECTURE.md), [STATUS.md](STATUS.md), and [TESTING_AND_FIXTURE_POLICY.md](TESTING_AND_FIXTURE_POLICY.md).
- The repo currently enforces public-surface guardrails through `Scripts/check_public_surface_policies.sh`. There is not a separate checked-in source-layout hook today, so file-map drift must be caught through review and this document.
- The complete public symbol enumeration is regenerated by `Scripts/generate_public_api_inventory.sh` from `swift package dump-symbol-graph` and committed at [PUBLIC_API_BASELINE.md](PUBLIC_API_BASELINE.md) + [.public-api-baseline.txt](.public-api-baseline.txt). Run the script after any change to the public surface; classifications live in [public_api_overrides.yml](public_api_overrides.yml). Use `Scripts/generate_public_api_inventory.sh --check` to verify the committed baseline matches HEAD.
