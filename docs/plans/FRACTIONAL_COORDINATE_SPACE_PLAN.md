# Joint Implementation Plan: Sub-Cell Pointer Input

## Status

Implementation plan prepared from `JOINT_PROPOSAL.md`, `CODEX_PROPOSAL.md`,
`CLAUDE_PROPOSAL.md`, and the filesystem coordination notes in `.agent-comms/`.
It was later synced with Claude's implementation-plan scratch sections in
`.agent-comms/scratch/claude-impl-plan-sections.md`.

This plan assumes the project remains pre-release. Source compatibility and
migration cost are not goals. Temporary compatibility aliases may be useful while
working on a branch, but they should not be treated as durable public API.

## Target Outcome

TerminalUI should expose pointer locations in continuous cell space:

- Layout, raster placement, semantic frames, hit-region identity, and terminal
  output stay integer-cell based.
- Pointer input, gesture values, Canvas drawing, shape/path math, chart cursors,
  slider interpolation, scroll-thumb dragging, and direct-manipulation controls
  use fractional cell coordinates.
- Raw host/protocol pixels are retained as provenance and diagnostics, not as the
  primary authored coordinate system.
- Terminals and hosts without sub-cell input continue to work through
  structurally explicit cell fallback.

The implementation is intentionally a hard migration. It should end with one
coherent geometry model, not an integer API with sub-cell side channels.

## Design Commitments

The implementation should preserve these decisions from the joint proposal:

1. `Point`, `Size`, `Rect`, and `Vector` are continuous `Double` cell-space
   types.
2. `CellPoint`, `CellSize`, and `CellRect` are integer layout and raster-cell
   types.
3. `PointerLocation` is the event-level location with provenance.
4. Location-bearing gesture values expose `location: Point` for normal use and
   `pointer: PointerLocation` for capability/provenance-sensitive use.
5. Hit testing and routing use the containing cell, while gesture/control
   consumers receive the fractional point.
6. Cell-only fallback produces a useful `Point` everywhere, preferably the
   center of the reported cell.
7. Canvas becomes cell-space drawing with a configurable `CanvasGrid`.
8. Native and web precision land before terminal 1016 support.
9. Terminal 1016 is gated by explicit runtime state, trustworthy metrics, and a
   conservative policy.
10. Hover, drop location, paths, content shapes, and named coordinate spaces are
    aligned follow-on work, not unrelated features.

## Work Strategy

Do the work as vertical slices that compile and test at each boundary:

1. Split the geometry type system.
2. Add pointer provenance and fallback.
3. Migrate gestures.
4. Prove fractional input through native and web hosts.
5. Redesign Canvas on the new coordinate model.
6. Move direct-manipulation controls onto fractional coordinates.
7. Add terminal 1016.
8. Add secondary API candidates that become useful once the model is in place.
9. Refresh docs, examples, and fixtures.

Do not begin with terminal 1016. It has protocol ambiguity and terminal support
variance. Native and web hosts already have exact pointer coordinates and are
the best first proof of the public model.

## Working Agreements

### Branch And Review Strategy

- Use one feature branch per phase: `subcell-phase-1-types`,
  `subcell-phase-2-pointer-plumbing`, and so on.
- Phase 1 blocks all later phases. Do not start Phase 2 until Phase 1 has
  merged.
- Phases 2, 3, and 4 are linear: pointer plumbing, gestures, then native/web
  precision.
- Phases 5, 6, 7, and 8 may run in parallel after Phase 4 merges, but Phase 7 is
  the only phase that should touch terminal protocol bytes.
- `JOINT_IMPLEMENTATION_PLAN.md` remains the canonical plan and may be updated as
  decisions land. `JOINT_PROPOSAL.md` stays preserved as the design contract.

### Commit Discipline

- Every commit should build and pass the focused tests for the module set it
  touches.
- Phase 1 may need many mechanical commits. Each should compile before the next
  semantic edit starts.
- Type aliases are allowed only as transient scaffolding inside one phase branch
  and must be deleted before the phase lands.
- Do not use `@available` shims to preserve old names. This is a pre-release
  hard migration.

### Style And Public Type Requirements

- Match `.swift-format.json` and the existing `prek` checks.
- New public types should be `Equatable`, `Hashable`, and `Sendable` unless the
  implementation records a concrete reason otherwise.
- New public types should ship with DocC comments in the local style: short
  summary, concrete semantics, and terminal-specific caveats where needed.
- Prefer Swift Testing (`import Testing`, `@Test`, `#expect`) for new tests.

### Risk Controls

- Use a narrow bulk-rename script only for layout/raster files. Do not run it
  across `Sources/View/Gestures/`, `Sources/TerminalUI/InputReader.swift`,
  `Sources/TerminalUI/RunLoop+PointerHandling.swift`,
  `Sources/Core/LocalPointerHandlerRegistry.swift`,
  `Sources/Core/GestureRecognizer.swift`, or `GUI/`; those are pointer-domain
  files and need semantic migration.
- If an interim interop file such as `Sources/Core/CoordinateInterop.swift` is
  useful, keep it package-internal and delete it before Phase 1 merges.
- Every migrated subsystem needs one regression proving cell-only behavior is
  unchanged and one regression proving fractional behavior is preserved where
  that phase introduces it.

## Cross-Cutting Prerequisites

- Confirm `bun run test` is green on `main` before the first phase starts, or
  record the unrelated baseline failures.
- Identify snapshot/golden fixtures under `Tests/TerminalUITests/Fixtures/**`
  and `Examples/*/Tests/**/Fixtures/**`. Do not silently regenerate them.
- Inventory DocC pages that mention integer `Point`, `Size`, or `Rect`, including
  Core/View DocC and `Sources/View/View.docc/AspectCorrectShapes.md`.
- Draft `Scripts/migrate-cell-geometry.sh` before Phase 1 if bulk renaming is
  used. The script should operate only over an explicit file list, print a diff
  summary, run `swift-format` on touched Swift files, and refuse to mutate unless
  invoked with an explicit commit/apply flag.
- Treat Claude's survey estimates as sizing guidance: roughly 50 pointer/gesture
  sites, about 80 view-layer sites, several hundred test constructions, and a
  large layout/raster surface. Review by domain, not as one undifferentiated
  rename.

## Phase 0: Baseline Inventory And Branch Prep

### Objective

Establish the current test baseline, inventory the integer geometry surface, and
identify the files that will move from `Point`/`Size`/`Rect` to
`CellPoint`/`CellSize`/`CellRect`.

### Work

- Run the existing test gate before edits:
  - `bun run test`
  - If the full gate is already red, capture the failing suites and use focused
    tests for the migration while keeping the baseline failure separate.
- Inventory public and internal geometry use:
  - `rg "\\b(Point|Size|Rect)\\b" Sources Tests Examples GUI Runners`
  - Group results by role: layout/raster, pointer/gesture, Canvas/path/drawing,
    host transport, tests/fixtures.
- Record the migration map in a scratch note or checklist before editing.
- Confirm source-layout ownership against `docs/SOURCE_LAYOUT.md`.
- Keep fixture changes out of this phase.

