import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// The last O(dataset) payload cost named in register item D18: a hosted
/// collection materialized one `ListItemPayload` per row of the dataset on
/// every resolve, and every payload comparison walked the result. The rows are
/// committed child nodes, so those entries were N identical empty stubs
/// carrying no information but their count.
@MainActor
@Suite(.serialized)
struct VirtualRowCountTests {
  @Test("T-57: a viewport-backed payload carries a row count, not a row array")
  func viewportBackedPayloadStoresNoItems() throws {
    let artifacts = DefaultRenderer().render(
      List(0..<5_000, id: \.self) { row in
        Text("«\(row)»")
      },
      context: .init(identity: testIdentity("VirtualRows"), applyEnvironmentValues: false),
      proposal: .init(width: .finite(20), height: .finite(12))
    )

    let resolved = try #require(firstHostedList(in: artifacts.resolvedTree))
    guard case .list(let payload) = resolved.drawPayload else {
      Issue.record("the hosted list must carry a list payload")
      return
    }

    #expect(payload.isViewportBacked)
    #expect(payload.items.isEmpty, "no per-row stub array")
    #expect(payload.virtualRowCount == 5_000)
    #expect(payload.rowCount == 5_000, "arithmetic still sees every row")
    #expect(artifacts.rasterSurface.lines.joined(separator: "\n").contains("«0»"))
  }

  @Test("T-58: a payload-only caller is untouched — items are the content")
  func payloadOnlyCallerKeepsItems() {
    let payload = ListPayload(
      items: (0..<5).map { .init(kind: .row, text: "row \($0)") },
      selectedRowIndex: 1,
      style: .plain
    )

    #expect(payload.virtualRowCount == nil)
    #expect(payload.rowCount == 5)
    #expect(!payload.items.isEmpty)
  }

  @Test("T-59: measurement equivalence still separates payloads of different lengths")
  func equivalenceSeesTheVirtualCount() {
    // The risk the substitution introduces: with no items to compare, two
    // differently-sized collections would look identical to the reuse gate and
    // a stale measurement would be served.
    func viewportBacked(rowCount: Int) -> ListPayload {
      var payload = ListPayload(items: [], selectedRowIndex: nil, style: .plain)
      payload.isViewportBacked = true
      payload.virtualRowCount = rowCount
      return payload
    }

    let small = viewportBacked(rowCount: 10)
    let large = viewportBacked(rowCount: 5_000)

    #expect(!small.isEquivalentForMeasurement(to: large))
    #expect(small.isEquivalentForMeasurement(to: viewportBacked(rowCount: 10)))
    #expect(small != large, "and the same holds for full equality")
  }

  @Test("T-60: growing the dataset re-measures rather than reusing the old size")
  func rowCountChangeDeniesReuse() {
    // The end-to-end form of T-59: the reduction must not make a longer list
    // render at the shorter list's height.
    func height(ofListWith rowCount: Int) -> Int {
      let artifacts = DefaultRenderer().render(
        List(0..<rowCount, id: \.self) { row in
          Text("«\(row)»")
        },
        context: .init(
          identity: testIdentity("VirtualRowsHeight"),
          applyEnvironmentValues: false
        ),
        proposal: .init(width: .finite(20), height: .unspecified)
      )
      return firstHostedList(in: artifacts.resolvedTree).map { _ in
        artifacts.placedTree.bounds.size.height
      } ?? 0
    }

    #expect(height(ofListWith: 40) > height(ofListWith: 4))
  }
}

private func firstHostedList(in root: ResolvedNode) -> ResolvedNode? {
  if root.semanticMetadata.hostedCollectionContainer?.kind == .list {
    return root
  }
  for child in root.children {
    if let match = firstHostedList(in: child) {
      return match
    }
  }
  return nil
}
