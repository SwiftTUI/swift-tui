# Codex Phase 1 Migration Map

## Baseline

- Branch: `subcell-phase-1-types`
- Full gate before edits: `bun run test`
- Baseline status: red only in `Examples/layouts`
  `DividerOrientationFlipBehaviourTests`:
  - `VStack divider draws a horizontal rule between V-1 and V-2 rows`
  - `HStack divider draws a vertical rule between H-1 and H-2 cells`
- Fixture policy: no fixture regeneration in Phase 1.

## Geometry Domains

- Continuous cell-space: `Point`, `Size`, `Rect`, `Vector`.
  - Intended for pointer input, gesture values, authored drawing, interpolation,
    and later Canvas/path work.
- Integer terminal cells: `CellPoint`, `CellSize`, `CellRect`.
  - Intended for layout proposals/results, placed bounds, semantics, raster
    surfaces, terminal cursor movement, and hit-region identity.
- Integer pixels: `PixelPoint`, `PixelSize`.
  - Intended for host/protocol pixel provenance, image grids, and cell-pixel
    capability metadata.

## Phase 1 File Groups

- New geometry files:
  - `Sources/Core/Geometry/Point.swift`
  - `Sources/Core/Geometry/CellGeometry.swift`
  - `Sources/Core/Geometry/PixelGeometry.swift`
- Layout/raster/semantic migration:
  - `Sources/Core/LayoutTypes.swift`
  - `Sources/Core/LayoutEngine*.swift`
  - `Sources/Core/RenderTreeAndSemanticsTypes.swift`
  - `Sources/Core/Semantics.swift`
  - `Sources/Core/Rasterizer.swift`
  - `Sources/Core/RasterTypes.swift`
  - `Sources/Core/ImageTypes.swift`
  - `Sources/Core/CommitAndFrameTypes.swift`
  - `Sources/Core/Snapshots.swift`
- Pointer-adjacent files migrated semantically, not by bulk rename:
  - `Sources/Core/LocalPointerHandlerRegistry.swift`
  - `Sources/Core/ScrollIndicatorSupport.swift`
  - `Sources/TerminalUI/InputReader.swift`
  - `Sources/View/Gestures/*.swift`
  - `GUI/SwiftUITUIGUI/Sources/SwiftUITUIGUI/NativeTerminalSurfaceView.swift`

## Verification Notes

- `swiftly run swift build`: passed after the root package migration.
- `swiftly run swift test --filter CoreTests`: passed after test and peer-host
  type cleanup; SwiftPM compiled the broad root test bundle first.
- Remaining required Phase 1 focused gates:
  - `swiftly run swift test --filter ViewTests`
  - `swiftly run swift test --filter TerminalUITests.GeometryReaderSurfaceTests`
  - `swiftly run swift test --filter TerminalUITests.CellPixelMetricsRefreshTests`