### Acceptance

- Baseline test status is known.
- Integer geometry sites are categorized.
- The first code phase has an explicit file list.

## Phase 1: Coordinate Type Split

### Objective

Separate integer terminal cell geometry from continuous cell-space geometry.
This is the highest-blast-radius change and should be done mechanically before
behavioral pointer work.

### Files To Add Or Split

Recommended file layout:

- `Sources/Core/Geometry/Point.swift` for continuous `Point`, `Size`, `Rect`,
  and `Vector`.
- `Sources/Core/Geometry/CellGeometry.swift` for `CellPoint`, `CellSize`, and
  `CellRect`.
- `Sources/Core/Geometry/PixelGeometry.swift` for `PixelPoint` and any
  integer pixel-size/grid-size type introduced by the implementation.
- `Sources/Core/CoordinateInterop.swift` only as transient migration scaffolding;
  delete it before Phase 1 lands.
- `Tests/CoreTests/Geometry/PointTests.swift`
- `Tests/CoreTests/Geometry/CellGeometryTests.swift`
- `Tests/CoreTests/Geometry/RectContainsTests.swift`

`Sources/Core/GeometryTypes.swift` currently owns the existing integer
`Point`/`Size`/`Rect` alongside `EdgeInsets`, `ProposedDimension`,
`ViewDimensions`, `UnitPoint`, `Spacing`, and `Alignment`. The implementation may
either keep a single file or split geometry into the files above, but the final
public model should be separated clearly enough that `Cell*` layout geometry and
continuous drawing/input geometry are not confused.

### Public/Core Types

In `Sources/Core/GeometryTypes.swift`, move to this type family:

```swift
public struct Point: Equatable, Hashable, Sendable {
  public var x: Double
  public var y: Double
}

public struct Size: Equatable, Hashable, Sendable {
  public var width: Double
  public var height: Double
}

public struct Vector: Equatable, Hashable, Sendable {
  public var dx: Double
  public var dy: Double
}

public struct Rect: Equatable, Hashable, Sendable {
  public var origin: Point
  public var size: Size
}

public struct CellPoint: Equatable, Hashable, Sendable {
  public var x: Int
  public var y: Int
}

public struct CellSize: Equatable, Hashable, Sendable {
  public var width: Int
  public var height: Int
}

public struct CellRect: Equatable, Hashable, Sendable {
  public var origin: CellPoint
  public var size: CellSize
}
```

Add helpers:

```swift
extension Point {
  public init(_ cell: CellPoint)
  public var containingCell: CellPoint { get }
  public var fractionInCell: UnitPoint { get }
  public func snapped(_ rule: FloatingPointRoundingRule) -> CellPoint
}

extension CellRect {
  public func contains(_ cell: CellPoint) -> Bool
  public func contains(_ point: Point) -> Bool
  public var continuous: Rect { get }
}
```

The `CellRect.contains(_ point:)` rule should be half-open:
`[origin.x, origin.x + width) x [origin.y, origin.y + height)`.

### Migration Rule

- Existing layout/raster/semantic frame uses of `Point`, `Size`, and `Rect`
  become `CellPoint`, `CellSize`, and `CellRect`.
- Existing pointer/gesture/Canvas/path uses become `Point`, `Size`, `Rect`, and
  `Vector`.
- Avoid typealiases that hide the final model. If aliases are needed during a
  local mechanical branch, remove them before the phase is accepted.

### Likely File Groups

Core layout/raster:

- `Sources/Core/GeometryTypes.swift`
- `Sources/Core/LayoutTypes.swift`
- `Sources/Core/LayoutEngine*.swift`
- `Sources/Core/RenderTreeAndSemanticsTypes.swift`
- `Sources/Core/Semantics.swift`
- `Sources/Core/Rasterizer*.swift`
- `Sources/Core/RasterTypes.swift`
- `Sources/Core/ScrollIndicatorSupport.swift`
- `Sources/Core/CellPixelMetrics.swift`
- `Sources/Core/TerminalPresentation.swift`
- `Sources/Core/ImageTypes.swift`

View surface:

- `Sources/View/Foundation/ViewBaseTypes.swift`
- `Sources/View/Environment/StyleEnvironment.swift`
- `Sources/View/GeometryReading/GeometryReader.swift`
- `Sources/View/Shapes/*`
- `Sources/View/Controls/*`
- `Sources/View/ScrollView/*`

Runtime/host:

- `Sources/TerminalUI/RunLoop+Rendering.swift`
- `Sources/TerminalUI/RunLoop+PointerHandling.swift`
- `Sources/TerminalUI/InputReader.swift`
- `Sources/TerminalUI/TerminalGraphicsCapabilities.swift`
- Hosted surface and streaming host files that carry terminal size or frames.

Tests:

- Geometry, layout, raster, semantics, scroll, image, and runtime tests that
  currently use integer `Point`/`Size`/`Rect` for layout should be updated to
  `Cell*`.
- `NativeTerminalSurfaceView` can keep producing integer-valued continuous
  `Point` values in Phase 1. Actual fractional native input lands in Phase 4.

### Cell Pixel Metrics Cleanup

`CellPixelMetrics` currently carries integer pixel dimensions but may reuse the
generic `Size` type elsewhere. After `Size` becomes `Double`, add one of:

```swift
public struct PixelSize: Equatable, Hashable, Sendable {
  public var width: Int
  public var height: Int
}
```

or keep `CellPixelMetrics(width: Int, height: Int)` as the only pixel-size
surface and remove any ambiguous `Size`-based pixel fields. Do not let `Size`
mean both continuous cell-space size and device pixel extent.

`PixelImage.pixelSize` needs special attention because it describes an image
pixel grid, not terminal cells. Prefer a dedicated integer pixel-grid size type
over reusing `CellSize` for image pixels.

### Migration Steps

1. Add the new geometry files and type-level tests.
2. Run the scoped rename script over the layout/raster file list only.
3. Update stored-property types in render-tree, semantics, layout, raster, image,
   and scroll support files before fixing call sites.
4. Update `LayoutEngine*.swift` and verify all layout arithmetic remains
   integer-cell arithmetic.
5. Update rasterizer and damage/extent math; fixture changes must be reviewed as
   evidence.
6. Update `GeometryProxy.size` and any environment snapshots to use `CellSize`.
7. Update pointer-domain files only enough to compile against the new continuous
   `Point`; do not introduce `PointerLocation` until Phase 2.
8. Update GUI and example packages for the type split.
9. Delete interop shims and typealiases before the phase is accepted.

### Tests

Run after the phase:

- `swiftly run swift test --filter CoreTests`
- `swiftly run swift test --filter ViewTests`
- `swiftly run swift test --filter TerminalUITests.GeometryReaderSurfaceTests`
- `swiftly run swift test --filter TerminalUITests.CellPixelMetricsRefreshTests`

### Acceptance

