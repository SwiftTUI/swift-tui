import Foundation
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

private func tableOutlineContainsInOrder(_ tokens: [String], in text: String) -> Bool {
  var cursor = text.startIndex
  for token in tokens {
    guard let range = text.range(of: token, range: cursor..<text.endIndex) else {
      return false
    }
    cursor = range.upperBound
  }
  return true
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

// MARK: - Attempt 002: table column cardinality churn

extension FrameworkStressTableOutlineTests {
  @Test("stress table outline 002 table column cardinality rebuilds cell mapping")
  func tableOutline002TableColumnCardinalityRebuildsCellMapping() {
    // Hypothesis: changing the number of columns can leave retained separators
    // or cell-to-column indices from the prior table payload.
    struct Root: View {
      let generation: Int

      var body: some View {
        Table(
          selection: .constant(1),
          columns: generation.isMultiple(of: 2)
            ? [.init("Only", width: 8)]
            : [
              .init("A", width: 6),
              .init("B", width: 7, alignment: .center),
              .init("C", width: 5, alignment: .trailing),
            ]
        ) {
          TableRow {
            Text("A-\(generation)")
            Text("B-\(generation)")
            Text("C-\(generation)")
          }
          .tag(1)
        }
        .frame(width: 34, height: 7, alignment: .topLeading)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("TableOutline002")
    for generation in 0..<18 {
      let root = Root(generation: generation)
      let retained = renderer.render(
        root,
        context: .init(
          identity: identity,
          invalidatedIdentities: generation == 0 ? [] : [identity]
        ),
        proposal: .init(width: 34, height: 7)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: identity),
        proposal: .init(width: 34, height: 7)
      )

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.resolvedTree.drawPayload == fresh.resolvedTree.drawPayload)
      #expect(tableOutlineText(retained).contains("A-\(generation)"))
      #expect(tableOutlineText(retained).contains("C-\(generation)") == !generation.isMultiple(of: 2))
    }
  }
}

// MARK: - Attempt 003: table header visibility churn

extension FrameworkStressTableOutlineTests {
  @Test("stress table outline 003 table header visibility leaves no stale row")
  func tableOutline003TableHeaderVisibilityLeavesNoStaleRow() {
    // Hypothesis: toggling the environment-driven header row can preserve its
    // old height or paint after the header payload becomes hidden.
    struct Root: View {
      let generation: Int

      var body: some View {
        Table(
          selection: .constant(1),
          columns: [.init("Header-\(generation)", width: 14)]
        ) {
          TableRow { Text("row-\(generation)") }.tag(1)
        }
        .tableHeaders(generation.isMultiple(of: 2) ? .visible : .hidden)
        .frame(width: 20, height: 7, alignment: .topLeading)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("TableOutline003")
    for generation in 0..<20 {
      let root = Root(generation: generation)
      let retained = renderer.render(
        root,
        context: .init(
          identity: identity,
          invalidatedIdentities: generation == 0 ? [] : [identity]
        ),
        proposal: .init(width: 20, height: 7)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: identity),
        proposal: .init(width: 20, height: 7)
      )
      let rendered = tableOutlineText(retained)

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.measuredTree.measuredSize == fresh.measuredTree.measuredSize)
      #expect(rendered.contains("Header-\(generation)") == generation.isMultiple(of: 2))
      #expect(rendered.contains("row-\(generation)"))
    }
  }
}

// MARK: - Attempt 004: table row reorder with live payloads

extension FrameworkStressTableOutlineTests {
  @Test("stress table outline 004 table row reorder keeps current cells and selection index")
  func tableOutline004TableRowReorderKeepsCurrentCellsAndSelectionIndex() {
    // Hypothesis: recursive table-row collapse can retain an old row index
    // after stable entities reorder while their cell payloads also change.
    struct Row: Identifiable {
      let id: Int
      let label: String
    }
    struct Root: View {
      let rows: [Row]

      var body: some View {
        Table(selection: .constant(2), columns: [.init("Rows", width: 14)]) {
          ForEach(rows) { row in
            TableRow { Text(row.label) }.tag(row.id)
          }
        }
        .frame(width: 20, height: 10, alignment: .topLeading)
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("TableOutline004")
    for generation in 0..<20 {
      let rows = [
        Row(id: 1, label: "A-\(generation)"),
        Row(id: 2, label: "B-\(generation)"),
        Row(id: 3, label: "C-\(generation)"),
      ]
      let ordered = generation.isMultiple(of: 2) ? rows : [rows[2], rows[0], rows[1]]
      let root = Root(rows: ordered)
      let retained = renderer.render(
        root,
        context: .init(
          identity: identity,
          invalidatedIdentities: generation == 0 ? [] : [identity]
        ),
        proposal: .init(width: 20, height: 10)
      )
      let fresh = DefaultRenderer().render(
        root,
        context: .init(identity: identity),
        proposal: .init(width: 20, height: 10)
      )
      let rendered = tableOutlineText(retained)

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(retained.resolvedTree.drawPayload == fresh.resolvedTree.drawPayload)
      #expect(tableOutlineContainsInOrder(ordered.map(\.label), in: rendered))
    }
  }
}
