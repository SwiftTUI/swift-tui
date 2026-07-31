import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph

/// Deep value trees are released recursively by the compiler's own value
/// witnesses: destroying the root releases its child array, whose storage
/// `deinit` destroys each element, each of which releases *its* child array.
/// No walker, comparator, or engine code appears in the trace, so a tree deeper
/// than the thread's stack allows dies with `SIGBUS` attributed to nothing.
///
/// Measured on macOS/arm64 (debug) at 128 KiB / 512 KiB / 1 MiB stacks, the
/// cost is linear in depth and specific to each node type's inline size:
/// `ResolvedNode` ~475 B/level (max depth ~1104 at the 512 KiB Dispatch worker
/// stack the frame tail runs on); `MeasuredNode`, `PlacedNode`, and `DrawNode`
/// ~267 B/level (~1968 — the per-level cost floors at the array-storage destroy
/// frames, which is why `DrawNode`'s smaller 248 B inline size lands in the
/// same bracket). ``DeeplyNestedValueTree/flattenForRelease()`` converts the
/// release into a heap worklist; the same probe then completed at depth
/// 197,632 on the same 512 KiB stack without overflowing at all.
///
/// The reductions run as exit tests: the drain happens in a child process, so
/// a regression that reintroduces recursive teardown reds the one test with a
/// `.signal(SIGBUS)` mismatch instead of taking the whole runner down. The
/// red-first evidence for each reduction is recorded in the landing commits —
/// with `flattenForRelease()` stubbed to return, all four take the child down
/// with SIGBUS.
@Suite("Deep tree teardown", .serialized)
struct DeepTreeTeardownTests {
  /// Inline-size budgets for the four phase-product node types.
  ///
  /// Teardown stack cost per level scales with the node's inline size — that is
  /// why ``PlacedNode/_boxedLayoutBehavior`` is boxed rather than stored flat,
  /// and it is the whole reason these types have a size budget at all. The
  /// numbers are the measured sizes on macOS/arm64 plus ~15% headroom for
  /// cross-platform layout differences: they exist to red on the class of
  /// change that silently eats the teardown margin (inlining a large enum
  /// payload costs ~1.6 kB per node), not to freeze the layout.
  ///
  /// If one of these reds, re-run the teardown characterisation before raising
  /// it — the budget is downstream of a measurement, not a style rule.
  private static let resolvedNodeSizeBudget = 1536
  private static let measuredNodeSizeBudget = 448
  private static let placedNodeSizeBudget = 640
  private static let drawNodeSizeBudget = 288

  // MARK: - Reductions, one per phase-product node type
  //
  // Exit-test bodies must be capture-free (they run in a fresh child process),
  // so each body calls a file-scope helper; fixtures and depths are file-scope
  // for the same reason.

  @Test("a resolved chain far past the natural bound tears down on a worker stack")
  func resolvedChainTearsDownOnWorkerStack() async {
    await #expect(processExitsWith: .success) {
      await drainResolvedChainOnWorkerStack()
    }
  }

  @Test("a measured chain far past the natural bound tears down on a worker stack")
  func measuredChainTearsDownOnWorkerStack() async {
    await #expect(processExitsWith: .success) {
      await drainMeasuredChainOnWorkerStack()
    }
  }

  @Test("a placed chain far past the natural bound tears down on a worker stack")
  func placedChainTearsDownOnWorkerStack() async {
    await #expect(processExitsWith: .success) {
      await drainPlacedChainOnWorkerStack()
    }
  }

  @Test("a draw chain far past the natural bound tears down on a worker stack")
  func drawChainTearsDownOnWorkerStack() async {
    await #expect(processExitsWith: .success) {
      await drainDrawChainOnWorkerStack()
    }
  }

  // MARK: - Drain semantics

  @Test("flattening leaves the value childless")
  func flatteningLeavesValueChildless() {
    var resolved = teardownResolvedChain(depth: 32)
    var measured = teardownMeasuredChain(depth: 32)
    var placed = teardownPlacedChain(depth: 32)
    var draw = teardownDrawChain(depth: 32)

    resolved.flattenForRelease()
    measured.flattenForRelease()
    placed.flattenForRelease()
    draw.flattenForRelease()

    #expect(resolved.children.isEmpty)
    #expect(measured.childMeasurements.isEmpty)
    #expect(placed.children.isEmpty)
    #expect(draw.children.isEmpty)
  }

  /// The drain only ever *replaces* a child array wholesale, never mutates one
  /// in place, so a subtree shared with a live tree is neither copied nor
  /// emptied. This is what makes the primitive safe to call on a value whose
  /// children came from a retained-reuse path — and it is the reason the doc
  /// comment insists callers flatten the value holding the last reference
  /// rather than a copy.
  @Test("flattening one copy leaves a sharing sibling intact")
  func flatteningDoesNotDisturbSharingSibling() {
    var flattened = teardownResolvedChain(depth: 16)
    let retained = flattened

    flattened.flattenForRelease()

    #expect(flattened.children.isEmpty)
    #expect(retained.subtreeNodeCount == 17)
    var depth = 0
    var cursor: ResolvedNode? = retained
    while let node = cursor {
      depth += 1
      cursor = node.children.first
    }
    #expect(depth == 17)
  }

  // MARK: - Size budgets

  @Test("phase-product node sizes stay inside the teardown budget")
  func phaseProductNodeSizesStayInsideTeardownBudget() {
    #expect(MemoryLayout<ResolvedNode>.size <= Self.resolvedNodeSizeBudget)
    #expect(MemoryLayout<MeasuredNode>.size <= Self.measuredNodeSizeBudget)
    #expect(MemoryLayout<PlacedNode>.size <= Self.placedNodeSizeBudget)
    #expect(MemoryLayout<DrawNode>.size <= Self.drawNodeSizeBudget)
  }
}