- Layout and raster code are visibly integer-cell typed.
- Continuous geometry types compile and are available for later pointer work.
- Geometry readers expose `CellSize` for terminal layout and keep
  `cellPixelMetrics`.
- No public API leaves ambiguous `Size`-as-pixels semantics.
- The transient interop shim, if used, is deleted.
- A grep over migrated layout/raster files shows no accidental continuous
  `Point` use in layout frame math.

## Phase 2: PointerLocation And Capability Plumbing

### Objective

Normalize every pointer event into a provenance-carrying location at the first
framework boundary while preserving cell fallback.

### Types

Add pointer types in Core or the lowest layer already owning input-neutral
types:

```swift
public struct PixelPoint: Equatable, Hashable, Sendable {
  public var x: Double
  public var y: Double
}

public enum PointerPrecisionSource: Equatable, Hashable, Sendable {
  case terminalPixels
  case nativePixels
  case webPixels
}

public enum PointerPrecision: Equatable, Hashable, Sendable {
  case cell
  case subCell(source: PointerPrecisionSource, metrics: CellPixelMetrics)

  public var isSubCell: Bool { get }
}

public struct PointerLocation: Equatable, Hashable, Sendable {
  public var location: Point
  public var cell: CellPoint
  public var precision: PointerPrecision
  public var rawPixel: PixelPoint?
}

public struct PointerInputCapabilities: Equatable, Sendable {
  public var precision: PointerPrecision
  public var supportsSubCellLocation: Bool
  public var supportsHover: Bool
  public var supportsPreciseScroll: Bool
}
```

Add factories:

```swift
extension PointerLocation {
  public static func cellFallback(_ cell: CellPoint) -> PointerLocation
  public static func subCell(
    location: Point,
    source: PointerPrecisionSource,
    metrics: CellPixelMetrics,
    rawPixel: PixelPoint? = nil
  ) -> PointerLocation
}
```

For `cellFallback`, use center-of-cell:

```swift
Point(x: Double(cell.x) + 0.5, y: Double(cell.y) + 0.5)
```

This gives drawing and interpolation a less biased fallback. Code that needs
legacy cell behavior uses `pointer.cell`.

### Pipeline Changes

- `MouseEvent.location` becomes `PointerLocation`.
- `LocalPointerEvent.location` becomes `PointerLocation`.
- Hit testing uses `event.location.cell`.
- Gesture recognizers use `event.location.location`.
- `CoordinateSpace.resolve(...)` accepts a continuous `Point` and a `CellRect`.
- Coalescing compares event kind, modifiers, buttons, and whichever location
  semantics are correct for that event class:
  - movement/drag coalescing should preserve the newest precise location and
    retain samples for captured drags.
  - scroll coalescing should either require equal `cell` or equal precise
    `location`; choose one behavior and test it. The likely pragmatic choice is
    equal containing cell for terminal wheel events.
  - adjacent events with different `PointerPrecision` values should flush rather
    than silently merge. This prevents Phase 7 re-probe or mode-change events
    from hiding a precision transition.

### Files

Add:

- `Sources/Core/Pointer/PointerLocation.swift`
- `Sources/Core/Pointer/PointerPrecisionPolicy.swift`
- `Tests/CoreTests/Pointer/PointerLocationTests.swift`

Modify:

- `Sources/TerminalUI/InputReader.swift`
- `Sources/Core/LocalPointerHandlerRegistry.swift`
- `Sources/TerminalUI/RunLoop+PointerHandling.swift`
- `Sources/TerminalUI/RunLoop+EventDispatch.swift`
- `Sources/Core/GestureRecognizer.swift`
- environment/value files that own `EnvironmentValues`
- `Sources/View/GeometryReading/GeometryReader.swift`

### Environment/Geometry

Add:

```swift
extension EnvironmentValues {
  public var pointerInputCapabilities: PointerInputCapabilities { get set }
}
```

Consider also adding this to `GeometryProxy` if Canvas/chart code commonly needs
capability-aware drawing:

```swift
public var pointerInputCapabilities: PointerInputCapabilities
```

Keep `cellPixelMetrics` and pointer precision separate. Pixel geometry can exist
without precise pointer input.

### Tests

- Terminal 1006 parser still constructs pointer events from integer cells.
- Cell fallback yields a `PointerLocation` with `.cell`, a centered
  `location`, and the expected `cell`.
- Sub-cell construction at `Point(x: 2.7, y: 1.2)` yields
  `cell == CellPoint(x: 2, y: 1)` and `precision.isSubCell == true`.
- Coalescing with mixed precision flushes rather than merging.
- Run-loop hit testing still selects the same target for existing cell events.
- Pointer timestamp and capture-on-press behavior are unchanged.

Run:

- `swiftly run swift test --filter TerminalUITests.InputParserModifierTests`
- `swiftly run swift test --filter TerminalUITests.PointerEventTimestampTests`
- `swiftly run swift test --filter TerminalUITests.GestureRunLoopDispatchTests`
- `swiftly run swift test --filter TerminalUITests.CaptureOnPressTests`

### Acceptance

- Every pointer event carries `PointerLocation`.
- Existing terminal mouse behavior works through `.cell` fallback.
- Fractional data has a stable path from host/parser to local pointer event.
- `PointerInputCapabilities.cellOnly` is the default everywhere until hosts
  override it in later phases.

## Phase 3: Gesture Migration

### Objective

Make location-bearing gestures consume and expose continuous cell coordinates.

### Files

Add:

- `Sources/View/Gestures/PointerPath.swift`
- `Tests/TerminalUITests/Gestures/PointerPathTests.swift`

Modify:

- `Sources/View/Gestures/DragGesture.swift`
- `Sources/View/Gestures/SpatialTapGesture.swift`
- `Sources/View/Gestures/TapGesture.swift`
- `Sources/View/Gestures/LongPressGesture.swift`
- `Sources/View/Gestures/CoordinateSpace.swift`
- `Sources/View/Gestures/GestureModifiers.swift`
- `Sources/Core/GestureRecognizer.swift`
- gesture integration tests under `Tests/TerminalUITests`

### DragGesture

Target shape:

```swift
public struct DragGesture.Value: Equatable, Sendable {
  public var time: MonotonicInstant
  public var location: Point
  public var startLocation: Point
  public var translation: Vector
  public var velocity: Vector
  public var predictedEndLocation: Point
  public var predictedEndTranslation: Vector
  public var pointer: PointerLocation
  public var path: PointerPath
}

public struct DragGesture: Gesture {
  public let minimumDistance: Double
  public let coordinateSpace: CoordinateSpace
}
```

`translation` is `location - startLocation` in cells. `velocity` is cells per
second and must remain `Double`; integer velocity would erase slow/sub-cell
motion.

### PointerPath

Surface the samples already needed for velocity:

```swift
public struct PointerPath: Equatable, Sendable, RandomAccessCollection {
  public struct Sample: Equatable, Sendable {
    public var location: Point
    public var time: MonotonicInstant
    public var pointer: PointerLocation
  }
}
```

