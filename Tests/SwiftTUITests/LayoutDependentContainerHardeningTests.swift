import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct LayoutDependentContainerHardeningTests {
  @Test("ScrollView re-realizes GeometryReader global frames after scroll offset changes")
  func scrollViewRealizesGeometryReaderGlobalFrameAfterOffsetChanges() {
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )
    let position = LockedBox(ScrollPosition.zero)

    func makeView() -> some View {
      ScrollView(
        .vertical,
        showsIndicators: false,
        position: Binding(
          get: { position.value },
          set: { position.value = $0 }
        )
      ) {
        VStack(alignment: .leading, spacing: 0) {
          Text("lead")
          GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            Text(
              "geo \(Int(frame.origin.x)),\(Int(frame.origin.y)) \(proxy.size.width)x\(proxy.size.height)"
            )
          }
          .frame(width: 20, height: 1, alignment: .topLeading)
          Text("tail")
        }
      }
      .frame(width: 20, height: 2, alignment: .topLeading)
    }

    let first = renderer.render(
      makeView(),
      context: .init(identity: testIdentity("ScrollGeometryRoot")),
      proposal: .init(width: 20, height: 2)
    )

    position.withLock {
      $0.scrollBy(y: 1)
    }

    let second = renderer.render(
      makeView(),
      context: .init(identity: testIdentity("ScrollGeometryRoot")),
      proposal: .init(width: 20, height: 2)
    )

    let firstRendered = first.rasterSurface.lines.joined(separator: "\n")
    let secondRendered = second.rasterSurface.lines.joined(separator: "\n")
    #expect(firstRendered.contains("geo 0,1 20x1"))
    #expect(secondRendered.contains("geo 0,0 20x1"))
    #expect(second.diagnostics.layoutDependentRealizations == 1)
    let geometryDiagnostics = second.diagnostics.geometryResolutionDiagnostics
    #expect(geometryDiagnostics.anchorResolutionMissCount == 0)
    #expect(geometryDiagnostics.missingNamedCoordinateSpaceCount == 0)
  }

  @Test("LazyVStack realizes visible indexed GeometryReader rows without off-screen rows")
  func lazyVStackRealizesVisibleGeometryReaderRowsWithoutOffscreenRows() {
    var realizedRows: [Int] = []

    let artifacts = DefaultRenderer().render(
      ScrollView(.vertical, showsIndicators: false) {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(0..<4) { row in
            GeometryReader { proxy in
              countedLazyStackGeometryText(
                "row \(row) \(proxy.size.width)x\(proxy.size.height)",
                row: row,
                realizedRows: &realizedRows
              )
            }
            .frame(width: 12, height: 1, alignment: .topLeading)
          }
        }
      }
      .frame(width: 12, height: 1, alignment: .topLeading),
      context: .init(identity: testIdentity("LazyGeometryRoot")),
      proposal: .init(width: 12, height: 1)
    )

    let rendered = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(realizedRows == [0])
    #expect(artifacts.diagnostics.layoutDependentRealizations == 1)
    #expect(rendered.contains("row 0 12x1"))
    #expect(!rendered.contains("row 1"))
    #expect(!rendered.contains("row 2"))
    #expect(!rendered.contains("row 3"))
  }
}

@MainActor
private func countedLazyStackGeometryText(
  _ text: String,
  row: Int,
  realizedRows: inout [Int]
) -> Text {
  realizedRows.append(row)
  return Text(text)
}
