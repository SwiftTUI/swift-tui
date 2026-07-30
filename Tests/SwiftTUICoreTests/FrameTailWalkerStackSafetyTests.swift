import Foundation
import Synchronization
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph

/// D72: every tree walker reachable from the fused frame tail completes on a
/// worker-sized stack.
///
/// The tail runs on plain `DispatchQueue` workers, whose threads carry the
/// small default Dispatch stack, and on WASI it runs synchronously on the
/// caller (ADR-0020). Two stack overflows already landed point fixes here —
/// `isEquivalentForMeasurement` became a heap-backed loop (45ffdc44) and
/// `MeasurementWorkItem` became `indirect` (0ed2028f) — but the same retained
/// layout path kept calling *sibling* recursive walkers over the same deep
/// subtree shapes. Each one re-opened the crash class until it individually
/// overflowed: release-only, input-shape-dependent, no attribution.
///
/// These reductions run each converted walker on a deliberately small stack
/// over a deep chain shaped like a node-hosted collection row subtree. Under
/// the pre-change recursive implementations they overflow and take the process
/// down; a crash cannot be expressed as a red test, so the red-first evidence
/// is recorded in the landing commit instead and these run green here.
@Suite("Frame-tail walker stack safety", .serialized)
struct FrameTailWalkerStackSafetyTests {
  /// Matches the Dispatch worker stack class the frame tail actually runs on.
  private static let workerStackSize = 512 << 10

  /// Deep enough that every converted walker's recursive form exceeds
  /// ``workerStackSize`` — 64 B per frame would already overflow at this depth,
  /// and these walkers' frames are far larger than that.
  ///
  /// This depth was once *also* capped from above: releasing the fixtures
  /// recursed one frame group per level, so a chain past ~1104 `ResolvedNode`
  /// levels took the process down on this stack before any walker ran. That
  /// ceiling is lifted — see ``DeepTreeTeardownTests`` — so the number here is
  /// now chosen purely by the property under test.
  private static let deepChainDepth = 512

  // MARK: - Running work on a worker-sized stack

  /// Runs `body` on a freshly spawned thread with an explicit stack size and
  /// awaits its completion, so a walker that still recurses overflows *here*
  /// rather than deep inside a release-only frame-tail run.
  ///
  /// `Thread` rather than raw `pthread`: setting `stackSize` is the whole
  /// requirement, and it keeps the suite free of the concurrency and
  /// memory-safety escape hatches the repo policy check forbids, on Linux as
  /// well as Darwin. The wait is a direct signal — the thread resumes the
  /// continuation when it finishes — rather than a timeout or a poll.
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

  /// A single-child chain of `depth` nodes, the shape a node-hosted collection
  /// row subtree or a deep custom-layout chain produces.
  private func deepResolvedChain(
    depth: Int,
    leafLabel: String = "leaf",
    divergeMetadataAtDepth: Int? = nil
  ) -> ResolvedNode {
    var node = ResolvedNode(
      identity: testIdentity("deep", leafLabel),
      kind: .view("Leaf")
    )
    for index in stride(from: depth - 1, through: 0, by: -1) {
      var semanticMetadata = SemanticMetadata()
      if index == divergeMetadataAtDepth {
        semanticMetadata.accessibilityLabel = "diverged"
      }
      node = ResolvedNode(
        identity: testIdentity("deep", "\(index)"),
        kind: .view("Container"),
        children: [node],
        semanticMetadata: semanticMetadata
      )
    }
    return node
  }

  private func deepMeasuredChain(depth: Int, leafWidth: Int = 1) -> MeasuredNode {
    var node = MeasuredNode(
      identity: testIdentity("deep", "leaf"),
      proposal: .init(width: .finite(leafWidth), height: .finite(1)),
      measuredSize: .init(width: leafWidth, height: 1)
    )
    for index in stride(from: depth - 1, through: 0, by: -1) {
      node = MeasuredNode(
        identity: testIdentity("deep", "\(index)"),
        proposal: .init(width: .finite(1), height: .finite(1)),
        measuredSize: .init(width: 1, height: 1),
        childMeasurements: [node]
      )
    }
    return node
  }

  private func deepPlacedChain(depth: Int) -> PlacedNode {
    var node = PlacedNode(
      identity: testIdentity("deep", "leaf"),
      kind: .view("Leaf"),
      bounds: .init(origin: .zero, size: .init(width: 1, height: 1)),
      drawPayload: .text("A")
    )
    for index in stride(from: depth - 1, through: 0, by: -1) {
      node = PlacedNode(
        identity: testIdentity("deep", "\(index)"),
        kind: .view("Container"),
        bounds: .init(origin: .zero, size: .init(width: 1, height: 1)),
        children: [node]
      )
    }
    return node
  }