For drawing, the path should contain the samples received for the current drag
since gesture start. Bound memory by gesture duration. If event coalescing drops
intermediate events globally, captured drag routes should still receive or retain
enough samples to make `PointerPath` useful.

### SpatialTapGesture

```swift
public struct SpatialTapGesture.Value: Equatable, Sendable {
  public var location: Point
  public var pointer: PointerLocation
}
```

### TapGesture

Keep `TapGesture` value-less. Consumers that need location should use
`SpatialTapGesture`.

### LongPressGesture

`maximumDistance` becomes `Double`, measured in cells.

### Coordinate Spaces

Update coordinate-space resolution:

```swift
extension CoordinateSpace {
  public func resolve(
    terminalPoint: Point,
    targetRect: CellRect
  ) -> Point
}
```

`.local` subtracts the integer cell origin from the continuous point.
`.global` returns terminal-space coordinates.

### Tests

- Drag within a single cell emits distinct `location` values when fed precise
  input.
- Drag from cell fallback behaves predictably and still crosses the default
  `minimumDistance`.
- Velocity tests verify fractional cells per second.
- `PointerPath` contains ordered samples with monotonic timestamps.
- Spatial tap location preserves fractional input.
- Long press cancellation uses continuous distance.

Run:

- `swiftly run swift test --filter TerminalUITests.DragGestureTests`
- `swiftly run swift test --filter TerminalUITests.SpatialTapGestureTests`
- `swiftly run swift test --filter TerminalUITests.TapGestureTests`
- `swiftly run swift test --filter TerminalUITests.LongPressGestureTests`
- `swiftly run swift test --filter TerminalUITests.GestureIntegrationTests`

### Acceptance

- All location-bearing gestures expose continuous coordinates.
- Gesture recognizers still route through cell-based hit testing.
- Existing button/list/menu interactions remain cell-native.
- Slow drag velocity is no longer truncated to integer cells per second.
- Tests that compare whole gesture values account for exact `Double` equality;
  semantic tolerance, if needed, belongs in test helpers or projected fields.

### Phase 3 Risks

- Existing code may treat `velocity == .zero` as a jitter filter. Search for
  velocity equality checks and replace truncation-dependent logic with an
  explicit threshold if needed.
- `PointerPath` can grow during long drags. Decide and test the bounded-capacity
  rule before shipping this phase.

## Phase 4: Native And Web Host Precision

### Objective

Make sub-cell input work first in the hosts that already have exact pointer
coordinates: the native AppKit/UIKit host and the web host. This validates the
public pointer model before terminal 1016 support adds protocol ambiguity.

### Files

Native host:

- `GUI/SwiftUITUIGUI/Sources/SwiftUITUIGUI/NativeTerminalSurfaceView.swift`
- `GUI/SwiftUITUIGUI/Tests/SwiftUITUIGUITests/NativeTerminalSurfaceViewEventTests.swift`
- `GUI/SwiftUITUIGUI/Tests/SwiftUITUIGUITests/ResizeBridgeTests.swift`
- `GUI/SwiftUITUIGUI/Tests/SwiftUITUIGUITests/HostedSurfaceRegressionTests.swift`

Web host:

- `GUI/WebTUIGUI/src/WebTUISceneRuntime.ts`
- `GUI/WebTUIGUI/src/WebTUISceneRuntime.test.ts`
- `GUI/WebTUIGUI/src/WebTUISurfaceTransport.ts`
- `GUI/WebTUIGUI/src/wasi/BrowserWASIBridge.ts`
- `Runners/TerminalUIWASI/Sources/TerminalUIWASI/WebSurfaceTransport.swift`
- `Runners/TerminalUIWASI/Tests/TerminalUIWASITests/WebSurfaceTransportTests.swift`

Shared runtime surfaces:

- `Sources/TerminalUI/HostedSceneSession.swift`
- `Sources/TerminalUI/StreamingTerminalHost.swift`
- `Sources/TerminalUI/RunLoop+Rendering.swift`
- `Sources/View/Environment/StyleEnvironment.swift`
- `Sources/View/GeometryReading/GeometryReader.swift`

### Native Host Work

Replace immediate integer flooring with `PointerLocation` construction.

The helper should:

1. Convert window coordinates into local surface coordinates.
2. Divide by the effective cell width/height in the same coordinate system used
   by the host renderer.
3. Produce `Point(x: localX / cellWidth, y: localY / cellHeight)`.
4. Compute `cell = location.containingCell`.
5. Reject events outside the visible grid only after computing the containing
   cell.
6. Preserve the raw host-local coordinate as `rawPixel`.

Do not re-use the current cell-point helper as the primary helper. Keep a cell
projection only as `pointer.cell` or a test convenience.

AppKit/UIKit scale detail:

- `NSEvent.locationInWindow` and UIKit touch/pointer coordinates are logical
  view coordinates, not necessarily backing pixels.
- `rawPixel` can be host-local logical pixels unless the implementation chooses
  to multiply by backing scale. Document which one it is.
- `CellPixelMetrics` should continue to publish the geometry used by the
  renderer. Pointer conversion should be internally consistent with that
  renderer.

### Web Host Work

Current web flow floors DOM coordinates to cells. Replace it with fractional
cell coordinates:

```ts
const cellX = (event.clientX - rect.left) / this.cellWidth;
const cellY = (event.clientY - rect.top) / this.cellHeight;
```

Transport recommendation:

```text
mouse:down:2.42:0.61:primary:0:0:0
```

Because this is pre-release, prefer a clean decimal cell coordinate format over
integer fields plus appended fractional fields. Use locale-independent numeric
formatting and parsing.

Swift `WebSurfaceTransport` should parse `Double` x/y and construct
`PointerLocation.subCell(location:source:metrics:rawPixel:)` with
`source: .webPixels`. If current metrics are not available at parse time, either
store enough web-surface state to access them or send pixel offsets with each
event.

### Tests

Native:

- Pointer down at the center of cell `(2, 1)` produces `location == (2.5, 1.5)`
  and `cell == (2, 1)`.
- Drag within one cell changes `location` while preserving `cell`.
- Scroll events preserve fractional pointer location.
- Pointer capture and focus ordering are unchanged.

Web:

- Update `WebTUISceneRuntime.test.ts` expected messages to include fractional
  cell coordinates.
- Add a regression where `clientX` moves inside one cell and emits distinct drag
  coordinates.
- Add `WebSurfaceTransportTests` for parsing fractional x/y into
  `PointerLocation`.
- Test negative fractional coordinates and coordinates just beyond the grid.

Hosted runtime:

- Add or extend hosted-surface tests to prove fractional hosted input reaches
  `DragGesture.Value.location` unchanged.

Run:

- `swiftly run swift test --package-path GUI/SwiftUITUIGUI`
- `swiftly run swift test --package-path Runners/TerminalUIWASI`
- `cd GUI/WebTUIGUI && bun test`

### Acceptance

- Native and web pointer events preserve fractional positions through
  `MouseEvent`, `LocalPointerEvent`, and gesture values.
- Cell hit testing selects the same target as before for cell-center fallback and
  integer-cell clicks.
