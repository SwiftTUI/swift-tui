import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// The table half of stage S3 of the scroll-currency program (root plan
/// `docs/plans/2026-07-28-007-collection-scroll-currency-plan.md`). Lists got a
/// height-aware layout product derived once at measure and carried to
/// placement, draw, and semantics; tables kept re-deriving their own and
/// accumulating a private `additionalYOffset`, which is exactly the register
/// item D19 convention drift lists no longer have.
@MainActor
@Suite(.serialized)
struct TableLayoutProductTests {
  @Test("T-36: a 2-line table row keeps its borders, content, and successors aligned")
  func tallRowsStayAligned() throws {
    let artifacts = DefaultRenderer().render(
      Table(0..<4, id: \.self, columns: [.init("Value", width: 8)]) { row in
        VStack(alignment: .leading, spacing: 0) {
          Text("«\(row)»a")
          Text("«\(row)»b")
        }
      },
      context: .init(identity: testIdentity("TallTableProduct"), applyEnvironmentValues: false),
      proposal: .init(width: .finite(24), height: .finite(20))
    )

    let lines = artifacts.rasterSurface.lines
    let surface = lines.joined(separator: "\n")
    for row in 0..<4 {
      guard let first = lines.firstIndex(where: { $0.contains("«\(row)»a") }) else {
        continue
      }
      let second = try #require(
        lines.firstIndex { $0.contains("«\(row)»b") },
        "row \(row)'s second line is missing from:\n\(surface)"
      )
      #expect(second == first + 1, "row \(row)'s two lines are adjacent:\n\(surface)")
    }

