import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph

/// STUI-1133: the engine re-entry chain that custom layouts and hosted
/// collections open on the native stack fits the frame-tail worker at the
/// offload budget, with headroom for instrumentation.
///
/// The frame tail offloads a tree whose engine re-entry nesting is at most
/// the runtime's worker budget (two; `FrameTailRenderer`'s
/// `workerEngineReentryNestingBudget`) onto a Dispatch worker with the
/// platform's small default stack, about 512 KiB on Darwin; ADR-0020 rules
/// out sizing that thread. Every re-entry level keeps the measurement driver,
/// the scheduler and the author callback live at once, and -Onone allocates
/// each function's temporaries statically, so the per-level cost is set by
/// the largest live frames rather than by the work. The campaign-two
/// AddressSanitizer baseline overflowed that stack at the budget with a plain
/// leaf at the tip: the sanitizer inflates every frame by about a third, and
/// the chain had no third to spare.
///
/// These tests run the same chain shapes on a thread with an explicit stack:
/// the worker's class, and half of it as the headroom the repair created. A
/// frame that grows back overflows *here*, in the core suite, rather than on
/// the worker under a sanitizer. An overflow takes the process down (a crash
/// cannot be a red test), so the red-first evidence is in the landing commit
/// and these run green.
///
/// The half-stack ratchet is defined on the plain `-Onone` build. Under the
/// sanitizer lane the worker-size tests are the contract; the hosted
/// collections' half-stack tests are skipped there because the list
/// presentation's line materialization at the tip (`ListStylePresentation`,
/// outside the re-entry chain) inflates past the ratchet under
/// AddressSanitizer while still fitting the worker.
@Suite("Measurement re-entry stack headroom", .serialized)
struct MeasurementReentryStackHeadroomTests {
  /// The Dispatch worker stack class the frame tail runs on.
  private static let workerStackSize = 512 << 10

  /// Half the worker stack: the margin the STUI-1133 repair left for
  /// sanitizer inflation and for growth in the node and product types.
  private static let headroomStackSize = workerStackSize / 2

  /// `Scripts/run_sanitizer_lane.sh` exports this for the suites it runs.
  private static let isSanitizerLane =
    ProcessInfo.processInfo.environment["SWIFTTUI_SANITIZER_LANE"] != nil

  /// The runtime's `FrameTailRenderer.workerEngineReentryNestingBudget`,
  /// which this layer cannot name; `AsyncFrameTailRenderingTests` pins both
  /// sides of that boundary on the real worker.
  private static let workerEngineReentryNestingBudget = 2

  @Test("custom-layout re-entries at the worker budget fit the worker stack")
  func customLayoutChainFitsWorkerStack() async {
    let measured = await measureOnThread(
      stackSize: Self.workerStackSize,
      makeReenteringCustomLayoutChain(depth: Self.workerEngineReentryNestingBudget)
    )
    #expect(measured.measuredSize == CellSize(width: 3, height: 1))
  }

  @Test("custom-layout re-entries at the worker budget keep half the worker stack free")
  func customLayoutChainKeepsHeadroom() async {
    let measured = await measureOnThread(
      stackSize: Self.headroomStackSize,
      makeReenteringCustomLayoutChain(depth: Self.workerEngineReentryNestingBudget)
    )
    #expect(measured.measuredSize == CellSize(width: 3, height: 1))
  }

  @Test("hosted-collection re-entries at the worker budget fit the worker stack")
  func hostedCollectionChainFitsWorkerStack() async {
    let resolved = makeNestedHostedListChain(depth: Self.workerEngineReentryNestingBudget)
    let measured = await measureOnThread(stackSize: Self.workerStackSize, resolved)
    #expect(measured.identity == resolved.identity)
  }

  @Test(
    "hosted-collection re-entries at the worker budget keep half the worker stack free",
    .enabled(if: !isSanitizerLane, "the hosted tip's presentation frames inflate under a sanitizer")
  )
  func hostedCollectionChainKeepsHeadroom() async {
    let resolved = makeNestedHostedListChain(depth: Self.workerEngineReentryNestingBudget)
    let measured = await measureOnThread(stackSize: Self.headroomStackSize, resolved)
    #expect(measured.identity == resolved.identity)
  }

  @Test(
    "a custom layout over a hosted collection keeps half the worker stack free",
    .enabled(if: !isSanitizerLane, "the hosted tip's presentation frames inflate under a sanitizer")
  )
  func customLayoutOverHostedCollectionKeepsHeadroom() async {
    let resolved = makeReenteringCustomLayoutNode(
      "custom-over-hosted",
      child: makeHostedListNode(
        "hosted-under-custom",
        rowContent: makeLayoutLeaf("hosted-under-custom-leaf", size: .init(width: 3, height: 1))
      )
    )
    let measured = await measureOnThread(stackSize: Self.headroomStackSize, resolved)
    #expect(measured.identity == resolved.identity)
  }

  // MARK: - Running a measurement on a sized stack