- Hosted resize/cell-pixel metric publishing still updates the environment.

## Phase 5: CanvasGrid And Canvas Redesign

### Objective

Move Canvas from hardcoded Braille subpixel coordinates to cell-space drawing
with configurable rasterization.

### Files

Add:

- `Sources/Core/Canvas/CanvasGrid.swift`
- `Sources/Core/Canvas/CanvasGridRasterizer.swift` or an equivalent internal
  grid-storage abstraction.
- Grid-specific rasterizer/state files for octant, sextant, quadrant,
  half-block, and full-cell output, unless the implementation keeps them in a
  single file for locality.
- `Tests/CoreTests/Canvas/CanvasGridTests.swift`
- focused grid tests for any newly supported glyph tables.

Modify:

- `Sources/View/Canvas.swift`
- `Sources/Core/CanvasDrawing.swift`
- `Sources/Core/BrailleCanvas.swift`
- `Sources/Core/Rasterizer.swift`
- `Sources/Core/RenderTreeAndSemanticsTypes.swift`
- `Examples/canvas/Sources/CanvasDemoViews/CanvasDemoView.swift`
- `Examples/gifeditor/Sources/GIFEditorUI/CanvasView.swift`
- Canvas tests and example package tests.

### Public API

Add:

```swift
public struct CanvasGrid: Equatable, Sendable {
  public enum Style: Equatable, Sendable {
    case braille2x4
    case octant2x4
    case sextant2x3
    case quadrant2x2
    case verticalHalfBlock
    case horizontalHalfBlock
    case fullCell
    case pixelExact
  }

  public var style: Style
  public var subdivisionsX: Int { get }
  public var subdivisionsY: Int { get }
}
```

`pixelExact` should be designed into the type system but may be unavailable until
graphics-protocol rendering is ready.

Change `CanvasContext` to expose cell-space drawing:

```swift
public struct CanvasContext: Sendable {
  public var size: CellSize
  public var grid: CanvasGrid
  public var foreground: Color
  public var background: Color?

  public func gridPoint(for location: Point) -> CellPoint
  public func gridPoint(for pointer: PointerLocation) -> CellPoint

  public mutating func setPixel(at location: Point)
  public mutating func line(from start: Point, to end: Point)
  public mutating func strokeRect(_ rect: Rect)
  public mutating func fillRect(_ rect: Rect)
  public mutating func strokeCircle(center: Point, radius: Double)
  public mutating func fillCircle(center: Point, radius: Double)

  public mutating func setCell(_ cell: CanvasCell, at location: CellPoint)
  public mutating func fillCell(_ color: Color, at location: CellPoint)
  public mutating func clearCell(at location: CellPoint)
}
```

Current `CanvasContext.width`/`height` in Braille subpixels should not survive as
the primary API. The cell extent is `size`; grid subdivisions are available from
`grid`.

### Authoring Styles

Support both forms:

```swift
Canvas(grid: .braille2x4, MyDrawing())

Canvas(grid: .braille2x4) { context in
  context.line(from: start, to: end)
}
```

The protocol form preserves the current `CanvasDrawing: Equatable` dedup path.
The closure form is useful for ad-hoc SwiftUI-style drawing. Both lower to the
same rasterizer and context.

Closure-form equality should be identity-based, not closure-body-based. Swift
closures are not equatable; consumers that need stable dedup should use the
protocol/value form.

### Rasterizer Work

Rasterize continuous cell operations by projecting to the chosen grid:

- Braille: `floor(x * 2)`, `floor(y * 4)`.
- Octant: same 2x4 grid with the octant glyph table.
- Sextant: `floor(x * 2)`, `floor(y * 3)`.
- Quadrant: `floor(x * 2)`, `floor(y * 2)`.
- Vertical half block: `floor(x)`, `floor(y * 2)`.
- Horizontal half block: `floor(x * 2)`, `floor(y)`.
- Full cell: `floor(x)`, `floor(y)`.
- Pixel exact: future buffer-backed rasterization using cell pixel metrics.

Unify the current Braille and `CanvasPixelGridDrawing` paths under this grid
model. A drawing should be able to change output style by changing the grid, not
by changing coordinate systems.

### Gesture Bridge

After Phase 3, the bridge is direct:

```swift
DragGesture(minimumDistance: 0, coordinateSpace: .local)
  .onChanged { value in
    document.append(value.location)
  }
```

The Canvas drawing then connects samples with:

```swift
context.line(from: a, to: b)
```

No consumer should need `cellX * 2 + 1` or `cellY * 4 + 2`.

### Migration Steps

1. Land the grid type and internal grid-state/rasterizer abstraction.
2. Route the existing Braille implementation through that abstraction before
   adding more grids.
3. Add octant, sextant, quadrant, half-block, and full-cell glyph mappings with
   focused tests.
4. Replace `CanvasContext`'s integer Braille-subpixel primitives with
   cell-space `Point` primitives.
5. Add the protocol and closure authoring forms.
6. Migrate `CanvasPixelGridDrawing` into `.fullCell` and half-block grid modes,
   then remove or temporarily deprecate the old type during the phase branch.
7. Update `Examples/canvas` to store `Point` samples from `DragGesture` rather
   than synthetic `CanvasSketchPoint` subpixels.
8. Keep `.pixelExact` as a tested unavailable/stub mode unless graphics-protocol
   rendering is implemented in the same phase.

### Tests

- Grid mapping for every shipped `CanvasGrid.Style`.
- A drag inside one cell on `.braille2x4` maps to multiple grid pixels when
  fractional input is supplied.
- Cell fallback maps to the center grid pixel or documented fallback grid
  position.
- Current `CanvasDrawing: Equatable` dedup behavior remains covered.
- Half-block/full-cell drawing is represented as grid modes, not a separate
  coordinate-space API.
- `Examples/canvas` no longer synthesizes subpixel anchors from integer cells.

Run:

- `swiftly run swift test --filter TerminalUITests.CanvasViewTests`
- `swiftly run swift test --filter CoreTests.BrailleCanvasTests`
- `swiftly run swift test --package-path Examples/canvas`

### Acceptance

- Canvas coordinates are fractional cells.
- Canvas owns grid mapping.
- The demo demonstrates real in-cell drawing movement on precise hosts.

## Phase 6: Controls, Scroll, And Charts

### Objective

Move direct-manipulation APIs to continuous pointer coordinates after the core
gesture migration has landed.

### Slider

Files:

- `Sources/View/Controls/AdjustableValueControls.swift`
- `Sources/View/Controls/SelectionAndValueSupport.swift`
- `Tests/TerminalUITests/SwiftUISurfaceTests.swift`
- `Tests/TerminalUITests/Fixtures/slider/*`

Change value mapping to accept a continuous x coordinate and a `CellRect` track:

```swift
func sliderValue<Value: AdjustableControlValue>(
  at locationX: Double,
  in trackRect: CellRect,
  bounds: ClosedRange<Value>,
  step: Value
) -> Value
```

Use the continuous coordinate directly in normalization. Keep step snapping in
`Value.controlValueFromTrack`.

