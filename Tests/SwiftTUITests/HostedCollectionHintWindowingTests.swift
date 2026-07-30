import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Stage S2 of the scroll-currency program (root plan
/// `docs/plans/2026-07-28-007-collection-scroll-currency-plan.md`): a
/// viewport-backed collection under a non-finite height proposal windows
/// against the enclosing scroll layout's declared measure viewport instead of
/// collapsing to full-dataset realization (register item D17).
@MainActor
@Suite(.serialized)
struct HostedCollectionHintWindowingTests {
  @Test("T-20: ScrollView { List } realizes only the hinted window")
  func scrollViewListIsWindowed() {
    IndexedChildRealizationProbe.reset()
    let artifacts = DefaultRenderer().render(
      ScrollView {
        List(0..<2_000, id: \.self) { row in
          Text("«\(row)»")
        }
      },
      context: .init(identity: testIdentity("HintWindowedList"), applyEnvironmentValues: false),
      proposal: .init(width: .finite(20), height: .finite(12))
    )

    #expect(
      IndexedChildRealizationProbe.realizedChildCount <= 32,
      """
      flipped from C-07: realized \(IndexedChildRealizationProbe.realizedChildCount) rows for a \
      12-line viewport
      """
    )
    #expect(artifacts.rasterSurface.lines.joined(separator: "\n").contains("«0»"))
    #expect(
      !artifacts.diagnostics.runtime.issues.map(\.code).contains("collection.unboundedRealization"),
      "a hinted collection is bounded, so it must not report the cliff"
    )
  }

  @Test("T-21: a .fixedSize() collection realizes everything and reports the cliff once")
  func unboundedRealizationIsReportedOnce() {
    IndexedChildRealizationProbe.reset()
    let artifacts = DefaultRenderer().render(
      List(0..<200, id: \.self) { row in
        Text("«\(row)»")
      }
      .fixedSize(),
      context: .init(identity: testIdentity("UnboundedList"), applyEnvironmentValues: false),
      proposal: .init(width: .finite(20), height: .finite(12))
    )

    // `.fixedSize()` is a deliberate request for the true ideal height, so the
    // realization stays complete — the cliff is reported, not estimated away.
    #expect(IndexedChildRealizationProbe.realizedChildCount == 200)
    let cliffIssues = artifacts.diagnostics.runtime.issues.filter {
      $0.code == "collection.unboundedRealization"
    }
    #expect(cliffIssues.count == 1, "exactly one issue per identity per pass")
  }

  @Test("T-22: the measured size still reports the full virtual content height")
  func measuredSizeReportsVirtualHeight() throws {
    // The enclosing ScrollView needs the true content extent to clamp
    // scrolling, and the viewport-backed ideal is arithmetic over the row
    // count — so windowing the realization must not shrink it.
    let artifacts = DefaultRenderer().render(
      ScrollView {
        List(0..<2_000, id: \.self) { row in
          Text("«\(row)»")
        }
      },
      context: .init(identity: testIdentity("HintWindowedExtent"), applyEnvironmentValues: false),
      proposal: .init(width: .finite(20), height: .finite(12))
    )

    let route = try #require(artifacts.semanticSnapshot.scrollRoutes.first)
    #expect(
      route.contentBounds.size.height >= 2_000,
      "content extent must stay virtual: \(route.contentBounds.size.height)"
    )
  }

  @Test("T-23: a Table under the hint is windowed too")
  func tableIsWindowedUnderHint() {
    IndexedChildRealizationProbe.reset()
    _ = DefaultRenderer().render(
      ScrollView {
        Table(0..<2_000, id: \.self, columns: [.init("Value", width: 10)]) { row in
          Text("«\(row)»")
        }
      },
      context: .init(identity: testIdentity("HintWindowedTable"), applyEnvironmentValues: false),
      proposal: .init(width: .finite(24), height: .finite(12))
    )

    #expect(
      IndexedChildRealizationProbe.realizedChildCount <= 32,
      "realized \(IndexedChildRealizationProbe.realizedChildCount) table rows"
    )
  }

  @Test("T-24: the hint window is recomputed from the current offset")
  func hintWindowTracksTheOffset() {
    // The stale-window guard's arithmetic, exercised directly: a windowed
    // product is valid only for the window its hint produced, so an
    // offset-only change must yield a different window (which is what makes
    // the retained-measurement deny leg fire).
    let engine = LayoutEngine()
    func window(offsetY: Int) -> Range<Int>? {
      engine.hostedCollectionHintWindow(
        hint: MeasureViewportHint(
          axes: .vertical,
          contentOffset: .init(x: 0, y: offsetY),
          viewportSize: .init(width: 20, height: 10)
        ),
        count: 2_000,
        rowStride: 1
      )
    }

    let atTop = window(offsetY: 0)
    let scrolled = window(offsetY: 500)
    #expect(atTop != scrolled)
    #expect(atTop?.lowerBound == 0)
    #expect(scrolled?.lowerBound == 499)
    #expect((scrolled?.count ?? 0) <= 13, "viewport plus bounded overscan")
    #expect(
      engine.hostedCollectionHintWindow(hint: nil, count: 2_000, rowStride: 1) == nil,
      "no hint means no window — the caller must fall back, not guess"
    )
  }
}