    // The rows that fit must not overlap: placement used to advance by the
    // measured height while draw painted every line one cell apart, so a row
    // after a tall one landed on cells the previous row already owned.
    let rowStarts = (0..<4).compactMap { row in
      lines.firstIndex { $0.contains("«\(row)»a") }
    }
    #expect(
      rowStarts == rowStarts.sorted() && Set(rowStarts).count == rowStarts.count,
      "rows are in order and disjoint:\n\(surface)"
    )
    for (previous, next) in zip(rowStarts, rowStarts.dropFirst()) {
      #expect(next >= previous + 2, "a 2-cell row is not overlapped by its successor")
    }
  }

  @Test(
    "T-36b: tall hosted table rows render across geometries",
    arguments: [
      (rowLines: 2, rows: 4, height: 20),
      (rowLines: 2, rows: 4, height: 8),
      (rowLines: 5, rows: 4, height: 20),
      (rowLines: 5, rows: 40, height: 12),
      (rowLines: 3, rows: 2, height: 6),
      (rowLines: 1, rows: 4, height: 20),
    ]
  )
  func tallRowGeometriesRender(geometry: (rowLines: Int, rows: Int, height: Int)) {
    // Every one of these crashed the frame before the product was carried:
    // placement advanced by the measured height while draw and semantics
    // counted one cell per line, so rows overlapped each other and the tail of
    // the body was dropped from placement entirely. The first case (2-line
    // rows, 4 rows, 20 cells tall) is the minimal reproduction — it died with
    // SIGBUS tearing down the frame artifacts.
    let artifacts = DefaultRenderer().render(
      Table(0..<geometry.rows, id: \.self, columns: [.init("Value", width: 8)]) { row in
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<geometry.rowLines, id: \.self) { line in
            Text("«\(row)»\(line)")
          }
        }
      },
      context: .init(
        identity: testIdentity("TallTable\(geometry.rowLines)x\(geometry.rows)x\(geometry.height)"),
        applyEnvironmentValues: false
      ),
      proposal: .init(width: .finite(24), height: .finite(geometry.height))
    )

    #expect(!artifacts.rasterSurface.lines.isEmpty)
  }

  @Test("T-37: the table layout is derived once and carried, not re-derived per phase")
  func layoutIsCarriedNotRederived() throws {
    // Invocation-economy pins measure the production pass; suppress the
    // layout shadow oracle's sampled re-run (intentional oracle-reduction).
    let probe = SoundnessProbeSuppression()
    defer { probe.restore() }
    TableLayoutDerivationProbe.reset()
    let artifacts = DefaultRenderer().render(
      Table(0..<20, id: \.self, columns: [.init("Value", width: 8)]) { row in
        Text("«\(row)»")
      },
      context: .init(identity: testIdentity("CarriedTableProduct"), applyEnvironmentValues: false),
      proposal: .init(width: .finite(24), height: .finite(12))
    )

    // Before this change measure, placement, draw, and semantics each derived
    // their own product; now the last three consume the measured one.
    #expect(
      TableLayoutDerivationProbe.derivationCount <= 3,
      "derived \(TableLayoutDerivationProbe.derivationCount) times"
    )
    let placed = try #require(firstPlacedTable(in: artifacts.placedTree))
    let carried = try #require(
      placed.hostedTableVisibleLayout,
      "the placed collection must carry the product its consumers read"
    )
    #expect(!carried.lines.isEmpty)
    #expect(carried.totalContentHeight >= carried.lines.count)
  }

  @Test("T-38: a payload-only table still lays out when no measured product exists")
  func payloadOnlyTableFallsBack() {
    // `TablePayload` is public API and can be drawn with no hosted children at
    // all, so every consumer must keep a working recompute path.
    let payload = TablePayload(
      columns: [.init(title: "Value", width: 8)],
      rows: (0..<5).map { .init(cells: [.init(text: "row \($0)")]) },
      selectedRowIndex: 1,
      style: .bordered
    )
    let layout = DrawExtractor().visibleTableLayout(
      for: payload,
      in: CellRect(origin: .init(x: 0, y: 0), size: .init(width: 20, height: 14))
    )

    #expect(!layout.lines.isEmpty)
    #expect(layout.lines.allSatisfy { $0.height == 1 }, "no measured heights means one cell each")
    for (index, line) in layout.lines.enumerated() {
      #expect(line.yOffset == index, "the one-cell model still puts line n at cell n")
    }
    #expect(layout.totalContentHeight == layout.lines.count)
  }

  @Test("T-39: table semantics row rects land on the cells the rows were placed at")
  func semanticsAgreesWithPlacement() throws {
    let tableIdentity = testIdentity("TableSemanticsAligned")
    let artifacts = DefaultRenderer().render(
      Table(0..<4, id: \.self, selection: .constant(0 as Int?), columns: [.init("V", width: 8)]) {
        row in
        VStack(alignment: .leading, spacing: 0) {
          Text("«\(row)»a")
          Text("«\(row)»b")
        }
      },
      context: .init(identity: tableIdentity, applyEnvironmentValues: false),
      proposal: .init(width: .finite(24), height: .finite(20))
    )

    let placed = try #require(firstPlacedTable(in: artifacts.placedTree))
    for row in 0..<4 {
      let identity = tableRowIdentity(for: tableIdentity, rowIndex: row)
      guard
        let region = artifacts.semanticSnapshot.interactionRegions.first(where: {
          $0.identity == identity
        })
      else {
        continue
      }
      let child = placed.children.first { child in
        child.semanticMetadata.hostedCollectionItem?.role == .tableRow(rowIndex: row)
      }
      guard let childBounds = child?.bounds else {
        continue
      }
      #expect(
        region.rect.origin.y == childBounds.origin.y,
        "row \(row): semantics at \(region.rect.origin.y), placed at \(childBounds.origin.y)"
      )
    }
  }

  @Test("T-39b: a one-cell-row table is unchanged by the height-aware model")
  func oneCellRowsAreUnchanged() {
    let artifacts = DefaultRenderer().render(
      Table(0..<6, id: \.self, columns: [.init("Value", width: 10)]) { row in
        Text("row \(row)")
      },
      context: .init(identity: testIdentity("OneCellTableRows"), applyEnvironmentValues: false),
      proposal: .init(width: .finite(24), height: .finite(20))
    )

    // A table body alternates row and separator lines, so consecutive rows sit
    // two cells apart — exactly as before the product was carried.
    let lines = artifacts.rasterSurface.lines
    let surface = lines.joined(separator: "\n")
    let starts = (0..<6).compactMap { row in
      lines.firstIndex { $0.contains("row \(row)") }
    }
    #expect(starts.count >= 2, "at least two rows are drawn:\n\(surface)")
    for (previous, next) in zip(starts, starts.dropFirst()) {
      #expect(next == previous + 2, "one row plus one separator, exactly as before:\n\(surface)")
    }
  }
}

private func firstPlacedTable(in root: PlacedNode) -> PlacedNode? {
  if root.semanticMetadata.hostedCollectionContainer?.kind == .table {
    return root
  }
  for child in root.children {
    if let match = firstPlacedTable(in: child) {
      return match
    }
  }
  return nil
}
