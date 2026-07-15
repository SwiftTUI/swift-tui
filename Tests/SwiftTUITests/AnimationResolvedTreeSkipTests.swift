import SwiftTUICore
import Testing

@testable import SwiftTUIRuntime

/// Pins the F66 head gate's controller-side contract: the resolved-tree
/// processing skip requires a processed baseline and no new animation batch.
/// Controller-owned in-flight work does not block an animation-equivalent tree from
/// skipping the snapshot/diff census (F149). The skip path counts its firings so
/// integration shapes can assert the gate is alive. The animation-equivalence
/// half of the proof (a fully-reused resolve) is asserted at the skip site in DEBUG.
@MainActor
@Suite
struct AnimationResolvedTreeSkipTests {
  @Test("skip gate requires a processed baseline and no new animation batch")
  func gateRequiresProcessedBaselineAndNoNewAnimationBatch() {
    let controller = AnimationController()
    let tree = ResolvedNode(
      identity: Identity(components: ["AnimationSkipRoot"]),
      kind: .view("Root")
    )
    let plain = TransactionSnapshot()

    // No processed baseline yet: the controller has nothing to diff against,
    // so the first frame must always process.
    #expect(!controller.canSkipResolvedTreeProcessing(transaction: plain))

    controller.processResolvedTree(
      tree,
      transaction: plain,
      timestamp: MonotonicInstant.now()
    )
    #expect(controller.canSkipResolvedTreeProcessing(transaction: plain))

    // A transaction opening an animation batch blocks the skip: an animation
    // could start, and its stranded-batch drain is owed even when nothing
    // interpolable changed.
    var animated = TransactionSnapshot()
    animated.animationRequest = .animate(
      controller.register(.linear(duration: .milliseconds(100)))
    )
    #expect(!controller.canSkipResolvedTreeProcessing(transaction: animated))

    // The skip path records its firing (integration tests assert liveness
    // through this counter) and stays skippable afterwards.
    #expect(controller.resolvedTreeProcessingSkipCount == 0)
    controller.noteSkippedResolvedTreeProcessing(resolved: tree)
    #expect(controller.resolvedTreeProcessingSkipCount == 1)
    #expect(controller.canSkipResolvedTreeProcessing(transaction: plain))
  }

  @Test("active property animation does not block an animation-equivalent tree skip")
  func activePropertyAnimationDoesNotBlockAnimationEquivalentTreeSkip() {
    let controller = AnimationController()
    let identity = Identity(components: ["AnimationSkipActiveLeaf"])
    var baseline = ResolvedNode(identity: identity, kind: .view("Leaf"))
    baseline.drawMetadata.baseStyle.explicitOpacity = 1
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(baseline, transaction: .init(), timestamp: t0)

    var target = baseline
    target.drawMetadata.baseStyle.explicitOpacity = 0
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(
      controller.register(.linear(duration: .milliseconds(500)))
    )
    controller.processResolvedTree(target, transaction: transaction, timestamp: t0)
    #expect(controller.activeAnimationCount == 1)

    #expect(
      controller.canSkipResolvedTreeProcessing(transaction: .init()),
      "a deadline-only tick owns no new authored target state to snapshot or diff"
    )
  }

  @Test("transaction-only changes do not invalidate an animation-equivalent skip")
  func transactionOnlyChangesDoNotInvalidateAnimationEquivalentSkip() {
    let controller = AnimationController()
    let identity = Identity(components: ["AnimationSkipDebugSignature"])
    let baseline = ResolvedNode(
      identity: identity,
      kind: .view("Leaf"),
      transactionSnapshot: .init(debugSignature: "baseline")
    )
    controller.processResolvedTree(
      baseline,
      transaction: .init(),
      timestamp: MonotonicInstant.now()
    )

    var transactionOnlyChange = TransactionSnapshot(debugSignature: "deadline")
    transactionOnlyChange.animationRequest = .disabled
    let reused = ResolvedNode(
      identity: identity,
      kind: .view("Leaf"),
      transactionSnapshot: transactionOnlyChange
    )
    #expect(controller.canSkipResolvedTreeProcessing(transaction: .init()))
    controller.noteSkippedResolvedTreeProcessing(resolved: reused)
    #expect(controller.resolvedTreeProcessingSkipCount == 1)
    #expect(controller.debugStateSnapshot().previousTreeRoot == reused)
  }
}