// MARK: - File-scope reduction support (exit-test bodies must be capture-free)

/// The Dispatch worker stack class the frame tail actually runs on, matching
/// ``FrameTailWalkerStackSafetyTests``.
private let teardownWorkerStackSize = 512 << 10

/// Comfortably past every measured natural-teardown bound (the deepest is
/// ~1968), so these reductions fail without the flatten regardless of which
/// node type regresses.
private let teardownDeepChainDepth = 8192

/// Runs `body` on a freshly spawned thread with an explicit stack size, so a
/// teardown that still recurses overflows *there* — inside the exit test's
/// child process — rather than deep inside a release-only frame-tail run.
/// `Thread` rather than raw `pthread`: setting `stackSize` is the whole
/// requirement, and it keeps the suite free of the escape hatches the repo
/// policy check forbids, on Linux as well as Darwin.
private func runOnWorkerSizedStack(
  _ body: @escaping @Sendable () -> Void
) async {
  await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
    let thread = Thread {
      body()
      continuation.resume()
    }
    thread.stackSize = teardownWorkerStackSize
    thread.start()
  }
}

private func drainResolvedChainOnWorkerStack() async {
  await runOnWorkerSizedStack {
    var tree = teardownResolvedChain(depth: teardownDeepChainDepth)
    tree.flattenForRelease()
  }
}

private func drainMeasuredChainOnWorkerStack() async {
  await runOnWorkerSizedStack {
    var tree = teardownMeasuredChain(depth: teardownDeepChainDepth)
    tree.flattenForRelease()
  }
}

private func drainPlacedChainOnWorkerStack() async {
  await runOnWorkerSizedStack {
    var tree = teardownPlacedChain(depth: teardownDeepChainDepth)
    tree.flattenForRelease()
  }
}

private func drainDrawChainOnWorkerStack() async {
  await runOnWorkerSizedStack {
    var tree = teardownDrawChain(depth: teardownDeepChainDepth)
    tree.flattenForRelease()
  }
}

// MARK: - File-scope fixtures

private func teardownResolvedChain(depth: Int) -> ResolvedNode {
  var node = ResolvedNode(identity: testIdentity("teardown", "leaf"), kind: .view("Leaf"))
  for index in stride(from: depth - 1, through: 0, by: -1) {
    node = ResolvedNode(
      identity: testIdentity("teardown", "\(index)"),
      kind: .view("Container"),
      children: [node]
    )
  }
  return node
}

private func teardownMeasuredChain(depth: Int) -> MeasuredNode {
  var node = MeasuredNode(
    identity: testIdentity("teardown", "leaf"),
    proposal: .init(width: .finite(1), height: .finite(1)),
    measuredSize: .init(width: 1, height: 1)
  )
  for index in stride(from: depth - 1, through: 0, by: -1) {
    node = MeasuredNode(
      identity: testIdentity("teardown", "\(index)"),
      proposal: .init(width: .finite(1), height: .finite(1)),
      measuredSize: .init(width: 1, height: 1),
      childMeasurements: [node]
    )
  }
  return node
}

private func teardownPlacedChain(depth: Int) -> PlacedNode {
  var node = PlacedNode(
    identity: testIdentity("teardown", "leaf"),
    kind: .view("Leaf"),
    bounds: .init(origin: .zero, size: .init(width: 1, height: 1)),
    drawPayload: .text("A")
  )
  for index in stride(from: depth - 1, through: 0, by: -1) {
    node = PlacedNode(
      identity: testIdentity("teardown", "\(index)"),
      kind: .view("Container"),
      bounds: .init(origin: .zero, size: .init(width: 1, height: 1)),
      children: [node]
    )
  }
  return node
}

private func teardownDrawChain(depth: Int) -> DrawNode {
  var node = DrawNode(
    identity: testIdentity("teardown", "leaf"),
    bounds: .init(origin: .zero, size: .init(width: 1, height: 1))
  )
  for index in stride(from: depth - 1, through: 0, by: -1) {
    node = DrawNode(
      identity: testIdentity("teardown", "\(index)"),
      bounds: .init(origin: .zero, size: .init(width: 1, height: 1)),
      children: [node]
    )
  }
  return node
}
