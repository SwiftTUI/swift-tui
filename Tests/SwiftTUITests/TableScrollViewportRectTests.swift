import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// A viewport-backed collection's scroll route must publish the rect it draws
/// rows into, not the node's full bounds. Lists learned this in stage S1 of the
/// scroll-currency program (root plan
/// `docs/plans/2026-07-28-007-collection-scroll-currency-plan.md`); tables kept
/// reporting their bounds, so every scroll consumer over-counted visible rows
/// by the header and border chrome.
@MainActor
@Suite(.serialized)
struct TableScrollViewportRectTests {
  @Test("T-47: a table's scroll route reports its body rect, not its bounds")
  func tableScrollRouteExcludesChrome() throws {
    let tableIdentity = testIdentity("TableViewportRect")
    let artifacts = DefaultRenderer().render(
      Table(0..<200, id: \.self, columns: [.init("Value", width: 10)]) { row in
        Text("row \(row)")
      },
      context: .init(identity: tableIdentity, applyEnvironmentValues: false),
      proposal: .init(width: .finite(24), height: .finite(16))
    )

    let placed = try #require(firstPlacedTable(in: artifacts.placedTree))
    let route = try #require(
      artifacts.semanticSnapshot.scrollRoutes.first { $0.identity == placed.identity },
      "a hosted table publishes a scroll route"
    )

    // Stated over the OBSERVED window, not a hardcoded height: the route must
    // cover exactly the cells the body rows were drawn into.
    let bodyRows = placed.children.compactMap { child -> CellRect? in
      guard case .tableRow = child.semanticMetadata.hostedCollectionItem?.role else {
        return nil
      }
      return child.bounds
    }
    #expect(!bodyRows.isEmpty, "the table realized some rows")
    let firstRowTop = try #require(bodyRows.map(\.origin.y).min())
    let lastRowBottom = try #require(bodyRows.map { $0.origin.y + $0.size.height }.max())

    #expect(
      route.viewportRect.origin.y == firstRowTop,
      "the route starts where the first body row does"
    )
    #expect(
      route.viewportRect.origin.y + route.viewportRect.size.height >= lastRowBottom,
      "the route covers the last body row"
    )

    // The whole point: the node's bounds claim more visible rows than exist.
    #expect(
      route.viewportRect != placed.bounds,
      "the route must not be the node's full bounds"
    )
    #expect(
      placed.bounds.size.height - route.viewportRect.size.height
        == chromeLineCount(showsHeaders: true),
      "the difference is exactly the header and border chrome"
    )
  }

  @Test("T-48: a header-less table loses only its two border lines")
  func headerlessTableExcludesBordersOnly() throws {
    let payload = viewportBackedTablePayload(showsHeaders: false)
    let bounds = CellRect(origin: .init(x: 2, y: 3), size: .init(width: 20, height: 12))
    let content = try #require(
      DrawExtractor().viewportBackedTableContentBounds(for: payload, in: bounds)
    )

    #expect(content.origin.y == bounds.origin.y + 1)
    #expect(content.size.height == bounds.size.height - chromeLineCount(showsHeaders: false))
    #expect(content.origin.x == bounds.origin.x, "chrome is vertical only")
    #expect(content.size.width == bounds.size.width)
  }

  @Test("T-49: a materialized table publishes no content rect")
  func materializedTableHasNoContentRect() {
    // The O(1) answer only exists for the viewport-backed line model; a
    // materialized payload keeps reporting its bounds, exactly as before.
    var payload = viewportBackedTablePayload(showsHeaders: true)
    payload.isViewportBacked = false
    let bounds = CellRect(origin: .zero, size: .init(width: 20, height: 12))

    #expect(DrawExtractor().viewportBackedTableContentBounds(for: payload, in: bounds) == nil)
  }

  @Test("T-50: a table shorter than its own chrome reports an empty body")
  func chromeTallerThanBoundsClampsToEmpty() throws {
    let payload = viewportBackedTablePayload(showsHeaders: true)
    let bounds = CellRect(origin: .zero, size: .init(width: 20, height: 2))
    let content = try #require(
      DrawExtractor().viewportBackedTableContentBounds(for: payload, in: bounds)
    )

    #expect(content.size.height == 0, "no body cells rather than a negative height")
  }
}

private func chromeLineCount(showsHeaders: Bool) -> Int {
  // Top border + (header + header rule) + bottom border.
  showsHeaders ? 4 : 2
}

private func viewportBackedTablePayload(showsHeaders: Bool) -> TablePayload {
  var payload = TablePayload(
    columns: [.init(title: "Value", width: 10)],
    rows: (0..<50).map { .init(cells: [.init(text: "row \($0)")]) },
    selectedRowIndex: nil,
    style: .bordered,
    showsHeaders: showsHeaders
  )
  payload.isViewportBacked = true
  return payload
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
