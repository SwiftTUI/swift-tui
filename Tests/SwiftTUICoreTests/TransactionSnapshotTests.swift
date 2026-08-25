import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@Suite("TransactionSnapshot reuse equivalence")
struct TransactionSnapshotTests {
  @Test("debug signatures do not affect retained reuse equivalence")
  func debugSignaturesDoNotAffectReuseEquivalence() {
    let first = TransactionSnapshot(debugSignature: "frame-a")
    let second = TransactionSnapshot(debugSignature: "frame-b")

    #expect(first.isReuseEquivalent(to: second))
  }

  @Test("animation requests affect retained reuse equivalence")
  func animationRequestsAffectReuseEquivalence() {
    let inherited = TransactionSnapshot()
    var disabled = TransactionSnapshot()
    disabled.animationRequest = .disabled

    #expect(!inherited.isReuseEquivalent(to: disabled))
  }

  @Test("animation batch IDs affect retained reuse equivalence")
  func animationBatchIDsAffectReuseEquivalence() {
    let unbatched = TransactionSnapshot()
    var batched = TransactionSnapshot()
    batched.animationBatchID = AnimationBatchID(1)

    #expect(!unbatched.isReuseEquivalent(to: batched))
  }

  @Test("isContinuous affects retained reuse equivalence")
  func isContinuousAffectsReuseEquivalence() {
    // A resolve-time reader (a `.transaction` transform) observes the flag,
    // so serving a stale value under subtree reuse would be a correctness
    // bug, not a performance choice. Continuity flips are rare (gesture
    // start and end), so the reuse cost is two denials per gesture.
    let discrete = TransactionSnapshot()
    var continuous = TransactionSnapshot()
    continuous.isContinuous = true

    #expect(!discrete.isReuseEquivalent(to: continuous))
  }

  @Test("scopeRole affects retained reuse equivalence")
  func scopeRoleAffectsReuseEquivalence() {
    // The animation controller reads the role at processing time to decide
    // which ancestor a scoped placeholder inherits from, so a reused subtree
    // must not serve a stale role.
    let plain = TransactionSnapshot()
    var placeholder = TransactionSnapshot()
    placeholder.scopeRole = .restoresOuter

    #expect(!plain.isReuseEquivalent(to: placeholder))
  }

  @Test("a frame plan's segment selection carries isContinuous")
  func planSegmentSelectionCarriesIsContinuous() {
    let identity = Identity(components: ["root", "leaf"])
    var segment = AnimationInvalidationSegment(
      identities: [identity],
      animationRequest: .disabled
    )
    segment.isContinuous = true
    let plan = FrameAnimationTransactionPlan(
      base: TransactionSnapshot(),
      segments: [segment]
    )

    #expect(plan.transaction(for: identity).isContinuous)
    #expect(!plan.transaction(for: Identity(components: ["root"])).isContinuous)
  }
}
