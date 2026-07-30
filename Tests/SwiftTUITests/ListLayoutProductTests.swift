import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Stage S3 of the scroll-currency program (root plan
/// `docs/plans/2026-07-28-007-collection-scroll-currency-plan.md`): the list's
/// visible layout becomes a height-aware product derived once at measure and
/// carried to placement, draw, and semantics — closing register item D19,
/// where each phase re-derived its own and the conventions disagreed.
@MainActor
@Suite(.serialized)
struct ListLayoutProductTests {
  @Test("T-30: a 2-line row keeps its marker, content, and successors aligned")
  func tallRowsStayAligned() throws {
    // Flipped from C-06, which pinned the marker landing one cell ABOVE its
    // own content because the line model counted every row as one cell while
    // placement advanced by the measured height.
    let artifacts = DefaultRenderer().render(
      List(0..<4, id: \.self, selection: .constant(2 as Int?)) { row in
        VStack(alignment: .leading, spacing: 0) {
          Text("«\(row)»a")
          Text("«\(row)»b")
        }
      },
      context: .init(identity: testIdentity("TallRowProduct"), applyEnvironmentValues: false),
      proposal: .init(width: .finite(20), height: .finite(14))
    )

    let lines = artifacts.rasterSurface.lines
    let surface = lines.joined(separator: "\n")
    let markerLine = try #require(
      lines.firstIndex { $0.contains("▌") },
      "no selection marker in:\n\(surface)"
    )
    let selectedRowLine = try #require(lines.firstIndex { $0.contains("«2»a") })
    #expect(
      markerLine == selectedRowLine,
      "the marker sits on its own row's first cell:\n\(surface)"
    )

    // Every row after the tall ones is still on its own cells: two per row.
    for row in 0..<4 {
      let first = try #require(lines.firstIndex { $0.contains("«\(row)»a") })
      let second = try #require(lines.firstIndex { $0.contains("«\(row)»b") })
      #expect(second == first + 1, "row \(row)'s two lines are adjacent")
    }
  }

  @Test("T-31: the layout is derived once and carried, not re-derived per phase")
  func layoutIsCarriedNotRederived() throws {
    ListLayoutDerivationProbe.reset()
    let artifacts = DefaultRenderer().render(
      List(0..<20, id: \.self, selection: .constant(0 as Int?)) { row in
        Text("«\(row)»")
      },
      context: .init(identity: testIdentity("CarriedProduct"), applyEnvironmentValues: false),
      proposal: .init(width: .finite(20), height: .finite(10))
    )

    // Before this stage measure, placement, draw, and semantics each derived
    // their own product; now the last three consume the measured one.
    #expect(
      ListLayoutDerivationProbe.derivationCount <= 2,
      "derived \(ListLayoutDerivationProbe.derivationCount) times"
    )
    let placed = try #require(firstPlacedList(in: artifacts.placedTree))
    let carried = try #require(
      placed.hostedListVisibleLayout,
      "the placed collection must carry the product its consumers read"
    )
    #expect(!carried.lines.isEmpty)
    #expect(carried.totalContentHeight >= carried.lines.count)
  }

  @Test("T-32: a payload-only list still lays out when no measured product exists")
  func payloadOnlyListFallsBack() {
    // `ListPayload` is public API and can be drawn with no hosted children at
    // all, so every consumer must keep a working recompute path.
    let payload = ListPayload(
      items: (0..<5).map { .init(kind: .row, text: "row \($0)") },
      selectedRowIndex: 1,
      style: .plain
    )
    let layout = payload.style.visibleListLayout(
      for: payload,
      in: CellRect(origin: .init(x: 0, y: 0), size: .init(width: 20, height: 8))
    )

    #expect(!layout.lines.isEmpty)
    #expect(layout.lines.allSatisfy { $0.height == 1 }, "no measured heights means one cell each")
    for (index, line) in layout.lines.enumerated() {
      #expect(line.yOffset == index, "the one-cell model still puts line n at cell n")
    }
    #expect(layout.totalContentHeight == layout.lines.count)
  }

  @Test("T-33: a windowed measurement attributes row heights to their own rows")
  func windowedHeightsAreAttributedBySourceIndex() throws {
    // The measured size used to zip window measurements POSITIONALLY against
    // the global item array, so a window starting at row N had its heights
    // credited to rows 0, 1, 2… Invisible while every row is one cell tall,
    // wrong the moment one is not.
    let engine = LayoutEngine()
    var payload = ListPayload(
      items: (0..<100).map { .init(kind: .row, text: "row \($0)") },
      selectedRowIndex: 0,
      style: .plain
    )
    payload.isViewportBacked = true

    let tallMeasurement = MeasuredNode(
      identity: testIdentity("Tall"),
      proposal: .init(width: .finite(20), height: .unspecified),
      measuredSize: .init(width: 4, height: 3),
      childMeasurements: []
    )
    let positional = engine.measuredHostedListSize(
      for: payload,
      childMeasurements: [tallMeasurement],
      proposal: .init(width: .finite(20), height: .unspecified)
    )
    let attributed = engine.measuredHostedListSize(
      for: payload,
      childMeasurements: [tallMeasurement],
      sourceIndices: [50],
      proposal: .init(width: .finite(20), height: .unspecified)
    )

    // Both credit the same extra height — the point is that the attributed
    // form asks item 50 for its kind rather than item 0.
    #expect(positional.height == attributed.height)
    #expect(attributed.height > 100, "the tall row's extra cells are counted")
  }

  @Test("T-34: semantics row rects land on the cells the rows were placed at")
  func semanticsAgreesWithPlacement() throws {
    let listIdentity = testIdentity("SemanticsAligned")
    let artifacts = DefaultRenderer().render(
      List(0..<4, id: \.self, selection: .constant(0 as Int?)) { row in
        VStack(alignment: .leading, spacing: 0) {
          Text("«\(row)»a")
          Text("«\(row)»b")
        }
      },
      context: .init(identity: listIdentity, applyEnvironmentValues: false),
      proposal: .init(width: .finite(20), height: .finite(14))
    )

    let placed = try #require(firstPlacedList(in: artifacts.placedTree))
    for row in 0..<3 {
      let identity = listRowIdentity(for: listIdentity, rowIndex: row)
      guard
        let region = artifacts.semanticSnapshot.interactionRegions.first(where: {
          $0.identity == identity
        })
      else {
        continue
      }
      let child = placed.children.first { child in
        child.semanticMetadata.hostedCollectionItem?.role == .listRow(rowIndex: row)
      }
      let childBounds = try #require(child?.bounds, "row \(row) was not placed")
      #expect(
        region.rect.origin.y == childBounds.origin.y,
        "row \(row): semantics at \(region.rect.origin.y), placed at \(childBounds.origin.y)"
      )
    }
  }

  @Test("T-35: a one-cell-row list is unchanged by the height-aware model")
  func oneCellRowsAreUnchanged() {
    let artifacts = DefaultRenderer().render(
      List(0..<6, id: \.self, selection: .constant(0 as Int?)) { row in
        Text("row \(row)")
      },
      context: .init(identity: testIdentity("OneCellRows"), applyEnvironmentValues: false),
      proposal: .init(width: .finite(20), height: .finite(10))
    )

    let lines = artifacts.rasterSurface.lines
    let first = lines.firstIndex { $0.contains("row 0") }
    for row in 0..<6 {
      guard let index = lines.firstIndex(where: { $0.contains("row \(row)") }),
        let first
      else {
        continue
      }
      #expect(index == first + row, "one cell per row, exactly as before")
    }
  }
}

private func firstPlacedList(in root: PlacedNode) -> PlacedNode? {
  if root.semanticMetadata.hostedCollectionContainer?.kind == .list {
    return root
  }
  for child in root.children {
    if let match = firstPlacedList(in: child) {
      return match
    }
  }
  return nil
}