  // MARK: - Reductions, one per converted walker

  @Test("isEquivalentForPlacement completes on a worker-sized stack")
  func placementEquivalencePredicateIsStackSafe() async {
    let lhs = deepResolvedChain(depth: Self.deepChainDepth)
    let rhs = deepResolvedChain(depth: Self.deepChainDepth)
    let verdict = Mutex<Bool?>(nil)

    await runOnSmallStack { verdict.withLock { $0 = lhs.isEquivalentForPlacement(to: rhs) } }

    #expect(verdict.withLock { $0 } == true)
  }

  @Test("placementEquivalence completes on a worker-sized stack and reports identical")
  func placementEquivalenceIsStackSafe() async {
    let lhs = deepResolvedChain(depth: Self.deepChainDepth)
    let rhs = deepResolvedChain(depth: Self.deepChainDepth)
    let verdict = Mutex<ResolvedNode.PlacementEquivalence?>(nil)

    await runOnSmallStack { verdict.withLock { $0 = lhs.placementEquivalence(to: rhs) } }

    #expect(verdict.withLock { $0 } == .identical)
  }

  @Test("placementEquivalence reports geometryReusable for a deep metadata-only divergence")
  func placementEquivalenceReportsGeometryReusableAtDepth() async {
    // The tri-state fold is the one non-mechanical conversion: the recursion
    // merged verdicts on the way back up, the loop folds globally. A metadata
    // divergence buried deep in the chain must still poison the root verdict.
    let lhs = deepResolvedChain(depth: Self.deepChainDepth)
    let rhs = deepResolvedChain(
      depth: Self.deepChainDepth,
      divergeMetadataAtDepth: Self.deepChainDepth - 2
    )
    let verdict = Mutex<ResolvedNode.PlacementEquivalence?>(nil)

    await runOnSmallStack { verdict.withLock { $0 = lhs.placementEquivalence(to: rhs) } }

    #expect(verdict.withLock { $0 } == .geometryReusable)
  }

  @Test("placementEquivalence reports divergent for a deep geometry divergence")
  func placementEquivalenceReportsDivergentAtDepth() async {
    let lhs = deepResolvedChain(depth: Self.deepChainDepth)
    let rhs = deepResolvedChain(depth: Self.deepChainDepth, leafLabel: "other-leaf")
    let verdict = Mutex<ResolvedNode.PlacementEquivalence?>(nil)

    await runOnSmallStack { verdict.withLock { $0 = lhs.placementEquivalence(to: rhs) } }

    #expect(verdict.withLock { $0 } == .divergent)
  }

  @Test("memoReuseEquivalent completes on a worker-sized stack")
  func memoReuseEquivalentIsStackSafe() async {
    let lhs = deepResolvedChain(depth: Self.deepChainDepth)
    let rhs = deepResolvedChain(depth: Self.deepChainDepth)
    let verdict = Mutex<Bool?>(nil)

    await runOnSmallStack { verdict.withLock { $0 = lhs.memoReuseEquivalent(to: rhs) } }

    #expect(verdict.withLock { $0 } == true)
  }

  @Test("memoUnsoundContentDivergence completes on a worker-sized stack and keeps its path")
  func memoDivergenceDiagnosticsAreStackSafe() async {
    let depth = 64
    let lhs = deepResolvedChain(depth: depth)
    let rhs = deepResolvedChain(depth: depth, divergeMetadataAtDepth: 3)
    let field = Mutex<String??>(nil)

    await runOnSmallStack { field.withLock { $0 = lhs.memoUnsoundContentDivergence(from: rhs) } }

    // The probe histogram keys on this string, so the prefix depth must be
    // exactly the recursion's: three `child.` hops to the node at depth 3.
    #expect(field.withLock { $0 } == "child.child.child.semanticMetadata")

    let deepLhs = deepResolvedChain(depth: Self.deepChainDepth)
    let deepRhs = deepResolvedChain(depth: Self.deepChainDepth)
    let clean = Mutex<String??>(nil)
    await runOnSmallStack {
      clean.withLock { $0 = deepLhs.memoUnsoundContentDivergence(from: deepRhs) }
    }
    #expect(clean.withLock { $0 } == String?.none)
  }

  @Test("memoFirstDifferingField completes on a worker-sized stack")
  func memoFirstDifferingFieldIsStackSafe() async {
    let lhs = deepResolvedChain(depth: Self.deepChainDepth)
    let rhs = deepResolvedChain(depth: Self.deepChainDepth)
    let field = Mutex<String??>(nil)

    await runOnSmallStack { field.withLock { $0 = lhs.memoFirstDifferingField(from: rhs) } }

    #expect(field.withLock { $0 } == String?.none)
  }

