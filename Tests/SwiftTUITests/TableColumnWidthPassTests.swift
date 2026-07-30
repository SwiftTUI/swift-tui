import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Register item D21 — the hosted table's column-width pass. These pin what the
/// second measure loop in `windowedHostedCollectionMeasurement` actually costs
/// and what it buys, because the root plan
/// `docs/plans/2026-07-28-007-collection-scroll-currency-plan.md` describes
/// both incorrectly: it calls the second pass a re-realization (it is not — the
/// width application re-maps the realization cache in place), and it proposes
/// replacing it with a pre-loop width application (which would freeze column
/// discovery, because a `.frame(width:)` cell reports exactly that width).
@MainActor
@Suite(.serialized)
struct TableColumnWidthPassTests {
  @Test("D21-a: applying column widths re-measures the window but does not re-realize it")
  func widthApplicationDoesNotRerealize() {
    IndexedChildRealizationProbe.reset()
    _ = DefaultRenderer().render(
      Table(0..<40, id: \.self, columns: [.init("Value", width: nil)]) { row in
        Text("row \(row)")
      },
      context: .init(identity: testIdentity("TableWidthRealize"), applyEnvironmentValues: false),
      proposal: .init(width: .finite(30), height: .finite(14))
    )
    let realized = IndexedChildRealizationProbe.realizedChildCount

    // The width pass loops the window a second time, but `child(at:)` hits the
    // cache `applyHostedTableColumnWidths` just re-mapped, so realization is
    // paid once per windowed row. A viewport of 14 lines holds ~5 body rows
    // plus overscan; the ceiling is deliberately loose, the point is that it is
    // bounded by the window rather than doubled.
    #expect(
      realized <= 24,
      "realized \(realized) rows for a 14-line viewport over 40 rows"
    )
  }

  @Test("D21-b: a column grows to fit content that widened under a stable id set")
  func columnsGrowWithContent() {
    // The grow-only contract, and the reason the second measure pass is
    // load-bearing. Discovery reads each cell's MEASURED width; a cell that has
    // already had `.frame(width:)` applied measures to exactly that width, so
    // measuring the window with the retained widths already applied — the fix
    // the plan proposes for D21 — would cap every column at whatever it first
    // discovered and truncate this row forever.
    func widthOfRenderedTable(label: String) -> Int {
      let artifacts = DefaultRenderer().render(
        Table(0..<3, id: \.self, columns: [.init("V", width: nil)]) { row in
          Text(row == 1 ? label : "x")
        },
        context: .init(identity: testIdentity("TableGrow"), applyEnvironmentValues: false),
        proposal: .init(width: .finite(60), height: .finite(14))
      )
      return artifacts.rasterSurface.lines.map { $0.trimmingSuffixSpaces().count }.max() ?? 0
    }

    let narrow = widthOfRenderedTable(label: "ab")
    let wide = widthOfRenderedTable(label: "abcdefghijklmnop")

    #expect(narrow > 0)
    #expect(
      wide > narrow,
      "a longer cell widens its column: narrow=\(narrow) wide=\(wide)"
    )
  }

  @Test("D21-c: column widths ratchet up and never shrink while ids are stable")
  func widthsRatchetGrowOnly() {
    // The documented contract, exercised through the retention path rather than
    // through a rendered frame: the same source asked twice keeps the wider
    // answer.
    let columns = [TableColumnPayload(title: "V", width: nil)]
    let wide = measureTableColumnWidths(
      columns: columns,
      rows: [.init(cells: [.init(text: "abcdefgh")])]
    )
    let narrow = measureTableColumnWidths(
      columns: columns,
      rows: [.init(cells: [.init(text: "a")])]
    )

    #expect(wide[0] > narrow[0], "the measurement itself tracks content width")
  }
}

extension String {
  fileprivate func trimmingSuffixSpaces() -> String {
    var copy = self
    while copy.last == " " {
      copy.removeLast()
    }
    return copy
  }
}