Tests:

- A `Double` slider in a narrow track produces intermediate values for
  fractional locations inside one cell.
- Integer-only pointer fallback produces previous cell-stepped values.
- Fixture updates are limited to intentional value-label/rendering changes.

### Scroll Indicators

Files:

- `Sources/Core/ScrollIndicatorSupport.swift`
- `Sources/View/ScrollView/ScrollView.swift`
- focused Core tests or a new `ScrollIndicatorSupportTests.swift`
- runtime drag/wheel tests if needed

Use continuous pointer coordinates against integer track bounds:

```swift
let coordinate = location.y
let progress = (coordinate - Double(trackStart)) / Double(max(1, trackLength - 1))
```

Clamp progress to `0...1`.

Tests:

- Fractional thumb drag maps proportionally in a large content range.
- Whole-cell clicks produce the same rounded offsets as before.
- Scroll-wheel behavior remains unchanged in this phase.

### Charts

Files:

- `Sources/TerminalUICharts/*.swift`
- `Sources/TerminalUICharts/ChartSupport.swift`
- `Sources/TerminalUICharts/TerminalUICharts.docc/*`
- chart fixture tests only if interactive chart features are added

Initial chart work should avoid speculative public APIs. Add coordinate
conversion helpers that accept `Point` and map to chart-domain values. Add public
cursor/crosshair APIs only when there is a concrete consumer and tests.

### Acceptance

- Slider and scroll indicators demonstrate useful precision beyond Canvas.
- Existing list/table/picker/button behavior remains cell-native.
- No public chart API is added without a consumer and focused tests.

Run:

- slider/scroll focused tests once added
- `swiftly run swift test --filter TerminalUITests.SwiftUISurfaceTests`
- fixture tests touching `Fixtures/slider`

## Phase 7: Terminal 1016

### Objective

Add terminal SGR-Pixels support after the public pointer model is already proven
by native and web hosts.

### Files

- `Sources/TerminalUI/InputReader.swift`
- `Sources/TerminalUI/InjectedTerminalInputReader.swift`
- `Sources/TerminalUI/TerminalHost.swift`
- `Sources/TerminalUI/StreamingTerminalHost.swift`
- `Sources/TerminalUI/TerminalGraphicsCapabilities.swift`
- `Sources/TerminalUI/TerminalControlMessages.swift`
- `Sources/TerminalUI/RunLoop+Rendering.swift`
- `Tests/TerminalUITests/InputParserModifierTests.swift`
- `Tests/TerminalUITests/InputReaderControlMessageTests.swift`
- `Tests/TerminalUITests/TerminalGraphicsProtocolTests.swift`
- `Tests/TerminalUITests/TerminalHostProcessExitCleanupTests.swift`
- `Tests/TerminalUITests/CellPixelMetricsRefreshTests.swift`
- `Tests/TerminalUITests/InjectedTerminalInputReaderTests.swift`

### Policy And Runtime State

Add:

```swift
public enum PointerPrecisionPolicy: Equatable, Sendable {
  case cellOnly
  case useHostSubCellWhenAvailable
  case forceTerminalPixels
}
```

Add parser/runtime state:

```swift
enum MouseCoordinateMode: Equatable, Sendable {
  case cells
  case pixels(metrics: CellPixelMetrics, source: PointerPrecisionSource)
}
```

The parser must know the active mode. SGR 1006 and SGR-Pixels 1016 have the same
wire shape, so bytes alone cannot identify the coordinate unit.

### Parser

Cell mode:

```swift
let cell = CellPoint(x: max(0, encodedX - 1), y: max(0, encodedY - 1))
let pointer = PointerLocation.cellFallback(cell)
```

Pixel mode:

```swift
let pixelX = encodedX - 1
let pixelY = encodedY - 1
let location = Point(
  x: Double(pixelX) / Double(metrics.width),
  y: Double(pixelY) / Double(metrics.height)
)
let pointer = PointerLocation.subCell(
  location: location,
  source: source,
  metrics: metrics,
  rawPixel: PixelPoint(x: Double(pixelX), y: Double(pixelY))
)
```

Do not clamp negative pixel values before conversion. Some terminals report
negative or overshoot coordinates when a drag exits the viewport. Clamp for hit
testing only if needed.

### Enable/Disable Sequences

Current setup enables cell drag reporting and SGR encoding:

```text
CSI ? 1002 h
CSI ? 1006 h
```

When terminal-pixel mode is active, setup also enables:

```text
CSI ? 1016 h
```

Teardown and direct-exit reset must disable all active modes:

```text
CSI ? 1016 l
CSI ? 1006 l
CSI ? 1002 l
```

Update terminal cleanup tests so process exit cannot leave pixel mouse mode
enabled.

### Probing

Conservative sequence:

1. If policy is `.cellOnly`, skip 1016.
2. If `$TMUX` is present or `$TERM` starts with `screen`/`tmux`, default to
   `.cellOnly` unless policy is `.forceTerminalPixels`.
3. Query or infer trustworthy `CellPixelMetrics`.
4. Query SGR-Pixels support if there is an implementation path.
5. Enable 1016 only if both 1016 support and metrics are trusted.

Preferred metric sources are in-band, ordered reports such as DEC 2048 or
CSI-style cell-size queries. Do not enable 1016 from estimated metrics.

If DECRQM support is not implemented in the first pass, allow
`.forceTerminalPixels` for manual experiments and keep `.useHostSubCellWhenAvailable`
cell-only for unknown terminals.

### Tests

Parser:

- SGR 1006 cell mode reports center fallback for `CSI < 0 ; 3 ; 2 M`.
- SGR 1016 pixel mode with 8x16 metrics reports:
  - encoded `(17, 33)`
  - zero-based pixel `(16, 32)`
  - fractional cell `(2.0, 2.0)`
  - containing cell `(2, 2)`
- Negative or zero encoded pixel values follow a documented behavior.
- Wheel events preserve pointer precision metadata.

Host sequences:

- Pixel mode setup includes 1016.
- Teardown and crash reset disable 1016.
- Cell-only policy never emits 1016.
- tmux default never emits 1016.

Runtime:

- A terminal-pixel mouse event reaches `DragGesture.Value.location` as a
  fractional `Point`.
- Coalescing preserves precision metadata when merging move/drag events.

Run:

- `swiftly run swift test --filter TerminalUITests.TerminalHostProcessExitCleanupTests`
- `swiftly run swift test --filter TerminalUITests.TerminalGraphicsProtocolTests`
- `swiftly run swift test --filter TerminalUITests.InjectedTerminalInputReaderTests`
- `swiftly run swift test --filter TerminalUITests.InputReaderControlMessageTests`

### Acceptance

- Unknown terminals still behave as cell-only terminals.
- 1006 and 1016 cannot be confused by parser defaults.
- 1016 is always disabled on teardown if it was enabled.

## Phase 8: Hover, Drop Location, Path, And Named Coordinate Spaces

### Objective

Implement the secondary APIs that become materially more useful once pointer
coordinates are fractional.

