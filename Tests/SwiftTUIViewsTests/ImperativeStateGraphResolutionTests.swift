import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph
@testable import SwiftTUIViews

/// Proves the imperative `@State` resolution path that fixes the gallery "Logo
/// Breaker" footgun: a read or write that fires *outside* a resolve pass (a
/// `.task` loop, a gesture callback) reaches the graph-backed state slot even
/// when the body never read that property — so no per-box seed can go stale.
///
/// The end-to-end behavior is pinned by `TaskReadsUnbodiedStateTests`; these
/// tests isolate the mechanism. Since plan 2026-08-20-001 Stage 5 the
/// imperative tier serves only exactly-known bindings — the carried capture
/// or the dispatch snapshot's exact recorded owner — so this suite pins both
/// halves: the exact tier lands reads and writes on the owner's graph slot,
/// and every shape the deleted guessing tiers (ancestor walk, sole live
/// binding, imperative mint) used to serve now REFUSES loudly instead of
/// forking or borrowing state. A retired graph scope still falls back to the
/// seed instead of leaking another session's state.
@MainActor
struct ImperativeStateGraphResolutionTests {
  /// Smuggles the imperative authoring snapshot captured during resolve out to
  /// the test, the way `TaskLifecycleModifier` captures it for a `.task`.
  @MainActor
  final class CapturedSnapshot {
    var snapshot: ImperativeAuthoringContextSnapshot?
  }

  /// A view whose body **never reads** `flag` (it appears only in the imperative
  /// accessors below), reproducing the shape that left `LogoTab.isDragging`
  /// stale. The slot ordinal is pinned so the test can inspect the graph slot
  /// directly.
  private struct BodyNeverReadsFlagProbe: View {
    static let flagColumn: UInt = 7

    @State private var flag: Bool
    let captured: CapturedSnapshot

    init(captured: CapturedSnapshot, column: UInt = Self.flagColumn) {
      _flag = State(initialValue: false, line: 0, column: column)
      self.captured = captured
    }

    var body: some View {
      // Body never reads `flag`; it only records the imperative snapshot.
      captured.snapshot = currentImperativeAuthoringContextSnapshot()
      return Text("static")
    }

    /// A reader/writer pair closing over *this instance's* `StateBox`, the way a
    /// gesture or task closure captures `self`.
    func flagReader() -> @MainActor () -> Bool { { flag } }
    func flagWriter() -> @MainActor (Bool) -> Void { { flag = $0 } }
    // `rememberedOwnerCountForTesting` is `#if DEBUG` in SwiftTUIViews, so the
    // owner-accumulation assertion below is debug-only. The rest of this suite
    // is configuration-independent and still runs under `swift test -c release`.
    #if DEBUG
      func rememberedOwnerCount() -> Int { _flag.rememberedOwnerCountForTesting }
    #endif
  }

  private static let flagOrdinal = StateSlotOrdinals.authored(
    line: 0,
    column: BodyNeverReadsFlagProbe.flagColumn
  )

