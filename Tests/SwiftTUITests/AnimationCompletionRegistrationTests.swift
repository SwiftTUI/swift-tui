import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Stage T0 pins for completion registration (plan 2026-08-25-002 §6, T1 +
/// T3): list-valued completions with per-closure barriers,
/// `Transaction.addAnimationCompletion`, and `Animation.logicallyComplete(after:)`.
/// Driven deterministically through the controller with explicit timestamps.
@MainActor
@Suite("Animation completion registration")
struct AnimationCompletionRegistrationTests {
  /// Records completion firings in order.
  @MainActor
  private final class FiringLog {
    private(set) var entries: [String] = []
    func record(_ label: String) { entries.append(label) }
  }

  private static func leaf(_ identity: Identity, opacity: Double) -> ResolvedNode {
    var metadata = DrawMetadata()
    metadata.baseStyle.explicitOpacity = opacity
    return ResolvedNode(identity: identity, kind: .view("Leaf"), drawMetadata: metadata)
  }

  /// Runs frame 1 at full opacity and frame 2 at zero opacity under
  /// `transaction`, returning the frame-2 tree to tick.
  private static func startFade(
    _ controller: AnimationController,
    identity: Identity,
    transaction: TransactionSnapshot,
    at t0: MonotonicInstant
  ) -> ResolvedNode {
    controller.processResolvedTree(leaf(identity, opacity: 1), transaction: .init(), timestamp: t0)
    let frame2 = leaf(identity, opacity: 0)
    controller.processResolvedTree(frame2, transaction: transaction, timestamp: t0)
    return frame2
  }

  // MARK: - List-valued completions

  @Test("two completions registered on one batch both fire")
  func twoCompletionsOnOneBatchBothFire() {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(100))
    controller.register(animation)
    let batchID = AnimationBatchID(8_001)
    let log = FiringLog()
    controller.registerCompletion(batchID: batchID) { log.record("first") }
    controller.registerCompletion(batchID: batchID) { log.record("second") }

    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    transaction.animationBatchID = batchID
    let t0 = MonotonicInstant.now()
    var tree = Self.startFade(
      controller, identity: testIdentity("two-completions"), transaction: transaction, at: t0
    )

    _ = controller.applyInterpolations(to: &tree, at: t0.advanced(by: .milliseconds(50)))
    #expect(log.entries.isEmpty)
    _ = controller.applyInterpolations(to: &tree, at: t0.advanced(by: .milliseconds(150)))
    #expect(log.entries == ["first", "second"], "registration order, both fired once")
    #expect(controller.debugStateSnapshot().completionClosureBatchIDs.isEmpty)
  }

  @Test("logicallyComplete(after:) fires the logical barrier early while .removed waits")
  func logicalDurationSplitsBarriers() {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(1_000))
      .logicallyComplete(after: .milliseconds(200))
    controller.register(animation)
    let batchID = AnimationBatchID(8_002)
    let log = FiringLog()
    controller.registerCompletion(batchID: batchID, barrier: .logicallyComplete) {
      log.record("logical")
    }
    controller.registerCompletion(batchID: batchID, barrier: .removed) {
      log.record("removed")
    }

    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    transaction.animationBatchID = batchID
    let t0 = MonotonicInstant.now()
    var tree = Self.startFade(
      controller, identity: testIdentity("logical-split"), transaction: transaction, at: t0
    )

    _ = controller.applyInterpolations(to: &tree, at: t0.advanced(by: .milliseconds(100)))
    #expect(log.entries.isEmpty, "before the logical instant nothing fires")
    _ = controller.applyInterpolations(to: &tree, at: t0.advanced(by: .milliseconds(250)))
    #expect(log.entries == ["logical"], "the logical barrier fires while the curve keeps running")
    #expect(controller.activeAnimationCount == 1, "the curve is still in flight")
    _ = controller.applyInterpolations(to: &tree, at: t0.advanced(by: .milliseconds(600)))
    #expect(log.entries == ["logical"], "the logical barrier fires only once")
    _ = controller.applyInterpolations(to: &tree, at: t0.advanced(by: .milliseconds(1_100)))
    #expect(log.entries == ["logical", "removed"], ".removed fires when the curve ends")
    #expect(controller.activeAnimationCount == 0)
  }

  @Test("a stranded batch drains at the logical duration when every registration is logical")
  func strandedDrainHonorsLogicalDuration() {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(1_000))
      .logicallyComplete(after: .milliseconds(200))
    controller.register(animation)
    let batchID = AnimationBatchID(8_003)
    let log = FiringLog()
    controller.registerCompletion(batchID: batchID) { log.record("logical") }

    // Nothing animatable changes between the frames: the batch strands.
    let identity = testIdentity("stranded-logical")
    let frame = ResolvedNode(identity: identity, kind: .view("Leaf"))
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame, transaction: .init(), timestamp: t0)
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    transaction.animationBatchID = batchID
    var tree = frame
    controller.processResolvedTree(tree, transaction: transaction, timestamp: t0)

    _ = controller.applyInterpolations(to: &tree, at: t0.advanced(by: .milliseconds(150)))
    #expect(log.entries.isEmpty)
    _ = controller.applyInterpolations(to: &tree, at: t0.advanced(by: .milliseconds(250)))
    #expect(log.entries == ["logical"], "drained at the shorter logical duration")
  }

  @Test("a stranded batch with a .removed registration drains at the full duration")
  func strandedDrainWaitsForRemovedRegistration() {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(1_000))
      .logicallyComplete(after: .milliseconds(200))
    controller.register(animation)
    let batchID = AnimationBatchID(8_004)
    let log = FiringLog()
    controller.registerCompletion(batchID: batchID, barrier: .logicallyComplete) {
      log.record("logical")
    }
    controller.registerCompletion(batchID: batchID, barrier: .removed) { log.record("removed") }

    let identity = testIdentity("stranded-mixed")
    let frame = ResolvedNode(identity: identity, kind: .view("Leaf"))
    let t0 = MonotonicInstant.now()
    controller.processResolvedTree(frame, transaction: .init(), timestamp: t0)
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    transaction.animationBatchID = batchID
    var tree = frame
    controller.processResolvedTree(tree, transaction: transaction, timestamp: t0)

    _ = controller.applyInterpolations(to: &tree, at: t0.advanced(by: .milliseconds(500)))
    #expect(log.entries.isEmpty)
    _ = controller.applyInterpolations(to: &tree, at: t0.advanced(by: .milliseconds(1_100)))
    #expect(log.entries == ["logical", "removed"])
  }

  // MARK: - Transaction.addAnimationCompletion through withTransaction

  @Test("withTransaction registers every added completion on one batch and scopes the batch ID")
  func withTransactionRegistersAddedCompletions() {
    let sink = RecordingCompletionSink()
    var transaction = Transaction(animation: .linear(duration: .milliseconds(100)))
    transaction.addAnimationCompletion {}
    transaction.addAnimationCompletion(criteria: .removed) {}

    var observedBatch: AnimationBatchID?
    AnimationCompletionStorage.withSink(sink) {
      withTransaction(transaction) {
        observedBatch = AnimationContextStorage.currentBatchID
      }
    }

    #expect(observedBatch != nil, "the scope carries the batch its completions registered on")
    #expect(sink.registrations.count == 2)
    #expect(Set(sink.registrations.map(\.batchID)).count == 1, "both on the same batch")
    #expect(sink.registrations.map(\.barrier) == [.logicallyComplete, .removed])
    #expect(sink.registrations.first?.batchID == observedBatch)
  }

  @Test("withAnimation's completion overload takes the same batch path")
  func withAnimationCompletionUsesSharedPath() {
    let sink = RecordingCompletionSink()
    var observedBatch: AnimationBatchID?
    AnimationCompletionStorage.withSink(sink) {
      withAnimation(.linear(duration: .milliseconds(100)), completionCriteria: .removed) {
        observedBatch = AnimationContextStorage.currentBatchID
      } completion: {
      }
    }
    #expect(sink.registrations.count == 1)
    #expect(sink.registrations.first?.barrier == .removed)
    #expect(sink.registrations.first?.batchID == observedBatch)
  }

  @Test("a binding-stored completion registers per write outside any scope and never inside one")
  func bindingStoredCompletionRegistersOutsideScopesOnly() {
    let sink = RecordingCompletionSink()
    let store = ValueStore()
    var transaction = Transaction(animation: .linear(duration: .milliseconds(100)))
    transaction.addAnimationCompletion {}
    let binding = Binding(
      get: { store.value },
      set: { store.value = $0 }
    ).transaction(transaction)

    AnimationCompletionStorage.withSink(sink) {
      binding.wrappedValue = 1
      binding.wrappedValue = 2
      #expect(sink.registrations.count == 2, "one registration per write outside a scope")

      withAnimation(.easeInOut) {
        binding.wrappedValue = 3
      }
      #expect(
        sink.registrations.count == 2,
        "a write inside withAnimation never sees the stored transaction")
    }
    #expect(store.value == 3)
  }
}

// MARK: - Support

@MainActor
private final class RecordingCompletionSink: AnimationCompletionSink {
  struct Registration {
    var batchID: AnimationBatchID
    var barrier: AnimationCompletionBarrier
  }

  private(set) var registrations: [Registration] = []

  func registerCompletion(
    batchID: AnimationBatchID,
    barrier: AnimationCompletionBarrier,
    closure: @escaping @MainActor @Sendable () -> Void
  ) {
    registrations.append(Registration(batchID: batchID, barrier: barrier))
  }
}

@MainActor
private final class ValueStore {
  var value = 0
}
