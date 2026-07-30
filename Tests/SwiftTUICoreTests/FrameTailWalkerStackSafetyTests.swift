import Synchronization
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(Musl)
  import Musl
#endif

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
  private static let deepChainDepth = 512

  // MARK: - Running work on a worker-sized stack

  /// Runs `body` on a freshly spawned thread with an explicit stack size and
  /// waits for it, so a walker that still recurses overflows *here* rather than
  /// deep inside a release-only frame-tail run.
  ///
  /// `pthread` rather than `Thread` so the suite stays importable unchanged on
  /// Linux CI, where the test targets are the only place this is allowed.
  private func runOnSmallStack(
    stackSize: Int = workerStackSize,
    _ body: @escaping @Sendable () -> Void
  ) throws {
    final class Work: @unchecked Sendable {
      let body: @Sendable () -> Void
      init(body: @escaping @Sendable () -> Void) { self.body = body }
    }

    let work = Unmanaged.passRetained(Work(body: body)).toOpaque()

    var attributes = unsafe pthread_attr_t()
    guard unsafe pthread_attr_init(&attributes) == 0 else {
      Unmanaged<Work>.fromOpaque(work).release()
      throw StackSafetyReductionError.threadSetupFailed
    }
    defer { unsafe _ = pthread_attr_destroy(&attributes) }
    guard unsafe pthread_attr_setstacksize(&attributes, stackSize) == 0 else {
      Unmanaged<Work>.fromOpaque(work).release()
      throw StackSafetyReductionError.threadSetupFailed
    }

    #if canImport(Darwin)
      var thread: pthread_t?
    #else
      var thread = pthread_t()
    #endif

    let started = unsafe pthread_create(
      &thread,
      &attributes,
      { argument in
        let work = unsafe Unmanaged<Work>.fromOpaque(argument).takeRetainedValue()
        work.body()
        return nil
      },
      work
    )
    guard started == 0 else {
      Unmanaged<Work>.fromOpaque(work).release()
      throw StackSafetyReductionError.threadSetupFailed
    }

    #if canImport(Darwin)
      guard let thread else {
        throw StackSafetyReductionError.threadSetupFailed
      }
      unsafe _ = pthread_join(thread, nil)
    #else
      unsafe _ = pthread_join(thread, nil)
    #endif
  }

  private enum StackSafetyReductionError: Error {
    case threadSetupFailed
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
  func placementEquivalencePredicateIsStackSafe() throws {
    let lhs = deepResolvedChain(depth: Self.deepChainDepth)
    let rhs = deepResolvedChain(depth: Self.deepChainDepth)
    let verdict = Mutex<Bool?>(nil)

    try runOnSmallStack { verdict.withLock { $0 = lhs.isEquivalentForPlacement(to: rhs) } }

    #expect(verdict.withLock { $0 } == true)
  }

  @Test("placementEquivalence completes on a worker-sized stack and reports identical")
  func placementEquivalenceIsStackSafe() throws {
    let lhs = deepResolvedChain(depth: Self.deepChainDepth)
    let rhs = deepResolvedChain(depth: Self.deepChainDepth)
    let verdict = Mutex<ResolvedNode.PlacementEquivalence?>(nil)

    try runOnSmallStack { verdict.withLock { $0 = lhs.placementEquivalence(to: rhs) } }

    #expect(verdict.withLock { $0 } == .identical)
  }

  @Test("placementEquivalence reports geometryReusable for a deep metadata-only divergence")
  func placementEquivalenceReportsGeometryReusableAtDepth() throws {
    // The tri-state fold is the one non-mechanical conversion: the recursion
    // merged verdicts on the way back up, the loop folds globally. A metadata
    // divergence buried deep in the chain must still poison the root verdict.
    let lhs = deepResolvedChain(depth: Self.deepChainDepth)
    let rhs = deepResolvedChain(
      depth: Self.deepChainDepth,
      divergeMetadataAtDepth: Self.deepChainDepth - 2
    )
    let verdict = Mutex<ResolvedNode.PlacementEquivalence?>(nil)

    try runOnSmallStack { verdict.withLock { $0 = lhs.placementEquivalence(to: rhs) } }

    #expect(verdict.withLock { $0 } == .geometryReusable)
  }

  @Test("placementEquivalence reports divergent for a deep geometry divergence")
  func placementEquivalenceReportsDivergentAtDepth() throws {
    let lhs = deepResolvedChain(depth: Self.deepChainDepth)
    let rhs = deepResolvedChain(depth: Self.deepChainDepth, leafLabel: "other-leaf")
    let verdict = Mutex<ResolvedNode.PlacementEquivalence?>(nil)

    try runOnSmallStack { verdict.withLock { $0 = lhs.placementEquivalence(to: rhs) } }

    #expect(verdict.withLock { $0 } == .divergent)
  }

  @Test("memoReuseEquivalent completes on a worker-sized stack")
  func memoReuseEquivalentIsStackSafe() throws {
    let lhs = deepResolvedChain(depth: Self.deepChainDepth)
    let rhs = deepResolvedChain(depth: Self.deepChainDepth)
    let verdict = Mutex<Bool?>(nil)

    try runOnSmallStack { verdict.withLock { $0 = lhs.memoReuseEquivalent(to: rhs) } }

    #expect(verdict.withLock { $0 } == true)
  }

  @Test("memoUnsoundContentDivergence completes on a worker-sized stack and keeps its path")
  func memoDivergenceDiagnosticsAreStackSafe() throws {
    let depth = 64
    let lhs = deepResolvedChain(depth: depth)
    let rhs = deepResolvedChain(depth: depth, divergeMetadataAtDepth: 3)
    let field = Mutex<String??>(nil)

    try runOnSmallStack { field.withLock { $0 = lhs.memoUnsoundContentDivergence(from: rhs) } }

    // The probe histogram keys on this string, so the prefix depth must be
    // exactly the recursion's: three `child.` hops to the node at depth 3.
    #expect(field.withLock { $0 } == "child.child.child.semanticMetadata")

    let deepLhs = deepResolvedChain(depth: Self.deepChainDepth)
    let deepRhs = deepResolvedChain(depth: Self.deepChainDepth)
    let clean = Mutex<String??>(nil)
    try runOnSmallStack {
      clean.withLock { $0 = deepLhs.memoUnsoundContentDivergence(from: deepRhs) }
    }
    #expect(clean.withLock { $0 } == String?.none)
  }

  @Test("memoFirstDifferingField completes on a worker-sized stack")
  func memoFirstDifferingFieldIsStackSafe() throws {
    let lhs = deepResolvedChain(depth: Self.deepChainDepth)
    let rhs = deepResolvedChain(depth: Self.deepChainDepth)
    let field = Mutex<String??>(nil)

    try runOnSmallStack { field.withLock { $0 = lhs.memoFirstDifferingField(from: rhs) } }

    #expect(field.withLock { $0 } == String?.none)
  }

  @Test("ResolvedNode == completes on a worker-sized stack")
  func resolvedNodeEqualityIsStackSafe() throws {
    let lhs = deepResolvedChain(depth: Self.deepChainDepth)
    let rhs = deepResolvedChain(depth: Self.deepChainDepth)
    let verdict = Mutex<Bool?>(nil)

    try runOnSmallStack { verdict.withLock { $0 = (lhs == rhs) } }

    #expect(verdict.withLock { $0 } == true)
  }

  @Test("MeasuredNode == completes on a worker-sized stack")
  func measuredNodeEqualityIsStackSafe() throws {
    let lhs = deepMeasuredChain(depth: Self.deepChainDepth)
    let rhs = deepMeasuredChain(depth: Self.deepChainDepth)
    let equal = Mutex<Bool?>(nil)
    let unequal = Mutex<Bool?>(nil)

    try runOnSmallStack { equal.withLock { $0 = (lhs == rhs) } }
    #expect(equal.withLock { $0 } == true)

    // The deep inequality must be found too, not short-circuited at the root.
    let differing = deepMeasuredChain(depth: Self.deepChainDepth, leafWidth: 2)
    try runOnSmallStack { unequal.withLock { $0 = (lhs == differing) } }
    #expect(unequal.withLock { $0 } == false)
  }

  @Test("PlacedNode == completes on a worker-sized stack")
  func placedNodeEqualityIsStackSafe() throws {
    let lhs = deepPlacedChain(depth: Self.deepChainDepth)
    let rhs = deepPlacedChain(depth: Self.deepChainDepth)
    let verdict = Mutex<Bool?>(nil)

    try runOnSmallStack { verdict.withLock { $0 = (lhs == rhs) } }

    #expect(verdict.withLock { $0 } == true)
  }

  @Test("isEquivalentForViewportTranslation completes on a worker-sized stack")
  func viewportTranslationEquivalenceIsStackSafe() throws {
    let engine = LayoutEngine()
    let lhs = deepMeasuredChain(depth: Self.deepChainDepth)
    let rhs = deepMeasuredChain(depth: Self.deepChainDepth)
    let verdict = Mutex<Bool?>(nil)

    try runOnSmallStack {
      verdict.withLock { $0 = engine.isEquivalentForViewportTranslation(lhs, rhs) }
    }

    #expect(verdict.withLock { $0 } == true)
  }

  @Test("translatedPlacement completes on a worker-sized stack and translates every node")
  func translatedPlacementIsStackSafe() throws {
    let engine = LayoutEngine()
    let tree = deepPlacedChain(depth: Self.deepChainDepth)
    let translated = Mutex<PlacedNode?>(nil)
    let delta = CellPoint(x: 3, y: 7)

    try runOnSmallStack {
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
  func retainedMetadataSyncIsStackSafe() throws {
    let engine = LayoutEngine()
    let placed = deepPlacedChain(depth: Self.deepChainDepth)
    let resolved = deepResolvedChain(
      depth: Self.deepChainDepth,
      divergeMetadataAtDepth: Self.deepChainDepth - 2
    )
    let synced = Mutex<PlacedNode?>(nil)

    try runOnSmallStack {
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
