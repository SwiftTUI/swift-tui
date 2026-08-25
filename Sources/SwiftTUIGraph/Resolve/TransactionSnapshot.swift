/// A transaction snapshot captured while resolving a frame.
public struct TransactionSnapshot: Equatable, Sendable {
  public var debugSignature: String
  package var animationRequest: AnimationRequest = .inherit
  /// Optional batch identifier used to associate every animation
  /// enqueued under the same ``withAnimation`` scope so the animation
  /// controller can fire a single completion closure once the whole
  /// batch has settled.
  package var animationBatchID: AnimationBatchID? = nil
  /// Whether the transaction reports a continuous or fluid update, e.g.
  /// one of a stream of during-gesture writes. Authored transforms and
  /// scoped writes set it; resolve-time transforms read it. It carries no
  /// animation intent of its own — a continuity-only transaction is not
  /// animation-explicit (see `AnimationInvalidationSegment.isExplicit`).
  package var isContinuous: Bool = false
  /// Custom `TransactionKey` values, keyed by the key type's identity.
  /// Like `isContinuous`, resolve-side data with no animation intent of
  /// its own.
  package var customValues: [ObjectIdentifier: AnyHashableSendable] = [:]
  /// The node's part in a scoped transaction (`View.animation(_:body:)` /
  /// `View.transaction(_:body:)`); `.none` for every ordinary node.
  package var scopeRole: TransactionScopeRole = .none

  public init(debugSignature: String = "") {
    self.debugSignature = debugSignature
  }

  /// Returns `true` when two snapshots carry equivalent resolve-time intent.
  ///
  /// Unlike `==`, this ignores debug-only fields such as `debugSignature`
  /// that would otherwise defeat retained resolve reuse. `isContinuous`
  /// participates: a `.transaction` transform reads it at resolve, so a
  /// reused subtree would otherwise observe a stale value. Continuity flips
  /// are rare (gesture start and end), costing two denials per gesture.
  package func isReuseEquivalent(to other: Self) -> Bool {
    animationRequest == other.animationRequest
      && animationBatchID == other.animationBatchID
      && isContinuous == other.isContinuous
      && customValues == other.customValues
      && scopeRole == other.scopeRole
  }
}

/// How a resolved node takes part in a scoped transaction. The animation
/// controller inherits an `.inherit` request from the resolved parent; the
/// two roles let a scoped modifier's wrapped content inherit from *outside*
/// the scope instead.
package enum TransactionScopeRole: Sendable, Equatable {
  /// An ordinary node.
  case none
  /// The scoped modifier's own node: its effective transaction is the
  /// "outer" transaction its placeholder restores.
  case scopeRoot
  /// The placeholder standing in for the wrapped content: an `.inherit`
  /// request here inherits from the nearest `scopeRoot` ancestor's
  /// effective transaction, not from the scoped parent.
  case restoresOuter
}
