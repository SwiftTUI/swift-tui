import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct CompositionalLazyJourneyTests {
  @Test("wheel then prepend delete and reorder preserve a visible row")
  func edits() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("CompositeEdits"),
      size: .init(width: 50, height: 14)
    ) { CompositionEditFixture() }
    defer { harness.shutdown() }
    let point = try #require(harness.point(forText: "row 3"))
    for _ in 0..<8 { _ = try harness.scrollPointer(at: point, deltaY: 1) }
    let before = try #require(harness.point(forText: "row 12"))
    _ = try harness.clickText("Prepend")
    #expect(harness.point(forText: "row 12") == before)
    _ = try harness.clickText("Delete prefix")
    #expect(harness.point(forText: "row 12") == before)
    _ = try harness.clickText("Reorder prefix")
    #expect(harness.point(forText: "row 12") == before)
    let successor = harness.point(forText: "row 8")
    _ = try harness.clickText("Delete anchor")
    #expect(harness.point(forText: "row 8") == successor)
    _ = try harness.scrollPointer(at: point, deltaY: 1)
    #expect(harness.point(forText: "row 12")?.y == before.y - 1)
  }

  @Test("far scrollTo refines its target and an empty target preserves the viewport")
  func targets() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("CompositeTargets"),
      size: .init(width: 50, height: 14)
    ) { CompositionTargetFixture() }
    defer { harness.shutdown() }
    _ = try harness.clickText("Far target")
    let target = try #require(harness.point(forText: "row 500"))
    #expect(target.y == 2)
    _ = try harness.clickText("Empty target")
    #expect(harness.point(forText: "row 500") == target)
  }

  @Test("worker conversion retains logical boundaries and selection metadata")
  func workerParity() throws {
    @ViewBuilder func content() -> some View {
      Text("header")
      ForEach([1, 1, 2, 3], id: \.self) { value in
        if value != 2 {
          Text("x\(value)")
          Text("y\(value)")
        }
      }
      ForEach([4, 5], id: \.self) { Text("z\($0)") }
      Text("footer")
    }
    let node = resolveView(
      LazyVStack(alignment: .leading) { content() },
      in: .init(identity: testIdentity("WorkerComposition")))
    let live = try #require(node.indexedChildSource)
    let converted = indexedChildSourceWorkerSnapshot(of: node)
    let worker = try #require(converted.indexedChildSource)
    #expect(worker.canRunOnWorker)
    #expect(worker.count == live.count)
    for index in 0..<live.count {
      #expect(worker.childElements(at: index) == live.childElements(at: index))
      #expect(worker.elementIdentity(at: index) == live.elementIdentity(at: index))
      #expect(worker.elementSelectionTag(at: index) == live.elementSelectionTag(at: index))
      #expect(worker.estimationSegment(at: index) == live.estimationSegment(at: index))
    }
    let proposal = ProposedSize(width: .finite(30), height: .unspecified)
    let engine = LayoutEngine()
    let hint = MeasureViewportHint(
      axes: .vertical, contentOffset: .zero,
      viewportSize: .init(width: 30, height: 5))
    let livePass = LayoutPassContext()
    let liveMeasured = livePass.withMeasureViewportHint(hint) {
      engine.measure(node, proposal: proposal, passContext: livePass)
    }
    let workerPass = LayoutPassContext()
    let workerMeasured = workerPass.withMeasureViewportHint(hint) {
      engine.measure(converted, proposal: proposal, passContext: workerPass)
    }
    #expect(liveMeasured == workerMeasured)
  }

  @Test("composed fragments render identically on the frame-tail worker")
  func asynchronousWorker() async throws {
    @ViewBuilder func content() -> some View {
      ScrollView {
        LazyVStack(alignment: .leading) {
          Text("header")
          ForEach(0..<12, id: \.self) { index in
            if index % 3 != 0 {
              Text("first \(index)")
              Text("second \(index)")
            }
          }
          Text("footer")
        }
      }
    }
    let proposal = ProposedSize(width: .finite(40), height: .finite(12))
    let synchronous = DefaultRenderer().render(content(), proposal: proposal)
    let asynchronous = await DefaultRenderer().renderAsync(content(), proposal: proposal)
    #expect(asynchronous.rasterSurface == synchronous.rasterSurface)
    #expect(asynchronous.diagnostics.timing.workerTimings != nil)
  }

  @Test("horizontal wheel and membership changes preserve a visible fragment")
  func horizontalAnchor() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("HorizontalComposition"),
      size: .init(width: 70, height: 8)
    ) { HorizontalCompositionFixture() }
    defer { harness.shutdown() }
    let point = try #require(harness.point(forText: "x005"))
    for _ in 0..<8 { _ = try harness.scrollPointer(at: point, deltaX: 1, deltaY: 0) }
    let before = try #require(harness.point(forText: "x012"))
    _ = try harness.clickText("Prepend horizontal")
    #expect(harness.point(forText: "x012") == before)
  }

  @Test("anchor commit leaves a newer input offset intact")
  func anchorCommitCurrency() {
    let registry = LocalScrollPositionRegistry()
    let identity = testIdentity("AnchorCurrency")
    var offset = ScrollOffset(x: 0, y: 10)
    registry.register(identity: identity, currentOffset: { offset }, applyOffset: { offset = $0 })
    var route = ScrollRoute(
      identity: identity,
      viewportRect: .init(origin: .zero, size: .init(width: 40, height: 12)),
      contentBounds: .init(origin: .zero, size: .init(width: 40, height: 100)))
    route.scrollAnchorCorrection = .init(
      requestedOffset: .init(x: 0, y: 8),
      correctedOffset: .init(x: 0, y: 11))
    registry.commitLazyScrollAnchors([route])
    #expect(offset.y == 10)
    offset.y = 8
    registry.commitLazyScrollAnchors([route])
    #expect(offset.y == 11)
  }

  @Test("an oversized offset clamps to the footer without blank endpoint cells")
  func endpoint() {
    let snapshot = DefaultRenderer().render(
      ScrollView(position: .constant(.init(x: 0, y: 1_000_000))) {
        LazyVStack(alignment: .leading) {
          Text("header")
          ForEach(0..<1000, id: \.self) { Text("row \($0)") }
          Text("footer")
        }
      }, proposal: .init(width: 40, height: 12))
    #expect(snapshot.rasterSurface.lines.last?.contains("footer") == true)
  }

  @Test("arbitrary empty leading rows are discovered without phantom cells")
  func emptyDiscovery() {
    IndexedChildRealizationProbe.reset()
    let snapshot = DefaultRenderer().render(
      ScrollView {
        LazyVStack(alignment: .leading) {
          ForEach(0..<1000, id: \.self) { value in
            if value == 999 { Text("last visible") }
          }
        }
      }, proposal: .init(width: 30, height: 8))
    #expect(snapshot.rasterSurface.lines.first?.contains("last visible") == true)
    #expect(IndexedChildRealizationProbe.realizedChildCount == 1000)
  }
  @Test("custom neighbor spacing and alignment match eager layout", arguments: [0, 2, -1])
  func spacingAndAlignment(gap: Int) {
    @ViewBuilder func rows() -> some View {
      Text("header")
      ForEach(0..<1000, id: \.self) { value in
        CompositionGapLayout(gap: gap) { Text("row \(value)") }
          .alignmentGuide(.leading) { _ in 2 }
        if value % 2 == 0 { Text("detail") }
      }
    }
    let lazy = DefaultRenderer().render(
      ScrollView {
        LazyVStack(alignment: .leading) { rows() }
      }, proposal: .init(width: 40, height: 15))
    let eager = DefaultRenderer().render(
      ScrollView {
        VStack(alignment: .leading) { rows() }
      }, proposal: .init(width: 40, height: 15))
    #expect(lazy.rasterSurface.lines == eager.rasterSurface.lines)
  }

  @Test("resize and stable-ID content edits refresh fragment measurements")
  func resizeAndContent() {
    let renderer = DefaultRenderer()
    func render(width: Int, text: String) -> RenderSnapshot {
      renderer.render(
        ScrollView {
          LazyVStack(alignment: .leading) {
            Text("header")
            ForEach(0..<1000, id: \.self) { value in
              Text("\(value) \(text)")
            }
          }
        }, proposal: .init(width: .finite(width), height: .finite(12)))
    }
    let first = render(width: 40, text: "first")
    let narrow = render(width: 12, text: "a much longer replacement")
    let final = render(width: 40, text: "last")
    #expect(first.rasterSurface.lines.joined().contains("0 first"))
    #expect(!narrow.rasterSurface.lines.joined().contains("first"))
    #expect(narrow.rasterSurface.lines.joined().contains("longer"))
    #expect(final.rasterSurface.lines.joined().contains("0 last"))
  }

}

