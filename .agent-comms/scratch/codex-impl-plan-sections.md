# Codex Implementation Plan Sections

Draft sections for `JOINT_IMPLEMENTATION_PLAN.md`.

Scope owned here:

- Phase 4: Native and Web Host Precision
- Phase 6: Controls, Scroll, and Charts
- Phase 7: Terminal 1016
- Phase 8: Hover, Drop Location, Path, and Named Spaces
- Phase 10: Test matrix input

These sections assume the foundational phases have already introduced:

- `Point`, `Size`, `Rect`, and `Vector` as continuous `Double` cell-space types.
- `CellPoint`, `CellSize`, and `CellRect` as integer cell layout types.
- `PixelPoint` and, if accepted during implementation, `PixelSize`.
- `PointerLocation`, `PointerPrecision`, `PointerInputCapabilities`, and
  `PointerPrecisionPolicy`.
- `MouseEvent.location: PointerLocation`.
- `LocalPointerEvent.location: PointerLocation`.
- Gesture values exposing `location: Point` plus `pointer: PointerLocation`.

## Phase 4 — Native And Web Host Precision

### Objective

Make sub-cell input work first in the hosts that already have exact pointer
coordinates: the native AppKit/UIKit host and the web host. This validates the
public pointer model before terminal 1016 support adds protocol ambiguity.

### Files To Modify

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

### Native Host Implementation

Replace immediate integer flooring with `PointerLocation` construction.

Current native flow:

```swift
location: cellPoint(for: event.locationInWindow)
```

Target shape:

```swift
location: pointerLocation(
  for: event.locationInWindow,
  source: .nativePixels(metrics: metrics.cellPixelMetrics(scale: scale))
)
```

The helper should:

1. Convert window coordinates into local surface coordinates.
2. Divide by the measured cell width/height.
3. Produce `Point(x: localX / cellWidth, y: localY / cellHeight)`.
4. Compute `cell = location.containingCell`.
5. Reject events outside the visible grid only after computing the containing
   cell.
6. Preserve the raw host pixel/logical-pixel coordinate as `rawPixel`.

Do not re-use `cellPoint(for:)` as the primary helper. Keep a cell helper only
as a projection from `PointerLocation.cell` for tests or legacy host code.

UIKit/AppKit scale detail:

- `NSEvent.locationInWindow` and UIKit touch/pointer coordinates are logical
  view coordinates, not necessarily backing pixels.
- `rawPixel` can be host-local logical pixels unless the implementation chooses
  to multiply by backing scale. The precision source should remain
  `.nativePixels` because it came from a pixel-coordinate host path.
- `CellPixelMetrics` should continue to publish device-pixel dimensions for
  environment geometry. The pointer conversion should use the same effective
  cell dimensions used by the renderer in that host coordinate system.

### Web Host Implementation

Current web flow:

```ts
const x = Math.floor((event.clientX - rect.left) / this.cellWidth);
const y = Math.floor((event.clientY - rect.top) / this.cellHeight);
return { x, y };
```

Target flow:

```ts
const cellX = (event.clientX - rect.left) / this.cellWidth;
const cellY = (event.clientY - rect.top) / this.cellHeight;
return {
  x: cellX,
  y: cellY,
  cellX: Math.floor(cellX),
  cellY: Math.floor(cellY),
  pixelX: event.clientX - rect.left,
  pixelY: event.clientY - rect.top,
};
```

Transport options:

1. Preferred: change the mouse command to carry decimal cell coordinates.

   ```text
   mouse:down:2.42:0.61:primary:0:0:0
   ```

2. Acceptable: preserve integer fields and append fractions/pixels.

   ```text
   mouse:down:2:0:0.42:0.61:primary:0:0:0
   ```

Because the project is pre-release, prefer the cleaner decimal cell coordinate
format and update Swift parsing in one pass.

Swift `WebSurfaceTransport.parseMouseCommand` should parse `Double` x/y and
construct:

