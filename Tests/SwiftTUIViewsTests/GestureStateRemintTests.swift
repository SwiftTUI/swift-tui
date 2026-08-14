import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

/// A recognizer registration belongs to one exact graph-owner lifetime. An
/// authored identity can be re-minted for a different entity after teardown;
/// stale recognizer updates must remain inert with respect to that new owner.
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

  @Test("a recognizer update does not cross a same-identity owner re-mint")
  func recognizerUpdateDoesNotCrossOwnerRemint() throws {
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

    // The recognizer fires with its retired owner handle. Identity equality is
    // not successor authority, so the write may update only the retired
    // binding's transient fallback, never the live replacement slot.
    withImperativeAuthoringContext(snapshot) {
      box.setValue(42)
    }

    #expect(
      reminted.stateSlot(ordinal: Self.offsetOrdinal, seed: 0) == 0,
      "the retired recognizer crossed into a distinct owner lifetime"
    )
  }
}
