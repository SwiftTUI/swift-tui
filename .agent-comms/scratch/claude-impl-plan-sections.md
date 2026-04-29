# Claude Implementation Plan Sections

Draft sections for `JOINT_IMPLEMENTATION_PLAN.md`.

Scope owned here:

- §0 Working Agreements
- §1 Cross-Cutting Prerequisites
- §2 Phase 1 — Coordinate Types
- §3 Phase 2 — PointerLocation Plumbing
- §4 Phase 3 — Gesture Migration
- §6 Phase 5 — Canvas Redesign
- §11 Open Questions For Implementer

Codex owns: §5 (Phase 4 native/web), §7 (Phase 6 controls), §8 (Phase 7 terminal 1016), §9 (Phase 8 hover/drop/path/named).
Joint: §10 (test matrix).

---

## §0 — Working Agreements

### Branch strategy

- One feature branch per phase: `subcell-phase-1-types`, `subcell-phase-2-pointer-plumbing`, etc. Each phase ships as a single PR.
- Phase 1 (types) blocks all later phases; do not start Phase 2 until Phase 1 has merged.
- Phases 2 → 3 → 4 are linear.
- Phases 5, 6, 7, 8 can run in parallel after Phase 4 merges (gesture/host plumbing landed). Phase 7 is the only one that touches terminal protocol bytes; the others only consume the new types.

### Commit discipline

- Every commit must build and pass Swift Testing for at least the same module set that was green at HEAD before the commit started. Phase 1 in particular will produce many "rename only" intermediate commits; each of those must compile and pass tests after each commit.
- Use type aliases (`typealias OldPoint = CellPoint`) only as transient scaffolding within a single PR. Remove before the PR lands.
- Never use `@available` to "preserve" an old name during the migration. Pre-release means we delete the old name and accept the breakage.

### Style requirements

- Match the existing `.swift-format.json` configuration. The repo already has `prek` configured.
- New public types ship with full DocC comments matching the existing style (see `Sources/Core/CellPixelMetrics.swift` and `Sources/View/Gestures/DragGesture.swift` for tone — short header sentence, concrete example, terminal-faithful caveats).
- New public types must be `Equatable, Hashable, Sendable` unless there is a stated reason otherwise (matches every other public geometry type in the codebase).

### Test policy

- Swift Testing (`import Testing`, `@Test`/`#expect`) for new tests; do not regress to XCTest. Existing tests remain in their current framework.
- Each new public type gets at least one type-level `@Test` covering construction, equality, and any computed property (e.g., `containingCell`, `fractionInCell`).
- Each migrated subsystem (parser, gesture, Canvas, hosts) gets at least one regression test that asserts integer-cell behavior is unchanged on cell-only input AND fractional behavior is correct on sub-cell input.
- The full-gate is `bun run test`. Each PR must pass it.

### Risk-of-breakage discipline

- Phase 1 is the biggest single migration (~800–1200 LOC, ~167 test files touched). Use a script to do the bulk rename `Point` → `CellPoint`, `Size` → `CellSize`, `Rect` → `CellRect` for files in the **layout/raster** scope; review per file. Do *not* run the script over `Sources/View/Gestures/`, `Sources/TerminalUI/InputReader.swift`, `Sources/TerminalUI/RunLoop+PointerHandling.swift`, `Sources/Core/LocalPointerHandlerRegistry.swift`, `Sources/Core/GestureRecognizer.swift`, or `GUI/` — those are pointer-domain and migrate in Phases 2/3/4 to the new continuous `Point`.
- Keep an "interim shim" file (`Sources/Core/CoordinateInterop.swift`, deleted before Phase 1 ships) that hosts free functions like `Point(_ cell: CellPoint) -> Point` and `CellPoint(_ point: Point, rule: FloatingPointRoundingRule = .down) -> CellPoint` so callers can be migrated incrementally during the phase.

### Working-doc location

- This document (`JOINT_IMPLEMENTATION_PLAN.md`) is the canonical plan. It is updated, not appended-to, as decisions land. The original `JOINT_PROPOSAL.md` is preserved and not modified — it's the design contract.
- Per-phase decisions are captured in PR descriptions, not in this plan. The plan describes intent; PRs capture history.

---

## §1 — Cross-Cutting Prerequisites

Before Phase 1 begins, the following groundwork should land in a small prep PR (or as the first commit of Phase 1).

### 1.1 Test fixture preparation

- Identify all snapshot / golden-output fixtures (`Tests/TerminalUITests/Fixtures/**`, `Examples/*/Tests/**/Fixtures/**`). These will need re-baselining after geometry migration. List them in PR descriptions; do not silently regenerate.
- Confirm that `prek` and the test-sealed CI gate (`bun run test`) are green on `main` before any phase work starts.

### 1.2 Documentation prep

- The `Sources/Core/Core.docc` and `Sources/View/View.docc` doc bundles reference `Point`, `Size`, `Rect`. Note all DocC pages that mention the integer geometry types so they can be updated to the new dual-type story.
- `Sources/View/View.docc/AspectCorrectShapes.md` already discusses cell-pixel metrics; review it for needed updates.

### 1.3 Survey artifacts

The following call-site inventories are reference material the implementer may want during the migration:

- ~150 `Point`/`Size`/`Rect` constructions in `Sources/Core/LayoutEngine*.swift` (layout placement, alignment, stack, list, table).
- ~100 in `Sources/Core/Rasterizer.swift` (surface allocation, damage tracking, extent math) and `Sources/Core/CanvasDrawing.swift` / `Sources/Core/BrailleCanvas.swift`.
- ~50 in pointer/gesture pipeline (`Sources/Core/GestureRecognizer.swift`, `Sources/Core/LocalPointerHandlerRegistry.swift`, `Sources/TerminalUI/InputReader.swift`, `Sources/TerminalUI/RunLoop+PointerHandling.swift`).
- ~80 across view types (gestures, geometry-reader, canvas, controls, scrolls, shapes).
- ~412 constructions in tests across ~167 test files. The bulk of test churn lives in `Tests/TerminalUITests/` (gestures, layout, rasterizer assertions).
- ~320 in the GUI bridge (`GUI/SwiftUITUIGUI/Sources/SwiftUITUIGUI/NativeTerminalSurfaceView.swift` and adjacent).

These figures bound the migration size and inform PR review pacing — expect Phase 1 to be a multi-day review.

### 1.4 Type-rename script (pre-implementation)

A shell script that does the layout-domain bulk rename should be drafted before Phase 1 starts and committed to `Scripts/migrate-cell-geometry.sh`. It should:

- Operate only over a passed list of file paths (not the whole tree).
- Use `sed`/`perl` for rename, then run `swift-format` over each file.
- Print a diff summary; refuse to run without `--commit` to avoid surprise.

The script's purpose is to handle the obvious `Point → CellPoint` renames; humans handle the rest.

---

## §2 — Phase 1: Coordinate Types

### Objective

Introduce two parallel geometry families:

- `Point`, `Size`, `Rect`, `Vector` as `Double`-valued continuous cell-space types.
- `CellPoint`, `CellSize`, `CellRect` as `Int`-valued integer cell layout types.

Migrate the layout engine, rasterizer, render tree, and most internal types to the integer `Cell*` family. Leave gesture/pointer/Canvas types referencing `Point`/`Size`/`Rect` (they migrate to the continuous form *as types* in Phase 1, but their *use* still produces integer-valued doubles until Phases 2–4 plumb sub-cell data through).

