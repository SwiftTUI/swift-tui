extension FrameDropBlocker {
  package static func blocker(for category: CommitEffectCategory) -> Self? {
    switch category {
    case .lifecycleAppear:
      .lifecycleAppear
    case .lifecycleDisappear:
      .lifecycleDisappear
    case .lifecycleChange:
      .lifecycleChange
    case .taskStart:
      .taskStart
    case .taskCancel:
      .taskCancel
    case .handlerInstallations:
      .handlerInstallations
    }
  }
}

/// Reports whether a completed frame candidate is visual-only or must commit.
package struct FrameDropEligibility: Equatable, Sendable {
  package typealias Blocker = FrameDropBlocker

  /// Candidate-level classification result.
  package enum Decision: Equatable, Sendable {
    case mustCommit(blockers: Set<Blocker>)
    case canDropVisualOnly
  }

  /// Inputs for candidate-level classification.
  package struct Candidate: Equatable, Sendable {
    /// The completed frame artifacts to classify.
    package var artifacts: FrameArtifacts

    /// Runtime-context blockers that are not stored directly in
    /// `FrameArtifacts`.
    package var additionalBlockers: Set<Blocker>

    /// Whether every formerly `.unobservable` barrier has an explicit signal in
    /// `artifacts` or `additionalBlockers`.
    package var hasCompleteBarrierSignals: Bool
    /// Whether handler installation entries are known to be redundant with the
    /// last committed runtime routing graph. This lets stale visual-only frames
    /// with stable interactive chrome drop without reinstalling equivalent
    /// handlers.
    package var redundantHandlerInstallationsAreVisualOnly: Bool

    package init(
      artifacts: FrameArtifacts,
      additionalBlockers: Set<Blocker> = [],
      hasCompleteBarrierSignals: Bool = false,
      redundantHandlerInstallationsAreVisualOnly: Bool = false
    ) {
      self.artifacts = artifacts
      self.additionalBlockers = additionalBlockers
      self.hasCompleteBarrierSignals = hasCompleteBarrierSignals
      self.redundantHandlerInstallationsAreVisualOnly =
        redundantHandlerInstallationsAreVisualOnly
    }
  }

  /// The candidate-level decision.
  package let decision: Decision

  /// Closed non-visual impact categories used to derive ``decision``.
  package let impact: CompletedFrameImpact

  /// The set of barriers this frame's artifacts surface.  Observational
  /// classifiers keep this non-empty by inserting `.unobservable`; fully
  /// classified candidates can return an empty set.
  package var blockers: Set<Blocker> {
    switch decision {
    case .mustCommit(let blockers):
      blockers
    case .canDropVisualOnly:
      []
    }
  }

  package init(blockers: Set<Blocker>) {
    self.init(
      blockers: blockers,
      impact: CompletedFrameImpact(blockers: blockers)
    )
  }

  private init(
    blockers: Set<Blocker>,
    impact: CompletedFrameImpact
  ) {
    if blockers.isEmpty {
      decision = .canDropVisualOnly
    } else {
      decision = .mustCommit(blockers: blockers)
    }
    self.impact = impact
  }

  package init(decision: Decision) {
    self.init(
      decision: decision,
      impact: Self.impact(for: decision)
    )
  }

  private init(
    decision: Decision,
    impact: CompletedFrameImpact
  ) {
    self.decision = decision
    self.impact = impact
  }

  /// Whether this frame is safe to drop.
  ///
  /// Currently always `false`. Runtime code should use the explicit
  /// completed-frame policy and reconciliation result, not this compatibility
  /// flag, before skipping commit.
  package var canDrop: Bool {
    false
  }

  /// Classifies a completed frame.
  ///
  /// This is a pure function of the frame's artifacts and does not
  /// observe runtime state outside of `FrameArtifacts`.  The verdict
  /// for any given artifact value is therefore stable and testable
  /// in isolation.
  package static func classify(_ artifacts: FrameArtifacts) -> Self {
    classify(artifacts, additionalBlockers: [])
  }

  /// Classifies a completed frame with runtime-context blockers that are not
  /// stored directly in `FrameArtifacts`.
  package static func classify(
    _ artifacts: FrameArtifacts,
    additionalBlockers: Set<Blocker>
  ) -> Self {
    classify(
      Candidate(
        artifacts: artifacts,
        additionalBlockers: additionalBlockers,
        hasCompleteBarrierSignals: false
      ))
  }

  /// Classifies a completed frame candidate.
  ///
  /// A candidate can be reported as `.canDropVisualOnly` only when the caller has
  /// proven that every non-visual barrier is represented by explicit blocker
  /// signals.  Otherwise an otherwise-empty blocker set is still treated as
  /// `.unobservable` and therefore `.mustCommit`.
  package static func classify(_ candidate: Candidate) -> Self {
    let artifacts = candidate.artifacts
    var blockers: Set<Blocker> = []
    var impact = CompletedFrameImpact()
    func record(_ blocker: Blocker) {
      blockers.insert(blocker)
      impact.formUnion(CompletedFrameImpact(blocker: blocker))
    }

    for category in artifacts.commitPlan.effectCategories {
      if category == .handlerInstallations,
        candidate.redundantHandlerInstallationsAreVisualOnly
      {
        continue
      }
      record(Blocker.blocker(for: category) ?? .unobservable)
    }
    if artifacts.diagnostics.work.customLayoutFallbackCount > 0 {
      record(.customLayoutFallback)
    }
    for blocker in candidate.additionalBlockers {
      record(blocker)
    }
    for blocker in artifacts.diagnostics.drop.eligibilityBlockers {
      record(blocker)
    }
    if let damage = artifacts.diagnostics.presentation.damage {
      if damage.requiresFullTextRepaint {
        record(.presentationFullRepaint)
      }
      if damage.requiresFullGraphicsReplay || damage.graphicsInvalidationCount > 0 {
        record(.graphicsReplay)
      }
    }
    if impact.isVisualOnly, candidate.hasCompleteBarrierSignals {
      return Self(decision: .canDropVisualOnly, impact: impact)
    }
    if blockers.isEmpty {
      record(.unobservable)
    }
    return Self(blockers: blockers, impact: impact)
  }

  package static func frameTailCommitBlockers(
    hasWorkerCustomLayoutCacheUpdates: Bool
  ) -> Set<Blocker> {
    var blockers: Set<Blocker> = []
    if hasWorkerCustomLayoutCacheUpdates {
      blockers.insert(.workerCustomLayoutCacheUpdate)
    }
    return blockers
  }

  private static func impact(for decision: Decision) -> CompletedFrameImpact {
    switch decision {
    case .canDropVisualOnly:
      return CompletedFrameImpact()
    case .mustCommit(let blockers):
      return CompletedFrameImpact(blockers: blockers)
    }
  }
}