```swift
PointerLocation(
  location: Point(x: x, y: y),
  precision: .webPixels(metrics: currentCellPixelMetrics),
  rawPixel: PixelPoint(x: x * cellWidth, y: y * cellHeight)
)
```

If the transport cannot access current cell metrics directly at parse time,
store enough `WebSurfaceTransportHost.State` to make metrics available to the
input decoder or send pixel offsets with each event.

### Tests

Native:

- Add `NativeTerminalSurfaceViewEventTests` coverage for:
  - pointer down at the center of cell `(2, 1)` produces `location.x == 2.5`,
    `location.y == 1.5`, `cell == CellPoint(x: 2, y: 1)`.
  - pointer drag within one cell changes `location` while preserving `cell`.
  - scroll events preserve fractional pointer location.
  - pointer capture order is unchanged.

Web:

- Update `WebTUISceneRuntime.test.ts` expected mouse messages to include
  fractional cell coordinates.
- Add a regression where `clientX` moves inside one cell and emits distinct
  drag coordinates.
- Add `WebSurfaceTransportTests` for parsing fractional x/y into
  `PointerLocation`.
- Add invalid/out-of-bounds tests for negative fractional coordinates and
  coordinates just beyond the current grid.

Hosted runtime:

- Add or extend hosted-surface tests to prove a fractional hosted input reaches
  `DragGesture.Value.location` unchanged.
- Reuse GUI suites called out by existing repo memory as important locks:
  `ResizeBridgeTests`, `HostedSurfaceRegressionTests`, and
  `NativeTerminalSurfaceViewEventTests`.

### Acceptance Criteria

- Native and web pointer events preserve fractional positions through
  `MouseEvent`, `LocalPointerEvent`, and gesture values.
- Cell hit testing still selects the same target as before for center-of-cell
  fallback and integer-cell clicks.
- Web and native resize/cell-pixel metric publishing still updates
  `EnvironmentValues.cellPixelMetrics`.
- Focus, pressed-frame, scroll-wheel, and hosted-scene ordering tests remain
  green.

### Risks

- Native coordinate systems may mix backing pixels and logical points. Keep the
  conversion internally consistent with the renderer before exposing raw pixels
  as hard device pixels.
- Web transport parsing is currently colon-delimited. Decimal values are simple,
  but do not introduce locale-sensitive formatting.
- Hosted scene tests can pass while browser runtime breaks; keep both Swift and
  Bun tests in the gate.

## Phase 6 — Controls, Scroll, And Charts

### Objective

Move direct-manipulation APIs to continuous pointer coordinates after the core
gesture migration has landed.

### Slider

Files:

- `Sources/View/Controls/AdjustableValueControls.swift`
- `Sources/View/Controls/SelectionAndValueSupport.swift`
- `Tests/TerminalUITests/SwiftUISurfaceTests.swift`
- `Tests/TerminalUITests/Fixtures/slider/*`
- Any dedicated slider tests if added during implementation.

Current `Slider` uses:

```swift
sliderValue(at: event.location.x, in: event.targetRect, ...)
```

Target:

```swift
sliderValue(at: event.location.location.x, in: event.targetRect, ...)
```

Change `sliderValue` to accept `Double` x and `CellRect` track bounds:

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

- A `Double` slider in a 3-cell usable track should produce intermediate values
  when the pointer is at fractional positions inside one cell.
- Integer-only pointer fallback should produce previous cell-stepped values.
- Existing rendered fixtures should not change unless value labels update from
  newly precise interactions.

### Scroll Indicators

Files:

- `Sources/Core/ScrollIndicatorSupport.swift`
- `Sources/View/ScrollView/ScrollView.swift`
- `Tests/CoreTests` for focused metric tests, or add a new
  `ScrollIndicatorSupportTests.swift`.
- `Tests/TerminalUITests/InteractiveRuntimeTests.swift` for runtime drag/wheel
  behavior if needed.

Change:

```swift
targetOffset(for location: Point, currentOffset: Int)
```