### Files To Add

- `Sources/Core/Geometry/Point.swift` (continuous Point, Vector, Size, Rect)
- `Sources/Core/Geometry/CellGeometry.swift` (CellPoint, CellSize, CellRect)
- `Sources/Core/Geometry/PixelGeometry.swift` (PixelPoint and, if introduced, PixelSize)
- `Sources/Core/CoordinateInterop.swift` (transient migration shim — deleted before Phase 1 PR ships)
- `Tests/CoreTests/Geometry/PointTests.swift`
- `Tests/CoreTests/Geometry/CellGeometryTests.swift`
- `Tests/CoreTests/Geometry/RectContainsTests.swift`

### Files To Modify (canonical list)

The current `Sources/Core/GeometryTypes.swift` defines `Point`, `Size`, `Rect` (lines 624–700) plus `EdgeInsets`, `ProposedDimension`, `ViewDimensions`, `UnitPoint`, `Spacing`, `Alignment`. Split this:

- Move `Point`, `Size`, `Rect` into the new `Point.swift` file with `Double` storage and Phase 1 semantics.
- Move `CellPoint`, `CellSize`, `CellRect` into the new `CellGeometry.swift`.
- Keep `EdgeInsets` (`Int`), `ViewDimensions` (`Int`), `ProposedDimension` (`Int?`), `Spacing`, `Alignment`, `UnitPoint` (`Double`) in `GeometryTypes.swift` (or split further if naturally partitioned).

Modules that migrate from `Point`/`Size`/`Rect` to `CellPoint`/`CellSize`/`CellRect` (layout-domain):

- `Sources/Core/LayoutEngine.swift` and `LayoutEngine+Alignment.swift`, `LayoutEngine+List.swift`, `LayoutEngine+Placement.swift`, `LayoutEngine+Stack.swift`, `LayoutEngine+Table.swift`, `LayoutEngine+Utility.swift`
- `Sources/Core/LayoutTypes.swift` (`ChildAllocation.size`, `MeasuredNode.measuredSize`)
- `Sources/Core/RenderTreeAndSemanticsTypes.swift` (`PlacedNode.bounds/contentBounds/clipBounds`, `InteractionRegion.rect`, `FocusRegion.rect`, `ScrollRoute.viewportRect/contentBounds`, `DrawNode.bounds/clipBounds`, `SemanticNode.explicitInteractionRect`)
- `Sources/Core/NodeMetadata.swift` (`intrinsicSize`)
- `Sources/Core/RasterTypes.swift` (`RasterSurface.size`)
- `Sources/Core/Rasterizer.swift` and all rasterizer companion paths (~60 sites)
- `Sources/Core/CommitPlanner.swift` (committed frame geometry)
- `Sources/Core/ImageTypes.swift` (`PixelImage.intrinsicCellSize`, `PixelImage.cellPixelSize` → `CellSize`; `PixelImage.pixelSize` may stay `CellSize` of the *pixel grid* OR introduce a new `PixelGridSize` type — see Open Questions §11)
- `Sources/View/GeometryReading/GeometryReader.swift` (`GeometryProxy.size: Size` → `CellSize`)
- `Sources/View/Environment/StyleEnvironment.swift` (any geometry-typed env values)
- `Sources/Core/Styling.swift` (any geometry-typed environment snapshots)
- `Sources/View/Layout/*`, `Sources/View/Stacks/*`, `Sources/View/Shapes/*` (consumers of layout geometry)
- `Sources/View/ScrollView/ScrollView.swift` (viewport/content bounds — these are layout, migrate)
- `Sources/TerminalUICharts/*` (chart geometry — migrate to `CellRect` for layout, but allow `Point`/`Rect` for fractional cursor projections)
- All test files that construct or compare `Point`/`Size`/`Rect` for layout assertions

Modules that retain `Point`/`Size`/`Rect` *but the type's storage becomes `Double`* (pointer/drawing-domain — values remain integer-valued until Phases 2–4 land sub-cell data):

- `Sources/TerminalUI/InputReader.swift` (`MouseEvent.location: Point`) — value still integer in Phase 1
- `Sources/TerminalUI/RunLoop+PointerHandling.swift` (most pointer plumbing) — values integer in Phase 1
- `Sources/Core/LocalPointerHandlerRegistry.swift` (`LocalPointerEvent.location`, `targetRect: Rect`) — Phase 1 just changes types; semantics in Phase 2
- `Sources/Core/GestureRecognizer.swift` (`targetRect: Rect`)
- `Sources/View/Gestures/DragGesture.swift`, `SpatialTapGesture.swift`, `LongPressGesture.swift`, `TapGesture.swift`, `Gesture.swift`, `GestureModifiers.swift`, `GestureViewModifier.swift`, `ExclusiveGesture.swift`, `CoordinateSpace.swift` — gesture values migrate to `Double` storage
- `Sources/View/Canvas.swift`, `Sources/Core/CanvasDrawing.swift`, `Sources/Core/BrailleCanvas.swift` — Canvas primitives migrate in Phase 5; in Phase 1 they only need to compile against the new `Point`/`Size`/`Rect` types (which is mostly cosmetic since CanvasContext currently uses raw `Int` parameters, not these types)

GUI bridge (`GUI/SwiftUITUIGUI/Sources/`):

- `NativeTerminalSurfaceView.swift` — the existing `cellPoint(for:) -> Point` helper now produces `Point(Double)` with integer values; full sub-cell wiring lands in Phase 4.

### New Type Signatures

```swift
// Continuous cell-space geometry (Sources/Core/Geometry/Point.swift)

/// A 2D position in continuous cell coordinates.
///
/// `(0.0, 0.0)` is the top-leading edge of cell `(0, 0)`. `(0.5, 0.5)` is the
/// center of cell `(0, 0)`. `(1.0, 0.0)` is the top-leading edge of cell
/// `(1, 0)`. The containing cell of any `Point` is `floor(x), floor(y)`.
public struct Point: Equatable, Hashable, Sendable {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }

  public init(_ cell: CellPoint) {
    self.init(x: Double(cell.x), y: Double(cell.y))
  }

  public static let zero = Self(x: 0, y: 0)

  /// The integer cell that contains this position. Equivalent to
  /// `CellPoint(x: Int(x.rounded(.down)), y: Int(y.rounded(.down)))`.
  public var containingCell: CellPoint {
    CellPoint(x: Int(x.rounded(.down)), y: Int(y.rounded(.down)))
  }

  /// The fractional offset within the containing cell, both in `0..<1`.
  public var fractionInCell: UnitPoint {
    UnitPoint(x: x - Double(containingCell.x), y: y - Double(containingCell.y))
  }

  public func snapped(_ rule: FloatingPointRoundingRule = .down) -> CellPoint {
    CellPoint(x: Int(x.rounded(rule)), y: Int(y.rounded(rule)))
  }
}

public struct Vector: Equatable, Hashable, Sendable {
  public var dx: Double
  public var dy: Double
  public init(dx: Double, dy: Double) { self.dx = dx; self.dy = dy }
  public static let zero = Self(dx: 0, dy: 0)
}

public struct Size: Equatable, Hashable, Sendable {
  public var width: Double
  public var height: Double
  public init(width: Double, height: Double) { self.width = width; self.height = height }
  public init(_ cell: CellSize) { self.init(width: Double(cell.width), height: Double(cell.height)) }
  public static let zero = Self(width: 0, height: 0)
}

public struct Rect: Equatable, Hashable, Sendable {
  public var origin: Point
  public var size: Size
  public init(origin: Point, size: Size) { self.origin = origin; self.size = size }
  public init(_ cell: CellRect) {
    self.init(origin: Point(cell.origin), size: Size(cell.size))
  }
  public static let zero = Self(origin: .zero, size: .zero)

  public var maxX: Double { origin.x + size.width }
  public var maxY: Double { origin.y + size.height }
  public var isEmpty: Bool { size.width <= 0 || size.height <= 0 }

  /// Half-open containment: `[x, x+width) × [y, y+height)`.
  public func contains(_ point: Point) -> Bool {
    !isEmpty
      && point.x >= origin.x && point.x < maxX
      && point.y >= origin.y && point.y < maxY
  }

  public func intersection(_ other: Rect) -> Rect? { /* same as today, Double */ }
}
```

