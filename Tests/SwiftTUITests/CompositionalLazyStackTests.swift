@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct CompositionalLazyStackTests {
  @Test(
    "composed default-spacing stacks bound row bodies", arguments: [1_000, 10_000, 100_000],
    [false, true])
  func composed(count: Int, variable: Bool) {
    let renderer = DefaultRenderer()
    func render() -> RenderSnapshot {
      renderer.render(
        ScrollView {
          LazyVStack(alignment: .leading) {
            Text("header")
            ForEach(0..<count / 2, id: \.self) {
              Text("a \($0)" + (variable && $0 % 2 == 0 ? "\ndetail" : ""))
            }
            ForEach(0..<count / 2, id: \.self) {
              Text("b \($0)" + (variable && $0 % 2 == 0 ? "\ndetail" : ""))
            }
            Text("footer")
          }
        }, context: .init(identity: testIdentity("Composed"), applyEnvironmentValues: false),
        proposal: .init(width: .finite(40), height: .finite(12)))
    }
    var result: RenderSnapshot!
    for phase in ["cold", "warm"] {
      IndexedChildRealizationProbe.reset()
      let start = ContinuousClock.now
      result = render()
      let elapsed = start.duration(to: .now)
      var pending = [result.placedTree]
      var fragments = 0
      var metadata = 0
      while let node = pending.popLast() {
        if let allocation = node.lazyStackAllocationSnapshot {
          fragments += allocation.fragments?.count ?? 0
          metadata += allocation.childMainLengths.count
        }
        pending.append(contentsOf: node.children)
      }
      print(
        "STUI480 rows=\(count) variable=\(variable) phase=\(phase) time=\(elapsed) bodies=\(IndexedChildRealizationProbe.realizedChildCount) fragmentRequests=\(result.diagnostics.work.layoutBranching.lazyFragmentMeasureRequests) exactFragments=\(fragments) nodeMeasurements=\(result.diagnostics.work.measuredNodesComputed) metadataElements=\(metadata)"
      )
      #expect(IndexedChildRealizationProbe.realizedChildCount < 40)
      #expect(fragments < 40)
      #expect(metadata == count + 2)
    }
    let text = result.rasterSurface.lines.joined(separator: "\n")
    #expect(text.contains("header"))
    #expect(text.contains("a 5"))
    #expect(!text.contains("footer"))
    #expect(IndexedChildRealizationProbe.realizedChildCount < 40)
  }

  @Test("empty and multiple fragments match eager output", arguments: [false, true])
  func cardinality(horizontal: Bool) {
    @ViewBuilder func rows() -> some View {
      Text("H")
      ForEach(0..<1000, id: \.self) { value in
        if value % 3 != 0 {
          Text("x\(value)")
          Text("y\(value)")
        }
      }
      Text("F")
    }
    let context = ResolveContext(identity: testIdentity("Fragments"), applyEnvironmentValues: false)
    let proposal = ProposedSize(width: .finite(40), height: .finite(12))
    IndexedChildRealizationProbe.reset()
    let lazy = DefaultRenderer().render(
      ScrollView(horizontal ? .horizontal : .vertical) {
        if horizontal { LazyHStack { rows() } } else { LazyVStack(alignment: .leading) { rows() } }
      }, context: context, proposal: proposal)
    #expect(IndexedChildRealizationProbe.realizedChildCount < 80)
    let eager = DefaultRenderer().render(
      ScrollView(horizontal ? .horizontal : .vertical) {
        if horizontal { HStack { rows() } } else { VStack(alignment: .leading) { rows() } }
      }, context: context, proposal: proposal)
    #expect(
      lazy.rasterSurface.lines.joined(separator: "\n")
        == eager.rasterSurface.lines.joined(separator: "\n"))
  }
  @Test("production identity and flattened cardinality match eager declared traversal")
  func identityAndCardinality() {
    let context = ResolveContext(identity: testIdentity("ProofParity"))
    @ViewBuilder func content(_ header: Bool) -> some View {
      if header { Text("header") }
      Group {
        ForEach([1, 1, 2], id: \.self) { value in
          if value == 2 {
            EmptyView()
          } else {
            Text("first \(value)")
            Text("second \(value)")
          }
        }
        EmptyView()
        ForEach([1, 3], id: \.self) { Text("other \($0)") }
      }
      for index in 0..<2 { Text("static \(index)") }
      Text("footer")
    }
    for header in [false, true] {
      let source = makeCompositionalIndexedChildSource(
        from: content(header), in: context, kindName: "ProofStack")
      let actual = (0..<source.count).flatMap { source.childElements(at: $0) }
      let eager = resolveDeclaredChildren(content(header), in: context, kindName: "ProofStack")
      #expect(actual.map(\.identity) == eager.map(\.identity))
      #expect(actual.map(\.structuralPath) == eager.map(\.structuralPath))
      #expect(actual.map(\.entityIdentity) == eager.map(\.entityIdentity))
      #expect(actual.map(\.entityStructuralPath) == eager.map(\.entityStructuralPath))
      #expect(actual.count == (header ? 10 : 9))
      // Three logical rows yield four fragments; logical count differs.
      #expect(source.count == (header ? 9 : 8))
      #expect(Set(actual.map(\.identity)).count == actual.count)
    }
  }

  @Test("selection and identity survive changes in preceding segment cardinality")
  func membershipAndSelection() throws {
    @ViewBuilder func content(_ ids: [Int], header: Bool) -> some View {
      if header { Text("header") }
      ForEach(ids, id: \.self) { Text("a \($0)") }
      ForEach([700, 700, 900], id: \.self) { Text("b \($0)") }
    }
    let context = ResolveContext(identity: testIdentity("ProofMembership"))
    IndexedChildRealizationProbe.reset()
    let before = makeCompositionalIndexedChildSource(
      from: content([1, 2], header: false), in: context, kindName: "ProofStack")
    let after = makeCompositionalIndexedChildSource(
      from: content([0, 1, 2, 3], header: true), in: context, kindName: "ProofStack")
    let tag = SelectionTag(value: 700)
    let first = try #require(before.elementIndex(forSelectionTag: tag))
    let second = try #require(after.elementIndex(forSelectionTag: tag))
    #expect(first == 2)
    #expect(second == 5)
    #expect(before.elementIdentity(at: first) == after.elementIdentity(at: second))
    #expect(before.elementIdentity(at: first + 1) == after.elementIdentity(at: second + 1))
    #expect(before.elementIdentity(at: first) != before.elementIdentity(at: first + 1))
    #expect(before.measurementSignature != after.measurementSignature)
    #expect(IndexedChildRealizationProbe.realizedChildCount == 0)
  }

  @Test("live row state and task survive preceding segment changes and retire on removal")
  func liveStateAndTasks() async throws {
    let probe = CompositionTaskProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ProofLive"), size: .init(width: 60, height: 20)
    ) { CompositionLiveFixture(probe: probe) }
    defer { harness.shutdown() }
    try await waitForComposition { probe.starts == 1 }
    _ = try harness.clickText("Retained 0")
    #expect(harness.frame.contains("Retained 1"))
    let identity = try harness.focusIdentity(forText: "Retained")
    let prefixPoint = harness.point(forText: "prefix 100")
    _ = try harness.clickText("Change prefix")
    #expect(harness.point(forText: "prefix 100") == prefixPoint)
    #expect(harness.frame.contains("Retained 1"))
    #expect(try harness.focusIdentity(forText: "Retained") == identity)
    #expect(probe.starts == 1)
    #expect(probe.cancellations == 0)
    _ = try harness.clickText("Toggle content")
    try await waitForComposition { probe.cancellations == 1 }
    #expect(harness.activeTaskCount == 0)
    #expect(!harness.frame.contains("Retained"))
    _ = try harness.clickText("Toggle content")
    try await waitForComposition { probe.starts == 2 }
    #expect(harness.frame.contains("Retained 0"))
    _ = try harness.clickText("Toggle content")
    try await waitForComposition { probe.cancellations == 2 }
    #expect(harness.activeTaskCount == 0)
  }
  @Test("composite detached row owners retire, and a retained source does not retain the graph")
  func teardown() throws {
    let probe = CompositionLifetimeProbe()
    retainThenReleaseRenderer(probe)
    #expect(probe.graph == nil)
    #expect(probe.owner == nil)
    #expect(probe.source != nil)
    probe.source = nil
  }

  private func retainThenReleaseRenderer(_ probe: CompositionLifetimeProbe) {
    let renderer = DefaultRenderer()
    probe.graph = renderer.viewGraph
    let context = ResolveContext(identity: testIdentity("CompositionLifetime"))
    let snapshot = renderer.render(
      ScrollView {
        LazyVStack {
          Text("header")
          ForEach(0..<1000) { index in CompositionLifetimeRow(index: index, probe: probe) }
        }
      }, context: context, proposal: .init(width: 80, height: 24))
    var pending = [snapshot.resolvedTree]
    while let node = pending.popLast() {
      if let source = node.indexedChildSource {
        probe.source = source
        break
      }
      pending.append(contentsOf: node.children)
    }
    #expect(probe.owner != nil)
    _ = renderer.render(Text("removed"), context: context, proposal: .init(width: 80, height: 24))
    #expect(probe.owner.flatMap { renderer.viewGraph.nodeForViewNodeID($0.viewNodeID) } == nil)
  }

}
@MainActor
private final class CompositionTaskProbe {
  var starts = 0
  var cancellations = 0
}

