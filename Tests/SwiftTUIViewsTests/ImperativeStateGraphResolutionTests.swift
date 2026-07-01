import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

/// Proves the imperative `@State` resolution path that fixes the gallery "Logo
/// Breaker" footgun: a read or write that fires *outside* a resolve pass (a
/// `.task` loop, a gesture callback) reaches the graph-backed state slot even
/// when the body never read that property — so no per-box seed can go stale.
///
/// The end-to-end behavior is pinned by `TaskReadsUnbodiedStateTests`; these
/// tests isolate the mechanism: the imperative write lands on the graph slot,
/// the imperative read observes it live, a different `StateBox` for the same
/// owner rendezvous at that same slot, and a retired graph scope falls back to
/// the seed instead of leaking another session's state.
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

    init(captured: CapturedSnapshot) {
      _flag = State(initialValue: false, line: 0, column: Self.flagColumn)
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

  @Test("a write through one box is observed by a read through a different box")
  func crossBoxRendezvousAtGraphSlot() throws {
    // `probe1` is resolved (creating the owner node + registering the graph) and
    // supplies the read closure bound to box 1 — standing in for the long-lived
    // `.task` that captured the first body's box. `probe2` is never resolved;
    // its write closure is bound to a distinct box 2 — standing in for the
    // gesture that captured a later body's box. They share neither box nor seed,
    // only the owner identity and graph scope.
    let captured1 = CapturedSnapshot()
    let probe1 = BodyNeverReadsFlagProbe(captured: captured1)
    let probe2 = BodyNeverReadsFlagProbe(captured: CapturedSnapshot())
    let (graph, ownerIdentity, snapshot) = try resolve(probe1, captured: captured1)

    let readViaBox1 = probe1.flagReader()
    let writeViaBox2 = probe2.flagWriter()

    #expect(withImperativeAuthoringContext(snapshot) { readViaBox1() } == false)

    withImperativeAuthoringContext(snapshot) { writeViaBox2(true) }

    // Box 2's write rendezvous with box 1's read at the shared graph slot.
    #expect(withImperativeAuthoringContext(snapshot) { readViaBox1() } == true)
    let node = try #require(graph.nodeForIdentity(ownerIdentity))
    let storage = try #require(node.stateSlotStorage(ordinal: Self.flagOrdinal))
    #expect(storage.value(as: Bool.self) == true)
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
}
