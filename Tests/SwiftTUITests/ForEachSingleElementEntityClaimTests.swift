import SwiftTUICore
@_spi(Testing) import SwiftTUITestSupport
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
///
/// Since then a lone `ForEach` element keeps the one-child `Group` its siblings
/// would share (`normalizeResolvedElements`): the container is never the
/// element's absorber, so growth inserts a sibling under an unchanged parent —
/// no re-homing, no task cancel, no snapped animation. The entity-claim pins
/// stay as regression coverage for the absorber paths.
///
/// The writes below render through `render()`, the frame the state write itself
/// scheduled, on a harness created with `selectiveEvaluation: true` so that
/// frame is the run loop's selective dirty-frontier frame, as production.
/// `renderAfterExternalMutation()` invalidates the content root and so always
/// evaluates from the root (`.rootInvalidated`), which hides selective-only
/// symptoms such as the `Group` re-nesting.
@MainActor
@Suite(.serialized)
struct ForEachSingleElementEntityClaimTests {
  @Test("a lone ForEach element keeps its state owner across an imperative write")
  func loneElementKeepsItsStateOwner() throws {
    let ledger = ElementLedger()
    let rootIdentity = testIdentity("LoneElementRoot")
    let harness = try StressRuntimeHarness(
      rootIdentity: rootIdentity,
      size: .init(width: 40, height: 6),
      selectiveEvaluation: true
    ) {
      LoneElementFixture(ledger: ledger)
    }
    defer { harness.shutdown() }
    #expect(ledger.observedProgress[0] == [0])

    // The ripple shape: a closure the element's body created writes the
    // element's own `@State` outside any resolve pass.
    let bump = try #require(ledger.bumps[0])
    bump()
    _ = try harness.render()

    #expect(
      ledger.observedProgress[0]?.last == 1,
      "the element's body re-evaluated against another state owner: \(ledger.observedProgress)"
    )
    try expectSelectiveElementFrame(harness, rootIdentity: rootIdentity)
    try expectNoElementRoutesToTheContainer(harness)
  }

  @Test("growing a lone ForEach element to two keeps a flat Group")
  func growingToTwoElementsKeepsAFlatGroup() throws {
    let ledger = ElementLedger()
    let rootIdentity = testIdentity("GrowingElementRoot")
    let harness = try StressRuntimeHarness(
      rootIdentity: rootIdentity,
      size: .init(width: 40, height: 6),
      selectiveEvaluation: true
    ) {
      LoneElementFixture(ledger: ledger)
    }
    defer { harness.shutdown() }

    let lone = try backgroundShape(harness)
    let loneHome = try elementNode(harness, elementSuffix: "ID[0]")
    let bumpFirst = try #require(ledger.bumps[0])
    bumpFirst()
    _ = try harness.render()
    let setCount = try #require(ledger.setCount)
    setCount(2)
    _ = try harness.render()
    let grown = try backgroundShape(harness)
    let grownHome = try elementNode(harness, elementSuffix: "ID[0]")
    let bumpSecond = try #require(ledger.bumps[1])
    bumpSecond()
    _ = try harness.render()
    let afterWrite = try backgroundShape(harness)

    // One element already has the `Group` two share, so growth inserts a
    // sibling under an unchanged parent instead of re-rooting the container.
    #expect(
      lone == "Group[Rectangle@ID[0]]",
      "a lone element resolved without its Group: \(lone)"
    )
    #expect(
      grown == "Group[Rectangle@ID[0], Rectangle@ID[1]]",
      "the lone element's node was hijacked before the second element arrived: \(grown)"
    )
    #expect(
      grownHome == loneHome,
      "growth re-homed the first element: \(loneHome) -> \(grownHome)"
    )
    #expect(
      afterWrite == grown,
      "a dirty re-evaluation re-nested the previous Group: \(afterWrite)"
    )
    #expect(
      ledger.observedProgress[1]?.last == 1,
      "the second element's body never observed its own write: \(ledger.observedProgress)"
    )
    try expectSelectiveElementFrame(harness, rootIdentity: rootIdentity)
    try expectNoElementRoutesToTheContainer(harness)
    try expectNoSelfChildCycles(harness)
  }

  @Test("a stateless lone ForEach element keeps one node across re-renders")
  func statelessLoneElementIsNotReMintedEveryFrame() throws {
    let ledger = ElementLedger()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StatelessElementRoot"),
      size: .init(width: 40, height: 6),
      selectiveEvaluation: true
    ) {
      StatelessLoneElementFixture(ledger: ledger)
    }
    defer { harness.shutdown() }

    // Flattened up as its container's value, the element's node was parentless
    // and index-shadowed by the container, so its lifetime rested on its entity
    // route and `lifetimeReachabilityContext`'s flattened-element fact; without
    // that fact the barrier reclaimed it as a stale absorbed shadow every frame
    // and the next resolve minted a fresh one. As a `Group` child it is an
    // ordinary parented node; the pin stays. Root re-renders are the harsher
    // case here: every frame re-resolves the container.
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
    #expect(
      ledger.appearances == 1,
      "a lone element resolved directly as modifier content published .onAppear \(ledger.appearances) times"
    )
    try expectNoElementRoutesToTheContainer(harness)
    try expectNoSelfChildCycles(harness)
  }

  @Test("a lone ForEach element's container publishes appear and disappear once")
  func loneElementContainerPublishesLifecycleOnce() throws {
    // The container node's committed value WAS the element's resolved node,
    // handler IDs included, so a fresh container appeared — and a departing
    // one disappeared — with the element's handlers alongside the element's
    // own node: same handler ID under two identities, and the per-frame
    // dedupe keyed on both missed it. Both the handler-ID dedupe and the
    // one-child `Group` now stand between this test and that double.
    let ledger = ElementLedger()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("LifecycleOnceRoot"),
      size: .init(width: 40, height: 8),
      selectiveEvaluation: true
    ) {
      RemovableContainerFixture(ledger: ledger)
    }
    defer { harness.shutdown() }
    #expect(ledger.appearances == 1, "initial appear count: \(ledger.appearances)")
    #expect(ledger.disappearances == 0)

    let setShown = try #require(ledger.setShown)
    setShown(false)
    _ = try harness.render()
    #expect(ledger.appearances == 1, "hiding published an appear: \(ledger.appearances)")
    #expect(
      ledger.disappearances == 1,
      "hiding the container published .onDisappear \(ledger.disappearances) times"
    )

    setShown(true)
    _ = try harness.render()
    #expect(
      ledger.appearances == 2,
      "re-showing the container published .onAppear \(ledger.appearances - 1) times"
    )
    #expect(ledger.disappearances == 1)
    try expectNoElementRoutesToTheContainer(harness)
  }

  @Test("growing a lone ForEach element to two keeps the first element's task")
  func loneElementGrowthKeepsTheFirstElementsTask() throws {
    let ledger = ElementLedger()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("TaskGrowthRoot"),
      size: .init(width: 40, height: 6),
      selectiveEvaluation: true
    ) {
      TaskedElementsFixture(ledger: ledger)
    }
    defer { harness.shutdown() }
    func activeTaskIDs() -> [String] {
      harness.runLoop.lifecycleCoordinator.activeTaskDescriptors.values
        .flatMap { $0.map(\.id) }
        .sorted()
    }
    let initial = activeTaskIDs()
    #expect(
      initial.count == 1 && initial.first?.hasSuffix("/ID[0]#task") == true,
      "the lone element's task did not start: \(initial)"
    )

    let setCount = try #require(ledger.setCount)
    setCount(2)
    _ = try harness.render()
    let grown = activeTaskIDs()
    #expect(
      grown.contains { $0.hasSuffix("/ID[1]#task") },
      "the second element's task did not start: \(grown)"
    )
    // With the lone element flattened up as the container's value, the task
    // runner keyed the element's task by the identity index owner — the
    // container — and the container cancelled its previous resolved
    // identity's tasks when its value changed from the lone element to a
    // `Group` (org task T172). The one-element `Group` keeps the container's
    // resolved identity its own, so the element owns its task throughout.
    #expect(
      grown.contains { $0.hasSuffix("/ID[0]#task") },
      "the first element's task was cancelled by the container's growth: \(grown)"
    )
  }

  @Test("growing a lone ForEach element to two keeps the first element's animation")
  func loneElementGrowthKeepsTheFirstElementsAnimation() throws {
    // The counter demo's ripple: the first ring's animation is in flight when
    // the second ring arrives. Re-rooting the container from the lone element
    // to a fresh `Group` restarted the first ring from its origin — the
    // flicker — and cancelled its task (T172). The animated offset of the
    // first element's marker must keep advancing through the growth frame.
    let ledger = ElementLedger()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("AnimatedGrowthRoot"),
      size: .init(width: 40, height: 6),
      selectiveEvaluation: true
    ) {
      AnimatedElementsFixture(ledger: ledger)
    }
    defer { harness.shutdown() }
    let controller = harness.runLoop.renderer.internalAnimationController
    let clock = DeadlineDrivenFrameClock(harness: harness)

    let animateFirst = try #require(ledger.animations[0])
    try withAnimationSinks(controller) {
      animateFirst()
      _ = try harness.render()
      try clock.advance(by: .milliseconds(800))
      // The deadline chain's last frame lands just short of the target
      // instant; sample a frame AT the instant the growth frame will use.
      harness.runLoop.scheduler.requestExternalWake(reason: "sample")
      _ = try harness.render()
    }
    let midway = try #require(markerColumn(in: harness.frame, row: 0))
    #expect(midway > 0, "the marker never left its origin:\n\(harness.frame)")
    #expect(
      controller.activeAnimationCount == 1, "the first element's offset animation is in flight")

    let setCount = try #require(ledger.setCount)
    try withAnimationSinks(controller) {
      setCount(2)
      _ = try harness.render()
    }
    let grownAtSameInstant = markerColumn(in: harness.frame, row: 0)
    #expect(
      grownAtSameInstant == midway,
      "the second element's arrival moved the first element's marker: \(midway) -> \(String(describing: grownAtSameInstant))\n\(harness.frame)"
    )
    #expect(controller.activeAnimationCount == 1, "growth cancelled or restarted the animation")

    try withAnimationSinks(controller) {
      try clock.advance(by: .milliseconds(400))
    }
    let later = try #require(markerColumn(in: harness.frame, row: 0))
    #expect(
      later > midway,
      "the first element's animation stopped advancing after growth: \(midway) -> \(later)\n\(harness.frame)"
    )
    try withAnimationSinks(controller) {
      try clock.advance(by: .milliseconds(1_000))
    }
    #expect(
      markerColumn(in: harness.frame, row: 0) == 30, "the marker did not settle:\n\(harness.frame)")
    #expect(
      ledger.completions == 1, "the first element's completion fired \(ledger.completions) times")
  }
}