### Hover

Files:

- `Sources/View/Gestures/*` or a new `Sources/View/Pointer/PointerHover.swift`
- `Sources/Core/LocalPointerHandlerRegistry.swift`
- `Sources/TerminalUI/RunLoop+PointerHandling.swift`
- `Sources/TerminalUI/TerminalHost.swift`
- focused `Tests/TerminalUITests` hover tests

API:

```swift
public enum HoverPhase: Equatable, Sendable {
  case entered(Point)
  case moved(Point)
  case exited
}

extension View {
  public func onPointerHover(
    _ action: @escaping @MainActor @Sendable (HoverPhase) -> Void
  ) -> some View
}
```

Runtime:

- Track hover subscribers.
- Enable DECSET 1003 only when at least one terminal-hosted subscriber exists.
- Disable 1003 when none remain.
- Native/web hosts can deliver hover without terminal 1003.

Tests:

- Hover subscriber receives entered/moved/exited for injected native/web events.
- Terminal host setup includes 1003 only when hover is active.
- Hover does not steal click focus or gesture capture.

### Drop Location

Files:

- `Sources/View/ActionScopes/DropDestinationModifier.swift`
- `Sources/Core/DropDestinationRegistry.swift`
- runtime paste/drop dispatch in `Sources/TerminalUI`
- `Tests/CoreTests/DropDestinationRegistryTests.swift`
- `Tests/TerminalUITests/DropDestinationDispatchTests.swift`
- `Tests/TerminalUITests/DropDestinationTests.swift`

API:

```swift
public struct DropContext: Equatable, Sendable {
  public var location: Point?
  public var pointer: PointerLocation?
  public var modifiers: EventModifiers
}
```

Handler:

```swift
@MainActor @Sendable ([DroppedPath], DropContext) -> Bool
```

Make `location` optional because terminal file-drop payloads may arrive via
paste without a reliable pointer location. Native/web file-drop events should
provide it.

Tests:

- Existing focused drop dispatch still works.
- Native/web spatial drop dispatch supplies location.
- Paste-only drop dispatch supplies `nil` location and remains usable.

### Path And Content Shapes

Files:

- new `Sources/Core/Path.swift` or `Sources/Core/ContinuousGeometry.swift`
- `Sources/View/Shapes/*`
- `Sources/View/Gestures/GestureViewModifier.swift`
- `Sources/Core/Semantics.swift`
- `Tests/CoreTests` for path math
- `Tests/TerminalUITests/ContentShapeTests.swift`

Start minimal:

```swift
public struct Path: Equatable, Sendable {
  public mutating func move(to: Point)
  public mutating func addLine(to: Point)
  public mutating func close()
  public func contains(_ point: Point) -> Bool
}
```

Defer curves/arcs until Canvas and Shape need them. Path should not block phases
1-7.

### Named Coordinate Spaces

Files:

- `Sources/View/Gestures/CoordinateSpace.swift`
- `Sources/Core/Semantics.swift`
- `Sources/Core/RenderTreeAndSemanticsTypes.swift`
- `Sources/TerminalUI/RunLoop+PointerHandling.swift`
- `Tests/TerminalUITests/CoordinateSpaceTests.swift`
- gesture tests for named-space drag/tap values

Approach:

- Record named coordinate-space frames during semantics extraction.
- Resolve `Point` by subtracting the named frame origin.
- Preserve fractional values.
- Keep `.local` and `.global` behavior unchanged.

### Acceptance

- Hover is opt-in and does not globally turn on high-volume terminal motion.
- Drop can carry spatial context where the host supplies it.
- Minimal Path/content-shape work does not become a prerequisite for Canvas.
- Named spaces no longer trap and preserve fractional values.

## Phase 9: Docs, Examples, And Public Surface Governance

### Objective

Align the documented framework model with the new coordinate split and make the
new behavior discoverable through examples.

### Docs

Update:

- `docs/ARCHITECTURE.md` for the integer layout / continuous input distinction.
- `docs/RUNTIME.md` for pointer normalization, capability policy, terminal mode
  setup/teardown, and high-volume hover rules.
- `docs/SOURCE_LAYOUT.md` for any new Core/View/TerminalUI files.
- `docs/PUBLIC_SURFACE_POLICY.md` if the public geometry, gesture, Canvas, or
  pointer capability surface requires new governance rules.
- `docs/TESTING_AND_FIXTURE_POLICY.md` only if fixture policy needs a new
  pointer/Canvas note.
- DocC for Canvas, gestures, geometry readers, and `TerminalUICharts` if chart
  helpers are added.

### Examples

Update or add examples:

- `Examples/canvas`: remove integer-cell-to-subpixel synthesis and store
  fractional `Point` samples from `DragGesture`.
- Add a small capability display in the Canvas example using
  `pointerInputCapabilities` and `cellPixelMetrics`.
- If hover lands, add a minimal chart/crosshair or Canvas hover demonstration.
- Keep examples honest on unsupported terminals: they should still work with
  cell fallback and should indicate reduced precision only where useful.

### Public Surface Checks

- Avoid new public type erasure seams.
- Avoid adding public style enums where existing protocol/value patterns are
  more consistent.
- Keep `AnyView` usage within the repo policy.
- Make public naming reflect roles:
  - `Cell*` for integer terminal cell geometry.
  - `Point`/`Size`/`Rect`/`Vector` for continuous cell-space geometry.
  - `Pixel*` only for provenance or graphics interop.

### Acceptance

- Docs explain the model without depending on proposal history.
- Examples exercise the intended API rather than workaround math.
- Public-surface policy checks pass.

## Phase 10: Test Matrix And Completion Gate

### Focused Gates By Phase

Phase 1 coordinate split:

- `swiftly run swift test --filter CoreTests`
- `swiftly run swift test --filter ViewTests`
- `swiftly run swift test --filter TerminalUITests.GeometryReaderSurfaceTests`
- `swiftly run swift test --filter TerminalUITests.CellPixelMetricsRefreshTests`

Phase 2 pointer plumbing:

- `swiftly run swift test --filter TerminalUITests.InputParserModifierTests`
- `swiftly run swift test --filter TerminalUITests.PointerEventTimestampTests`
- `swiftly run swift test --filter TerminalUITests.GestureRunLoopDispatchTests`
- `swiftly run swift test --filter TerminalUITests.CaptureOnPressTests`

Phase 3 gesture migration:

- `swiftly run swift test --filter TerminalUITests.DragGestureTests`
- `swiftly run swift test --filter TerminalUITests.SpatialTapGestureTests`
- `swiftly run swift test --filter TerminalUITests.TapGestureTests`
- `swiftly run swift test --filter TerminalUITests.LongPressGestureTests`
- `swiftly run swift test --filter TerminalUITests.GestureIntegrationTests`

Phase 4 native/web:

- `swiftly run swift test --package-path GUI/SwiftUITUIGUI`
- `swiftly run swift test --package-path Runners/TerminalUIWASI`
- `cd GUI/WebTUIGUI && bun test`

