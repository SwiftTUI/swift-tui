/// Per-frame inputs shared across pipeline phases.
public struct FrameContext: Equatable, Sendable {
  public var environment: EnvironmentSnapshot
  public var transaction: TransactionSnapshot
  public var invalidatedIdentities: Set<Identity> {
    didSet {
      invalidationSummary = .init(
        invalidatedIdentities: invalidatedIdentities
      )
    }
  }
  package var invalidationSummary: InvalidationSummary
  public var timestamp: MonotonicInstant
  package var animationRequest: AnimationRequest
  package var animationBatchID: AnimationBatchID?

  /// Creates a frame context.
  public init(
    environment: EnvironmentSnapshot = .init(),
    transaction: TransactionSnapshot = .init(),
    invalidatedIdentities: Set<Identity> = [],
    timestamp: MonotonicInstant = .now()
  ) {
    self.environment = environment
    self.transaction = transaction
    self.invalidatedIdentities = invalidatedIdentities
    invalidationSummary = .init(
      invalidatedIdentities: invalidatedIdentities
    )
    self.timestamp = timestamp
    self.animationRequest = .inherit
    self.animationBatchID = nil
  }

  /// Creates a frame context with an animation request.
  package init(
    environment: EnvironmentSnapshot = .init(),
    transaction: TransactionSnapshot = .init(),
    invalidatedIdentities: Set<Identity> = [],
    timestamp: MonotonicInstant = .now(),
    animationRequest: AnimationRequest,
    animationBatchID: AnimationBatchID? = nil
  ) {
    self.environment = environment
    self.transaction = transaction
    self.invalidatedIdentities = invalidatedIdentities
    invalidationSummary = .init(
      invalidatedIdentities: invalidatedIdentities
    )
    self.timestamp = timestamp
    self.animationRequest = animationRequest
    self.animationBatchID = animationBatchID
  }

  /// Returns whether `identity` is directly invalidated in this frame.
  public func isInvalidated(_ identity: Identity) -> Bool {
    invalidatedIdentities.contains(identity)
  }

  /// Returns whether the invalidation set intersects the subtree rooted at
  /// `identity`.
  public func invalidationAffectsSubtree(
    at identity: Identity
  ) -> Bool {
    invalidationSummary.intersectsSubtree(at: identity)
  }
}
