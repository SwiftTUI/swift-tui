import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

/// The depth-capped worklist resolve (`DeferredResolveDriver`): a resolve
/// pass whose inline descent is capped at K levels must produce the same
/// committed graph as the unbounded recursion — the cut serves the node's
/// stale committed snapshot as a structural placeholder, the drain
/// re-resolves the subtree from a shallow stack, and the ancestor snapshot
/// rebuild splices the result. These tests force tiny caps on native so the
/// WASI-only production profile's mechanism is exercised by the repo gate.
@MainActor
struct DeferredResolveChunkingTests {
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
  /// the resolve descent is guaranteed deeper than any test cap.
  private func nested(_ levels: Int, leaf: some View) -> AnyView {
    var current = AnyView(leaf)
    for _ in 0..<levels {
      let wrapped = current
      current = AnyView(VStack { wrapped })
    }
    return current
  }

  /// Structural projection that ignores per-graph bookkeeping (node IDs mint
  /// in a different order under chunking) but pins identity, kind, entity
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

  @Test("a first-sight chunked resolve commits the unchunked structure")
  func firstSightChunkedMatchesUnchunkedStructure() {
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

    let chunkedGraph = ViewGraph()
    chunkedGraph.setDeferredResolveDepthLimitForTesting(2)
    let chunked = resolveFrame(view, graph: chunkedGraph, rootIdentity: rootIdentity)

    #expect(
      chunkedGraph.deferredResolveDriver.deferralCount > 0,
      "the cap never engaged — the fixture is shallower than the cut depth"
    )
    // Cuts only fire at structural child edges, so inline descent may
    // overshoot the cap by the deepest non-structural chain (here the
    // AnyView payload level) — but must stay far below the unbounded depth.
    #expect(
      chunkedGraph.deferredResolveDriver.maxDescentDepth
        < baselineGraph.deferredResolveDriver.maxDescentDepth / 2,
      """
      chunked inline depth \(chunkedGraph.deferredResolveDriver.maxDescentDepth) \
      is not meaningfully below the unbounded \
      \(baselineGraph.deferredResolveDriver.maxDescentDepth)
      """
    )
    #expect(
      structuralDescription(chunked) == structuralDescription(baseline)
    )
    #expect(
      !containsKind(chunked, named: "DeferredResolvePlaceholder"),
      "a placeholder leaked past the drain into the committed tree"
    )
  }

  // MARK: - Steady-state parity

  @Test("a chunked second frame recommits the unchunked first frame byte-for-byte")
  func steadyStateChunkedFrameMatchesUnchunkedCommit() {
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

    graph.setDeferredResolveDepthLimitForTesting(2)
    let second = resolveFrame(view, graph: graph, rootIdentity: rootIdentity)

    #expect(graph.deferredResolveDriver.deferralCount > 0)
    #expect(
      structuralDescription(second) == structuralDescription(first)
    )
  }

  // MARK: - Preference bubbling across the cut

  @Test("toolbar-item preferences authored below the cut bubble to the root")
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

    let chunkedGraph = ViewGraph()
    chunkedGraph.setDeferredResolveDepthLimitForTesting(2)
    let chunked = resolveFrame(view, graph: chunkedGraph, rootIdentity: rootIdentity)
    let chunkedItems = chunked.preferenceValues[ToolbarItemsPreferenceKey.self]

    #expect(chunkedGraph.deferredResolveDriver.deferralCount > 0)
    #expect(baselineItems.map(\.title) == ["Deep"])
    #expect(
      chunkedItems.map(\.title) == baselineItems.map(\.title),
      "the spliced subtree's preferences did not rebuild through the ancestor spine"
    )
  }

  // MARK: - Lifecycle events across the cut

  @Test("appear and task events for subtrees below the cut match the unchunked frame")
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

    let chunkedGraph = ViewGraph()
    chunkedGraph.setDeferredResolveDepthLimitForTesting(2)
    _ = resolveFrame(probe(), graph: chunkedGraph, rootIdentity: rootIdentity)
    let chunkedState = chunkedGraph.debugTotalStateSnapshot()

    #expect(chunkedGraph.deferredResolveDriver.deferralCount > 0)
    #expect(
      chunkedState.structuralAppearEvents.map(\.identity)
        == baselineState.structuralAppearEvents.map(\.identity),
      "appear events dropped or reordered across the chunk boundary"
    )
    #expect(
      chunkedState.stableTaskStartEvents.map(\.identity)
        == baselineState.stableTaskStartEvents.map(\.identity)
    )
    #expect(
      chunkedState.stableTaskCancelEvents.isEmpty
        == baselineState.stableTaskCancelEvents.isEmpty
    )
  }

  @Test("a steady chunked re-resolve emits no spurious task cancels or restarts")
  func steadyChunkedFrameKeepsTasksStable() {
    let rootIdentity = testIdentity("Root")
    let view = nested(6, leaf: Text("alive").task {})

    let graph = ViewGraph()
    _ = resolveFrame(view, graph: graph, rootIdentity: rootIdentity)

    graph.setDeferredResolveDepthLimitForTesting(2)
    _ = resolveFrame(view, graph: graph, rootIdentity: rootIdentity)
    let state = graph.debugTotalStateSnapshot()

    #expect(graph.deferredResolveDriver.deferralCount > 0)
    #expect(
      state.stableTaskCancelEvents.isEmpty,
      "the cut's stale placeholder commit was diffed as a task change"
    )
    #expect(
      state.stableTaskStartEvents.isEmpty,
      "a steady frame restarted an already-running task across the cut"
    )
    #expect(state.structuralAppearEvents.isEmpty)
  }

  // MARK: - State across the cut and across boundary movement

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

  @Test("state below the cut persists when the chunk boundary moves between frames")
  func statePersistsAcrossBoundaryMovement() throws {
    let rootIdentity = testIdentity("Root")
    let captured = StateProbeBox()
    let view = nested(6, leaf: CountingLeaf(captured: captured))

    let graph = ViewGraph()
    graph.setDeferredResolveDepthLimitForTesting(3)
    _ = resolveFrame(view, graph: graph, rootIdentity: rootIdentity)
    #expect(graph.deferredResolveDriver.deferralCount > 0)
    #expect(captured.lastSeenCount == 0)

    let binding = try #require(captured.binding)
    let snapshot = try #require(captured.snapshot)
    withImperativeAuthoringContext(snapshot) {
      binding.wrappedValue = 42
    }

    // The boundary moves: the node that was a chunk root last frame resolves
    // inline this frame (and vice versa); its state slot must follow.
    graph.setDeferredResolveDepthLimitForTesting(2)
    _ = resolveFrame(view, graph: graph, rootIdentity: rootIdentity)
    #expect(
      captured.lastSeenCount == 42,
      "the deferred re-resolve lost the state slot written between frames"
    )
  }

  // MARK: - Entity identity occurrences across the cut

  @Test("duplicate explicit-.id siblings keep distinct occurrences across the cut")
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

    let chunkedGraph = ViewGraph()
    chunkedGraph.setDeferredResolveDepthLimitForTesting(2)
    let chunked = resolveFrame(view, graph: chunkedGraph, rootIdentity: rootIdentity)

    #expect(chunkedGraph.deferredResolveDriver.deferralCount > 0)
    #expect(
      structuralDescription(chunked) == structuralDescription(baseline),
      "entity occurrence assignment diverged across the chunk boundary"
    )
  }

  // MARK: - Driver bookkeeping

  @Test("the driver is idle at every frame boundary")
  func driverIsIdleAtFrameBoundaries() {
    let rootIdentity = testIdentity("Root")
    let view = nested(8, leaf: Text("leaf"))

    let graph = ViewGraph()
    graph.setDeferredResolveDepthLimitForTesting(2)
    _ = resolveFrame(view, graph: graph, rootIdentity: rootIdentity)
    #expect(graph.deferredResolveDriver.isIdle)

    _ = resolveFrame(view, graph: graph, rootIdentity: rootIdentity)
    #expect(graph.deferredResolveDriver.isIdle)
  }

  @Test("the native default leaves the driver disabled")
  func nativeDefaultDisablesTheDriver() {
    let graph = ViewGraph()
    #expect(graph.deferredResolveDriver.depthLimit == nil)

    let rootIdentity = testIdentity("Root")
    _ = resolveFrame(
      nested(8, leaf: Text("leaf")),
      graph: graph,
      rootIdentity: rootIdentity
    )
    #expect(graph.deferredResolveDriver.deferralCount == 0)
  }
}