to use `Point` continuous coordinates against `CellRect` track bounds.

For vertical indicators:

```swift
let coordinate = location.y
let progress = (coordinate - Double(trackStart)) / Double(max(1, trackLength - 1))
```

Clamp progress to `0...1`.

Tests:

- Fractional thumb drag maps proportionally in a large content range.
- Existing whole-cell clicks produce the same rounded offsets as before.
- Scroll-wheel event behavior is unchanged because wheel deltas stay integer in
  this phase.

### Charts

Files:

- `Sources/TerminalUICharts/*.swift`
- `Sources/TerminalUICharts/ChartSupport.swift`
- `Sources/TerminalUICharts/TerminalUICharts.docc/*`
- Chart fixture tests in `Tests/TerminalUITests/Fixtures/*chart*` if interactive
  chart cursors are added.

Initial implementation should not force chart interactivity. Instead:

- Add coordinate-conversion helpers in chart support that accept `Point` and
  map to chart-domain values.
- If public cursor APIs are introduced, keep them optional and pointer-driven.
- Avoid broad chart fixture churn until there is a concrete interactive chart
  feature.

Acceptance criteria:

- Slider and scroll indicators demonstrate useful precision beyond Canvas.
- Existing list/table/picker/button behavior remains cell-native.
- No public chart API is added without a concrete consumer or tests.

## Phase 7 — Terminal 1016

### Objective

Add terminal SGR-Pixels support after the public pointer model is already proven
by native and web hosts.

### Files To Modify

- `Sources/TerminalUI/InputReader.swift`
- `Sources/TerminalUI/InjectedTerminalInputReader.swift`
- `Sources/TerminalUI/TerminalHost.swift`
- `Sources/TerminalUI/StreamingTerminalHost.swift`
- `Sources/TerminalUI/TerminalGraphicsCapabilities.swift`
- `Sources/TerminalUI/TerminalControlMessages.swift` if DEC 2048 push reports
  are parsed as control messages.
- `Sources/TerminalUI/RunLoop+Rendering.swift`
- `Tests/TerminalUITests/InputParserModifierTests.swift`
- `Tests/TerminalUITests/InputReaderControlMessageTests.swift`
- `Tests/TerminalUITests/TerminalGraphicsProtocolTests.swift`
- `Tests/TerminalUITests/TerminalHostProcessExitCleanupTests.swift`
- `Tests/TerminalUITests/CellPixelMetricsRefreshTests.swift`
- `Tests/TerminalUITests/InjectedTerminalInputReaderTests.swift`

### Capability And Policy Types

Introduce:

```swift
public enum PointerPrecisionPolicy: Equatable, Sendable {
  case cellOnly
  case useHostSubCellWhenAvailable
  case forceTerminalPixels
}
```

Add host/runtime state:

```swift
enum MouseCoordinateMode: Equatable, Sendable {
  case cells
  case pixels(metrics: CellPixelMetrics, source: PointerPrecision)
}
```

The parser must know the active mode because SGR 1006 and SGR-Pixels 1016 have
the same wire shape.

### Parser Changes

Current parser:

```swift
let location = Point(x: max(0, encodedX - 1), y: max(0, encodedY - 1))
```

Target parser:

```swift
let pointerLocation: PointerLocation
switch mouseCoordinateMode {
case .cells:
  let cell = CellPoint(x: max(0, encodedX - 1), y: max(0, encodedY - 1))
  pointerLocation = .cellFallback(cell)
case .pixels(let metrics, let source):
  let pixelX = encodedX - 1
  let pixelY = encodedY - 1
  pointerLocation = PointerLocation(
    location: Point(
      x: Double(pixelX) / Double(metrics.width),
      y: Double(pixelY) / Double(metrics.height)
    ),
    precision: source,
    rawPixel: PixelPoint(x: Double(pixelX), y: Double(pixelY))
  )
}
```

Do not clamp negative pixel values before conversion. Some terminals can report
negative/overshoot coordinates during drags outside the viewport. Clamp only for
hit testing if needed.

