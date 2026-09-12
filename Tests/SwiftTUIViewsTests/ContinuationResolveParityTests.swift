import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

/// State, identity, preferences and lifecycle parity across explicit continuations.
@MainActor
struct ContinuationResolveParityTests {
  // MARK: - Harness

  private func makeContext(
    _ graph: ViewGraph,
    identity: Identity
  ) -> ResolveContext {
    var context = ResolveContext(
      identity: identity,
      environmentValues: .init(),
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    return context
  }

  /// Resolves `view` for one frame, finalizes the frame (committed-presence
  /// latching, teardown barrier, lifecycle plan), and returns the committed
  /// root snapshot.
  private func resolveFrame<V: View>(
    _ view: V,
    graph: ViewGraph,
    rootIdentity: Identity
  ) -> ResolvedNode {
    graph.beginFrame()
    _ = Resolver().resolve(view, in: makeContext(graph, identity: rootIdentity))
    let resolved = graph.snapshot(rootIdentity: rootIdentity)
    _ = graph.finalizeFrame(
      rootIdentity: rootIdentity,
      resolved: resolved,
      placed: nil
    )
    return resolved
  }

  /// Type-erased nesting: wraps `leaf` in `levels` single-child VStacks so
  /// the runtime nesting crosses many continuation boundaries.
  private func nested(_ levels: Int, leaf: some View) -> AnyView {
    var current = AnyView(leaf)
    for _ in 0..<levels {
      let wrapped = current
      current = AnyView(VStack { wrapped })
    }
    return current
  }

  /// Structural projection that ignores per-graph bookkeeping (node IDs mint
  /// independently in different graphs) but pins identity, kind, entity
  /// identity + occurrence, and tree shape.
  private func structuralDescription(
    _ node: ResolvedNode,
    indent: String = ""
  ) -> String {
    var line = "\(indent)\(node.identity.path) kind=\(node.kind)"
    if let entity = node.entityIdentity {
      line += " entity=\(entity.value) occ=\(entity.occurrence)"
      line += " esp=\(node.entityStructuralPath?.description ?? "nil")"
      line += " sp=\(node.structuralPath.description)"
    }
    var lines = [line]
    for child in node.children {
      lines.append(structuralDescription(child, indent: indent + "  "))
    }
    return lines.joined(separator: "\n")
  }

  private func containsKind(
    _ node: ResolvedNode,
    named name: String
  ) -> Bool {
    if node.kind == .view(name) {
      return true
    }
    return node.children.contains { containsKind($0, named: name) }
  }

  // MARK: - First-sight parity

  @Test("a first-sight independent resolve commits the baseline structure")
  func firstSightIndependentMatchesUnindependentStructure() {
    let rootIdentity = testIdentity("Root")
    let view = nested(
      8,
      leaf: HStack {
        Text("left")
        Text("right")
      }
    )

    let baselineGraph = ViewGraph()
    let baseline = resolveFrame(view, graph: baselineGraph, rootIdentity: rootIdentity)

    let independentGraph = ViewGraph()
    let independent = resolveFrame(view, graph: independentGraph, rootIdentity: rootIdentity)

    #expect(
      structuralDescription(independent) == structuralDescription(baseline)
    )
    #expect(
      !containsKind(independent, named: "DeferredResolvePlaceholder"),
      "a placeholder leaked past the drain into the committed tree"
    )
  }

  // MARK: - Steady-state parity

  @Test("a independent second frame recommits the baseline first frame byte-for-byte")
  func steadyStateIndependentFrameMatchesUnindependentCommit() {
    let rootIdentity = testIdentity("Root")
    let view = nested(
      8,
      leaf: VStack {
        Text("stable")
        Text("content")
      }
    )

    let graph = ViewGraph()
    let first = resolveFrame(view, graph: graph, rootIdentity: rootIdentity)

    let second = resolveFrame(view, graph: graph, rootIdentity: rootIdentity)

    #expect(
      structuralDescription(second) == structuralDescription(first)
    )
  }

  // MARK: - Preference bubbling across continuations

  @Test("toolbar-item preferences authored across continuations bubble to the root")
  func toolbarPreferencesBubbleAcrossTheCut() {
    let rootIdentity = testIdentity("Root")
    let view = nested(
      6,
      leaf: Text("content").toolbarItem(
        ToolbarItemConfig(title: "Deep") {}
      )
    )

    let baselineGraph = ViewGraph()
    let baseline = resolveFrame(view, graph: baselineGraph, rootIdentity: rootIdentity)
    let baselineItems = baseline.preferenceValues[ToolbarItemsPreferenceKey.self]

    let independentGraph = ViewGraph()
    let independent = resolveFrame(view, graph: independentGraph, rootIdentity: rootIdentity)
    let independentItems = independent.preferenceValues[ToolbarItemsPreferenceKey.self]

    #expect(baselineItems.map(\.title) == ["Deep"])
    #expect(
      independentItems.map(\.title) == baselineItems.map(\.title),
      "child preferences did not propagate through their parent continuations"
    )
  }

  // MARK: - Lifecycle events across continuations

  @Test("appear and task events for subtrees across continuations match the baseline frame")
  func lifecycleEventsMatchAcrossTheCut() {
    let rootIdentity = testIdentity("Root")
    func probe() -> AnyView {
      nested(
        6,
        leaf: Text("alive")
          .onAppear {}
          .task {}
      )
    }

    let baselineGraph = ViewGraph()
    _ = resolveFrame(probe(), graph: baselineGraph, rootIdentity: rootIdentity)
    let baselineState = baselineGraph.debugTotalStateSnapshot()

    let independentGraph = ViewGraph()
    _ = resolveFrame(probe(), graph: independentGraph, rootIdentity: rootIdentity)
    let independentState = independentGraph.debugTotalStateSnapshot()

    #expect(
      independentState.structuralAppearEvents.map(\.identity)
        == baselineState.structuralAppearEvents.map(\.identity),
      "appear events dropped or reordered across the continuation boundary"
    )
    #expect(
      independentState.stableTaskStartEvents.map(\.identity)
        == baselineState.stableTaskStartEvents.map(\.identity)
    )
    #expect(
      independentState.stableTaskCancelEvents.isEmpty
        == baselineState.stableTaskCancelEvents.isEmpty
    )
  }

  @Test("a steady independent re-resolve emits no spurious task cancels or restarts")
  func steadyIndependentFrameKeepsTasksStable() {
    let rootIdentity = testIdentity("Root")
    let view = nested(6, leaf: Text("alive").task {})

    let graph = ViewGraph()
    _ = resolveFrame(view, graph: graph, rootIdentity: rootIdentity)

    _ = resolveFrame(view, graph: graph, rootIdentity: rootIdentity)
    let state = graph.debugTotalStateSnapshot()

    #expect(
      state.stableTaskCancelEvents.isEmpty,
      "a completed steady pass was diffed as a task change"
    )
    #expect(
      state.stableTaskStartEvents.isEmpty,
      "a steady frame restarted an already-running task across continuations"
    )
    #expect(state.structuralAppearEvents.isEmpty)
  }

  // MARK: - State across continuations and across boundary movement

  @MainActor
  private final class StateProbeBox {
    var binding: Binding<Int>?
    var snapshot: ImperativeAuthoringContextSnapshot?
    var lastSeenCount: Int?
  }

  private struct CountingLeaf: View {
    @State private var count = 0
    let captured: StateProbeBox

    var body: some View {
      captured.binding = $count
      captured.snapshot = currentImperativeAuthoringContextSnapshot()
      captured.lastSeenCount = count
      return Text("count=\(count)")
    }
  }

  @Test("state across continuations persists when the continuation boundary moves between frames")
  func statePersistsAcrossBoundaryMovement() throws {
    let rootIdentity = testIdentity("Root")
    let captured = StateProbeBox()
    let view = nested(6, leaf: CountingLeaf(captured: captured))

    let graph = ViewGraph()
    _ = resolveFrame(view, graph: graph, rootIdentity: rootIdentity)
    #expect(captured.lastSeenCount == 0)

    let binding = try #require(captured.binding)
    let snapshot = try #require(captured.snapshot)
    withImperativeAuthoringContext(snapshot) {
      binding.wrappedValue = 42
    }

    // A second completed pass must keep the same state owner.
    _ = resolveFrame(view, graph: graph, rootIdentity: rootIdentity)
    #expect(
      captured.lastSeenCount == 42,
      "the next resolve lost the state slot written between frames"
    )
  }

  // MARK: - Entity identity occurrences across continuations

  @Test("duplicate explicit-.id siblings keep distinct occurrences across continuations")
  func duplicateEntityOccurrencesSurviveTheCut() {
    let rootIdentity = testIdentity("Root")
    let view = nested(
      4,
      leaf: VStack {
        Text("first").id("dup")
        Text("second").id("dup")
      }
    )

    let baselineGraph = ViewGraph()
    let baseline = resolveFrame(view, graph: baselineGraph, rootIdentity: rootIdentity)

    let independentGraph = ViewGraph()
    let independent = resolveFrame(view, graph: independentGraph, rootIdentity: rootIdentity)

    #expect(
      structuralDescription(independent) == structuralDescription(baseline),
      "entity occurrence assignment diverged across the continuation boundary"
    )
  }

  // MARK: - Driver bookkeeping

  @Test("the driver is idle at every frame boundary")
  func driverIsIdleAtFrameBoundaries() {
    let rootIdentity = testIdentity("Root")
    let view = nested(8, leaf: Text("leaf"))

    let graph = ViewGraph()
    _ = resolveFrame(view, graph: graph, rootIdentity: rootIdentity)
    #expect(ResolveWorkDiagnostics.activeDrains == 0)

    _ = resolveFrame(view, graph: graph, rootIdentity: rootIdentity)
    #expect(ResolveWorkDiagnostics.activeDrains == 0)
  }

}
