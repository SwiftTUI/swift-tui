import Foundation
import Synchronization
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
/// stack the frame tail runs on), `MeasuredNode` and `PlacedNode` ~267 B/level
/// (~1968). ``DeeplyNestedValueTree/flattenForRelease()`` converts the release
/// into a heap worklist; the same probe then completed at depth 197,632 on the
/// same 512 KiB stack for all three types without overflowing at all.
///
/// A crash cannot be expressed as a red test, so the red-first evidence for the
/// reductions below is recorded in the landing commit: at ``deepChainDepth``
/// each of them takes the process down without the flatten and passes with it.
@Suite("Deep tree teardown", .serialized)
struct DeepTreeTeardownTests {
  /// The Dispatch worker stack class the frame tail actually runs on, matching
  /// ``FrameTailWalkerStackSafetyTests``.
  private static let workerStackSize = 512 << 10

  /// Comfortably past every measured natural-teardown bound (the deepest is
  /// ~1968), so these reductions fail without the flatten regardless of which
  /// node type regresses.
  private static let deepChainDepth = 8192

  /// Inline-size budgets for the three phase-product node types.
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

  // MARK: - Running work on a worker-sized stack

  /// Runs `body` on a freshly spawned thread with an explicit stack size, so a
  /// teardown that still recurses overflows *here* rather than deep inside a
  /// release-only frame-tail run. `Thread` rather than raw `pthread`: setting
  /// `stackSize` is the whole requirement, and it keeps the suite free of the
  /// escape hatches the repo policy check forbids, on Linux as well as Darwin.
  private func runOnSmallStack(
    stackSize: Int = workerStackSize,
    _ body: @escaping @Sendable () -> Void
  ) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let thread = Thread {
        body()
        continuation.resume()
      }
      thread.stackSize = stackSize
      thread.start()
    }
  }

  // MARK: - Fixtures

  private static func resolvedChain(depth: Int) -> ResolvedNode {
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

  private static func measuredChain(depth: Int) -> MeasuredNode {
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

  private static func placedChain(depth: Int) -> PlacedNode {
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

  // MARK: - Reductions, one per phase-product node type

  @Test("a resolved chain far past the natural bound tears down on a worker stack")
  func resolvedChainTearsDownOnWorkerStack() async {
    let torndown = Mutex(false)

    await runOnSmallStack {
      var tree = Self.resolvedChain(depth: Self.deepChainDepth)
      tree.flattenForRelease()
      torndown.withLock { $0 = true }
    }

    #expect(torndown.withLock { $0 })
  }

  @Test("a measured chain far past the natural bound tears down on a worker stack")
  func measuredChainTearsDownOnWorkerStack() async {
    let torndown = Mutex(false)

    await runOnSmallStack {
      var tree = Self.measuredChain(depth: Self.deepChainDepth)
      tree.flattenForRelease()
      torndown.withLock { $0 = true }
    }

    #expect(torndown.withLock { $0 })
  }

  @Test("a placed chain far past the natural bound tears down on a worker stack")
  func placedChainTearsDownOnWorkerStack() async {
    let torndown = Mutex(false)

    await runOnSmallStack {
      var tree = Self.placedChain(depth: Self.deepChainDepth)
      tree.flattenForRelease()
      torndown.withLock { $0 = true }
    }

    #expect(torndown.withLock { $0 })
  }

  // MARK: - Drain semantics

  @Test("flattening leaves the value childless")
  func flatteningLeavesValueChildless() {
    var resolved = Self.resolvedChain(depth: 32)
    var measured = Self.measuredChain(depth: 32)
    var placed = Self.placedChain(depth: 32)

    resolved.flattenForRelease()
    measured.flattenForRelease()
    placed.flattenForRelease()

    #expect(resolved.children.isEmpty)
    #expect(measured.childMeasurements.isEmpty)
    #expect(placed.children.isEmpty)
  }

  /// The drain only ever *replaces* a child array wholesale, never mutates one
  /// in place, so a subtree shared with a live tree is neither copied nor
  /// emptied. This is what makes the primitive safe to call on a value whose
  /// children came from a retained-reuse path — and it is the reason the doc
  /// comment insists callers flatten the value holding the last reference
  /// rather than a copy.
  @Test("flattening one copy leaves a sharing sibling intact")
  func flatteningDoesNotDisturbSharingSibling() {
    var flattened = Self.resolvedChain(depth: 16)
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
  }
}