/// Column of the first element's marker glyph in `row`, or nil when absent.
private func markerColumn(in frame: String, row: Int) -> Int? {
  let lines = frame.split(separator: "\n", omittingEmptySubsequences: false)
  guard row < lines.count else { return nil }
  return Array(lines[row]).firstIndex(of: "A")
}

/// Drives the harness through every deadline the controller arms: the frame
/// instant is the armed deadline, so wall time only advances one frame per
/// render and a probe must render each turn to reach a later instant.
@MainActor
private final class DeadlineDrivenFrameClock<Content: View> {
  private let harness: StressRuntimeHarness<Content>
  private(set) var now = MonotonicInstant.now()

  init(harness: StressRuntimeHarness<Content>) {
    self.harness = harness
    harness.runLoop.frameClock = { [self] in now }
  }

  /// Advances the clock to `now + duration`, rendering every turn armed on
  /// the way; stops early once no turn is pending.
  func advance(by duration: Duration, maxTurns: Int = 2_000) throws {
    let target = now.advanced(by: duration)
    var turns = 0
    while turns < maxTurns {
      let scheduler = harness.runLoop.scheduler
      guard let wake = scheduler.nextWakeInstant(after: now), wake <= target else { break }
      now = wake
      _ = try harness.render()
      turns += 1
    }
    now = target
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

/// The frame just rendered was the state write's own selective frame: it
/// re-evaluated a `ForEach` element and neither the content root nor the
/// presentation portal host above it. A root-shaped frame here means the
/// harness escalated (org task T170) and the resolved-tree pins above ran on
/// the wrong frame shape.
@MainActor
private func expectSelectiveElementFrame<V: View>(
  _ harness: StressRuntimeHarness<V>,
  rootIdentity: Identity
) throws {
  let graph = harness.runLoop.renderer.debugRuntimeSubsystemSnapshot().viewGraph
  let evaluated = graph.evaluatedNodeIDsThisFrame
  let evaluatedPaths = evaluated.compactMap { graph.identityByNodeID[$0]?.path }.sorted()
  let rootNodeID = try #require(graph.nodeIDByIdentity[rootIdentity])
  #expect(
    !evaluated.contains(rootNodeID),
    "the state write's frame evaluated the content root: \(evaluatedPaths)"
  )
  for nodeID in evaluated {
    let identity = try #require(graph.identityByNodeID[nodeID])
    #expect(
      identity.path.hasPrefix(rootIdentity.path + "/"),
      "the state write's frame evaluated above the content root: \(evaluatedPaths)"
    )
  }
  // Element nodes by their explicit-ID identity, not the entity route table:
  // an element re-evaluated alone (a `Group` child whose frontier excludes
  // the container's `ForEach` pass) commits without its entity stamp and
  // holds no route until the next container pass re-binds it.
  let evaluatedAnElement = evaluated.contains { nodeID in
    graph.identityByNodeID[nodeID]?.path.split(separator: "/").last?.hasPrefix("ID[") == true
  }
  #expect(
    evaluatedAnElement,
    "the state write's frame evaluated no ForEach element: \(evaluatedPaths)"
  )
}