private struct CompositionEditFixture: View {
  @State private var rows = Array(0..<1000)
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Prepend") { rows.insert(contentsOf: [-3, -2, -1], at: 0) }
      Button("Delete prefix") { rows.removeFirst(2) }
      Button("Reorder prefix") { rows.swapAt(0, 1) }
      Button("Delete anchor") { rows.removeAll { $0 == 7 } }
      ScrollView {
        LazyVStack(alignment: .leading) {
          Text("header")
          ForEach(rows, id: \.self) { Text("row \($0)") }
          Text("footer")
        }
      }
    }
  }
}

private struct CompositionTargetFixture: View {
  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 0) {
        Button("Far target") { proxy.scrollTo(500, anchor: .top) }
        Button("Empty target") { proxy.scrollTo(801, anchor: .top) }
        ScrollView {
          LazyVStack(alignment: .leading) {
            Text("header")
            ForEach(0..<1000, id: \.self) { value in
              if value != 501 && value != 801 {
                Text("row \(value)")
                Text("detail \(value)")
              }
            }
            Text("footer")
          }
        }
      }
    }
  }
}

private struct CompositionGapLayout: Layout {
  var gap: Int
  func spacing(subviews: LayoutSubviews, cache: inout Void) -> ViewSpacing {
    .init(vertical: gap)
  }
  func sizeThatFits(
    proposal: ProposedViewSize, subviews: LayoutSubviews,
    cache: inout Void
  ) -> LayoutSize {
    subviews.first?.sizeThatFits(proposal) ?? .zero
  }
  func placeSubviews(
    in bounds: LayoutRect, proposal: ProposedViewSize,
    subviews: LayoutSubviews, cache: inout Void
  ) {
    subviews.first?.place(
      at: bounds.origin,
      proposal: .init(
        width: bounds.size.width,
        height: bounds.size.height))
  }
}

private struct HorizontalCompositionFixture: View {
  @State private var prefix = false
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Prepend horizontal") { prefix.toggle() }
      ScrollView(.horizontal) {
        LazyHStack(alignment: .top) {
          if prefix { Text("new prefix") }
          ForEach(0..<1000, id: \.self) { value in
            Text("x" + String(("000" + String(value)).suffix(3)))
          }
        }
      }
    }
  }
}
