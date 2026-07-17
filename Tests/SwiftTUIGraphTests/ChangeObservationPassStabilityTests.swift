import Testing

@testable import SwiftTUIGraph

/// Pins the pass-stable read semantics of the `onChange` previous-value store
/// (gallery fuzzer, 2026-07-17 §9.5: the palette-sheet `onChange` skip).
///
/// `ChangeLifecycleModifier` registers its committed change handler only on a
/// resolve whose should-trigger decision fires, and every fresh resolve resets
/// the owner node's registration records. A same-pass re-resolve (the
/// presentation-portal reconcile re-resolves overlay subtrees) must therefore
/// reproduce the first resolve's trigger decision, or it erases the record and
/// registers nothing — the committed change entry then dispatches into hollow
/// stores. That reduces to one store contract: reads within the pass that
/// wrote an entry see the pass's baseline, not the pass's own writes.
@MainActor
@Suite
struct ChangeObservationPassStabilityTests {
  private let identity = testIdentity("Root", "Palette")

  @Test("same-pass reads see the pass baseline, not the pass's own writes")
  func samePassReadsSeeBaseline() {
    let graph = ViewGraph()
    graph.beginFrame()

    // First observation ever: the write must stay invisible to this pass so a
    // re-resolve recomputes "no previous value" and re-arms `initial:`.
    graph.recordChangeObservationValue(1, identity: identity, ordinal: 0)
    #expect(!graph.hasChangeObservationValue(identity: identity, ordinal: 0))
    #expect(graph.changeObservationValue(identity: identity, ordinal: 0, as: Int.self) == nil)

    // Later same-pass writes update the stored value but not the baseline.
    graph.recordChangeObservationValue(2, identity: identity, ordinal: 0)
    #expect(!graph.hasChangeObservationValue(identity: identity, ordinal: 0))
    #expect(graph.changeObservationValue(identity: identity, ordinal: 0, as: Int.self) == nil)

    // The next pass observes the last committed write as the previous value.
    graph.beginFrame()
    #expect(graph.hasChangeObservationValue(identity: identity, ordinal: 0))
    #expect(graph.changeObservationValue(identity: identity, ordinal: 0, as: Int.self) == 2)
  }

  @Test("a later pass's writes shift the previous pass's value into the baseline")
  func laterPassWritesShiftBaseline() {
    let graph = ViewGraph()
    graph.beginFrame()
    graph.recordChangeObservationValue(1, identity: identity, ordinal: 0)

    graph.beginFrame()
    graph.recordChangeObservationValue(5, identity: identity, ordinal: 0)
    // A same-pass re-resolve compares against pass entry state (1), so it
    // recomputes the 1 → 5 transition — and re-registers the handler the
    // capture reset erased.
    #expect(graph.hasChangeObservationValue(identity: identity, ordinal: 0))
    #expect(graph.changeObservationValue(identity: identity, ordinal: 0, as: Int.self) == 1)

    graph.recordChangeObservationValue(7, identity: identity, ordinal: 0)
    #expect(graph.changeObservationValue(identity: identity, ordinal: 0, as: Int.self) == 1)

    // The next pass reads the last write.
    graph.beginFrame()
    #expect(graph.changeObservationValue(identity: identity, ordinal: 0, as: Int.self) == 7)
  }

  @Test("distinct ordinals at one identity keep independent baselines")
  func distinctOrdinalsAreIndependent() {
    let graph = ViewGraph()
    graph.beginFrame()
    graph.recordChangeObservationValue(1, identity: identity, ordinal: 0)

    graph.beginFrame()
    graph.recordChangeObservationValue(2, identity: identity, ordinal: 0)
    graph.recordChangeObservationValue(9, identity: identity, ordinal: 1)

    #expect(graph.changeObservationValue(identity: identity, ordinal: 0, as: Int.self) == 1)
    // Ordinal 1's first-ever observation stays invisible within its pass.
    #expect(!graph.hasChangeObservationValue(identity: identity, ordinal: 1))
  }
}