  /// Measures `resolved` on a freshly spawned thread with an explicit stack
  /// size and awaits the product. `Thread` rather than raw `pthread`: the
  /// stack size is the whole requirement, and it keeps the suite free of the
  /// escape hatches the repository policy forbids. The thread resumes the
  /// continuation when it finishes; there is no timeout or poll.
  private func measureOnThread(
    stackSize: Int,
    _ resolved: ResolvedNode
  ) async -> MeasuredNode {
    await withCheckedContinuation { (continuation: CheckedContinuation<MeasuredNode, Never>) in
      let thread = Thread {
        let engine = LayoutEngine()
        let passContext = LayoutPassContext()
        continuation.resume(
          returning: engine.measure(
            resolved,
            proposal: .init(width: 20, height: 6),
            passContext: passContext
          )
        )
      }
      thread.stackSize = stackSize
      thread.start()
    }
  }
}

// MARK: - Fixtures

/// A custom layout whose `sizeThatFits` measures each subview on the native
/// stack, as `LayoutSubview.sizeThatFits` does for an author layout.
private final class ReenteringCustomLayoutProxy: LayoutPassContextCustomLayoutProxy {
  var debugName: String {
    "ReenteringCustomLayoutProxy"
  }

  func measureContainer(
    engine: LayoutEngine,
    node: ResolvedNode,
    proposal: ProposedSize
  ) -> CellSize {
    measureContainer(engine: engine, node: node, proposal: proposal, passContext: nil)
  }

  func measureContainer(
    engine: LayoutEngine,
    node: ResolvedNode,
    proposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> CellSize {
    var size = CellSize.zero
    for child in node.children {
      let childSize = engine.measure(child, proposal: proposal, passContext: passContext)
        .measuredSize
      size.width = max(size.width, childSize.width)
      size.height = max(size.height, childSize.height)
    }
    return size
  }

  func placeSubviews(
    engine: LayoutEngine,
    node: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect
  ) -> [PlacedNode] {
    placeSubviews(engine: engine, node: node, measured: measured, in: bounds, passContext: nil)
  }

  func placeSubviews(
    engine: LayoutEngine,
    node: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect,
    passContext: LayoutPassContext?
  ) -> [PlacedNode] {
    node.children.map { child in
      let childMeasurement = engine.measure(
        child,
        proposal: measured.proposal,
        passContext: passContext
      )
      return engine.place(
        child,
        measured: childMeasurement,
        in: CellRect(origin: bounds.origin, size: childMeasurement.measuredSize),
        passContext: passContext
      )
    }
  }
}

private let reenteringCustomLayoutProxy = ReenteringCustomLayoutProxy()

private func makeReenteringCustomLayoutNode(_ name: String, child: ResolvedNode) -> ResolvedNode {
  ResolvedNode(
    identity: testIdentity(name),
    kind: .view("ReenteringCustomLayout"),
    children: [child],
    layoutBehavior: .custom(CustomLayoutHandle(reenteringCustomLayoutProxy))
  )
}

/// `depth` nested re-entering custom layouts over one leaf.
private func makeReenteringCustomLayoutChain(depth: Int) -> ResolvedNode {
  var node = makeLayoutLeaf("reentering-leaf", size: .init(width: 3, height: 1))
  for index in stride(from: depth - 1, through: 0, by: -1) {
    node = makeReenteringCustomLayoutNode("reentering-\(index)", child: node)
  }
  return node
}

private func makeLayoutLeaf(_ name: String, size: CellSize) -> ResolvedNode {
  ResolvedNode(
    identity: testIdentity(name),
    kind: .view("Leaf"),
    intrinsicSize: size
  )
}

/// A hosted-collection (`List`) container whose single realized row is
/// `rowContent`: the shape that drives `windowedHostedCollectionMeasurement`
/// into its native `measure` re-entry per nesting level.
private func makeHostedListNode(_ name: String, rowContent: ResolvedNode) -> ResolvedNode {
  var node = ResolvedNode(
    identity: testIdentity(name),
    kind: .view("List"),
    drawPayload: .list(
      ListPayload(
        items: [ListItemPayload(kind: .row, text: "row")],
        selectedRowIndex: nil,
        style: .plain
      )
    )
  )
  node.semanticMetadata.hostedCollectionContainer = .init(kind: .list)
  node.indexedChildSource = IndexedChildSourceSnapshot(
    identityRoot: node.identity,
    measurementSignature: .init(elementPaths: [name]),
    children: [rowContent]
  )
  return node
}

/// `depth` nested hosted lists over one leaf.
private func makeNestedHostedListChain(depth: Int) -> ResolvedNode {
  var node = makeHostedListNode(
    "hosted-0",
    rowContent: makeLayoutLeaf("hosted-leaf", size: .init(width: 2, height: 1))
  )
  for level in 1..<max(1, depth) {
    node = makeHostedListNode("hosted-\(level)", rowContent: node)
  }
  return node
}