  @Test("ResolvedNode == completes on a worker-sized stack")
  func resolvedNodeEqualityIsStackSafe() async {
    let lhs = deepResolvedChain(depth: Self.deepChainDepth)
    let rhs = deepResolvedChain(depth: Self.deepChainDepth)
    let verdict = Mutex<Bool?>(nil)

    await runOnSmallStack { verdict.withLock { $0 = (lhs == rhs) } }

    #expect(verdict.withLock { $0 } == true)
  }

  @Test("MeasuredNode == completes on a worker-sized stack")
  func measuredNodeEqualityIsStackSafe() async {
    let lhs = deepMeasuredChain(depth: Self.deepChainDepth)
    let rhs = deepMeasuredChain(depth: Self.deepChainDepth)
    let equal = Mutex<Bool?>(nil)
    let unequal = Mutex<Bool?>(nil)

    await runOnSmallStack { equal.withLock { $0 = (lhs == rhs) } }
    #expect(equal.withLock { $0 } == true)

    // The deep inequality must be found too, not short-circuited at the root.
    let differing = deepMeasuredChain(depth: Self.deepChainDepth, leafWidth: 2)
    await runOnSmallStack { unequal.withLock { $0 = (lhs == differing) } }
    #expect(unequal.withLock { $0 } == false)
  }

  @Test("PlacedNode == completes on a worker-sized stack")
  func placedNodeEqualityIsStackSafe() async {
    let lhs = deepPlacedChain(depth: Self.deepChainDepth)
    let rhs = deepPlacedChain(depth: Self.deepChainDepth)
    let verdict = Mutex<Bool?>(nil)

    await runOnSmallStack { verdict.withLock { $0 = (lhs == rhs) } }

    #expect(verdict.withLock { $0 } == true)
  }

  @Test("isEquivalentForViewportTranslation completes on a worker-sized stack")
  func viewportTranslationEquivalenceIsStackSafe() async {
    let engine = LayoutEngine()
    let lhs = deepMeasuredChain(depth: Self.deepChainDepth)
    let rhs = deepMeasuredChain(depth: Self.deepChainDepth)
    let verdict = Mutex<Bool?>(nil)

    await runOnSmallStack {
      verdict.withLock { $0 = engine.isEquivalentForViewportTranslation(lhs, rhs) }
    }

    #expect(verdict.withLock { $0 } == true)
  }

  @Test("translatedPlacement completes on a worker-sized stack and translates every node")
  func translatedPlacementIsStackSafe() async {
    let engine = LayoutEngine()
    let tree = deepPlacedChain(depth: Self.deepChainDepth)
    let translated = Mutex<PlacedNode?>(nil)
    let delta = CellPoint(x: 3, y: 7)

    await runOnSmallStack {
      translated.withLock { $0 = engine.translatedPlacement(tree, by: delta) }
    }

    let result = translated.withLock { $0 }
    #expect(result?.bounds.origin == delta)
    // Every descendant moved, not just the root: walk down iteratively and
    // check the leaf, which the rebuild reaches last.
    var node = result
    var visited = 0
    while let current = node, let child = current.children.first {
      #expect(child.bounds.origin == delta, "child at depth \(visited)")
      node = child
      visited += 1
    }
    #expect(visited == Self.deepChainDepth)
  }

  @Test("synchronizeRetainedPhaseMetadata completes on a worker-sized stack")
  func retainedMetadataSyncIsStackSafe() async {
    let engine = LayoutEngine()
    let placed = deepPlacedChain(depth: Self.deepChainDepth)
    let resolved = deepResolvedChain(
      depth: Self.deepChainDepth,
      divergeMetadataAtDepth: Self.deepChainDepth - 2
    )
    let synced = Mutex<PlacedNode?>(nil)

    await runOnSmallStack {
      synced.withLock {
        $0 = engine.synchronizeRetainedPhaseMetadata(placed: placed, from: resolved)
      }
    }

    // The rebuilt tree keeps its depth and carries the resolved metadata down
    // to the node that diverged.
    var node = synced.withLock { $0 }
    var depth = 0
    var sawDivergedLabel = false
    while let current = node {
      if current.semanticMetadata.accessibilityLabel == "diverged" {
        sawDivergedLabel = true
      }
      guard let child = current.children.first else { break }
      node = child
      depth += 1
    }
    #expect(depth == Self.deepChainDepth)
    #expect(sawDivergedLabel)
  }
}