  /// Resolves `probe` into a fresh graph rooted at "Root" and returns the graph
  /// plus the captured imperative snapshot.
  private func resolve(
    _ probe: BodyNeverReadsFlagProbe,
    captured: CapturedSnapshot
  ) throws -> (
    graph: ViewGraph, ownerIdentity: Identity, snapshot: ImperativeAuthoringContextSnapshot
  ) {
    let graph = ViewGraph()
    let ownerIdentity = testIdentity("Root")
    graph.beginFrame()
    var context = ResolveContext(
      identity: ownerIdentity,
      environmentValues: .init(),
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    _ = Resolver().resolve(probe, in: context)
    let snapshot = try #require(captured.snapshot)
    return (graph, ownerIdentity, snapshot)
  }

  @Test("an imperative read of a body-unread @State resolves the live graph slot")
  func imperativeReadResolvesLiveSlot() throws {
    let captured = CapturedSnapshot()
    let probe = BodyNeverReadsFlagProbe(captured: captured)
    let (graph, ownerIdentity, snapshot) = try resolve(probe, captured: captured)

    // No box ever remembered a location (the body never read `flag`), so this
    // read can only succeed through the registry-backed imperative fallback. It
    // returns the seed-initialized slot value, and initializes the slot on the
    // owner node — not a detached per-box seed.
    let value = withImperativeAuthoringContext(snapshot) { probe.flagReader()() }
    #expect(value == false)
    // The read initialized the slot on the owner node itself, not a detached seed.
    let node = try #require(graph.nodeForIdentity(ownerIdentity))
    let storage = try #require(node.stateSlotStorage(ordinal: Self.flagOrdinal))
    #expect(storage.value(as: Bool.self) == false)
  }

  @Test("an imperative write of a body-unread @State reaches the graph slot")
  func imperativeWriteReachesGraphSlot() throws {
    let captured = CapturedSnapshot()
    let probe = BodyNeverReadsFlagProbe(captured: captured)
    let (graph, ownerIdentity, snapshot) = try resolve(probe, captured: captured)

    withImperativeAuthoringContext(snapshot) { probe.flagWriter()(true) }

    // The write must land on the owner's graph slot, observable to any later
    // resolve — not on a per-box seed the next view construction would discard.
    let node = try #require(graph.nodeForIdentity(ownerIdentity))
    let storage = try #require(node.stateSlotStorage(ordinal: Self.flagOrdinal))
    #expect(storage.value(as: Bool.self) == true)

    let readBack = withImperativeAuthoringContext(snapshot) { probe.flagReader()() }
    #expect(readBack == true)
  }

  /// Deliberate refusals in this suite fire the gate-on
  /// `state-seed-fallback` oracle by design: suppress its trace, restore
  /// its counter, and drain the runtime-issue queue afterward so no
  /// parallel or later test observes this suite's deliberate fallbacks
  /// (the oracle-reduction convention).
  private func withDeliberateSeedFallback<Result>(
    _ body: () throws -> Result
  ) rethrows -> Result {
    let savedTrace = SoundnessProbeConfiguration.isTraceEnabled
    let savedCount = SoundnessProbeConfiguration.stateSeedFallbackViolationCount
    SoundnessProbeConfiguration.isTraceEnabled = false
    defer {
      SoundnessProbeConfiguration.isTraceEnabled = savedTrace
      SoundnessProbeConfiguration.stateSeedFallbackViolationCount = savedCount
      _ = ImperativeRuntimeIssueQueue.drain()
    }
    return try body()
  }

  @Test("a foreign-snapshot dispatch refuses instead of walking to an ancestor")
  func foreignSnapshotDispatchRefusesLoudly() throws {
    let captured = CapturedSnapshot()
    let probe = BodyNeverReadsFlagProbe(captured: captured)
    let (graph, ownerIdentity, ownerSnapshot) = try resolve(probe, captured: captured)
    let descendantIdentity = testIdentity("Root", "ForwardedButton")
    _ = graph.applySnapshot(
      ResolvedNode(
        identity: ownerIdentity,
        kind: .root,
        children: [ResolvedNode(identity: descendantIdentity, kind: .view("Button"))]
      )
    )
    let descendant = try #require(graph.nodeForIdentity(descendantIdentity))
    let descendantSnapshot = try snapshot(for: descendant)

    // The deleted live-parent ancestor walk used to route this write to the
    // author's slot. A dispatch context naming a foreign owner now refuses:
    // the write reaches only the box seed — loudly — and no node's slot
    // forks. The real forwarded-action shape carries the author as a
    // capture (the closure is created in the author's body) and never
    // reaches this tier.
    withDeliberateSeedFallback {
      withImperativeAuthoringContext(descendantSnapshot) { probe.flagWriter()(true) }
    }
    let owner = try #require(graph.nodeForIdentity(ownerIdentity))
    #expect(owner.stateSlot(ordinal: Self.flagOrdinal, seed: false) == false)
    #expect(descendant.stateSlotStorage(ordinal: Self.flagOrdinal) == nil)
    // The author's own snapshot still serves the live slot exactly.
    #expect(withImperativeAuthoringContext(ownerSnapshot) { probe.flagReader()() } == false)
  }

  @Test("eager unread State binding prunes retired owner lifetimes")
  func eagerUnreadBindingPrunesRetiredOwners() throws {
    let captured = CapturedSnapshot()
    let probe = BodyNeverReadsFlagProbe(captured: captured)

    for index in 0..<8 {
      captured.snapshot = nil
      let mounted = try resolve(probe, captured: captured)
      let owner = try #require(mounted.graph.nodeForIdentity(mounted.ownerIdentity))
      if index < 7 {
        mounted.graph.beginFrame()
        mounted.graph.removeSubtree(rootedAt: owner)
      }
    }

    #if DEBUG
      #expect(probe.rememberedOwnerCount() == 1)
    #endif
  }

  @Test("cross-box rendezvous requires a resolved binding; an unresolved copy refuses")
  func crossBoxRendezvousRequiresAResolvedBinding() throws {
    let captured1 = CapturedSnapshot()
    let probe1 = BodyNeverReadsFlagProbe(captured: captured1)
    let (graph, ownerIdentity, snapshot) = try resolve(probe1, captured: captured1)
    let readViaBox1 = probe1.flagReader()

    // An unresolved copy's closure carries no capture and no remembered
    // binding. The deleted imperative mint used to fabricate a location
    // from the ambient handle; the write now reaches only that copy's own
    // pre-mount seed (its box was never graph-bound, so this stays the
    // quiet pre-mount arm) and the graph slot is untouched.
    let unresolved = BodyNeverReadsFlagProbe(captured: CapturedSnapshot())
    withImperativeAuthoringContext(snapshot) { unresolved.flagWriter()(true) }
    #expect(withImperativeAuthoringContext(snapshot) { readViaBox1() } == false)

    // A LATER RESOLVED copy — the real "a gesture captured a later body's
    // box" shape — rendezvous at the shared slot through its own binding.
    let captured2 = CapturedSnapshot()
    let probe2 = BodyNeverReadsFlagProbe(captured: captured2)
    var context = ResolveContext(
      identity: ownerIdentity,
      environmentValues: .init(),
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    _ = Resolver().resolve(probe2, in: context)
    withImperativeAuthoringContext(snapshot) { probe2.flagWriter()(true) }

    #expect(withImperativeAuthoringContext(snapshot) { readViaBox1() } == true)
    let node = try #require(graph.nodeForIdentity(ownerIdentity))
    let storage = try #require(node.stateSlotStorage(ordinal: Self.flagOrdinal))
    #expect(storage.value(as: Bool.self) == true)
  }

  @Test("a leaf-snapshot dispatch never walks the parent chain or forks a node")
  func leafSnapshotDispatchRefusesWithoutWalkOrFork() throws {
    let captured = CapturedSnapshot()
    let probe = BodyNeverReadsFlagProbe(captured: captured)
    let (graph, ownerIdentity, _) = try resolve(probe, captured: captured)
    let wrapperIdentity = testIdentity("Root", "Wrapper")
    let leafIdentity = testIdentity("Root", "Wrapper", "DeepButton")
    let siblingIdentity = testIdentity("Root", "Sibling")
    _ = graph.applySnapshot(
      ResolvedNode(
        identity: ownerIdentity,
        kind: .root,
        children: [
          ResolvedNode(
            identity: wrapperIdentity,
            kind: .view("Wrapper"),
            children: [ResolvedNode(identity: leafIdentity, kind: .view("Button"))]
          ),
          ResolvedNode(identity: siblingIdentity, kind: .view("Mount")),
        ]
      )
    )
    let leaf = try #require(graph.nodeForIdentity(leafIdentity))
    let sibling = try #require(graph.nodeForIdentity(siblingIdentity))
    let leafSnapshot = try snapshot(for: leaf)

    // The deleted live-parent walk used to find the author's binding from
    // here, and the deleted sole-binding pick used to serve it even from
    // detached subtrees. Both now refuse: the write reaches only the box
    // seed — loudly, since the box was graph-bound — and no node in any
    // branch forks a slot. Graph- and sibling-isolation hold by refusal.
    withDeliberateSeedFallback {
      withImperativeAuthoringContext(leafSnapshot) { probe.flagWriter()(true) }
    }
    let owner = try #require(graph.nodeForIdentity(ownerIdentity))
    #expect(owner.stateSlot(ordinal: Self.flagOrdinal, seed: false) == false)
    #expect(leaf.stateSlotStorage(ordinal: Self.flagOrdinal) == nil)
    #expect(sibling.stateSlotStorage(ordinal: Self.flagOrdinal) == nil)
  }

  @Test("a retired descendant handle cannot recover an unmounted State owner")
  func retiredDescendantDoesNotRecoverUnmountedAncestor() throws {
    let probe = BodyNeverReadsFlagProbe(captured: CapturedSnapshot())
    let graph = ViewGraph()
    let rootIdentity = testIdentity("RetiredAncestorFallback")
    let ownerIdentity = testIdentity("RetiredAncestorFallback", "Owner")
    let leafIdentity = testIdentity("RetiredAncestorFallback", "Owner", "Button")
    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(
            identity: ownerIdentity,
            kind: .view("Owner"),
            children: [ResolvedNode(identity: leafIdentity, kind: .view("Button"))]
          )
        ]
      )
    )
    let owner = try #require(graph.nodeForIdentity(ownerIdentity))
    let leaf = try #require(graph.nodeForIdentity(leafIdentity))
    _ = withImperativeAuthoringContext(try snapshot(for: owner)) { probe.flagReader()() }
    let retiredLeafSnapshot = try snapshot(for: leaf)