/// The view node ID and parent identity of the `ForEach` element whose
/// identity ends in `elementSuffix`.
@MainActor
private func elementNode<V: View>(
  _ harness: StressRuntimeHarness<V>,
  elementSuffix: String
) throws -> String {
  let graph = harness.runLoop.renderer.debugRuntimeSubsystemSnapshot().viewGraph
  let matches = graph.nodesByNodeID.filter { nodeID, _ in
    graph.identityByNodeID[nodeID]?.path.hasSuffix("/" + elementSuffix) == true
  }
  let (nodeID, node) = try #require(matches.first, "no node for \(elementSuffix)")
  #expect(
    matches.count == 1,
    "several nodes for \(elementSuffix): \(matches.keys.map(\.rawValue))"
  )
  return "\(nodeID.rawValue) under \(node.parentIdentity?.path ?? "nil")"
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
  var setShown: ((Bool) -> Void)?
  var appearances = 0
  var disappearances = 0
  var animations: [Int: () -> Void] = [:]
  var completions = 0
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

/// The lone-element container behind a structural `if`, so hiding tears the
/// container down with the element still spliced up as its value.
private struct RemovableContainerFixture: View {
  let ledger: ElementLedger
  @State private var shown = true

  var body: some View {
    ledger.setShown = { shown = $0 }
    return VStack {
      Text("top")
      if shown {
        Text("host")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background {
            ForEach(0..<1, id: \.self) { _ in
              Rectangle()
                .fill(Color.green)
                .onAppear { ledger.appearances += 1 }
                .onDisappear { ledger.disappearances += 1 }
            }
          }
      }
    }
  }
}

