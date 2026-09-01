import SwiftTUICore
import Testing

@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Counter-demo ripple regression (2026-09-01): a `ForEach` whose data holds a
/// SINGLE element, resolved as a modifier's content (`.background { ForEach … }`),
/// hands that element's resolved node — stamped with the element's entity —
/// straight up as the container's own resolved value (`normalizeResolvedElements`
/// unwraps a lone element instead of minting a `Group`). The container node's
/// apply then claimed the element's entity under the "outermost same-frame claim
/// owns the entity" rule (`ViewGraph.bindEntityIdentity`), so the next frame's
/// `nodeForIdentity` routed the element onto the CONTAINER node: its `@State`
/// re-seeded there, an imperative write made through a body-created closure (the
/// ripple's `.task`) landed on the orphaned element node, and the element's body
/// never observed it — the ripple stayed at `progress == 0` until its completion
/// removed it.
///
/// Growing the data to two elements then evaluated the hijacked element ON the
/// container mid-evaluation, where retained reuse served the container's whole
/// committed `Group` as that element — nesting the previous frame's `Group` one
/// level deeper on every re-evaluation until the DEBUG skip oracle
/// (`AnimationController.noteSkippedResolvedTreeProcessing`) trapped.
@MainActor
@Suite(.serialized)
struct ForEachSingleElementEntityClaimTests {
  @Test("a lone ForEach element keeps its state owner across an imperative write")
  func loneElementKeepsItsStateOwner() throws {
    let ledger = ElementLedger()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("LoneElementRoot"),
      size: .init(width: 40, height: 6)
    ) {
      LoneElementFixture(ledger: ledger)
    }
    defer { harness.shutdown() }
    #expect(ledger.observedProgress[0] == [0])

    // The ripple shape: a closure the element's body created writes the
    // element's own `@State` outside any resolve pass.
    let bump = try #require(ledger.bumps[0])
    bump()
    _ = try harness.renderAfterExternalMutation()

    #expect(
      ledger.observedProgress[0]?.last == 1,
      "the element's body re-evaluated against another state owner: \(ledger.observedProgress)"
    )
    try expectNoElementRoutesToTheContainer(harness)
  }

  @Test("growing a lone ForEach element to two keeps a flat Group")
  func growingToTwoElementsKeepsAFlatGroup() throws {
    let ledger = ElementLedger()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("GrowingElementRoot"),
      size: .init(width: 40, height: 6)
    ) {
      LoneElementFixture(ledger: ledger)
    }
    defer { harness.shutdown() }

    let bumpFirst = try #require(ledger.bumps[0])
    bumpFirst()
    _ = try harness.renderAfterExternalMutation()
    let setCount = try #require(ledger.setCount)
    setCount(2)
    _ = try harness.renderAfterExternalMutation()
    let grown = try backgroundShape(harness)
    let bumpSecond = try #require(ledger.bumps[1])
    bumpSecond()
    _ = try harness.renderAfterExternalMutation()
    let afterWrite = try backgroundShape(harness)

    #expect(
      grown == "Group[Rectangle@ID[0], Rectangle@ID[1]]",
      "the lone element's node was hijacked before the second element arrived: \(grown)"
    )
    #expect(
      afterWrite == grown,
      "a dirty re-evaluation re-nested the previous Group: \(afterWrite)"
    )
    #expect(
      ledger.observedProgress[1]?.last == 1,
      "the second element's body never observed its own write: \(ledger.observedProgress)"
    )
    try expectNoElementRoutesToTheContainer(harness)
    try expectNoSelfChildCycles(harness)
  }

  @Test("a stateless lone ForEach element keeps one node across re-renders")
  func statelessLoneElementIsNotReMintedEveryFrame() throws {
    let ledger = ElementLedger()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StatelessElementRoot"),
      size: .init(width: 40, height: 6)
    ) {
      StatelessLoneElementFixture(ledger: ledger)
    }
    defer { harness.shutdown() }

    // The element's node is parentless and index-shadowed by its container
    // (the flattening absorber), so its lifetime rests on its entity route and
    // `lifetimeReachabilityContext`'s flattened-element fact. Without that fact
    // the barrier reclaims the node as a stale absorbed shadow every frame and
    // the next resolve mints a fresh one.
    let initialHomes = try elementHomes(harness)
    #expect(initialHomes.count == 1, "expected one routed element: \(initialHomes)")
    for _ in 0..<4 {
      _ = try harness.renderAfterExternalMutation()
    }
    let finalHomes = try elementHomes(harness)
    #expect(
      finalHomes == initialHomes,
      "the lone element's node was re-minted: \(finalHomes) != \(initialHomes)"
    )
    // `.onAppear` fires twice for a lone `ForEach` element resolved directly as
    // modifier content — on the unfixed tree as well, and only in that shape
    // (two elements fire once each; a lone element under `ZStack`/`VStack`
    // fires once). That is a separate lifecycle-publication defect tracked as
    // T171 in the org root's `docs/TASKS.csv`; this test pins node stability
    // only, so the count is recorded but not asserted.
    _ = ledger.appearances
    try expectNoElementRoutesToTheContainer(harness)
    try expectNoSelfChildCycles(harness)
  }
}

