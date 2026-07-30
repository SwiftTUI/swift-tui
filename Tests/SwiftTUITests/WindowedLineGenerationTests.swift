import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// The interim cost stage S2 named and left behind (root plan
/// `docs/plans/2026-07-28-007-collection-scroll-currency-plan.md`): inside a
/// `ScrollView` a hosted collection is laid out against its own full content
/// height, so the line model built one display line per row of the whole
/// dataset even after child realization became O(viewport). S3 reduced that
/// from four builds per frame to one; this reduces the one to O(window).
@MainActor
@Suite(.serialized)
struct WindowedLineGenerationTests {
  @Test("T-51: a collection inside a ScrollView generates O(window) display lines")
  func scrollViewCollectionGeneratesWindowedLines() throws {
    let artifacts = DefaultRenderer().render(
      ScrollView {
        List(0..<2_000, id: \.self) { row in
          Text("«\(row)»")
        }
      },
      context: .init(identity: testIdentity("WindowedLines"), applyEnvironmentValues: false),
      proposal: .init(width: .finite(20), height: .finite(12))
    )

    let placed = try #require(firstPlacedList(in: artifacts.placedTree))
    let layout = try #require(placed.hostedListVisibleLayout)

    #expect(
      layout.lines.count <= 64,
      "generated \(layout.lines.count) display lines for a 12-line viewport over 2,000 rows"
    )
    // The window is bounded but the CONTENT is not: everything below the
    // window still occupies its cells, or the scroll view would think the
    // content ended at the window.
    #expect(
      layout.totalContentHeight >= 2_000,
      "content height is the whole dataset, not the window: \(layout.totalContentHeight)"
    )
    #expect(artifacts.rasterSurface.lines.joined(separator: "\n").contains("«0»"))
  }

  @Test("T-52: the generated lines are the rows that were realized")
  func generatedLinesCoverTheRealizedRows() throws {
    let artifacts = DefaultRenderer().render(
      ScrollView {
        List(0..<2_000, id: \.self) { row in
          Text("«\(row)»")
        }
      },
      context: .init(identity: testIdentity("WindowedLineRows"), applyEnvironmentValues: false),
      proposal: .init(width: .finite(20), height: .finite(12))
    )

    let placed = try #require(firstPlacedList(in: artifacts.placedTree))
    let layout = try #require(placed.hostedListVisibleLayout)
    let generatedRows = Set(layout.lines.compactMap(\.rowIndex))
    let placedRows = Set(
      placed.children.compactMap { child -> Int? in
        guard case .listRow(let rowIndex) = child.semanticMetadata.hostedCollectionItem?.role else {
          return nil
        }
        return rowIndex
      }
    )

    #expect(!placedRows.isEmpty, "some rows were placed")
    #expect(
      placedRows.isSubset(of: generatedRows),
      """
      every placed row has a line: placed \(placedRows.sorted()) \
      generated \(generatedRows.sorted())
      """
    )
  }

  @Test("T-53: windowing generation moves nothing — every line keeps its content offset")
  func windowedLinesKeepAbsoluteOffsets() throws {
    // The reduction, stated as an equivalence rather than as an absolute:
    // deriving the same payload with and without a row window must agree on
    // every line the windowed derivation produced. That is what makes the
    // arithmetic sound — skipped rows are one cell each, so they can be
    // counted instead of built.
    var payload = ListPayload(
      items: (0..<2_000).map { _ in .init(kind: .row, text: "") },
      selectedRowIndex: 0,
      style: .plain
    )
    payload.isViewportBacked = true
    // Bounds that cover the whole content, which is the situation windowing
    // applies to: a hosted collection inside a `ScrollView` is laid out against
    // its own content height, not against the viewport.
    let contentHeight = payload.style.measuredListIdealSize(for: payload).height
    let bounds = CellRect(
      origin: .init(x: 3, y: 4),
      size: .init(width: 20, height: contentHeight)
    )

    let full = payload.style.visibleListLayout(for: payload, in: bounds)
    let windowed = payload.style.visibleListLayout(
      for: payload,
      in: bounds,
      rowWindow: 900..<940
    )

    #expect(windowed.lines.count < full.lines.count / 10, "generation actually shrank")
    #expect(
      windowed.totalContentHeight == full.totalContentHeight,
      "the content is the same height either way"
    )
    #expect(windowed.contentBounds == full.contentBounds)

    let fullByRow = Dictionary(
      full.lines.compactMap { line in line.rowIndex.map { ($0, line) } },
      uniquingKeysWith: { first, _ in first }
    )
    for line in windowed.lines {
      guard let rowIndex = line.rowIndex, let reference = fullByRow[rowIndex] else {
        continue
      }
      #expect(
        line.yOffset == reference.yOffset,
        "row \(rowIndex): windowed offset \(line.yOffset), full offset \(reference.yOffset)"
      )
      #expect(line.height == reference.height)
    }
    #expect(
      windowed.lines.contains { $0.rowIndex == 900 },
      "the requested window is the band that got built"
    )
  }

  @Test("T-55: a table inside a ScrollView generates O(window) display lines")
  func scrollViewTableGeneratesWindowedLines() throws {
    let artifacts = DefaultRenderer().render(
      ScrollView {
        Table(0..<2_000, id: \.self, columns: [.init("Value", width: 8)]) { row in
          Text("«\(row)»")
        }
      },
      context: .init(identity: testIdentity("WindowedTableLines"), applyEnvironmentValues: false),
      proposal: .init(width: .finite(24), height: .finite(14))
    )

    let placed = try #require(firstPlacedTable(in: artifacts.placedTree))
    let layout = try #require(placed.hostedTableVisibleLayout)

    #expect(
      layout.lines.count <= 80,
      "generated \(layout.lines.count) display lines for a 14-line viewport over 2,000 rows"
    )
    #expect(
      layout.totalContentHeight >= 2_000,
      "content height is the whole dataset: \(layout.totalContentHeight)"
    )
    #expect(artifacts.rasterSurface.lines.joined(separator: "\n").contains("«0»"))
  }

  @Test("T-56: a windowed table keeps its chrome lines and their content offsets")
  func windowedTableKeepsChromeOffsets() throws {
    var payload = TablePayload(
      columns: [.init(title: "Value", width: 8)],
      rows: (0..<1_000).map { _ in .init(cells: [.init(text: "")]) },
      selectedRowIndex: nil,
      style: .plain
    )
    payload.isViewportBacked = true
    let extractor = DrawExtractor()
    let contentHeight =
      extractor.tableChromeLineCounts(for: payload).top
      + (payload.rows.count * 2 - 1)
      + extractor.tableChromeLineCounts(for: payload).bottom
    let bounds = CellRect(origin: .zero, size: .init(width: 24, height: contentHeight))

    let full = extractor.visibleTableLayout(for: payload, in: bounds)
    let windowed = extractor.visibleTableLayout(
      for: payload,
      in: bounds,
      rowWindow: 400..<440
    )

    #expect(windowed.lines.count < full.lines.count / 10, "generation actually shrank")
    #expect(windowed.totalContentHeight == full.totalContentHeight)
    // The bottom border still sits below every row it closes, even though the
    // rows between it and the window were never built.
    let windowedBottom = try #require(windowed.lines.last)
    let fullBottom = try #require(full.lines.last)
    #expect(windowedBottom.role == fullBottom.role)
    #expect(
      windowedBottom.yOffset == fullBottom.yOffset,
      "bottom border at \(windowedBottom.yOffset), unwindowed says \(fullBottom.yOffset)"
    )

    let fullByRow = Dictionary(
      full.lines.compactMap { line in line.rowIndex.map { ($0, line) } },
      uniquingKeysWith: { first, _ in first }
    )
    for line in windowed.lines {
      guard let rowIndex = line.rowIndex, let reference = fullByRow[rowIndex] else {
        continue
      }
      #expect(
        line.yOffset == reference.yOffset,
        "row \(rowIndex): windowed offset \(line.yOffset), full offset \(reference.yOffset)"
      )
    }
  }

  @Test("T-54: a collection outside a ScrollView is unwindowed and unchanged")
  func plainCollectionIsUnaffected() throws {
    let artifacts = DefaultRenderer().render(
      List(0..<2_000, id: \.self) { row in
        Text("«\(row)»")
      },
      context: .init(identity: testIdentity("UnwindowedLines"), applyEnvironmentValues: false),
      proposal: .init(width: .finite(20), height: .finite(12))
    )

    let placed = try #require(firstPlacedList(in: artifacts.placedTree))
    let layout = try #require(placed.hostedListVisibleLayout)

    // A finite proposal already IS the viewport, so the line model's own
    // window applies and generation was never O(dataset) here.
    #expect(layout.lines.count <= 12)
    #expect(layout.totalContentHeight <= 12)
    #expect(artifacts.rasterSurface.lines.joined(separator: "\n").contains("«0»"))
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