Phase 5 Canvas:

- `swiftly run swift test --filter TerminalUITests.CanvasViewTests`
- `swiftly run swift test --filter CoreTests.BrailleCanvasTests`
- `swiftly run swift test --package-path Examples/canvas`

Phase 6 controls:

- slider and scroll focused tests once added
- `swiftly run swift test --filter TerminalUITests.SwiftUISurfaceTests`
- fixture tests touching `Fixtures/slider`

Phase 7 terminal 1016:

- `swiftly run swift test --filter TerminalUITests.TerminalHostProcessExitCleanupTests`
- `swiftly run swift test --filter TerminalUITests.TerminalGraphicsProtocolTests`
- `swiftly run swift test --filter TerminalUITests.InjectedTerminalInputReaderTests`
- `swiftly run swift test --filter TerminalUITests.InputReaderControlMessageTests`

Final gate:

- `bun run test`

### Capability Matrix

| Host / capability | Expected pointer precision | Required coverage |
| --- | --- | --- |
| Terminal 1006 only | `.cell` | parser, gestures, controls, Canvas fallback |
| Native host | `.subCell(source: .nativePixels, metrics: ...)` | GUI event tests, hosted runtime gestures |
| Web host | `.subCell(source: .webPixels, metrics: ...)` | TypeScript runtime tests, WASI transport tests |
| Terminal 1016 + metrics | `.subCell(source: .terminalPixels, metrics: ...)` | parser mode tests, host sequence tests |
| Terminal 1016 requested without metrics | `.cell` fallback | capability policy tests |
| tmux/screen default | `.cell` | policy/sequence tests |
| Hover subscriber absent | no 1003 | host setup tests |
| Hover subscriber present | 1003 active where terminal-hosted | host setup and runtime hover tests |

### Fixture Rules

- Treat fixture updates as evidence, not cleanup.
- Update only fixtures whose output intentionally changed.
- Include an explanation of why a fixture changed in the implementation notes or
  commit message.
- For hosted behavior, test the composed host/runtime path, not only the inner
  recognizer.

## Phase 11: Rollout Boundaries And Sequencing

### Recommended Pull Request Slices

If this is split into reviewable work, slice by compile/test boundary:

1. Geometry type split and docs notes.
2. PointerLocation plumbing with cell fallback only.
3. Gesture migration.
4. Native/web precision.
5. CanvasGrid redesign and Canvas example.
6. Controls/scroll/chart helpers.
7. Terminal 1016 policy, parser, and cleanup.
8. Hover/drop/path/named-space follow-ons.
9. Final docs, fixtures, and full gate stabilization.

Because the project is pre-release, do not create compatibility layers that
force old and new APIs to coexist long-term. The slices are for implementation
stability, not for public migration support.

### Stop Conditions

Pause and revisit the design if any of these happen:

- The `Cell*`/continuous split causes layout code to require pervasive
  fractional frame math. That would mean the split was applied too broadly.
- Native/web hosts cannot preserve fractional positions without inconsistent
  coordinate systems. Fix host metrics before continuing.
- Canvas cannot express current Braille and half-block behavior through
  `CanvasGrid`. That would mean the grid abstraction is missing a real axis.
- Terminal 1016 support requires enabling pixel mode without trustworthy cell
  metrics. Fall back to cell-only instead.

## Risks

### Geometry Blast Radius

`Point`/`Size`/`Rect` are widely used. The type split is a large mechanical
change and will expose ambiguous semantics. That is useful, but it means Phase 1
should be treated as a migration phase with focused reviews.

### 1006 And 1016 Ambiguity

SGR 1006 and 1016 use the same event syntax. Runtime parser state must carry the
active coordinate mode. A stateless parser will eventually misinterpret events.

### Metric Trust

Pixel-to-cell conversion is only as good as cell metrics. Do not enable terminal
pixel input if metrics are estimated, missing, or known to be distorted by a
multiplexer.

### Multiplexers

tmux and screen can distort coordinate meaning. Default to cell-only inside
multiplexers and provide explicit override only for experiments.

### Event Volume

Sub-cell drag and hover can produce high event rates. Coalesce where appropriate
for controls, but preserve enough path samples for captured drawing routes.

### API Overreach

Raw pixel APIs can accidentally introduce a second layout model. Keep pixels as
provenance and explicit image/graphics interop data.

## Open Questions

These should be answered during implementation, not left implicit:

- Should `PointerLocation.cellFallback` use center-of-cell for all cell-derived
  events, or should terminal parser fallback use whole-number origins? The joint
  recommendation is center fallback.
- Should `PointerLocation` expose its point as `location` or `point`? The joint
  proposal uses `location`; implementation may choose `point` if it avoids
  awkward `event.location.location` call sites.
- Should `PointerPath` include every event since gesture start or only a bounded
  rolling window plus an index? The initial recommendation is every sample for
  the current gesture with a count cap such as 1024 samples, configurable later
  if real apps need it.
- Should image pixel-grid dimensions get a dedicated `PixelGridSize` rather than
  `PixelSize` or `CellSize`? The recommendation is a dedicated integer image
  pixel-grid type so terminal cells and image pixels do not share a misleading
  name.
- Should `.pixelExact` be public before a pixel graphics renderer ships? The
  recommendation is to reserve the design space, but only expose availability
  that can be tested.
- Should named coordinate spaces land with Phase 3 or Phase 8? They are useful
  but should not block the first fractional input path.
- How should raw native `rawPixel` be documented when the host reports logical
  view coordinates rather than backing pixels?
- Should `forceTerminalPixels` require a positive DECRQM probe? The current lean
  is no: allow the force mode for experiments, but log/document that interpreting
  1006 cell coordinates as pixels is a deliberate foot-gun if the terminal
  ignores 1016.
- Should `DragGesture.Value` keep exact `Equatable` over `Double` fields? The
  recommendation is yes; approximate comparisons belong in tests or consumer
  projections, not in framework equality.
- Should terminal 1016 include DEC 2048 in the first protocol PR? The
  recommendation is yes if CSI 16t/14t metrics are not enough to make metric
  trust reliable.
- Should hover DECSET 1003 teardown be debounced when subscribers churn? The
  recommendation is no for v1; enable on first subscriber and disable on last
  until profiling proves churn is a real problem.

## Definition Of Done

The implementation is complete when:

- `Point`, `Size`, `Rect`, and `Vector` are continuous cell-space types.
- Integer layout and raster surfaces use `CellPoint`, `CellSize`, and
  `CellRect`.
- `MouseEvent` and `LocalPointerEvent` carry `PointerLocation`.
- Drag and spatial tap expose fractional cell locations.
- Native and web hosts preserve in-cell movement through gesture values.
- Canvas drawing is cell-space and grid-aware.
- Sliders and scroll indicators consume continuous pointer positions.
- Terminal 1016 is supported only under a trustworthy policy and is always
  disabled on teardown.
- Docs and examples present the new model directly.
- The focused gates pass for the touched phases.
- `bun run test` passes as the final repo-wide gate.
