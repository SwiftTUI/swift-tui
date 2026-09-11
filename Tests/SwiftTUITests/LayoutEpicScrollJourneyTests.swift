@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct LayoutEpicScrollJourneyTests {
  @Test(
    "STUI-484: reverse-wheel bursts survive an in-flight frame after tab churn",
    .timeLimit(.minutes(1)))
  func reversalDuringAsyncFrame() async throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("AsyncScrollReversal"), size: .init(width: 40, height: 12)
    ) { ScrollReversalFixture() }
    defer { harness.shutdown() }
    for _ in 0..<2 {
      _ = try harness.clickText("Other")
      _ = try harness.clickText("Content")
    }
    let point = try #require(harness.point(forText: "line 2"))
    _ = try harness.scrollPointer(at: point, deltaY: 15)
    let before = try #require(harness.runLoop.latestSemanticSnapshot.scrollRoutes.first)
    let gate = AsyncFrameTailBlockingGate(blockingEntry: 1)
    harness.runLoop.renderer.setFrameTailRenderHooks(.init(beforeRaster: { gate.beforeRaster() }))
    defer {
      gate.release()
      harness.runLoop.renderer.setFrameTailRenderHooks(nil)
    }
    let pump = SwiftTUIRuntime.RunLoop<Int, ScrollReversalFixture>.EventPump(
      stream: AsyncStream { $0.finish() }, drainEvents: { [] }, hasPendingEvents: { false },
      cancel: {}, scheduleDeadlineWake: { _ in })
    func reverse() {
      _ = harness.runLoop.handle(
        .input(
          .mouse(
            .init(
              kind: .scrolled(deltaX: 0, deltaY: -1), location: point))))
    }
    reverse()
    let renderTask = Task { @MainActor in
      var frames = 0
      _ = try await harness.runLoop.renderPendingFramesAsync(
        renderedFrames: &frames, eventPump: pump)
    }
    await gate.waitUntilBlocked()
    for _ in 0..<5 { reverse() }
    gate.release()
    try await renderTask.value
    var frames = 0
    _ = try await harness.runLoop.renderPendingFramesAsync(renderedFrames: &frames, eventPump: pump)
    let after = try #require(harness.runLoop.latestSemanticSnapshot.scrollRoutes.first)
    #expect(after.contentBounds.origin.y == before.contentBounds.origin.y + 6)
    _ = try harness.scrollPointer(at: point, deltaY: -1)
    let final = try #require(harness.runLoop.latestSemanticSnapshot.scrollRoutes.first)
    #expect(final.contentBounds.origin.y == after.contentBounds.origin.y + 1)
  }

  @Test(
    "STUI-75: outer scrolling preserves hosted three-line collection rows",
    arguments: [true, false])
  func outerScrollPreservesTallRows(table: Bool) throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("OuterTallCollection"), size: .init(width: 40, height: 12)
    ) { TallCollectionFixture(table: table) }
    defer { harness.shutdown() }
    let before = try #require(harness.point(forText: "R1-c"))
    let beforeFirst = try #require(harness.point(forText: "R1-a"))
    let beforeNext = try #require(harness.point(forText: "R2-a"))
    _ = try harness.scrollPointer(at: .init(x: 35, y: 7), deltaY: 1)
    let first = try #require(harness.point(forText: "R1-a"))
    let third = try #require(harness.point(forText: "R1-c"))
    let next = try #require(harness.point(forText: "R2-a"))
    #expect(third.y == before.y - 1)
    #expect(third.y == first.y + 2)
    #expect(next.y - first.y == beforeNext.y - beforeFirst.y)
    _ = try harness.scrollPointer(at: .init(x: 35, y: 7), deltaY: -1)
    #expect(harness.point(forText: "R1-c")?.y == before.y)
  }

  @Test(
    "STUI-352: eager Table wheel and programmatic anchors change rendered rows",
    arguments: [true, false])
  func eagerTableAnchor(showsIndicators: Bool) throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("EagerTableAnchor"), size: .init(width: 24, height: 10)
    ) {
      ScrollViewReader { proxy in
        VStack(spacing: 0) {
          Button("Bottom") { proxy.scrollTo(edge: .bottom) }
          Button("Top") { proxy.scrollTo(edge: .top) }
          Table(columns: [.init("Value", width: 16)]) {
            ForEach(0..<10) { row in TableRow { Text("Row \(row)") } }
          }
          .tableHeaders(.hidden)
          .scrollIndicators(showsIndicators ? .visible : .hidden)
        }
      }
    }
    defer { harness.shutdown() }
    let point = try #require(harness.point(forText: "Row 0"))
    _ = try harness.scrollPointer(at: point, deltaY: 1)
    #expect(!harness.frame.contains("Row 0"))
    #expect(harness.frame.contains("Row 1"))
    _ = try harness.scrollPointer(at: point, deltaY: -1)
    #expect(harness.frame.contains("Row 0"))
    _ = try harness.clickText("Bottom")
    #expect(harness.frame.contains("Row 9"))
    _ = try harness.clickText("Top")
    #expect(harness.frame.contains("Row 0"))
  }

  @Test("STUI-484: wheel reversal after tab churn moves one cell per notch")
  func scrollReversalAfterTabChurn() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ScrollReversal"), size: .init(width: 40, height: 12)
    ) { ScrollReversalFixture() }
    defer { harness.shutdown() }
    for _ in 0..<2 {
      _ = try harness.clickText("Other")
      _ = try harness.clickText("Content")
    }
    let point = try #require(harness.point(forText: "line 2"))
    _ = try harness.clickText("line 2")
    for _ in 0..<15 { _ = try harness.scrollPointer(at: point, deltaY: 1) }
    for _ in 0..<10 {
      let before = try #require(harness.runLoop.latestSemanticSnapshot.scrollRoutes.first)
      _ = try harness.scrollPointer(at: point, deltaY: -1)
      let after = try #require(harness.runLoop.latestSemanticSnapshot.scrollRoutes.first)
      #expect(after.contentBounds.origin.y == before.contentBounds.origin.y + 1)
      #expect(after.contentBounds.size == before.contentBounds.size)
    }
  }
}

@MainActor
private struct TallCollectionFixture: View {
  let table: Bool
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        Text("Header")
        if table {
          Table(0..<6, id: \.self, columns: [.init("Value", width: 12)]) { row in
            rowContent(row)
          }
          .tableHeaders(.hidden)
          .frame(width: 20, height: 18)
        } else {
          List(0..<6, id: \.self) { row in rowContent(row) }
            .frame(width: 20, height: 18)
        }
        Text("Footer")
      }
    }
  }

  private func rowContent(_ row: Int) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("R\(row)-a")
      Text("R\(row)-b")
      Text("R\(row)-c")
    }
  }
}

@MainActor
private struct ScrollReversalFixture: View {
  @State private var tab = 0
  var body: some View {
    TabView(selection: $tab) {
      Tab("Content", value: 0) {
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<30) { index in
              Button("line \(index)") {}
            }
          }
        }
      }
      Tab("Other", value: 1) { Text("Elsewhere") }
    }
  }
}
