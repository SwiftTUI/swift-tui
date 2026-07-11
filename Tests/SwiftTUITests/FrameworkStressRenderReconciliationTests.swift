import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct FrameworkStressRenderReconciliationTests {}

private func renderStressText(_ snapshot: RenderSnapshot) -> String {
  snapshot.rasterSurface.lines.joined(separator: "\n")
}

// MARK: - Attempt 001: Input-keyed canvas redraw

extension FrameworkStressRenderReconciliationTests {
  @Test("stress render reconciliation 001 keyed canvas redraws its current marker")
  func renderReconciliation001KeyedCanvasRedrawsCurrentMarker() {
    // Hypothesis: Canvas disables retained phase extraction, but an enclosing retained frame
    // can still substitute an earlier DrawNode when the input-keyed payload changes in place.
    struct Root: View {
      let markerColumn: Int

      var body: some View {
        Canvas(markerColumn) { context, markerColumn in
          context.setCell(
            at: CellPoint(x: markerColumn, y: 0),
            character: "X",
            foreground: .green
          )
        }
        .frame(width: 5, height: 1)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("RenderReconciliation001")

    for generation in 0..<16 {
      let expectedColumn = generation % 5
      let frame = renderer.render(
        Root(markerColumn: expectedColumn),
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        )
      )
      for column in 0..<5 {
        #expect(
          frame.rasterSurface.cells[0][column].character
            == (column == expectedColumn ? "X" : " ")
        )
      }
    }
  }
}


// MARK: - Attempt 002: Recreated closure canvas capture

extension FrameworkStressRenderReconciliationTests {
  @Test("stress render reconciliation 002 closure canvas uses its current capture")
  func renderReconciliation002ClosureCanvasUsesCurrentCapture() {
    // Hypothesis: closure-backed Canvas payloads intentionally compare by storage identity, but
    // retained draw substitution may still replay the first closure after repeated reconstruction.
    struct Root: View {
      let generation: Int

      var body: some View {
        Canvas { context in
          context.setCell(
            at: CellPoint(x: generation % 4, y: 0),
            character: Character(String(generation % 10)),
            foreground: .blue
          )
        }
        .frame(width: 4, height: 1)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("RenderReconciliation002")

    for generation in 0..<16 {
      let frame = renderer.render(
        Root(generation: generation),
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        )
      )
      let expectedColumn = generation % 4
      #expect(
        frame.rasterSurface.cells[0][expectedColumn].character
          == Character(String(generation % 10))
      )
      #expect(
        frame.rasterSurface
          == DefaultRenderer().render(
            Root(generation: generation),
            context: .init(identity: rootIdentity)
          ).rasterSurface
      )
    }
  }
}


// MARK: - Attempt 003: Canvas grid churn

extension FrameworkStressRenderReconciliationTests {
  @Test("stress render reconciliation 003 canvas grid follows every current frame")
  func renderReconciliation003CanvasGridFollowsCurrentFrame() {
    // Hypothesis: retained draw state may key Canvas only by drawing equality and overlook a
    // changed packing grid, replaying Braille cells after the author switches to quadrant cells.
    struct Dot: CanvasDrawing, Equatable {
      func draw(into context: inout CanvasContext) {
        context.setPixel(at: Point(x: 0.25, y: 0.25))
        context.setPixel(at: Point(x: 0.75, y: 0.75))
      }
    }

    struct Root: View {
      let grid: CanvasGrid

      var body: some View {
        Canvas(Dot(), grid: grid)
          .frame(width: 2, height: 1)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("RenderReconciliation003")
    let grids: [CanvasGrid] = [.braille2x4, .quadrant2x2, .verticalHalfBlock]

    for generation in 0..<18 {
      let root = Root(grid: grids[generation % grids.count])
      let retained = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        )
      )
      let fresh = DefaultRenderer().render(root, context: .init(identity: rootIdentity))
      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.rasterSurface.cells[0][0].character != " ")
    }
  }
}


// MARK: - Attempt 004: Canvas geometry churn

extension FrameworkStressRenderReconciliationTests {
  @Test("stress render reconciliation 004 canvas context tracks oscillating geometry")
  func renderReconciliation004CanvasContextTracksOscillatingGeometry() {
    // Hypothesis: a retained Canvas DrawNode may invoke its drawing with the cached frame size
    // after the same identity revisits an earlier measurement-cache proposal.
    struct CurrentCorner: CanvasDrawing, Equatable {
      func draw(into context: inout CanvasContext) {
        context.setCell(
          at: CellPoint(x: max(0, context.size.width - 1), y: max(0, context.size.height - 1)),
          character: "C",
          foreground: .green
        )
      }
    }

    struct Root: View {
      let width: Int
      let height: Int

      var body: some View {
        Canvas(CurrentCorner())
          .frame(width: width, height: height)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("RenderReconciliation004")
    let sizes = [(2, 1), (7, 3), (3, 2), (6, 1), (2, 3)]

    for generation in 0..<20 {
      let size = sizes[generation % sizes.count]
      let frame = renderer.render(
        Root(width: size.0, height: size.1),
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        )
      )
      #expect(frame.rasterSurface.size == CellSize(width: size.0, height: size.1))
      #expect(frame.rasterSurface.cells[size.1 - 1][size.0 - 1].character == "C")
    }
  }
}


// MARK: - Attempt 005: Direct-cell Canvas style churn

extension FrameworkStressRenderReconciliationTests {
  @Test("stress render reconciliation 005 direct canvas cells keep current glyph and style")
  func renderReconciliation005DirectCanvasCellsKeepCurrentGlyphAndStyle() {
    // Hypothesis: direct-cell Canvas writes can retain a prior cell payload independently from
    // the Braille buffer, producing a current glyph with a stale foreground or background.
    struct StyledCell: CanvasDrawing, Equatable {
      let generation: Int

      func draw(into context: inout CanvasContext) {
        context.setCell(
          at: .zero,
          character: generation.isMultiple(of: 2) ? "A" : "B",
          foreground: generation.isMultiple(of: 3) ? .red : .green,
          background: generation.isMultiple(of: 2) ? .blue : .white
        )
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let rootIdentity = testIdentity("RenderReconciliation005")

    for generation in 0..<18 {
      let root = Canvas(StyledCell(generation: generation)).frame(width: 1, height: 1)
      let frame = renderer.render(
        root,
        context: .init(
          identity: rootIdentity,
          invalidatedIdentities: generation == 0 ? [] : [rootIdentity]
        )
      )
      let cell = frame.rasterSurface.cells[0][0]
      #expect(cell.character == (generation.isMultiple(of: 2) ? "A" : "B"))
      #expect(cell.style?.foregroundColor == (generation.isMultiple(of: 3) ? .red : .green))
      #expect(cell.style?.backgroundColor == (generation.isMultiple(of: 2) ? .blue : .white))
    }
  }
}

// MARK: - End
