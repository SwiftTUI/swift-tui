import SwiftTUICore
import Testing

@testable import SwiftTUIRuntime

/// Pins the F66 head gate's controller-side contract: the resolved-tree
/// processing skip requires a processed baseline and a fully idle controller
/// (no animation batch on the transaction, no active animations, no removal
/// overlays), and the skip path counts its firings so integration shapes can
/// assert the gate is alive. The value-identity half of the proof (a
/// fully-reused resolve) is asserted at the skip site in DEBUG.
@MainActor
@Suite
struct AnimationResolvedTreeSkipTests {
  @Test("skip gate requires a processed baseline and an idle controller")
  func gateRequiresProcessedBaselineAndIdleController() {
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
}