```swift
// Integer cell layout geometry (Sources/Core/Geometry/CellGeometry.swift)

public struct CellPoint: Equatable, Hashable, Sendable {
  public var x: Int
  public var y: Int
  public init(x: Int, y: Int) { self.x = x; self.y = y }
  public static let zero = Self(x: 0, y: 0)
}

public struct CellSize: Equatable, Hashable, Sendable {
  public var width: Int
  public var height: Int
  public init(width: Int, height: Int) { self.width = width; self.height = height }
  public static let zero = Self(width: 0, height: 0)
}

public struct CellRect: Equatable, Hashable, Sendable {
  public var origin: CellPoint
  public var size: CellSize
  public init(origin: CellPoint, size: CellSize) { self.origin = origin; self.size = size }
  public static let zero = Self(origin: .zero, size: .zero)

  public var maxX: Int { origin.x + size.width }
  public var maxY: Int { origin.y + size.height }
  public var isEmpty: Bool { size.width <= 0 || size.height <= 0 }

  public func contains(_ cell: CellPoint) -> Bool {
    !isEmpty
      && cell.x >= origin.x && cell.x < maxX
      && cell.y >= origin.y && cell.y < maxY
  }

  /// Cell-rect contains a fractional Point if its containing cell is inside.
  public func contains(_ point: Point) -> Bool { contains(point.containingCell) }

  public func intersection(_ other: CellRect) -> CellRect? { /* same as Rect today, Int */ }
}
```

```swift
// Pixel provenance (Sources/Core/Geometry/PixelGeometry.swift)

/// A device-pixel position. Optional in `PointerLocation.rawPixel` for diagnostics
/// and for graphics-protocol consumers.
public struct PixelPoint: Equatable, Hashable, Sendable {
  public var x: Double
  public var y: Double
  public init(x: Double, y: Double) { self.x = x; self.y = y }
  public static let zero = Self(x: 0, y: 0)
}
```

### Migration Steps

