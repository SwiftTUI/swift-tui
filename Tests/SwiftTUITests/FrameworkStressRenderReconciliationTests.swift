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

// MARK: - End