private struct CompositionLiveFixture: View {
  @State private var expanded = false
  @State private var shown = true
  let probe: CompositionTaskProbe

  var body: some View {
    VStack(spacing: 0) {
      Button("Change prefix") { expanded.toggle() }
      Button("Toggle content") { shown.toggle() }
      if shown {
        ScrollView {
          LazyVStack {
            if expanded { Text("header") }
            ForEach(expanded ? [100, 101] : [100], id: \.self) { Text("prefix \($0)") }
            ForEach([700], id: \.self) { _ in CompositionStatefulRow(probe: probe) }
            ForEach(0..<1000) { Text("tail \($0)") }
          }
        }
      }
    }
  }
}

private struct CompositionStatefulRow: View {
  @State private var count = 0
  let probe: CompositionTaskProbe

  var body: some View {
    Button("Retained \(count)") { count += 1 }
      .task {
        probe.starts += 1
        await suspendUntilCancelled()
        if Task.isCancelled { probe.cancellations += 1 }
      }
  }
}

@MainActor
private func waitForComposition(_ condition: () -> Bool) async throws {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: .seconds(3))
  while !condition(), clock.now < deadline { await Task.yield() }
  try #require(condition())
}

@MainActor
private final class CompositionLifetimeProbe {
  weak var graph: ViewGraph?
  weak var owner: SwiftTUICore.ViewNode?
  var source: (any IndexedChildSource)?
}

private struct CompositionLifetimeRow: View {
  var index: Int
  let probe: CompositionLifetimeProbe
  var body: some View {
    let _ = capture()
    Text("row \(index)")
  }
  private func capture() {
    if index == 0 { probe.owner = ViewNodeContext.current }
  }
}