/// Lone-element container whose elements each own a `.task`.
private struct TaskedElementsFixture: View {
  let ledger: ElementLedger
  @State private var count = 1

  var body: some View {
    ledger.setCount = { count = $0 }
    return Text("host")
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background {
        ForEach(0..<count, id: \.self) { _ in
          Rectangle()
            .fill(Color.green)
            .task { await suspendUntilCancelled() }
        }
      }
  }
}

/// Lone-element container whose elements animate a marker's offset, the
/// counter ripple's shape reduced to something the text frame can read.
private struct AnimatedElementsFixture: View {
  let ledger: ElementLedger
  @State private var count = 1

  var body: some View {
    ledger.setCount = { count = $0 }
    return Text("host")
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(alignment: .topLeading) {
        ForEach(0..<count, id: \.self) { index in
          AnimatedMarker(index: index, ledger: ledger)
        }
      }
  }
}

private struct AnimatedMarker: View {
  let index: Int
  let ledger: ElementLedger
  @State private var progress: Double = 0

  var body: some View {
    ledger.animations[index] = {
      withAnimation(.linear(duration: .milliseconds(1_600))) {
        progress = 1
      } completion: {
        ledger.completions += 1
      }
    }
    return Text(index == 0 ? "A" : "B")
      .offset(x: Int(progress * 30), y: index)
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