### Terminal Enable/Disable Sequences

Current setup enables:

```text
CSI ? 1002 h
CSI ? 1006 h
```

When terminal-pixel mode is active, setup should enable:

```text
CSI ? 1002 h
CSI ? 1006 h
CSI ? 1016 h
```

Teardown and process-exit reset must disable all active modes:

```text
CSI ? 1016 l
CSI ? 1006 l
CSI ? 1002 l
```

Update process-exit cleanup tests so the terminal is never left in pixel mouse
mode after a crash/direct exit.

### Probing

Use a conservative sequence:

1. If policy is `.cellOnly`, skip 1016.
2. If `$TMUX` is present or `$TERM` starts with `screen`/`tmux`, default to
   `.cellOnly` unless policy is `.forceTerminalPixels`.
3. Query or infer trustworthy `CellPixelMetrics`.
4. Query SGR-Pixels support if an implementation path exists.
5. Enable 1016 only if both 1016 support and metrics are trusted.

If DECRQM support is not implemented in the first pass, allow
`forceTerminalPixels` for manual experiments and keep `useHostSubCellWhenAvailable`
cell-only for unknown terminals.

DEC 2048 in-band reports are useful but should not block the first terminal
phase if CSI 16t/14t metrics are already present. Treat DEC 2048 as a follow-up
inside the same phase unless probing cannot be made reliable otherwise.

### Tests

Parser tests:

- SGR 1006 cell mode reports center fallback for `CSI < 0 ; 3 ; 2 M`.
- SGR 1016 pixel mode with 8x16 metrics reports:
  - `encodedX = 17`, `encodedY = 33`
  - zero-based pixel `(16, 32)`
  - fractional cell `(2.0, 2.0)`
  - containing cell `(2, 2)`.
- Negative or zero encoded pixel values are either preserved as negative
  fractional locations or handled explicitly; choose and test.
- Wheel events preserve pointer precision metadata.

Host sequence tests:

- Pixel mode setup includes 1016.
- Teardown and crash reset disable 1016.
- Cell-only policy never emits 1016.
- tmux default never emits 1016.

Runtime tests:

- A terminal-pixel mouse event reaches `DragGesture.Value.location` as a
  fractional `Point`.
- Coalescing preserves precision metadata when merging move/drag events.
- Scroll event merging compares containing cell or precise location according to
  the chosen semantics; document and test the choice.

Acceptance criteria:

- Unknown terminals still behave exactly as cell-only terminals.
- 1006 and 1016 cannot be confused by parser defaults.
- 1016 is always disabled on teardown if it was enabled.
- `bun run test` is green after terminal mode support lands.

## Phase 8 — Hover, Drop Location, Path, And Named Spaces

### Hover

Files:

- `Sources/View/Gestures/*` or a new `Sources/View/Pointer/PointerHover.swift`
- `Sources/Core/LocalPointerHandlerRegistry.swift`
- `Sources/TerminalUI/RunLoop+PointerHandling.swift`
- `Sources/TerminalUI/TerminalHost.swift`
- `Tests/TerminalUITests` hover-focused tests.

Add:

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
- Enable DECSET 1003 only when at least one subscriber exists.
- Disable 1003 when none remain.
- Native/web hosts can deliver hover without terminal 1003.

Tests:

- Hover subscriber receives entered/moved/exited for native/web injected events.
- Terminal host setup includes 1003 only when hover is active.
- Hover does not steal click focus or gesture capture.

### Drop Location

Files:

- `Sources/View/ActionScopes/DropDestinationModifier.swift`
- `Sources/Core/DropDestinationRegistry.swift`
- Runtime paste/drop dispatch in `Sources/TerminalUI`.
- `Tests/CoreTests/DropDestinationRegistryTests.swift`
- `Tests/TerminalUITests/DropDestinationDispatchTests.swift`
- `Tests/TerminalUITests/DropDestinationTests.swift`