1. Add the three new files. Run `swift build`. Existing code is unaffected because the new types live alongside the old.
2. Run the rename script over the layout-domain file list (see §1.4). Verify each file builds; fix obvious `init`-call mismatches.
3. Update `RenderTreeAndSemanticsTypes.swift`, `LayoutTypes.swift`, `RasterTypes.swift`, `NodeMetadata.swift`, `ImageTypes.swift`. These have the most stored-property changes.
4. Update `LayoutEngine*.swift`. Verify that integer arithmetic (alignment guides, stack accumulation) still produces correct results — this is the core layout math and any sign of double-precision drift is a bug.
5. Update `Rasterizer.swift` and its companions. Verify that surface/damage geometry remains pixel-accurate for snapshot fixtures.
6. Update `GeometryReader.swift` (`size: Size → CellSize`) and `Styling.swift` environment snapshot.
7. Update `ScrollView.swift` and other view-type consumers of layout geometry.
8. Pointer-domain files (`InputReader.swift`, `RunLoop+PointerHandling.swift`, `LocalPointerHandlerRegistry.swift`, gestures): only the type *storage* changes (`Point`'s fields become `Double`). Construction sites use `Point(x: Double(cell), y: Double(cell))` — values are still integer-valued. **Do not** introduce `PointerLocation` here; that is Phase 2.
9. Update tests. The bulk of the diff is in `Tests/`. Group test renames by domain (gesture tests use the new continuous `Point`; layout tests use `CellPoint`).
10. Update `Examples/` and `Examples/canvas` for the renames. Canvas itself doesn't change in Phase 1 — only the types it consumes from upstream.
11. Update `GUI/SwiftUITUIGUI/Sources/`. The `cellPoint(for:)` helper now produces `Point(Double)` with integer values.
12. Re-baseline any geometry-printed snapshots (the `Snapshots.swift` test util prints `Rect`/`Size` for diagnostic output — see existing usage).
13. Delete `Sources/Core/CoordinateInterop.swift` and any `typealias` shims.

### Tests

New tests:

- `PointTests`: construction, equality, `containingCell`, `fractionInCell`, `Point(_ cell:)`, `snapped(_:)`.
- `CellGeometryTests`: parallel coverage for `CellPoint`/`CellSize`/`CellRect`.
- `RectContainsTests`: half-open containment semantics for both `Rect.contains(Point)` and `CellRect.contains(CellPoint)` and `CellRect.contains(Point)`.
- `Phase1MigrationSmokeTest`: a sample layout that exercises layout → raster → committed-frame end-to-end, using both type families. Pin a snapshot of the resulting cell grid.

Migrated tests:

- All ~412 test constructions of `Point`/`Size`/`Rect` need rename or type swap. Group by domain and PR-section to keep review tractable.
- Per project memory note (`feedback_input_reader_timing.md`): when migrating timing-sensitive tests, do not rely on wall-clock; pin invariants synchronously where possible.

### Acceptance Criteria

- All tests pass at HEAD with the new types.
- Snapshot fixtures unchanged or re-baselined with explicit PR review.
- `bun run test` is green.
- No remaining references to integer `Point` outside the layout/raster domain (verified by `grep` of the migrated files).
- The interop shim file is deleted before the Phase 1 PR merges.

### Risks

- **Layout drift from Double arithmetic.** Rasterizer's alignment math is currently integer; introducing `Double` in any layout path could produce off-by-one rounding. Mitigation: keep layout strictly `CellPoint`/`CellSize`/`CellRect` and never accept a `Point` into a layout-engine function during Phase 1.
- **Large test churn.** ~167 test files, ~412 sites. Mitigation: split the Phase 1 PR into reviewable commits by directory (e.g., one commit per LayoutEngine extension file, one per RenderTreeAndSemanticsTypes property cluster, one per major test file group).
- **Hidden Point producers.** Some tests construct `Point` via tuples or convenience initializers that may not surface in `grep "Point("`. Mitigation: a CI test that fails if any test file references the old integer `Point` after the migration script has run.
- **GUI bridge cell conversion.** `NativeTerminalSurfaceView.cellPoint(for:)` does `Int(local.x / cellSize.width)`. After Phase 1 it must produce `Point(Double(cellX), Double(cellY))` with integer values; the actual fractional path lands in Phase 4. Don't accidentally expose fractional values too early.
- **Examples and demos.** `Examples/canvas` and `Examples/gifeditor` use these types; both have their own test suites. Mitigation: include them in the same Phase 1 PR.

---

## §3 — Phase 2: PointerLocation Plumbing

### Objective

Introduce the rich pointer event type. Replace `MouseEvent.location: Point` and `LocalPointerEvent.location: Point` with a `PointerLocation`-bearing wrapper, while preserving `Point` (continuous) as the primary consumer-facing field on every gesture value (Phase 3).

This phase is internal plumbing only — the parser still produces cell-only events, but the type system now carries provenance for Phases 4 and 7 to fill in.

### Files To Add

- `Sources/Core/Pointer/PointerLocation.swift` (`PointerLocation`, `PointerPrecision`, `PointerPrecisionSource`, `PointerInputCapabilities`)
- `Sources/Core/Pointer/PointerPrecisionPolicy.swift`
- `Tests/CoreTests/Pointer/PointerLocationTests.swift`

### Files To Modify

- `Sources/TerminalUI/InputReader.swift` — `MouseEvent.location: Point → PointerLocation` (lines 59–85). The SGR parser at lines 484–642 produces cell-derived locations using the **center fallback** (`Point(x: cell.x + 0.5, y: cell.y + 0.5)`). Coalescing predicates at lines 973–1007 must merge `PointerLocation` correctly (preserve the latest precision).
- `Sources/Core/LocalPointerHandlerRegistry.swift` — `LocalPointerEvent.location: Point → PointerLocation` (line 30). Update the `package struct` and the registry dispatch.
- `Sources/TerminalUI/RunLoop+PointerHandling.swift` — `handleMouseEvent`, `handleMouseDown/Up/Move`, `hitTarget(at:)` signatures. Lines 40–130 (handlers) and 362–376 (hit testing) must thread the `PointerLocation`. Note: `hitTarget(at:)` should accept the `cell: CellPoint` for hit testing while preserving the original `PointerLocation` for downstream dispatch.
- `Sources/TerminalUI/RunLoop+EventDispatch.swift` — case `.input(.mouse(...))` flow at lines 20–37.
- `Sources/Core/GestureRecognizer.swift` — `handle(event:)` now receives `LocalPointerEvent` with `PointerLocation`. Recognizers that ignore the location field don't change; those that read it (DragGesture, SpatialTapGesture) update in Phase 3.
- `Sources/Core/EnvironmentAndNodeTypes.swift` (or wherever `EnvironmentValues` lives) — add `pointerInputCapabilities`.
- `Sources/View/GeometryReading/GeometryReader.swift` — `GeometryProxy.pointerInputCapabilities`.

### New Type Signatures

```swift
// Sources/Core/Pointer/PointerLocation.swift

public enum PointerPrecisionSource: Equatable, Hashable, Sendable {
  case terminalPixels
  case nativePixels
  case webPixels
}

public enum PointerPrecision: Equatable, Hashable, Sendable {
  case cell
  case subCell(source: PointerPrecisionSource, metrics: CellPixelMetrics)

  public var isSubCell: Bool {
    if case .subCell = self { return true } else { return false }
  }
}

/// A pointer event location with provenance. `.location` is the primary
/// fractional cell position. `.cell` is the integer cell that contains it.
/// `.precision` indicates whether sub-cell data was real or center-estimated.
/// `.rawPixel` is optional device-pixel diagnostics (graphics-protocol consumers
/// may want it; ordinary gesture code should not).
public struct PointerLocation: Equatable, Hashable, Sendable {
  public var location: Point
  public var cell: CellPoint
  public var precision: PointerPrecision
  public var rawPixel: PixelPoint?

  public init(
    location: Point,
    cell: CellPoint,
    precision: PointerPrecision,
    rawPixel: PixelPoint? = nil
  ) {
    self.location = location
    self.cell = cell
    self.precision = precision
    self.rawPixel = rawPixel
  }

  /// Construct a `.cell`-precision location for a given integer cell.
  /// The `location` is set to the *center* of the cell.
  public static func cellFallback(_ cell: CellPoint) -> Self {
    Self(
      location: Point(x: Double(cell.x) + 0.5, y: Double(cell.y) + 0.5),
      cell: cell,
      precision: .cell
    )
  }

  /// Construct a `.subCell` location from a fractional point and its source.
  public static func subCell(
    location: Point,
    source: PointerPrecisionSource,
    metrics: CellPixelMetrics,
    rawPixel: PixelPoint? = nil
  ) -> Self {
    Self(
      location: location,
      cell: location.containingCell,
      precision: .subCell(source: source, metrics: metrics),
      rawPixel: rawPixel
    )
  }
}

public struct PointerInputCapabilities: Equatable, Hashable, Sendable {
  public var precision: PointerPrecision
  public var supportsSubCellLocation: Bool
  public var supportsHover: Bool
  public var supportsPreciseScroll: Bool

  public init(
    precision: PointerPrecision = .cell,
    supportsSubCellLocation: Bool = false,
    supportsHover: Bool = false,
    supportsPreciseScroll: Bool = false
  ) { ... }

  public static let cellOnly = Self(precision: .cell)
}
```

```swift
// Sources/Core/Pointer/PointerPrecisionPolicy.swift

public enum PointerPrecisionPolicy: Equatable, Hashable, Sendable {
  case cellOnly
  case subCellWhenKnown
  case forceTerminalPixels
}
```

### Migration Steps

1. Add the new types. They reference `Point`/`CellPoint`/`CellPixelMetrics` from Phase 1, so this PR depends on Phase 1 having merged.
2. Migrate `MouseEvent`:
   ```swift
   public struct MouseEvent: Equatable, Sendable {
     public var kind: Kind
     public var location: PointerLocation       // was: Point
     public var modifiers: Modifiers
   }
   ```
3. Update the SGR parser at `InputReader.swift:515–518`. The current code produces an integer cell:
   ```swift
   // BEFORE
   let location = Point(x: max(0, encodedX - 1), y: max(0, encodedY - 1))
   ```
   The Phase 2 form produces a `PointerLocation`:
   ```swift
   // AFTER
   let cell = CellPoint(x: max(0, encodedX - 1), y: max(0, encodedY - 1))
   let location: PointerLocation = .cellFallback(cell)
   ```
   Phase 7 will branch on the active mouse coordinate mode (cells vs pixels) and produce `.subCell(source: .terminalPixels, ...)` for SGR-1016. Phase 2 only handles the cell path.
4. Migrate `LocalPointerEvent` (`LocalPointerHandlerRegistry.swift:20–48`):
   ```swift
   package struct LocalPointerEvent: Equatable, Sendable {
     package var kind: Kind
     package var location: PointerLocation       // was: Point
     package var targetRect: CellRect            // was: Rect (now CellRect — layout)
     // ...
   }
   ```
5. Migrate `RunLoop+PointerHandling.swift` handlers. Hit testing operates on `event.location.cell`; recognizers receive the full `PointerLocation`.
6. Update coalescing in `InputReader.swift` (`isCoalescible`, `merged(with:)`):
   - `merged(.moved(loc1), .moved(loc2)) → .moved(loc2)` — the *latest* `PointerLocation` wins (preserves precision and rawPixel).
   - `merged(.scrolled(...), .scrolled(...))` — sums deltas; preserves the first or last location (document the choice; pin a test).
   - Importantly, *do not* coalesce events with different `PointerLocation.precision` values silently — a precision change means the input source changed (e.g., the runtime re-probed and 1016 just became active). The coalescer should flush the buffered event and start fresh.
7. Add `EnvironmentValues.pointerInputCapabilities`. Default value `.cellOnly`. Hosts override.
8. Update `GeometryProxy` to carry `pointerInputCapabilities` from the environment.

### Tests

New tests:

- `PointerLocationTests`:
  - `cellFallback(.zero).location == Point(x: 0.5, y: 0.5)`
  - `cellFallback(.zero).cell == CellPoint(x: 0, y: 0)`
  - `cellFallback(.zero).precision == .cell`
  - `subCell(location: Point(x: 2.7, y: 1.2), source: .terminalPixels, metrics: ...)` produces matching `cell == CellPoint(x: 2, y: 1)`.
  - `Equatable`, `Hashable`, `Sendable` (compile-only check via `_isSendable`).

Migrated tests (existing):

- `Tests/TerminalUITests/InputParserModifierTests.swift` — assert that 1006 mouse events still produce `.cell` precision and the same containing cell as before.
- `Tests/TerminalUITests/PointerEventTimestampTests.swift` — should be largely unchanged.
- `Tests/TerminalUITests/GestureRunLoopDispatchTests.swift` — events delivered to recognizers carry `PointerLocation`.
- `Tests/TerminalUITests/InjectedTerminalInputReaderTests.swift` — synthetic event construction now uses `PointerLocation`.
- `Tests/TerminalUITests/InputReaderControlMessageTests.swift` — coalescing tests for `PointerLocation` merging.

Per project memory (`feedback_input_reader_timing.md`): the InputReader has a dispatch-source state. Pin invariants synchronously by extracting the state into a testable type if not already done. Phase 2's coalescing changes are exactly the kind of place where wall-clock testing would be wrong.

### Acceptance Criteria

- All existing tests pass with the new types. Behavior on cell-only input is preserved (the integer cell of the new `PointerLocation` matches the old integer `Point`).
- `MouseEvent.location.cell` matches `MouseEvent.location` in the pre-Phase-2 form (modulo Int → CellPoint type wrap).
- `MouseEvent.location.location` (the new fractional Point) is at the *center* of the cell for cell-only input, per the proposal's center-fallback decision.
- `PointerInputCapabilities.cellOnly` is the default everywhere; hosts override in Phase 4.
- Coalescing with mixed precision flushes correctly (test pins this).

### Risks

- **Hit-testing semantics drift.** The pre-Phase-2 `Rect.contains(Point)` operated on integer cells. Post-Phase-2, `Rect` is `Double` and `CellRect` is integer. Hit testing now uses `event.location.cell` (a `CellPoint`) against `targetRect: CellRect`, which is unchanged in semantics. Mitigation: pin a hit-testing test that exercises every gesture's hit path with both center-fallback and integer-corner inputs.
- **Coalescing precision mixing.** Phase 7 will produce `.subCell` events; if Phase 2 doesn't handle precision-change-during-coalesce now, Phase 7 will surface it as a regression. Mitigation: the precision-change flush rule above.
- **Memory cost.** `PointerLocation` is wider than `Point`. Mouse-heavy tests may need slight memory headroom adjustments. Mitigation: profile if test runtime regresses by >5%.

---

## §4 — Phase 3: Gesture Migration

### Objective

Migrate every gesture's public `Value` type to expose a continuous `Point` location plus a `PointerLocation` provenance side-field. Convert distance/velocity/predicted-end fields to `Double`. Surface drag-sample paths via `PointerPath`.

### Files To Modify

- `Sources/View/Gestures/DragGesture.swift` — `Value`, `DragGestureRecognizer`, `minimumDistance: Int → Double`. Lines 21–58 (Value), 88–256 (recognizer).
- `Sources/View/Gestures/SpatialTapGesture.swift` — `Value.location: Point` (continuous), add `pointer: PointerLocation`.
- `Sources/View/Gestures/TapGesture.swift` — keep value-less, but movement-cancellation distance becomes `Double` internally.
- `Sources/View/Gestures/LongPressGesture.swift` — `maximumDistance: Int → Double`.
- `Sources/View/Gestures/Gesture.swift` — protocol stays.
- `Sources/View/Gestures/CoordinateSpace.swift` — `resolve(terminalPoint: Point, targetRect: CellRect) -> Point` (note the rect type change).
- `Sources/View/Gestures/GestureModifiers.swift` — `OnChangedDecorator`/`OnEndedDecorator` (lines ~40–192) signatures stay the same parametrically.
- `Sources/Core/GestureRecognizer.swift` — protocol stays; `targetRect: CellRect`.

### Files To Add

- `Sources/View/Gestures/PointerPath.swift` (`PointerPath` collection with `Sample` element type).
- `Tests/TerminalUITests/Gestures/PointerPathTests.swift`.

### New Type Signatures

```swift
// Sources/View/Gestures/PointerPath.swift

public struct PointerPath: Equatable, Hashable, Sendable, RandomAccessCollection {
  public struct Sample: Equatable, Hashable, Sendable {
    public var location: Point
    public var time: MonotonicInstant
    public var pointer: PointerLocation
  }

  private var samples: [Sample]

  public typealias Element = Sample
  public typealias Index = Int
  public var startIndex: Int { samples.startIndex }
  public var endIndex: Int { samples.endIndex }
  public subscript(position: Int) -> Sample { samples[position] }
  public func index(after i: Int) -> Int { i + 1 }

  package mutating func append(_ sample: Sample) { samples.append(sample) }
  // ... bounded-capacity helpers (see Open Questions §11)
}
```

```swift
// Updated DragGesture.Value

public struct Value: Equatable, Sendable {
  public var time: MonotonicInstant
  public var location: Point                    // was Point(Int) — now continuous
  public var startLocation: Point
  public var translation: Vector                // was Size(Int) — now Vector(Double)
  public var velocity: Vector                   // was Size(Int) cells/sec — now Double
  public var predictedEndLocation: Point
  public var predictedEndTranslation: Vector
  public var pointer: PointerLocation
  public var path: PointerPath
}

public struct DragGesture: Gesture {
  public typealias Body = Never
  public let minimumDistance: Double            // was Int
  public let coordinateSpace: CoordinateSpace
  public init(minimumDistance: Double = 0, coordinateSpace: CoordinateSpace = .local) { ... }
}
```

```swift
// Updated SpatialTapGesture.Value

public struct Value: Equatable, Sendable {
  public var location: Point
  public var pointer: PointerLocation
}
```

```swift
// Updated CoordinateSpace.resolve

extension CoordinateSpace {
  public func resolve(terminalPoint: Point, targetRect: CellRect) -> Point {
    switch kind {
    case .local:
      return Point(
        x: terminalPoint.x - Double(targetRect.origin.x),
        y: terminalPoint.y - Double(targetRect.origin.y)
      )
    case .global:
      return terminalPoint
    case .named(let name):
      // Phase 8 implements named spaces. Until then, keep trapping.
      fatalError("CoordinateSpace.named is not yet implemented (Phase 8): \(name)")
    }
  }
}
```

### Migration Steps

1. Add `PointerPath`. Wire it into `DragGestureRecognizer`'s existing `samples: [Sample]` array (line 102) — that buffer becomes `PointerPath` directly.
2. Update `DragGesture.Value`. Velocity/predicted-end math becomes `Double` arithmetic:
   ```swift
   private func computeVelocity(now: MonotonicInstant) -> Vector {
     guard samples.count >= 2 else { return .zero }
     let last = samples[samples.count - 1]
     // ... existing window-finding logic
     let dt = seconds(from: reference.time, to: last.time)
     guard dt > 0 else { return .zero }
     return Vector(
       dx: (last.location.x - reference.location.x) / dt,
       dy: (last.location.y - reference.location.y) / dt
     )
   }
   ```
   Note: the existing `Int(Double(...))` truncation goes away. Drag values previously truncated to integers — now they're real doubles.
3. Update `SpatialTapGesture.Value.location: Point → Point` (the storage type is the same name; its semantics are now continuous).
4. Update `CoordinateSpace.resolve` to accept `CellRect` and return `Point`. Note the type-asymmetry (Double minus Int): use explicit `Double(targetRect.origin.x)`.
5. Update `LongPressGesture.maximumDistance: Int → Double`.
6. The recognizer's `handle(event: LocalPointerEvent)` reads `event.location.location` (the continuous `Point` inside the `PointerLocation`). Hit testing happens upstream against `event.location.cell`.
7. Update `GestureViewModifier.swift` — the `coordinateSpace.resolve` call site at `DragGesture.swift:163–174` and similar spots.
8. Migrate all gesture tests. The bulk of churn lives in `Tests/TerminalUITests/`:
   - `DragGestureTests.swift`
   - `SpatialTapGestureTests.swift`
   - `TapGestureTests.swift`
   - `LongPressGestureTests.swift`
   - `GestureIntegrationTests.swift`
   - `GestureRunLoopDispatchTests.swift`
   - `CaptureOnPressTests.swift`

### Tests

New tests:

- `PointerPathTests`:
  - empty path is empty collection
  - append `n` samples, iterate, indices ok
  - bounded-capacity rule (see §11 open question)
- `DragGestureTests`:
  - drag through center-fallback locations behaves as before (cell-grained values)
  - drag with synthetic sub-cell input produces fractional translation/velocity
  - `path` contains all samples received during the drag
  - `velocity` is correctly Double-valued (no integer truncation regression)
- `CoordinateSpaceTests`:
  - `.local` resolution preserves fractional coordinates
  - integer `targetRect.origin` subtracted correctly
  - `.global` returns the terminalPoint unchanged

Migrated tests:

- All gesture tests need `Value` field type updates. Where the test asserts `value.location.x == 5`, it now asserts `value.location.x == 5.5` (cell center) or constructs a synthetic `PointerLocation` with explicit fractional coordinates.

### Acceptance Criteria

- All gesture tests pass with the new types.
- Drag through cell-only input produces values whose `.cell == oldPointValue` (proves backward-equivalent semantics under center-fallback).
- Drag through synthetic sub-cell input produces values where `.location` retains fractional precision and `.path.last?.location` matches.
- `LongPressGesture.maximumDistance: 0.5` correctly cancels a press that drifted half a cell.
- `value.translation` and `value.velocity` are `Vector` (Double) and never truncate to integers.

### Risks

- **Velocity behavior change.** Pre-Phase-3, velocity truncated to `Int` cells/sec, so motions slower than 1 cell/sec produced zero velocity. Post-Phase-3, all velocity values are real. Consumers that depended on the truncation (e.g., scroll views that ignored "jitter" by checking `velocity == .zero`) will see different behavior. Mitigation: search for `velocity == .zero` and `velocity.width == 0` patterns; either preserve the truncation as a separate threshold concept or document the change.
- **Equatable semantics on Double-typed values.** `DragGesture.Value` is `Equatable`. `Double` equality is exact-bitwise, so a re-rendered drag value that internally computed velocity slightly differently will not compare equal. Most use sites compare for non-equality (to detect change), so this is fine. Mitigation: review any test that uses `XCTAssertEqual` on `DragGesture.Value` with floating-point sensitivity.
- **PointerPath unbounded growth.** Long drags accumulate samples. Mitigation: see Open Questions §11 — decide on bounded capacity (count / time-window / byte-budget). Default suggestion: cap at 256 samples or 5 seconds, whichever first.

---

## §6 — Phase 5: Canvas Redesign

### Objective

Replace the hardcoded Braille 2×4 subpixel coordinate space with a cell-space (`Point`, Double) `CanvasContext` parameterized by a `CanvasGrid` that encapsulates the rasterization style. Eliminate the consumer-side `cellX * 2 + 1` arithmetic. Subsume `CanvasPixelGridDrawing` as a `.fullCell` / `.verticalHalfBlock` grid choice.

### Files To Add

- `Sources/Core/Canvas/CanvasGrid.swift` — `CanvasGrid`, `CanvasGrid.Style`, subdivision helpers
- `Sources/Core/Canvas/CanvasGridRasterizer.swift` — internal rasterizer registry (Braille / octant / sextant / quadrant / halfBlock / fullCell / pixelExact — the last as a stub if not first-impl)
- `Sources/Core/Canvas/OctantCanvas.swift` — analogous to BrailleCanvas, 2×4 octant glyph table
- `Sources/Core/Canvas/SextantCanvas.swift` — 2×3
- `Sources/Core/Canvas/QuadrantCanvas.swift` — 2×2
- `Sources/Core/Canvas/HalfBlockCanvas.swift` — 1×2 vertical (subsumes the existing half-block path)
- `Tests/CoreTests/Canvas/CanvasGridTests.swift`
- `Tests/CoreTests/Canvas/OctantCanvasTests.swift`
- `Tests/CoreTests/Canvas/QuadrantCanvasTests.swift`
- `Tests/CoreTests/Canvas/SextantCanvasTests.swift`

### Files To Modify

- `Sources/View/Canvas.swift` — add `Canvas(grid:_:)` initializer (protocol form); add `Canvas(grid:_:_)` closure form
- `Sources/Core/CanvasDrawing.swift` — `CanvasContext` becomes cell-space and grid-aware (lines 204–449). All drawing primitives switch to `Point`-typed parameters.
- `Sources/Core/BrailleCanvas.swift` — keep Braille rasterization, but expose it through the unified `CanvasGridRasterizer` interface
- `Sources/Core/Rasterizer.swift` — `paintCanvasDrawing` (lines 988–1080) constructs a `CanvasContext` with the chosen grid and routes to the right rasterizer
- `Sources/Core/RenderTreeAndSemanticsTypes.swift` — `CanvasPayload` carries `grid: CanvasGrid`
- `Examples/canvas/Sources/CanvasDemoViews/CanvasDemoView.swift` — drag-painting code at lines 198–215, 405, 464, 485–497 — eliminate `subpixelPoint(forLocalCell:)` helper, draw directly with `Point` (Double)
- `Examples/gifeditor/Sources/GIFEditorUI/CanvasView.swift` — same migration

### New Type Signatures

```swift
// Sources/Core/Canvas/CanvasGrid.swift

public struct CanvasGrid: Equatable, Hashable, Sendable {
  public enum Style: Equatable, Hashable, Sendable {
    case braille          // 2×4 Unicode Braille (U+2800)
    case octant           // 2×4 Unicode Octants (U+1FB00..)
    case sextant          // 2×3 Unicode Legacy Computing sextants (U+1FB00 range)
    case quadrant         // 2×2 quadrant block elements (U+2596..)
    case verticalHalfBlock   // 1×2 (▀ ▄ █)
    case horizontalHalfBlock // 2×1 (▌ ▐ █)
    case fullCell         // 1×1 (each cell is one pixel; uses background fill)
    case pixelExact       // honest pixels via Kitty/iTerm graphics protocol — not first-impl
  }

  public let style: Style

  public var subdivisionsX: Int {
    switch style {
    case .braille, .octant, .quadrant, .verticalHalfBlock: return 2
    case .sextant: return 2
    case .horizontalHalfBlock: return 2
    case .fullCell: return 1
    case .pixelExact: return 0   // sentinel: dynamic based on cellPixelMetrics
    }
  }

  public var subdivisionsY: Int {
    switch style {
    case .braille, .octant: return 4
    case .sextant: return 3
    case .quadrant, .horizontalHalfBlock, .verticalHalfBlock: return 2
    case .fullCell: return 1
    case .pixelExact: return 0
    }
  }

  public static let braille = Self(style: .braille)
  public static let octant = Self(style: .octant)
  public static let sextant = Self(style: .sextant)
  public static let quadrant = Self(style: .quadrant)
  public static let verticalHalfBlock = Self(style: .verticalHalfBlock)
  public static let horizontalHalfBlock = Self(style: .horizontalHalfBlock)
  public static let fullCell = Self(style: .fullCell)
  public static let pixelExact = Self(style: .pixelExact)
}
```

```swift
// Sources/View/Canvas.swift — both initializers

public struct Canvas<Drawing: CanvasDrawing>: View, ResolvableView {
  public let drawing: Drawing
  public let grid: CanvasGrid

  public init(grid: CanvasGrid = .braille, _ drawing: Drawing) {
    self.drawing = drawing
    self.grid = grid
  }
}

extension Canvas where Drawing == ClosureCanvasDrawing {
  /// SwiftUI-idiomatic closure form. Internally wraps the closure in an
  /// equatable-by-identity drawing.
  public init(
    grid: CanvasGrid = .braille,
    _ draw: @escaping @Sendable (inout CanvasContext) -> Void
  ) {
    self.drawing = ClosureCanvasDrawing(id: UUID(), draw: draw)
    self.grid = grid
  }
}

// Internal type that wraps a closure as an Equatable CanvasDrawing.
// Equatability is by `id`, not by closure identity (Swift can't compare closures).
public struct ClosureCanvasDrawing: CanvasDrawing, Equatable {
  let id: UUID
  let draw: @Sendable (inout CanvasContext) -> Void

  public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
  public func draw(into context: inout CanvasContext) { draw(&context) }
}
```

```swift
// Sources/Core/CanvasDrawing.swift — new CanvasContext

public struct CanvasContext: Sendable {
  public let size: CellSize           // frame extent in cells
  public let grid: CanvasGrid         // chosen rasterization grid
  public var foreground: Color
  public var background: Color?

  // All primitives in fractional cell space.
  public mutating func setPixel(at: Point)
  public mutating func setPixel(at: Point, foreground: Color, background: Color? = nil)
  public mutating func clearPixel(at: Point)
  public mutating func line(from: Point, to: Point)
  public mutating func strokeRect(_ rect: Rect)
  public mutating func fillRect(_ rect: Rect)
  public mutating func strokeCircle(center: Point, radius: Double)
  public mutating func fillCircle(center: Point, radius: Double)
  public mutating func strokeEllipse(center: Point, radii: Vector)
  public mutating func fillEllipse(center: Point, radii: Vector)

  // Whole-cell writes — unchanged in semantics.
  public mutating func setCell(_ cell: CanvasCell, at: CellPoint)
  public mutating func fillCell(_ color: Color, at: CellPoint)
  public mutating func clearCell(at: CellPoint)

  // Helpers for callers who want grid-aligned discretization explicitly.
  public func gridPoint(for location: Point) -> (gridX: Int, gridY: Int)
  public func gridPoint(for pointer: PointerLocation) -> (gridX: Int, gridY: Int)

  // Internal storage — the rasterizer reads these after draw() returns.
  package var braille: BrailleCanvas?     // populated only when grid == .braille
  package var octant: OctantCanvas?       // populated only when grid == .octant
  // ... or single internal `gridState: any CanvasGridState` polymorphic field
  package var brailleCellStyles: [[ResolvedTextStyle?]]
  package var directCells: [[CanvasCell?]]
}
```

### Migration Steps

1. Land Phase 1–3 first. Canvas's primitive-parameter changes only become natural once `Point` is `Double`.
2. Add `CanvasGrid` and the grid rasterizer scaffolding. The internal representation can be a polymorphic state (`any CanvasGridState`) or an enum of state cases. The polymorphic form is more extensible (e.g., adding `pixelExact` later); the enum form is faster (no existential dispatch). Recommendation: enum of cases, with each case holding the appropriate canvas state struct.
3. Migrate `BrailleCanvas` to expose its rasterization through a common `CanvasGridState` shape. Keep its existing public API (called by tests) intact.
4. Implement `OctantCanvas`, `SextantCanvas`, `QuadrantCanvas`, `HalfBlockCanvas`, `FullCellCanvas` as parallel structs with the same shape. Each provides `setPixel(gridX:gridY:)` and a `cells -> [[(glyph, style)]]` projection for the rasterizer.
5. Migrate `CanvasContext`. The existing primitives are renamed to take `Point` instead of `(x: Int, y: Int)`. The rasterizer routes the call to the active grid state:
   ```swift
   public mutating func setPixel(at: Point) {
     let gridX = Int((at.x * Double(grid.subdivisionsX)).rounded(.down))
     let gridY = Int((at.y * Double(grid.subdivisionsY)).rounded(.down))
     // route to active grid state
     switch gridStorage {
     case .braille(var c): c.setPixel(x: gridX, y: gridY); gridStorage = .braille(c)
     case .octant(var c): c.setPixel(x: gridX, y: gridY); gridStorage = .octant(c)
     // ...
     }
   }
   ```
6. Implement `Canvas(grid:_:)` (protocol form) and `Canvas(grid:_:)` (closure form). Note that the closure form's drawing is `Equatable` by injected `UUID`, not by closure identity.
7. Migrate `Rasterizer.paintCanvasDrawing` (Rasterizer.swift:988–1080). Construct the right `CanvasContext` with the right grid state, run the drawing, project the resulting cells into the cell raster.
8. Subsume `CanvasPixelGridDrawing` (CanvasDrawing.swift:84–188). The same logic moves into `Canvas(grid: .fullCell)` and `Canvas(grid: .verticalHalfBlock)`. Keep `CanvasPixelGridDrawing` as a deprecated alias for one PR cycle if desired (then delete pre-release).
9. Migrate `Examples/canvas`. The `subpixelPoint(forLocalCell:)` helper at `CanvasDemoView.swift:198–215` is deleted. The drag-painting code becomes:
   ```swift
   private func applyDragChange(_ value: DragGesture.Value) {
     let end = value.location  // already a Point in cell space
     document.apply(tool, from: lastDragPoint ?? value.startLocation, to: end)
     lastDragPoint = end
   }
   ```
   The `CanvasSketchPoint` internal type (the document's grid coordinate) can be removed or refactored to operate on `Point`.
10. Migrate `Examples/gifeditor` similarly.
11. `pixelExact`: in the first-impl, throw a clear error or no-op if a consumer tries to use it. Real implementation requires graphics-protocol probing (DECRQM for Kitty graphics, iTerm2 image protocol detection). Defer to a follow-up PR.

### Tests

New tests:

- `CanvasGridTests`: subdivisionsX/Y values for each style; `pixelExact.subdivisionsX == 0` (sentinel).
- `OctantCanvasTests`, `QuadrantCanvasTests`, `SextantCanvasTests`: parallel to `BrailleCanvasTests` — each style produces the right glyph for known pixel patterns.
- `CanvasContextGridRoutingTests`: setPixel at `Point(0.0, 0.0)` on a Braille grid sets braille subpixel `(0, 0)`; `Point(0.5, 0.5)` sets sub-cell `(1, 2)`; `Point(0.99, 0.99)` rounds down to `(1, 3)`.
- `CanvasClosureFormTests`: closure form produces the same output as protocol form for an equivalent drawing.

Migrated tests:

- `Tests/CoreTests/BrailleCanvasTests.swift` — remains the same; underlying engine unchanged.
- `Tests/TerminalUITests/CanvasViewTests.swift` — Canvas integration tests; need `grid:` parameter added to constructors.
- `Examples/canvas/Tests/CanvasDemoViewsTests/CanvasDemoViewTests.swift` — drag-painting fixture changes (now produces sub-cell motion within a single cell when input is sub-cell).
- `Examples/gifeditor/Tests/GIFEditorUITests/CanvasViewTests.swift` — similar.
- `Examples/layouts/Tests/LayoutsTests/ShapesCanvas/` — shape canvas tests.

### Acceptance Criteria

- All Canvas tests pass with the new types.
- A drawing that today uses `setPixel(x: 5, y: 13)` (Braille subpixel) compiles after migration via `setPixel(at: Point(x: 2.5, y: 3.25))` (cell-space, equivalent location). Both produce the same Braille bit set.
- A drag inside a single cell on sub-cell-precision input produces motion across multiple Braille subpixels (the demo test pins this; it was impossible before).
- The closure form renders identically to the protocol form for an equivalent drawing.
- `CanvasPixelGridDrawing` is removed (or deprecated for one cycle); `Canvas(grid: .fullCell, drawing)` and `Canvas(grid: .verticalHalfBlock, drawing)` work as replacements.

### Risks

- **Coordinate-space confusion in migrated examples.** The examples currently think in "Braille subpixels" (Int). The migration moves them to "cells" (Double). A drawing that currently calls `setPixel(x: 5, y: 13)` for a 40×8 cell canvas (so subpixel max is `(80, 32)`) now calls `setPixel(at: Point(x: 2.5, y: 3.25))`. This is a real arithmetic change, not a rename. Mitigation: each example's drag-painting tests should be re-baselined manually, with a brief PR comment explaining the new coordinate semantics.
- **`pixelExact` half-implementation.** Shipping the type without the implementation invites surprise. Mitigation: throw a recoverable error in the rasterizer when `pixelExact` is used and the host doesn't support graphics protocol; document this behavior; cover it with a test.
- **Closure form Equatable pitfall.** Two `Canvas(grid: .braille) { ctx in ... }` calls produce drawings that are *not* equal (different UUIDs), so re-render dedup is lost. This is intentional but can surprise. Mitigation: document explicitly. Recommend protocol form for static drawings, closure form for ad-hoc.
- **`Sources/Core/Canvas/` directory creation.** The repo doesn't currently have a `Canvas/` subdirectory. Decide on the layout (subdirectory vs flat); `prek` may need updating if file paths matter to its config.

---

## §11 — Open Questions For Implementer

These are decisions that surfaced during planning but are not yet resolved. Each implementer decision should be captured in a PR description.

1. **PointerPath bounded capacity.** Long drags (selection, freehand drawing) accumulate samples. Should the cap be by count (e.g., 256), by time window (e.g., last 5 seconds), or by byte budget? Recommendation: count-based with a default of 1024, configurable on the gesture (`DragGesture(minimumDistance: 0, maxPathSamples: 1024)`).

2. **PixelImage.pixelSize.** Currently `Size` (will become `CellSize` in Phase 1?). The field represents pixel-grid dimensions of an image asset, not cells. Should it become a new `PixelSize` (Int) type, or stay as a `CellSize` (which is a name lie), or migrate to `(Int, Int)` tuple? Recommendation: introduce a `PixelGridSize` (`Int`) sibling type for image-pixel-grid dimensions; keep `PixelPoint` (`Double`) for fractional pixel positions.

3. **Closure-form Canvas Equatable identity.** Two closure-form `Canvas(grid: .braille) { ctx in ... }` declarations are not equal (UUID-keyed). For animation/re-render dedup, the consumer who wants stable identity should use the protocol form. Should the framework warn at compile time? Probably not — Swift type system has no clean way. Document and move on.

4. **Cell-derived fallback location.** Recommendation in this plan: cell *center* `(x + 0.5, y + 0.5)`. The proposal also discusses cell origin `(x, y)` as an alternative. Confirm center; document; pin a test.

5. **Coalescing under precision change.** The current proposal says: when two adjacent events have different `PointerPrecision` values (e.g., `.cell` then `.subCell` after a re-probe), the coalescer must flush the buffered event and start fresh. Confirm this rule and pin a test.

6. **`forceTerminalPixels` semantics in unknown terminals.** If the user sets `PointerPrecisionPolicy.forceTerminalPixels` and the terminal silently ignores `CSI ? 1016 h`, the parser still receives 1006 cell coordinates but interprets them as pixels. This is a foot-gun. Should `forceTerminalPixels` only take effect after a positive DECRQM probe, or should it be unconditional? Recommendation: unconditional but log a runtime warning when no probe has confirmed support, and document the foot-gun in DocC.

7. **Equatable on DragGesture.Value with Double fields.** `Double` equality is exact-bitwise. Two recomputed values may not compare equal even when semantically the same. Should `Value` use a tolerance-based equality? Recommendation: keep exact Equatable. Consumers comparing for "no change" should compare specific projections (e.g., `cell` integer fields), not the whole Value.

8. **`Vector` vs `Size` for translation/velocity.** This plan uses `Vector` (dx/dy, signed). The existing code uses `Size` (width/height). Is there ever a case where translation should be unsigned? Recommendation: signed `Vector` is the only sensible choice for translation/velocity. `Size` stays for measurement (always non-negative).

9. **GUI transport break for web host.** The current colon-delimited message format (`mouse:down:2:0:primary:0:0:0`) is integer cell. The Phase 4 change introduces fractional values. The proposal favors a clean break (decimal cell coordinates: `mouse:down:2.42:0.61:primary:0:0:0`). Codex's plan section adopts this. Confirm pre-release transport break is acceptable; if not, fall back to appended-fields format.

10. **`pixelExact` Canvas first-impl scope.** Should the first implementation include any rasterizer support for `pixelExact`, even a stub that emits a "graphics protocol not supported" error? Recommendation: include the type and a stub rasterizer that throws a documented error; defer real implementation to a separate phase tracked as follow-up.

11. **Named coordinate space implementation timing.** Phase 8 includes named coordinate spaces. Should it land with Phase 3 (gesture migration) instead, since named spaces compose naturally with the new continuous `Point`? Recommendation: keep in Phase 8 to avoid bloating Phase 3, but treat as low-risk and parallelizable.

12. **Hover any-event tracking lifetime.** DECSET 1003 is bandwidth-heavy. Current proposal: enable on first hover subscriber, disable on last. Should we add a debounce (don't disable for 5 seconds in case another subscriber appears soon)? Recommendation: no debounce in v1; profile in production and add later if needed.

13. **`@Environment(\.pointerInputCapabilities)` granularity.** Per-window or global? Codex's plan section assumes global. Confirm. Multi-window terminal apps with mixed sources are rare today.

14. **DEC 2048 in-band reports.** Phase 7 mentions DEC 2048 as a follow-up if probing isn't reliable without it. Should it be in scope for the first 1016 PR or split into Phase 7.5? Recommendation: in scope for Phase 7 — without reliable cell-pixel metrics, 1016 is unsafe.