// MARK: - Support

/// The routed node of every ForEach element, keyed by entity description.
@MainActor
private func elementHomes<V: View>(_ harness: StressRuntimeHarness<V>) throws -> [String: UInt64] {
  let graph = harness.runLoop.renderer.debugRuntimeSubsystemSnapshot().viewGraph
  var homes: [String: UInt64] = [:]
  for (entity, nodeID) in graph.entityRoutingTable.nodeIDByEntity where entity.isForEachScoped {
    homes["\(entity)"] = nodeID.rawValue
  }
  return homes
}

/// Every entity route must target an element's own node (an explicit-ID
/// identity), never the `ForEach` container resolving as the background content.
@MainActor
private func expectNoElementRoutesToTheContainer<V: View>(
  _ harness: StressRuntimeHarness<V>
) throws {
  let graph = harness.runLoop.renderer.debugRuntimeSubsystemSnapshot().viewGraph
  for (entity, nodeID) in graph.entityRoutingTable.nodeIDByEntity {
    let identity = try #require(graph.identityByNodeID[nodeID])
    #expect(
      !identity.path.hasSuffix("/background"),
      "entity \(entity) is routed to the container node \(nodeID.rawValue)@\(identity.path)"
    )
  }
}

/// A hijacked element resolves ON its container while the container is
/// evaluating, so the container's child list comes to name the container itself —
/// the children-graph cycle whose re-stitching nests the previous frame's `Group`
/// one level deeper on every selective re-evaluation.
@MainActor
private func expectNoSelfChildCycles<V: View>(
  _ harness: StressRuntimeHarness<V>
) throws {
  let graph = harness.runLoop.renderer.debugRuntimeSubsystemSnapshot().viewGraph
  for (nodeID, node) in graph.nodesByNodeID {
    let identity = try #require(graph.identityByNodeID[nodeID])
    #expect(
      !node.children.contains(identity),
      "node \(nodeID.rawValue)@\(identity.path) lists itself as a child: \(node.children.map(\.path))"
    )
  }
}

/// Renders the background content's subtree as `Kind[children]`, leaves tagged
/// with the last component of their identity (`Rectangle@ID[0]`).
@MainActor
private func backgroundShape<V: View>(_ harness: StressRuntimeHarness<V>) throws -> String {
  let root = try #require(
    harness.runLoop.renderer
      .debugRuntimeSubsystemSnapshot()
      .animationController
      .previousTreeRoot
  )
  func kindName(_ node: ResolvedNode) -> String {
    if case .view(let name) = node.kind {
      return name
    }
    return "\(node.kind)"
  }
  func describe(_ node: ResolvedNode) -> String {
    guard !node.children.isEmpty else {
      let lastComponent = node.identity.path.split(separator: "/").last.map(String.init) ?? ""
      return "\(kindName(node))@\(lastComponent)"
    }
    return "\(kindName(node))[\(node.children.map(describe).joined(separator: ", "))]"
  }
  func findBackgroundContent(_ node: ResolvedNode) -> ResolvedNode? {
    if node.kind == .view("Background"), let content = node.children.first {
      return content
    }
    for child in node.children {
      if let found = findBackgroundContent(child) {
        return found
      }
    }
    return nil
  }
  let content = try #require(findBackgroundContent(root))
  return describe(content)
}

@MainActor
private final class ElementLedger {
  var observedProgress: [Int: [Double]] = [:]
  var bumps: [Int: () -> Void] = [:]
  var setCount: ((Int) -> Void)?
  var appearances = 0
}

private struct StatelessLoneElementFixture: View {
  let ledger: ElementLedger

  var body: some View {
    Text("host")
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background {
        ForEach(0..<1, id: \.self) { _ in
          Rectangle()
            .fill(Color.green)
            .onAppear { ledger.appearances += 1 }
        }
      }
  }
}

private struct LoneElementFixture: View {
  let ledger: ElementLedger
  @State private var count = 1

  var body: some View {
    ledger.setCount = { count = $0 }
    return Text("host")
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background {
        ForEach(0..<count, id: \.self) { index in
          // The counter's element chain: a draw-effect wrapper level above the
          // element, so the element's outermost evaluator is the modifier.
          ElementPane(index: index, ledger: ledger)
            .blendMode(.screen)
        }
      }
  }
}

/// The counter demo's `RippleLayer` shape: element-owned `@State` driven by a
/// closure the body creates.
private struct ElementPane: View {
  let index: Int
  let ledger: ElementLedger
  @State private var progress: Double = 0

  var body: some View {
    ledger.observedProgress[index, default: []].append(progress)
    ledger.bumps[index] = { progress += 1 }
    return Rectangle()
      .fill(progress > 0 ? Color.green : Color.red)
  }
}
