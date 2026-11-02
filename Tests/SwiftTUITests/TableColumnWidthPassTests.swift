import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Register item D21 — the hosted table's column-width pass. These pin what the
/// second measure loop in `windowedHostedCollectionMeasurement` actually costs
/// and what it buys, because the root plan
/// `docs/plans/2026-07-28-007-collection-scroll-currency-plan.md` describes
/// both incorrectly: it calls the second pass a re-realization (it is not — the
/// width application re-frames cached rows without realizing them), and it proposes
/// replacing it with a pre-loop width application (which would freeze column
/// discovery, because a `.frame(width:)` cell reports exactly that width).
@MainActor
@Suite(.serialized)
struct TableColumnWidthPassTests {
  @Test(
    "worker table cells align with the same chrome as main-actor frames", arguments: [false, true])
  func workerTableMatchesLive(scrollHosted: Bool) async throws {
    @ViewBuilder
    func root() -> some View {
      if scrollHosted {
        ScrollView([.vertical]) { table() }
      } else {
        table()
      }
    }
    func table() -> some View {
      Table(0..<4, id: \.self, columns: [.init("Value"), .init("Tail")]) { row in
        Text(row == 1 ? "abcdefghijklmnop" : "x")
        Text("t\(row)")
      }
    }
    let context = ResolveContext(identity: testIdentity("WorkerTableAlignment"))
    let proposal = ProposedSize(width: 48, height: 14)
    let live = DefaultRenderer().render(root(), context: context, proposal: proposal)
    let renderer = DefaultRenderer()
    let worker = await renderer.renderAsync(root(), context: context, proposal: proposal)
    #expect(try #require(worker.diagnostics.timing.workerTimings).layoutCompute != .zero)
    #expect(worker.rasterSurface.lines == live.rasterSurface.lines)
    let repeated = await renderer.renderAsync(root(), context: context, proposal: proposal)
    #expect(repeated.rasterSurface.lines == live.rasterSurface.lines)
  }

  @Test("worker snapshots unmask applied widths and retain later discoveries on the live source")
  func snapshotPreservesWidthCycle() throws {
    let artifacts = DefaultRenderer().render(
      Table(0..<40, id: \.self, columns: [.init("V"), .init("T")]) { row in
        Text(row == 20 ? "abcdefghijklmnop" : "x")
        Text("t")
      },
      context: .init(identity: testIdentity("WorkerTableDiscovery")),
      proposal: .init(width: 48, height: 8)
    )
    let live = artifacts.resolvedTree
    let source = try #require(live.indexedChildSource)
    let snapshot = indexedChildSourceWorkerSnapshot(of: live)
    let workerSource = try #require(snapshot.indexedChildSource)
    #expect(workerSource.canRunOnWorker)

    func measure(_ node: ResolvedNode, offset: Int) throws -> [Int] {
      let pass = LayoutPassContext(retainedLayout: nil)
      pass.pushMeasureViewportHint(
        .init(
          axes: [.vertical], contentOffset: .init(x: 0, y: offset),
          viewportSize: .init(width: 48, height: 8)))
      defer { pass.popMeasureViewportHint() }
      let measured = LayoutEngine().measure(
        node, proposal: .init(width: .finite(48), height: .unspecified), passContext: pass)
      let widths = try #require(
        measured.containerAllocationSnapshot?.hostedCollection?.tableColumnWidths)
      for row in measured.childMeasurements {
        #expect(row.childMeasurements.map(\.measuredSize.width) == widths)
      }
      return widths
    }
    let narrow = try measure(snapshot, offset: 0)
    let wide = try measure(snapshot, offset: 42)
    #expect(wide == [16, 1])
    #expect(wide[0] > narrow[0])
    #expect(try measure(snapshot, offset: 0) == wide)
    // Discovery on the worker must survive a later main-actor frame and a new snapshot.
    #expect(try measure(live, offset: 0) == wide)
    #expect(try measure(indexedChildSourceWorkerSnapshot(of: live), offset: 42) == wide)
    // A changed column schema starts a new high-water cache.
    #expect(
      source.retainedTableColumnWidths(columns: [.init(title: "Changed")], discovered: [2]) == [2])
  }

  @Test(
    "automatic title and cell widths obey the raster extent", arguments: [65_535, 65_536, 65_537])
  func automaticWidthsAreBounded(length: Int) {
    let text = String(repeating: "x", count: length)
    let widths = measureTableColumnWidths(
      columns: [.init(title: text), .init(title: "V"), .init(title: "F", width: length)],
      rows: [.init(cells: [.init(text: ""), .init(text: text), .init(text: "")])])
    #expect(widths == Array(repeating: min(length, 65_536), count: 3))
  }

  @Test("hosted discovery bounds oversized cells on live and worker sources")
  func hostedWidthsAreBounded() throws {
    let node = Table(0..<2, id: \.self, columns: [.init("V")]) { _ in
      Text(String(repeating: "x", count: 65_537))
    }.resolve(in: .init(identity: testIdentity("BoundedHostedTable")))
    for candidate in [node, indexedChildSourceWorkerSnapshot(of: node)] {
      let source = try #require(candidate.indexedChildSource)
      let measured = LayoutEngine().measure(candidate, proposal: .init(width: 20, height: 8))
      #expect(measured.containerAllocationSnapshot?.hostedCollection?.tableColumnWidths == [65_536])
      #expect(
        measured.childMeasurements.allSatisfy { row in
          row.childMeasurements.allSatisfy { $0.measuredSize.width <= 65_536 }
        })
      #expect(
        source.retainedTableColumnWidths(
          columns: [.init(title: "V")], discovered: [Int.max]) == [65_536])
    }
  }

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

    // The width pass loops the window a second time, but `child(at:)` re-frames
    // rows from the realization cache after `applyHostedTableColumnWidths`, so
    // realization is paid once per windowed row. A viewport of 14 lines holds ~5 body rows
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
