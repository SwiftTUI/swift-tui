import SwiftTUICore
import Testing

@testable import SwiftTUIRuntime

@Suite
struct HostWireLinkTableTests {
  @Test("wire link indexes retain first-seen order across rows and gaps")
  func deterministicIndexes() {
    let table = model([
      [linked("b"), linked("b"), .empty, linked("a")],
      [linked("a"), linked("c"), linked("b"), .empty],
      [.empty, .empty, .empty, .empty],
    ]).linkTable()
    #expect(table.targets == ["b", "a", "c"])
    #expect(table.rows.map(\.y) == [0, 1])
    #expect(table.rows[0].runs.map(\.start) == [0, 3])
    #expect(table.rows[0].runs.map(\.span) == [2, 1])
    #expect(table.rows[0].runs.map(\.target) == [0, 1])
    #expect(table.rows[1].runs.map(\.target) == [1, 2, 0])
  }

  @Test("wide leads own their continuations and runs do not cross gaps")
  func wideCellCoverage() {
    let table = model([
      [
        RasterCell(character: "界", spanWidth: 2, hyperlink: "wide"),
        RasterCell(continuationLeadX: 0, hyperlink: "ignored"),
        linked("wide"), .empty, linked("wide"),
      ]
    ]).linkTable()
    #expect(table.targets == ["wide"])
    #expect(table.rows[0].runs.map(\.start) == [0, 4])
    #expect(table.rows[0].runs.map(\.span) == [3, 1])
  }

  @Test("empty and entirely unlinked surfaces emit no link table")
  func noLinks() {
    for cells in [[], [[RasterCell.empty, .empty]]] {
      let table = model(cells).linkTable()
      #expect(table.targets.isEmpty)
      #expect(table.rows.isEmpty)
    }
  }

  @Test("large linked documents reconstruct every cell's destination")
  func largeDocumentRoundTrip() {
    // 9,600 cells with 4,800 unique targets exercise the high-cardinality
    // document shape, including cross-row repeats, without a wall-clock gate.
    let width = 160
    let height = 60
    let cells = (0..<height).map { y in
      (0..<width).map { x in
        linked("https://example.test/document/\(((y * width + x) / 2) % 4_800)")
      }
    }
    let table = model(cells).linkTable()
    #expect(table.targets.count == 4_800)
    #expect(table.rows.count == height)
    var reconstructed = Array(
      repeating: [String?](repeating: nil, count: width), count: height
    )
    for row in table.rows {
      for run in row.runs {
        for x in run.start..<(run.start + run.span) {
          reconstructed[row.y][x] = table.targets[run.target]
        }
      }
    }
    #expect(reconstructed == cells.map { $0.map(\.hyperlink) })
  }

  private func linked(_ destination: String) -> RasterCell {
    RasterCell(character: "x", hyperlink: destination)
  }

  private func model(_ cells: [[RasterCell]]) -> HostWireFrameModel {
    HostWireFrameModel(
      surface: RasterSurface(
        size: CellSize(width: cells.first?.count ?? 0, height: cells.count), cells: cells
      ),
      sequence: nil,
      semanticSnapshot: nil,
      focusedIdentity: nil,
      damage: nil,
      preferredLayoutSize: nil
    )
  }
}
