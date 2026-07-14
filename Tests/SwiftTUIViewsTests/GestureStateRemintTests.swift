import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

/// F135: `@GestureState` access must be re-keyed like `@State` — a recognizer
/// update that fires after the owning identity was re-minted (lazy-tab
/// revisit, mid-frame eviction) must land on the LIVE occupant's slot. The
/// previous location closures captured the registration-time node strongly
/// and re-resolved by node ID only, so post-re-mint updates wrote the
/// orphaned node's slots.
@MainActor
struct GestureStateRemintTests {
  @MainActor
  final class CapturedGestureBox {
    var box: GestureStateBox<Int>?
    var snapshot: ImperativeAuthoringContextSnapshot?
  }

  private struct GestureRemintProbe: View {
    static let column: UInt = 9

    @GestureState private var offset: Int
    let captured: CapturedGestureBox

    init(captured: CapturedGestureBox) {
      _offset = GestureState(initialValue: 0, line: 0, column: Self.column)
      self.captured = captured
    }

    var body: some View {
      // Capture what a recognizer captures: the box (via the projected
      // binding) and the imperative authoring snapshot its callbacks run
      // under.
      captured.box = $offset.box
      captured.snapshot = currentImperativeAuthoringContextSnapshot()
      return Text("static")
    }
  }

  private struct ReplacementProbe: View {
    var body: some View {
      Text("replacement")
    }
  }

  private static let offsetOrdinal = StateSlotOrdinals.authored(
    line: 0,
    column: GestureRemintProbe.column
  )

  @Test("a recognizer update after a same-identity re-mint lands on the live occupant")
  func recognizerUpdateFollowsIdentityAcrossRemint() throws {
    let captured = CapturedGestureBox()
    let probe = GestureRemintProbe(captured: captured)
    let graph = ViewGraph()
    let rootIdentity = testIdentity("GestureRemintRoot")
    let ownerIdentity = testIdentity("GestureRemintRoot", "Owner")
    graph.setRootEvaluator(rootIdentity: rootIdentity) {}

    func applyOwner() {
      _ = graph.applySnapshot(
        ResolvedNode(
          identity: rootIdentity,
          kind: .root,
          children: [
            ResolvedNode(identity: ownerIdentity, kind: .view("Owner"))
          ]
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
    let box = try #require(captured.box)
    let snapshot = try #require(captured.snapshot)
    let registered = try #require(graph.nodeForIdentity(ownerIdentity))

    // Leave and return: teardown evicts the owner, the next visit mints a
    // fresh node at the same identity (the lazy-tab revisit shape).
    _ = graph.applySnapshot(
      ResolvedNode(identity: rootIdentity, kind: .root, children: [])
    )
    applyOwner()
    let reminted = try #require(graph.nodeForIdentity(ownerIdentity))
    #expect(reminted !== registered, "the re-mint premise did not hold")

    // The recognizer fires: its box still holds the body-time location
    // (no fresh body ran for the gesture's owner). The write must follow
    // the identity to the live occupant.
    withImperativeAuthoringContext(snapshot) {
      box.setValue(42)
    }

    #expect(
      reminted.stateSlot(ordinal: Self.offsetOrdinal, seed: 0) == 42,
      "the recognizer update wrote the orphaned node's slot instead of the live occupant's"
    )
  }
}
