/// One identity-scoped animation transaction coalesced into a frame.
///
/// Segments are ordered oldest to newest. Their identity sets are normalized
/// to be disjoint: a later segment removes only its exact identities from older
/// segments, so unrelated same-frame mutations keep their own transactions.
package struct AnimationInvalidationSegment: Equatable, Sendable {
  package var identities: Set<Identity>
  package var animationRequest: AnimationRequest
  package var animationBatchID: AnimationBatchID?

  package init(
    identities: Set<Identity>,
    animationRequest: AnimationRequest,
    animationBatchID: AnimationBatchID? = nil
  ) {
    self.identities = identities
    self.animationRequest = animationRequest
    self.animationBatchID = animationBatchID
  }

  package var isExplicit: Bool {
    animationRequest != .inherit || animationBatchID != nil
  }
}

/// Shared normalization and selection rules for animation invalidation
/// segments. Keeping them in the graph layer lets scheduler replay, portal
/// rewrites, stored evaluator refresh, and the animation controller use one
/// definition of latest-wins and most-specific selection.
package enum AnimationInvalidationSegments {
  /// Appends `incoming` as the newest segment, removing only exact contested
  /// identities from older segments.
  package static func append(
    _ incoming: AnimationInvalidationSegment,
    to segments: inout [AnimationInvalidationSegment]
  ) {
    guard incoming.isExplicit, !incoming.identities.isEmpty else {
      return
    }

    for index in segments.indices {
      segments[index].identities.subtract(incoming.identities)
    }
    segments.removeAll { $0.identities.isEmpty }
    segments.append(incoming)
  }

  /// Replays `segments` through the append rule, preserving their chronological
  /// order while resolving any collisions introduced by an identity rewrite.
  package static func normalized(
    _ segments: [AnimationInvalidationSegment]
  ) -> [AnimationInvalidationSegment] {
    var result: [AnimationInvalidationSegment] = []
    result.reserveCapacity(segments.count)
    for segment in segments {
      append(segment, to: &result)
    }
    return result
  }

  package static func identityUnion(
    _ segments: [AnimationInvalidationSegment]
  ) -> Set<Identity> {
    segments.reduce(into: Set<Identity>()) { result, segment in
      result.formUnion(segment.identities)
    }
  }

  /// Distinct live batch IDs in first-segment order.
  package static func liveBatchIDs(
    in segments: [AnimationInvalidationSegment]
  ) -> [AnimationBatchID] {
    var result: [AnimationBatchID] = []
    for batchID in segments.compactMap(\.animationBatchID)
    where !result.contains(batchID) {
      result.append(batchID)
    }
    return result
  }

  /// Rewrites segment identities and re-applies latest-wins ordering to any
  /// collisions the rewrite creates.
  package static func rewritingIdentities(
    in segments: [AnimationInvalidationSegment],
    _ transform: (Set<Identity>) -> Set<Identity>
  ) -> [AnimationInvalidationSegment] {
    normalized(
      segments.map { segment in
        var rewritten = segment
        rewritten.identities = transform(segment.identities)
        return rewritten
      }
    )
  }
}

/// Resolve/controller view of one frame's animation transactions.
package struct FrameAnimationTransactionPlan: Equatable, Sendable {
  package var base: TransactionSnapshot
  package var segments: [AnimationInvalidationSegment]

  package init(
    base: TransactionSnapshot,
    segments: [AnimationInvalidationSegment] = []
  ) {
    self.base = base
    self.segments = AnimationInvalidationSegments.normalized(segments)
  }

  package var hasExplicitTransactions: Bool {
    !segments.isEmpty
  }

  package var liveBatchIDs: [AnimationBatchID] {
    AnimationInvalidationSegments.liveBatchIDs(in: segments)
  }

  /// Every distinct transaction snapshot represented by this plan, base first.
  package var transactions: [TransactionSnapshot] {
    var result = [base]
    for segment in segments {
      let candidate = transaction(for: segment)
      if !result.contains(candidate) {
        result.append(candidate)
      }
    }
    return result
  }

  /// Selects the deepest segment identity that contains `identity`. Segment
  /// normalization makes exact collisions impossible; array order remains the
  /// deterministic tie-breaker after an external identity rewrite.
  package func transaction(for identity: Identity) -> TransactionSnapshot {
    guard let selected = segment(for: identity) else {
      return base
    }
    return transaction(for: selected)
  }

  package func segment(
    for identity: Identity
  ) -> AnimationInvalidationSegment? {
    var selected: AnimationInvalidationSegment?
    var selectedDepth = -1
    for segment in segments {
      for candidate in segment.identities
      where candidate == identity || candidate.isAncestor(of: identity) {
        let depth = candidate.components.count
        if depth >= selectedDepth {
          selected = segment
          selectedDepth = depth
        }
      }
    }
    return selected
  }

  private func transaction(
    for segment: AnimationInvalidationSegment
  ) -> TransactionSnapshot {
    var transaction = base
    transaction.animationRequest = segment.animationRequest
    transaction.animationBatchID = segment.animationBatchID
    return transaction
  }
}
