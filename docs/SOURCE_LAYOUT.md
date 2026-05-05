# Source Layout

This is the current ownership map for the codebase. It documents where
subsystems live after the March 2026 source split and should stay aligned with
future file moves.

## Repository Layout

- `Sources/`: root Swift package targets (`SwiftTUICore`, `SwiftTUIViews`, `SwiftTUIAnimatedImage`,
  `SwiftTUICharts`, and `SwiftTUI`)
- `Tests/`: root Swift package tests for the package products
- `Platforms/`: peer SwiftPM platform-integration packages — runners (`CLI`, `WASI`) that own `App.main()`, plus embedded hosts (`SwiftUI`, `Web`) that retain `HostedSceneSession` values inside another app's runtime
- `Examples/`: sibling example apps and example-specific package manifests
- `Vendor/`: sibling vendored Swift packages such as `UnixSignals`, `swift-figlet`,
  `swift-hash`, `swift-png`, `swift-jpeg`, and `swift-gif`
- `Fixtures/`: shared transport fixtures consumed by both Swift and web tests
- `Scripts/`: repository policy scripts and hook helpers
- `docs/`: reference docs, plans, and historical implementation records

## Package Surface

- Library products:
  - `SwiftTUIViews`
  - `SwiftTUI`
  - `SwiftTUIAnimatedImage`
  - `SwiftTUICharts`
- Internal support targets:
  - `SwiftTUICore`

- Peer platform integration packages:
  - executable runner packages:
    - `Platforms/CLI`
    - `Platforms/WASI`
  - embedded host packages:
    - `Platforms/SwiftUI`
    - `Platforms/Web`
  - embedded terminal-program package:
    - `Platforms/Embedding`

- Vendored local packages:
  - `Vendor/UnixSignals`
  - `Vendor/swift-figlet`
  - `Vendor/swift-hash`
  - `Vendor/swift-png`
  - `Vendor/swift-jpeg` — pure-Swift baseline JPEG decoder, mirrors the
    `PNG.Image` / `BytestreamSource` / `RGBA<T>` shape of swift-png
  - `Vendor/swift-gif` — pure-Swift GIF decoder and encoder used by
    `SwiftTUIAnimatedImage` and GIF-focused example packages

`SwiftTUICore` remains the shared pipeline target, but it is not exposed as a separate
library product. Downstream package consumers reach those types through
`SwiftTUI` re-exports.

## `SwiftTUI`

`SwiftTUI` is the terminal runtime and umbrella product. It is organized
around runtime feature concerns:

```
Sources/SwiftTUI/
  Accessibility/ — runtime accessibility policy adapters for terminal targets
  RunLoop/      — runtime coordinator, event dispatch, pointer routing, render scheduling
  Lifecycle/    — post-present lifecycle staging, task running, animation control
  Scenes/       — App protocol, scene traversal, scene manifest, hosted scene sessions
  Terminal/     — terminal host, presentation, appearance + capability detection, image rendering
  Input/        — keyboard, pointer, paste, drop, signal, exit-key bindings input decoding
  Diagnostics/  — frame diagnostics logging
  Support/      — link opening, async-stream teardown, platform stdio helpers
  SwiftTUI.docc/ — module landing page and runtime guides
  SwiftTUI.swift — umbrella `@_exported` re-export of `SwiftTUICore`, `SwiftTUIViews`, plus runtime entry points
```

### Run loop and event dispatch

- `Accessibility/AccessibilityRuntimePolicy.swift`: terminal-runtime policy helpers that consume `SemanticSnapshot.accessibilityNodes`
- `Accessibility/LinearAccessibilityRenderer.swift`: semantic linear renderer for accessible CLI output
- `RunLoop/RunLoop.swift`: runtime coordinator and shared runtime state
- `RunLoop/RunLoop+EventDispatch.swift`: keyboard, signal, focus, action, and scroll dispatch
- `RunLoop/RunLoop+PointerHandling.swift`: pointer routing, activation, hover, capture, and scroll-wheel handling
- `RunLoop/RunLoop+EventPump.swift`: event buffering and coalescing
- `RunLoop/RunLoop+Rendering.swift`: render scheduling, resolve-context assembly, and focus application
- `RunLoop/RunLoop+GestureDeadlines.swift`: gesture-deadline coordination
- `RunLoop/RuntimeRenderMode.swift`: render-mode taxonomy
- `RunLoop/SkippedFrameReconciliation.swift`: dropped-frame reconciliation