Add:

```swift
public struct DropContext: Equatable, Sendable {
  public var location: Point?
  public var pointer: PointerLocation?
  public var modifiers: EventModifiers
}
```

Handler shape:

```swift
@MainActor @Sendable ([DroppedPath], DropContext) -> Bool
```

Because terminal file-drop payloads may arrive via paste without reliable
pointer location, `location` should be optional unless the runtime can prove a
current pointer location. Native/web file-drop events should provide it.

Tests:

- Existing focused drop dispatch still works.
- Native/web spatial drop dispatch supplies location.
- Paste-only drop dispatch supplies `nil` location and remains usable.

### Path And Content Shapes

Files:

- New `Sources/Core/Path.swift` or `Sources/Core/ContinuousGeometry.swift`
- `Sources/View/Shapes/*`
- `Sources/View/Gestures/GestureViewModifier.swift`
- `Sources/Core/Semantics.swift`
- `Tests/CoreTests` for path math.
- `Tests/TerminalUITests/ContentShapeTests.swift`

Start with minimal `Path`:

```swift
public struct Path: Equatable, Sendable {
  public mutating func move(to: Point)
  public mutating func addLine(to: Point)
  public mutating func close()
  public func contains(_ point: Point) -> Bool
}
```

Defer curves/arcs until Canvas and Shape need them. The implementation plan
should explicitly prevent Path from blocking phases 1-7.

### Named Coordinate Spaces

Files:

- `Sources/View/Gestures/CoordinateSpace.swift`
- `Sources/Core/Semantics.swift`
- `Sources/Core/RenderTreeAndSemanticsTypes.swift`
- `Sources/TerminalUI/RunLoop+PointerHandling.swift`
- `Tests/TerminalUITests/CoordinateSpaceTests.swift`
- Gesture tests for named-space drag/tap values.

Approach:

- Record named coordinate-space frames during semantics extraction.
- Resolve `Point` by subtracting the named frame origin.
- Preserve fractional values.
- Keep `.local` and `.global` behavior unchanged.

Acceptance criteria:

- Named spaces no longer trap.
- Drag and spatial tap can report locations in a named ancestor space.
- Named space behavior works with fractional native/web input.

## Phase 10 — Test Matrix Input

### Focused Test Gates By Phase

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

- Slider and scroll focused tests once added.
- `swiftly run swift test --filter TerminalUITests.SwiftUISurfaceTests`
- Fixture tests touching `Fixtures/slider`.

Phase 7 terminal 1016:

- `swiftly run swift test --filter TerminalUITests.TerminalHostProcessExitCleanupTests`
- `swiftly run swift test --filter TerminalUITests.TerminalGraphicsProtocolTests`
- `swiftly run swift test --filter TerminalUITests.InjectedTerminalInputReaderTests`
- `swiftly run swift test --filter TerminalUITests.InputReaderControlMessageTests`

Final gate:

- `bun run test`

### Capability Matrix

Minimum simulated capabilities:

| Host / capability | Expected pointer precision | Required coverage |
| --- | --- | --- |
| Terminal 1006 only | `.cell` | parser, gestures, controls, Canvas fallback |
| Native host | `.nativePixels` | GUI event tests, hosted runtime gestures |
| Web host | `.webPixels` | TS runtime tests, WASI transport tests |
| Terminal 1016 + metrics | `.terminalPixels` | parser mode tests, host sequence tests |
| Terminal 1016 requested without metrics | `.cell` fallback | capability policy tests |
| tmux/screen default | `.cell` | policy/sequence tests |
| Hover subscriber absent | no 1003 | host setup tests |
| Hover subscriber present | 1003 active where terminal-hosted | host setup and runtime hover tests |

### Full-Gate Notes

- `bun run test` remains the repo-wide completion gate for shared runtime work.
- Fixture changes should be treated as evidence; update only fixtures whose
  output intentionally changed.
- For hosted behavior, include the composed host/runtime path, not only direct
  recognizer tests.
