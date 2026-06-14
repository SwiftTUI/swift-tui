import Testing

@testable import SwiftTUICore

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
}