### Lifecycle and animation

- `Lifecycle/LifecycleCoordinator.swift`: post-present lifecycle staging
- `Lifecycle/TaskRunner.swift`: lifecycle-owned task execution and cancellation
- `Lifecycle/AnimationController.swift` and `Lifecycle/AnyAnimatable.swift`: animation coordination

### Scenes

- `Scenes/App.swift`: `App`, `Scene`, `SceneBuilder`, `WindowGroup`, `AnyScene`, and typed scene builder artifacts
- `Scenes/SceneTraversal.swift`: typed scene traversal, descriptor collection, and window-scene selection helpers
- `Scenes/SceneManifest.swift`: `SceneDescriptor`, `SceneManifest`, and manifest generation from authored scenes
- `Scenes/HostedSceneSession.swift`: retained hosted scene runtime for GUI host packages and other non-terminal hosts
- `Scenes/SceneSession.swift`: shared scene-session bootstrap used by hosted sessions and compatibility launch paths

### Terminal

- `Terminal/TerminalHost.swift`: defines the `PresentationSurface` protocol (the `RunLoop`'s pluggable presentation target) plus the fd-backed `TerminalHost` and WASI-facing `WebTerminalHost` implementations
- `Terminal/TerminalCursorFocusPresentationSurface.swift`: terminal-only cursor focus marker and cursor visibility helpers
- `Terminal/StreamingTerminalHost.swift`: closure-backed `PresentationSurface` for embedded hosts that don't own a file descriptor
- `Terminal/TerminalPresentation.swift`: capability-aware surface diffing,
  sanitized text presentation, and OSC 8 hyperlink lowering
- `Terminal/TerminalAppearanceDetection.swift`: appearance probing
- `Terminal/TerminalGraphicsCapabilities.swift`: Kitty, Sixel, and cell-pixel capability detection
- `Terminal/TerminalImageRendering.swift`: image protocol emitters and cell fallback rendering
- `Terminal/TerminalControlMessages.swift`: shared resize/control-message parsing
- `Terminal/ImageAssetRepository.swift`: shared decode + metadata cache for PNG and baseline JPEG

### Input

- `Input/InputReader.swift`: keyboard, mouse, pointer, paste, and drop input decoding
- `Input/InjectedTerminalInputReader.swift`: wrapper-managed input stream source that shares control-message parsing
- `Input/SignalReader.swift`: native and in-process signal readers
- `Input/ExitKeyBindings.swift`: exit-key configuration

### Diagnostics

- `Diagnostics/FrameDiagnosticsLogger.swift`: tab-separated per-frame diagnostics sink that joins pipeline counters with presentation metrics

### Support

- `Support/LinkOpening.swift`: runtime link opener
- `Support/AsyncStreamTeardown.swift`: managed `AsyncStream` lifecycle helper
- `Support/Standard.swift`: platform stdio helpers

### Umbrella

- `SwiftTUI.swift`: `@_exported` re-export of `SwiftTUICore` and `SwiftTUIViews` plus `DefaultRenderer` (retained-frame, resolve-reuse, portal-root integration, and presentation-aware frame artifacts)
- `SwiftTUI.docc/`: module landing page and runtime guides

## `Platforms/CLI`

- `SwiftTUICLI.swift`: re-export surface for the CLI runner package
- `TerminalRunner.swift`: terminal-native app launch, CLI-mode routing, and single-scene test helper
- `SceneRuntime.swift`: per-scene runtime orchestration for multi-scene terminal apps
- `SceneLifecycle.swift`: scene session coordination
- `CLIMode.swift`: attach/list CLI argument parsing
- `SceneInfoRegistry.swift`: scene discovery snapshots for running instances
- `SocketServer.swift` and `SocketClient.swift`: Unix-domain-socket discovery and attach plumbing
- `AttachProxy.swift`: terminal attach forwarding
- `ScenePty.swift`: pty-backed secondary-scene wrapper over
  `SwiftTUIPTYPrimitives.PTYPair`

## `Platforms/WASI`

The package ships two library targets:

- `SwiftTUIWASI` — process-owning launcher. App authors `import SwiftTUIWASI` to get `App.main()`.
  - `SwiftTUIWASI.swift`: re-export surface for the WASI launcher package
  - `WASIRunner.swift`: manifest mode plus WASI scene selection and launch
- `WASISurfaceBridge` — pure raster-surface transport, importable on its own without the launcher.
  - `WebSurfaceTransport.swift`: `web-surface` stdout encoder (`WebSurfaceFrameEncoder`),
    `WebSurfaceTransport` (presentation surface), and `WebSurfaceInputReader` /
    `WebSurfaceInputParser` for the resize/style/key/mouse stdin protocol that
    `Platforms/Web`'s `BrowserWASIBridge` consumes

## Embedded Host Packages

- `Platforms/SwiftUI`: native SwiftUI host package built on `SceneManifest` and `HostedSceneSession`
- `Platforms/Web`: Bun-based web host that consumes a `SwiftTUIWASI` build and manifest, using the `web-surface` transport to draw raster output onto a canvas

## `Platforms/Embedding`

The package ships two public library targets plus one internal C support
target:

- `SwiftTUIPTYPrimitives` — shared pty creation, fd lifecycle, read/write, and
  resize support used by `Platforms/CLI` scene attachment and terminal-program
  embedding.
- `SwiftTUITerminal` — SwiftTerm-backed emulator wrapper, child-process pty
  driver, `TerminalSession`, `TerminalProcessSession`, `TerminalView`, and
  terminal metadata modifiers.

`Platforms/Embedding` is a peer package. Root `SwiftTUI` does not depend on it;
apps and examples opt in when they need external terminal programs inside an
authored SwiftTUI view tree.

## `SwiftTUICore`

`SwiftTUICore` is organized around the seven-phase pipeline contract
(`resolve → measure → place → semantics → draw → raster → commit`) plus
cross-cutting buckets. The top-level layout mirrors the doctrine:

```
Sources/SwiftTUICore/
  Pipeline/    — orchestrators that drive the seven phases
  Resolve/     — view-graph machinery and resolved-tree types
  Measure/     — layout proposals, layout engine, and measured-node types
  Place/       — placement output and the placement engine pass
  Semantics/   — semantic extraction, focus, gestures, and routes
  Draw/        — draw extraction, draw payloads, and drawing primitives
  Raster/      — cell-surface lowering
  Commit/      — commit plans, frame artifacts, retained-frame state, diagnostics
  Geometry/    — cell, continuous, and pixel geometry
  Pointer/     — pointer location, hover, and precision policy
  Styling/     — color, gradient, border, tile, appearance
  Content/     — text layout, rich text, FIGlet, image types
  Animation/   — animation protocols and animatable storage
  Runtime/     — state, registries, action scopes, portals, drop destinations
  Support/     — platform locks, math, string utilities, monotonic instants
  SwiftTUICore.docc/ — module landing page and pipeline guides
```

### Pipeline orchestrators

- `Pipeline/Pipeline.swift` and `Pipeline/Snapshots.swift`: snapshot pipeline orchestration
- `Pipeline/Scheduler.swift`: invalidation and wake scheduling
- `Pipeline/FrameDropEligibility.swift`: conservative classifier for which
  frames may be dropped under back-pressure

### Resolve

- `Resolve/ResolvedNode.swift`: the resolve-phase output node plus per-node
  semantic and lifecycle metadata, indexed-child-source primitives, and
  matched-geometry namespace types
- `Resolve/Environment.swift`: `EnvironmentSnapshot` (immutable copy-on-write
  environment values captured during resolve)
- `Resolve/TransactionSnapshot.swift`: `TransactionSnapshot` (per-frame
  animation-request and batch-id transport)
- `Resolve/NodeKind.swift`: `NodeKind` enum (root / scene / view classification)
- `Resolve/NodeLifecycleInfo.swift`: grouped lifecycle metadata accessor on
  `ResolvedNode`
- `Resolve/ViewGraph.swift`, `Resolve/ViewNode.swift`, `Resolve/ViewNodeContext.swift`,
  `Resolve/StateSlot.swift`, `Resolve/StructuralDiff.swift`,
  `Resolve/ChildDescriptor.swift`, `Resolve/DependencyTracker.swift`,
  `Resolve/DependencySet.swift`, `Resolve/NodeHandlers.swift`,
  `Resolve/NodeLifecycle.swift`, `Resolve/RegistrationAliasDiagnostics.swift`:
  the graph that drives resolution, dependency tracking, and structural diffing
- `Resolve/LayoutDependentContent.swift`: realization policy for content
  authored during resolve but sized only after layout

### Measure

- `Measure/LayoutEngine.swift`: the public `LayoutEngine` struct and
  `measure`/`place`/`dimensions` entry points
- `Measure/LayoutEngine+Measurement.swift`: measurement dispatch
  (`measureChildren` and helpers)
- `Measure/LayoutEngine+CellSize.swift`: `measuredSize` plus flexible-frame
  resolution and overlay sizing
- `Measure/LayoutEngine+IntrinsicSize.swift`: text, figure, rule, shape, and
  image intrinsic-size helpers
- `Measure/LayoutEngine+RetainedLayout.swift`: retained-resolve reuse
  (`retainedMeasurement`, `retainedPlacement`, `refreshDrawMetadata`)
- `Measure/LayoutEngine+Insets.swift`: inset/outset helpers and safe-area
  inset accounting
- `Measure/LayoutEngine+Alignment.swift`, `Measure/LayoutEngine+List.swift`,
  `Measure/LayoutEngine+Stack.swift`, `Measure/LayoutEngine+Table.swift`, and
  `Measure/LayoutEngine+Utility.swift`: layout-behavior-specific extensions
- `Measure/MeasurementCache.swift`: retained measurement-result cache
- `Measure/MeasuredNode.swift`: measure-phase output node plus child-allocation
  snapshots and lazy-stack viewport context
- `Measure/LayoutBehavior.swift`: layout-behavior taxonomy used by the engine
- `Measure/LayoutMetadata.swift`: per-node layout metadata
- `Measure/CustomLayout.swift`: custom-layout proxy and worker-snapshot types
- `Measure/NodeLayoutInfo.swift`: grouped layout-relevant node metadata used by
  `MeasurementCache` plus draw-payload measurement-equivalence helpers

### Place

- `Place/LayoutEngine+Placement.swift`: the placement pass of the layout engine
- `Place/PlacedNode.swift`: place-phase output node and `SemanticRole`

### Semantics

- `Semantics/Semantics.swift`: semantic extraction and route generation
- `Semantics/SemanticSnapshot.swift`: focus regions, interaction regions, scroll/selection/navigation routes, semantic snapshot
- `Semantics/SemanticRoleTypes.swift` and `Semantics/BuiltinPointerRoutes.swift`:
  closed semantic roles and structured pointer routes
- `Semantics/NodeSemanticInfo.swift`: grouped semantic metadata accessor on
  `ResolvedNode`
- `Semantics/FocusTracker.swift`, `Semantics/FocusPolicy.swift`,
  `Semantics/FocusInteractionTypes.swift`, `Semantics/FocusPresentation.swift`,
  `Semantics/FocusedValues.swift`: focus state and focus-value transport
- `Semantics/InteractionGateTypes.swift`: primitive data for visible-but-disabled gating
- `Semantics/GestureRecognizer.swift`: gesture-recognizer state machine

### Draw

- `Draw/DrawExtractor.swift`, `Draw/DrawExtractor+Lists.swift`,
  `Draw/DrawExtractor+Tables.swift`: draw extraction
- `Draw/DrawTreeTypes.swift`: draw-tree data types including `DrawCommand`,
  `DrawNode`, `PreformattedTextRun`, and `PreformattedTextLine`
- `Draw/RenderMetadataTypes.swift`: per-node draw metadata, text/style payload
  types, list payloads, and selection tags
- `Draw/NodeDrawInfo.swift`: grouped draw metadata accessor on `ResolvedNode`
- `Draw/TableDrawSupport.swift` and `Draw/TableSupport.swift`: table layout/render helpers
- `Draw/ScrollIndicatorSupport.swift`: scroll-indicator chrome
- `Draw/CanvasDrawing.swift`, `Draw/BrailleCanvas.swift`, `Draw/CanvasGrid.swift`:
  drawing primitives consumed by `Canvas` views

### Raster

- `Raster/Rasterizer.swift` and `Raster/Rasterizer+CellSampling.swift`: raster lowering
- `Raster/RasterTypes.swift`: raster surface types

### Commit

- `Commit/CommitPlanner.swift`: lifecycle diffing and commit packaging
- `Commit/CommitPlan.swift`: `TaskPriority`, `TaskDescriptor`, `LifecycleCommit*`,
  `HandlerInstallation`, and the `CommitPlan` aggregate
- `Commit/FrameArtifacts.swift`: per-frame artifacts, `FrameContext`, and `FrameDiagnostics`
- `Commit/RetainedResolveFrame.swift`: retained-frame index and layout-session
  state for resolve-reuse
- `Commit/FrameMetrics.swift`: cache metrics and per-phase work accounting
- `Commit/FrameTimings.swift`: per-phase timings and render-generation tracking
- `Commit/PresentationDamage.swift`: refined presentation-damage diagnostics

### Geometry, Pointer, Styling, Content, Animation, Runtime, Support

- `Geometry/Point.swift`, `Geometry/CellGeometry.swift`,
  `Geometry/PixelGeometry.swift`, `Geometry/Path.swift`,
  `Geometry/GeometryTypes.swift`, `Geometry/AnchorTypes.swift`,
  `Geometry/CellPixelMetrics.swift`, `Geometry/AxisTypes.swift`: continuous,
  cell, and pixel geometry plus anchor metadata, cell-pixel metadata, and the
  `Axis`/`AxisSet`/`VerticalEdgeSet` taxonomy
- `Pointer/PointerLocation.swift`, `Pointer/PointerPrecisionPolicy.swift`,
  `Pointer/HoverPhase.swift`: pointer location, capability metadata, and hover phases
- `Styling/Styling.swift`, `Styling/Appearance.swift`, `Styling/ViewStyleTypes.swift`,
  `Styling/Color.swift`, `Styling/ColorAnimatable.swift`,
  `Styling/GradientAnimatable.swift`, `Styling/BorderSet.swift`,
  `Styling/BorderEdgeStyle.swift`, `Styling/BorderBlend.swift`,
  `Styling/TileStyle.swift`, `Styling/TerminalChromeStyle.swift`,
  `Styling/CollectionStylePresentations.swift`, `Styling/Visibility.swift`:
  styling and appearance support
- `Content/TextLayout.swift`, `Content/RichText.swift`,
  `Content/TextFigureSupport.swift`, `Content/ImageTypes.swift`: text and image content
- `Animation/AnimationProtocols.swift`, `Animation/AnimationContextStorage.swift`,
  `Animation/AnimatableArray.swift`: animation protocols and storage
- `Runtime/StateContainer.swift`: runtime-owned state storage
- `Runtime/Local*Registry.swift` (12 files): package-only per-frame runtime registries
- `Runtime/ActionScope.swift`, `Runtime/CommandRegistry.swift`,
  `Runtime/DropDestinationRegistry.swift`, `Runtime/DroppedPath.swift`,
  `Runtime/DroppedPathParsing.swift`: action scopes, command registry, drop routing
- `Runtime/PortalTypes.swift`: portal IDs, modal policy, overlay ordering, dismiss ordering
- `Runtime/PreferenceValues.swift`: preference storage
- `Runtime/RuntimeRegistrationSet.swift`, `Runtime/FrameHeadRegistrationDraft.swift`:
  frame-scoped runtime registration aggregates
- `Support/MonotonicInstant.swift`, `Support/PlatformLock.swift`,
  `Support/PlatformMath.swift`, `Support/StringUtilities.swift`,
  `Support/Boxed.swift`: low-level support helpers

### Loose at module root

- `SwiftTUICore.docc/`: target-level pipeline guides

(All other files now live inside phase-named or topic-named subfolders.)

## `SwiftTUIViews`

- `Foundation/AnyView.swift`, `Foundation/ErasedViewTypeID.swift`,
  `Foundation/StylePrimitives.swift`, `Foundation/ViewBaseTypes.swift`,
  `Foundation/ViewCompositionHelpers.swift`, `Foundation/ViewFoundation.swift`,
  and `Foundation/ViewModifier.swift`: `View`, `ViewModifier`,
  `ModifiedContent`, `Resolver`, `AnyView`, payload type identity, style
  primitives, and internal composition helpers
- `ViewBuilder/ViewBuilder.swift`, `ViewBuilder/TupleView.swift`, `ViewBuilder/ConditionalContentView.swift`, `ViewBuilder/VariadicView.swift`, and `ViewBuilder/EmptyView.swift`: typed builder artifacts and builder machinery
- `State/State.swift`, `State/GestureState.swift`, `State/FocusState.swift`,
  and `State/FocusedValue.swift`: graph-scoped dynamic state, gesture state,
  focus bindings, and focused-value projections
- `Environment/Environment.swift`, `Environment/ImageEnvironment.swift`, `Environment/Observation.swift`, `Environment/RuntimePolicyEnvironment.swift`, and `Environment/StyleEnvironment.swift`: environment storage, repo-owned `@Bindable`, image resource roots, runtime policy values, and style environment plumbing
- `Focus/DefaultFocus.swift`: default-focus modifiers and focus defaults
- `Layout/Layout.swift`, `Stacks/*.swift`, `ScrollView/*.swift`, `GeometryReading/*.swift`, `Collections/*.swift`, and `NavigationViews/*.swift`: layout, stack, scroll, geometry, collection, and navigation surfaces
- `Canvas.swift`: public Canvas view construction over `CanvasDrawing` and dense
  pixel-grid drawings
- `Gestures/*.swift`: gestures, pointer paths, coordinate-space resolution,
  content shapes, and hover modifiers
- `ActionScopes/Panel.swift`, `ActionScopes/DropDestinationModifier.swift`, `ActionScopes/KeyCommandModifier.swift`, `ActionScopes/PaletteCommandModifier.swift`, `ActionScopes/Toolbar.swift`, and `ActionScopes/ToolbarItem.swift`: the `Panel` primitive with `.panel(id:)` / `.panel()` / `FocusContainment`; `.dropDestination(...)` scoped path drops with optional spatial context; the `.keyCommand(...)` modifier for shallowest-wins keybindings; the `.paletteCommand(...)` modifier plus `ActivePaletteCommand` + `EnvironmentValues.activePaletteCommands` for consumer-queryable palette surfaces; and the `.toolbar(style:)` absorber, `.toolbarItem(...)` hoisting contribution, `ToolbarStyle` protocol, and `DefaultTopToolbarStyle` / `DefaultBottomToolbarStyle` defaults. See [proposals/ACTION_SCOPES_AND_COMMANDS.md](proposals/ACTION_SCOPES_AND_COMMANDS.md).
- `Primitives/*.swift` and `Shapes/*.swift`: text/image primitives including `TextFigure`, labeled containers, and basic shapes
- `Controls/*.swift`: control surfaces, rendering helpers, and shared control support
- `Presentation/InteractionGate.swift`, `Presentation/OverlayStack.swift`, `Presentation/Portal.swift`, and `Presentation/DismissStack.swift`: package-internal primitives for visible-but-disabled subtrees, root overlay composition, destination-owned portal content, and topmost-dismiss routing
- `Presentation/PresentationCoordinator.swift` and `Presentation/PresentationModifiers.swift`: presentation adapters and chrome for built-in alert/confirmation-dialog/sheet/menu/toast surfaces lowered into the primitive portal stack
- `Modifiers/Preference.swift`, `Modifiers/StyleModifiers.swift`, `Modifiers/ViewModifiers.swift`, and `Modifiers/OnKeyPress.swift`: public modifiers plus the package-only modifier-value lowering hooks that back them
- `SwiftTUIViews.docc/`: module landing page and authoring guides

## `SwiftTUICharts`

- chart files such as `BarChart.swift`, `BulletChart.swift`, `ColumnChart.swift`, `ComparisonChart.swift`, `HeatStrip.swift`, `Legend.swift`, `Meter.swift`, `Sparkline.swift`, `StackedBarChart.swift`, `ThresholdGauge.swift`, and `Timeline.swift`: compact chart and metric views
- `ChartModels.swift`: shared data models for chart families
- `ChartSupport.swift` and `ChartChromeSupport.swift`: shared chart rendering helpers
- `Exports.swift`: product-facing export glue
- `SwiftTUICharts.docc/`: module landing page and charting guide

## `SwiftTUIAnimatedImage`

- `AnimatedImage.swift`: public view that advances through a finite supplied
  frame sequence
- `AnimatedImageSequence.swift`, `AnimatedImageFrame.swift`, and
  `AnimatedImagePixel.swift`: pre-composed frame model and timing data
- `AnimatedGIF.swift`: GIF import/export bridge backed by `Vendor/swift-gif`
- `AnimatedImagePNGEncoder.swift`: small internal RGBA PNG encoder used to
  hand static frames to the existing `Image(data:)` renderer
- `Exports.swift`: product-facing export glue for `SwiftTUICore` and `SwiftTUIViews`
- `SwiftTUIAnimatedImage.docc/`: module landing page

## Tests

- `Tests/SwiftTUICoreTests`: pipeline, layout, raster, and focus infrastructure tests
- `Tests/SwiftTUIViewsTests`: authoring-layer and environment-level tests
- `Tests/SwiftTUIAnimatedImageTests`: animated image frame, playback, and GIF
  import/export tests
- `Tests/SwiftTUITests`: runtime, rendering, fixture, and end-to-end behavioral tests
- `Platforms/CLI/Tests/SwiftTUICLITests`: terminal-native runner, attach, pty, and CLI-scene-management tests
- `Platforms/WASI/Tests/SwiftTUIWASITests`: launcher tests (manifest mode, transport-mode resolution)
- `Platforms/WASI/Tests/WASISurfaceBridgeTests`: surface-bridge tests (frame encoder, input parser, transport)
- `Fixtures/Transport`: shared transport fixtures for terminal render-style encoding/decoding tests across Swift and web hosts

## Reliability Rules

- New files should belong to one subsystem only.
- Shared helpers should move into support files before they are duplicated across features.
- Source-map changes should be updated here alongside any relevant changes to [ARCHITECTURE.md](ARCHITECTURE.md), [STATUS.md](STATUS.md), and [TESTING_AND_FIXTURE_POLICY.md](TESTING_AND_FIXTURE_POLICY.md).
- The repo currently enforces public-surface guardrails through `Scripts/check_public_surface_policies.sh`. There is not a separate checked-in source-layout hook today, so file-map drift must be caught through review and this document.
- The complete public symbol enumeration is regenerated by `Scripts/generate_public_api_inventory.sh` from `swift package dump-symbol-graph` and committed at [PUBLIC_API_BASELINE.md](PUBLIC_API_BASELINE.md) + [.public-api-baseline.txt](.public-api-baseline.txt). Run the script after any change to the public surface; classifications live in [public_api_overrides.yml](public_api_overrides.yml). Use `Scripts/generate_public_api_inventory.sh --check` to verify the committed baseline matches HEAD.
