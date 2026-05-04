/// A transaction snapshot captured while resolving a frame.
public struct TransactionSnapshot: Equatable, Sendable {
  public var debugSignature: String
  package var animationRequest: AnimationRequest = .inherit
  /// Optional batch identifier used to associate every animation
  /// enqueued under the same ``withAnimation`` scope so the animation
  /// controller can fire a single completion closure once the whole
  /// batch has settled.
  package var animationBatchID: AnimationBatchID? = nil

  public init(debugSignature: String = "") {
    self.debugSignature = debugSignature
  }

  /// Returns `true` when two snapshots carry equivalent resolve-time intent.
  ///
  /// Unlike `==`, this ignores debug-only fields such as `debugSignature`
  /// that would otherwise defeat retained resolve reuse.
  package func isReuseEquivalent(to other: Self) -> Bool {
    animationRequest == other.animationRequest
      && animationBatchID == other.animationBatchID
  }
}
