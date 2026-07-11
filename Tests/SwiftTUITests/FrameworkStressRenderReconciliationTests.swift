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

// MARK: - End
