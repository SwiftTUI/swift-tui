import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI table and outline stress behavior", .serialized)
struct FrameworkStressTableOutlineTests {}

private func tableOutlineText(_ snapshot: RenderSnapshot) -> String {
  snapshot.rasterSurface.lines.joined(separator: "\n")
}

// MARK: - Attempt 001: table column contract replacement

extension FrameworkStressTableOutlineTests {
  @Test("stress table outline 001 table columns replace every retained contract field")
  func tableOutline001TableColumnsReplaceEveryRetainedContractField() {
    // Hypothesis: Table's value-collapsed draw payload can retain an earlier
    // column title, width, order, or alignment after the live array changes.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("TableOutline001")

    for generation in 0..<20 {
      let root = TableOutline001Root(generation: generation)
      let retained = renderer.render(
        root,
        context: .init(
          identity: identity,
          invalidatedIdentities: generation == 0 ? [] : [identity]
        ),
        proposal: .init(width: 28, height: 7)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: identity),
        proposal: .init(width: 28, height: 7)
      )

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.resolvedTree.drawPayload == fresh.resolvedTree.drawPayload)
      #expect(tableOutlineText(retained).contains("N\(generation)"))
      #expect(tableOutlineText(retained).contains("V\(generation)"))
    }
  }
}

@MainActor
private struct TableOutline001Root: View {
  let generation: Int

  private var columns: [TableColumn] {
    if generation.isMultiple(of: 2) {
      return [
        .init("N\(generation)", width: 8, alignment: .leading, titleAlignment: .center),
        .init("V\(generation)", width: 5, alignment: .trailing, titleAlignment: .leading),
      ]
    }
    return [
      .init("V\(generation)", width: 6, alignment: .center, titleAlignment: .trailing),
      .init("N\(generation)", width: 7, alignment: .trailing, titleAlignment: .center),
    ]
  }

  var body: some View {
    Table(selection: .constant(1), columns: columns) {
      TableRow {
        Text("name-\(generation)")
        Text("value-\(generation)")
      }
      .tag(1)
    }
    .frame(width: 28, height: 7, alignment: .topLeading)
  }
}