    graph.beginFrame()
    graph.removeSubtree(rootedAt: owner)
    let replacement = graph.nodeForIdentity(for: ownerIdentity)
    withImperativeAuthoringContext(retiredLeafSnapshot) { probe.flagWriter()(true) }

    #expect(replacement.stateSlotStorage(ordinal: Self.flagOrdinal) == nil)
    #expect(graph.nodeForOwnerLifetimeID(owner.ownerLifetimeID) == nil)
    #expect(graph.nodeForOwnerLifetimeID(leaf.ownerLifetimeID) == nil)
  }

  @Test("a remembered binding never crosses a checkpoint node-ID ABA successor")
  func rememberedBindingDoesNotCrossCheckpointNodeIDABA() throws {
    let captured = CapturedSnapshot()
    let probe = BodyNeverReadsFlagProbe(captured: captured)
    let graph = ViewGraph()
    let rootIdentity = testIdentity("StateOwnerABARoot")
    let ownerIdentity = testIdentity("StateOwnerABARoot", "Candidate")
    let successorIdentity = testIdentity("StateOwnerABARoot", "Successor")
    graph.setRootEvaluator(rootIdentity: rootIdentity) {}

    _ = graph.applySnapshot(ResolvedNode(identity: rootIdentity, kind: .root))
    let baseline = graph.makeCheckpoint()
    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [ResolvedNode(identity: ownerIdentity, kind: .view("Candidate"))]
      )
    )
    graph.beginFrame()
    var context = ResolveContext(
      identity: ownerIdentity,
      environmentValues: .init(),
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    _ = Resolver().resolve(probe, in: context)
    let snapshot = try #require(captured.snapshot)
    #expect(withImperativeAuthoringContext(snapshot) { probe.flagReader()() } == false)
    let candidateNodeID = try #require(graph.nodeForIdentity(ownerIdentity)).viewNodeID

    graph.restoreCheckpoint(baseline)
    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(identity: successorIdentity, kind: .view("Successor"))
        ]
      )
    )
    let successor = try #require(graph.nodeForIdentity(successorIdentity))
    #expect(
      successor.viewNodeID == candidateNodeID,
      "checkpoint restore must reproduce the raw ViewNodeID ABA premise"
    )

    withImperativeAuthoringContext(snapshot) {
      probe.flagWriter()(true)
    }

    #expect(
      successor.stateSlotStorage(ordinal: Self.flagOrdinal) == nil,
      "a retired candidate binding crossed into a different node lifetime reusing its raw ID"
    )
    #expect(withImperativeAuthoringContext(snapshot) { probe.flagReader()() } == true)
  }

  @Test("a remembered binding rejects raw-ID ABA even at the same authored identity")
  func rememberedBindingRejectsSameIdentityCheckpointABA() throws {
    let captured = CapturedSnapshot()
    let probe = BodyNeverReadsFlagProbe(captured: captured)
    let graph = ViewGraph()
    let rootIdentity = testIdentity("StateSameIdentityABARoot")
    let ownerIdentity = testIdentity("StateSameIdentityABARoot", "Owner")

    _ = graph.applySnapshot(ResolvedNode(identity: rootIdentity, kind: .root))
    let baseline = graph.makeCheckpoint()
    func applyOwner() {
      _ = graph.applySnapshot(
        ResolvedNode(
          identity: rootIdentity,
          kind: .root,
          children: [ResolvedNode(identity: ownerIdentity, kind: .view("Owner"))]
        )
      )
    }

    applyOwner()
    graph.beginFrame()
    var context = ResolveContext(
      identity: ownerIdentity,
      environmentValues: .init(),
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    _ = Resolver().resolve(probe, in: context)
    let snapshot = try #require(captured.snapshot)
    #expect(withImperativeAuthoringContext(snapshot) { probe.flagReader()() } == false)
    let retiredID = try #require(graph.nodeForIdentity(ownerIdentity)).viewNodeID

    graph.restoreCheckpoint(baseline)
    applyOwner()
    let replacement = try #require(graph.nodeForIdentity(ownerIdentity))
    #expect(replacement.viewNodeID == retiredID)

    withImperativeAuthoringContext(snapshot) {
      probe.flagWriter()(true)
    }

    #expect(replacement.stateSlotStorage(ordinal: Self.flagOrdinal) == nil)
    #expect(withImperativeAuthoringContext(snapshot) { probe.flagReader()() } == true)
  }

  @Test("a remembered binding never crosses the same identity into a different entity")
  func rememberedBindingDoesNotCrossSameIdentityDifferentEntity() throws {
    let probe = BodyNeverReadsFlagProbe(captured: CapturedSnapshot())
    let graph = ViewGraph()
    let ownerIdentity = testIdentity("StateEntityReplacementRoot", "Owner")
    var firstOwner: SwiftTUICore.ViewNode? = graph.nodeForIdentity(
      for: ownerIdentity,
      entityIdentity: EntityIdentity("first")
    )
    let firstNodeID = try #require(firstOwner).viewNodeID
    let weakFirstOwner = WeakStateOwnerReference(try #require(firstOwner))
    let snapshot: ImperativeAuthoringContextSnapshot
    do {
      let authoredContext = AuthoringContext(
        viewIdentity: ownerIdentity,
        focusedValues: FocusedValues(),
        viewNode: firstOwner
      )
      snapshot = try #require(
        withAuthoringContext(authoredContext) {
          #expect(probe.flagReader()() == false)
          return currentImperativeAuthoringContextSnapshot()
        }
      )
    }

    // Retire the first entity, then mint a distinct entity owner at the same
    // authored identity. The stale authored binding must not follow identity.
    graph.beginFrame()
    graph.removeSubtree(rootedAt: try #require(firstOwner))
    firstOwner = nil
    let replacement = graph.nodeForIdentity(
      for: ownerIdentity,
      entityIdentity: EntityIdentity("replacement")
    )
    #expect(replacement.viewNodeID != firstNodeID)
    #expect(graph.nodeForViewNodeID(firstNodeID) == nil)
    #expect(weakFirstOwner.node == nil)

    withImperativeAuthoringContext(snapshot) {
      probe.flagWriter()(true)
    }

    #expect(
      replacement.stateSlotStorage(ordinal: Self.flagOrdinal) == nil,
      "an authored identity match must not bridge distinct entity lifetimes"
    )
    #expect(withImperativeAuthoringContext(snapshot) { probe.flagReader()() } == true)
  }

  @Test("a remembered binding never crosses into a replacement owner identity")
  func rememberedBindingDoesNotCrossOwnerReplacement() throws {
    let captured = CapturedSnapshot()
    let probe = BodyNeverReadsFlagProbe(captured: captured)
    let graph = ViewGraph()
    let rootIdentity = testIdentity("StateOwnerReplacementRoot")
    let originalIdentity = testIdentity("StateOwnerReplacementRoot", "Original")
    let replacementIdentity = testIdentity("StateOwnerReplacementRoot", "Replacement")
    graph.setRootEvaluator(rootIdentity: rootIdentity) {}

    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [ResolvedNode(identity: originalIdentity, kind: .view("Original"))]
      )
    )
    graph.beginFrame()
    var context = ResolveContext(
      identity: originalIdentity,
      environmentValues: .init(),
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    _ = Resolver().resolve(probe, in: context)
    let snapshot = try #require(captured.snapshot)
    #expect(withImperativeAuthoringContext(snapshot) { probe.flagReader()() } == false)
    let retiredOwner = try #require(graph.nodeForIdentity(originalIdentity))

    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(identity: replacementIdentity, kind: .view("Replacement"))
        ]
      )
    )
    let replacementOwner = try #require(graph.nodeForIdentity(replacementIdentity))

    withImperativeAuthoringContext(snapshot) {
      probe.flagWriter()(true)
    }

    #expect(
      retiredOwner.stateSlot(ordinal: Self.flagOrdinal, seed: false) == false,
      "a retained reference must not let the binding write a node retired from its graph"
    )
    #expect(
      replacementOwner.stateSlotStorage(ordinal: Self.flagOrdinal) == nil,
      "a retired binding must not resurrect its slot in a different owner lifetime"
    )
    #expect(
      withImperativeAuthoringContext(snapshot) { probe.flagReader()() } == true,
      "the retired binding should retain its local fallback without crossing owners"
    )
  }

  @Test("a write keyed to a retired graph scope falls back to the seed, not another graph")
  func retiredScopeDoesNotLeakAcrossSessions() throws {
    // Resolve into a graph we then retire. The captured snapshot still names the
    // retired scope; the imperative path must resolve it to nil and fall back to
    // the box seed, never binding to a different live graph.
    let captured = CapturedSnapshot()
    let probe = BodyNeverReadsFlagProbe(captured: captured)
    var owningGraph: ViewGraph? = ViewGraph()
    let ownerIdentity = testIdentity("Root")
    owningGraph!.beginFrame()
    var context = ResolveContext(
      identity: ownerIdentity,
      environmentValues: .init(),
      applyEnvironmentValues: true
    )
    context.viewGraph = owningGraph
    _ = Resolver().resolve(probe, in: context)
    let snapshot = try #require(captured.snapshot)

    // A live, unrelated graph that must never be reached by the retired scope.
    let otherGraph = ViewGraph()
    otherGraph.beginFrame()

    owningGraph = nil  // retire the owning session

    // The write cannot reach any graph slot now; it falls back to the box seed.
    withImperativeAuthoringContext(snapshot) { probe.flagWriter()(true) }
    // The read sees the box's own retained seed (true) — never `otherGraph`.
    let readBack = withImperativeAuthoringContext(snapshot) { probe.flagReader()() }
    #expect(readBack == true)
    // And the unrelated live graph never received the write.
    let otherSlot = otherGraph.nodeForIdentity(ownerIdentity)?.stateSlotStorage(
      ordinal: Self.flagOrdinal
    )
    #expect(otherSlot == nil)
  }

  private func snapshot(
    for node: SwiftTUICore.ViewNode
  ) throws -> ImperativeAuthoringContextSnapshot {
    let context = AuthoringContext(
      viewIdentity: node.identity,
      focusedValues: FocusedValues(),
      viewNode: node
    )
    return try #require(
      withAuthoringContext(context) {
        currentImperativeAuthoringContextSnapshot()
      }
    )
  }
}

@MainActor
private final class WeakStateOwnerReference {
  weak var node: SwiftTUICore.ViewNode?

  init(_ node: SwiftTUICore.ViewNode) {
    self.node = node
  }
}
