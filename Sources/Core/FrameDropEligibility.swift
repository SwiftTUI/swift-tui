/// Reports whether a completed frame candidate is visual-only or must commit.
///
/// This is a **conservative classifier**.  The legacy artifact entry points are
/// still observational and inject `.unobservable` when no blocker is detected.
/// The candidate entry point can produce `.canDropVisualOnly`, but it does not
/// drive any drop behavior on its own. Higher-level completed-frame policy still
/// has to prove the candidate is stale and select an available reconciliation
/// mode before commit can be skipped.
///
/// The classifier intentionally errs on the side of `mustCommit`: every
/// frame whose artifacts and runtime context surface no specific blocker is
/// still tagged with the catch-all `.unobservable` blocker, because some
/// candidate-level effects are not visible from `FrameArtifacts` alone.
///
/// The classifier feeds the explicit completed-frame policy without weakening
/// ordered commit for frames that surface lifecycle, focus, task, preference,
/// animation, handler, cache, retained-baseline, or presentation barriers.
public struct FrameDropEligibility: Equatable, Sendable {
  /// Candidate-level classification result.
  public enum Decision: Equatable, Sendable {
    /// The frame carries commit-time effects that must either commit in order or
    /// be reconciled by a future skipped-frame policy.
    case mustCommit(blockers: Set<Blocker>)

    /// The frame carries no observed non-visual effects and is eligible for the
    /// completed-frame stale policy to consider.
    case canDropVisualOnly
  }

  /// A specific reason a frame must commit rather than being dropped.
  ///
  /// Each case corresponds to one barrier from the stale-policy
  /// proposal.  A frame's blocker set may contain multiple cases — for
  /// example, a frame can carry both an `appear` lifecycle edge and a
  /// task start.
  public enum Blocker: String, Sendable, CaseIterable, Hashable {
    /// The frame's commit plan contains at least one `.appear`
    /// lifecycle entry.  Dropping the frame would skip the `onAppear`
    /// handler that just fired.
    case lifecycleAppear

    /// The frame's commit plan contains at least one `.disappear`
    /// lifecycle entry.  Dropping the frame would skip the
    /// `onDisappear` handler.
    case lifecycleDisappear

    /// The frame's commit plan contains at least one `.change`
    /// lifecycle entry.  Dropping the frame would skip an
    /// `onChange(of:)` callback.
    case lifecycleChange

    /// The frame's commit plan contains at least one `.taskStart`
    /// entry.  Dropping the frame would prevent the corresponding
    /// `.task` block from launching.
    case taskStart

    /// The frame's commit plan contains at least one `.taskCancel`
    /// entry.  Dropping the frame would leave a previously-launched
    /// task running past its supposed cancellation point.
    case taskCancel

    /// The frame's commit plan installs at least one runtime handler
    /// (action, key, pointer, gesture, drop destination, ...).
    /// Dropping the frame would leave the live registries pointing at
    /// stale handlers from an earlier resolved tree.
    case handlerInstallations

    /// At least one custom-layout subtree fell back to main-actor
    /// measure/place during this frame.  Dropping the frame would
    /// leave the worker's layout cache for that subtree out of sync
    /// with the committed tree.
    case customLayoutFallback

    /// Focus regions changed while the runtime reconciled this frame.
    /// Dropping the frame would skip the committed semantic focus graph
    /// update the focus tracker used to converge.
    case focusGraph

    /// Focus-binding sync changed authored focus state or applied a
    /// pending focus request during this frame.
    case focusBindingSync

    /// Focused values changed for the committed focus identity.
    case focusedValueSync

    /// Scroll-position sync adjusted a bound scroll position.
    case scrollSync

    /// Preference observation handlers observed a changed preference
    /// value during this frame.
    case preferenceObservationDelta

    /// At least one animation completion is pending, deferred, or
    /// fired through this frame's animation bookkeeping.
    case animationCompletion

    /// Transition bookkeeping is present.  Dropping the frame could
    /// lose insertion, removal, or matched-geometry state that later
    /// ticks rely on.
    case animationTransition

    /// The scheduled frame carried a one-shot animation transaction.
    /// Dropping it would discard the transaction's animation intent.
    case animationTransaction

    /// Worker-side custom layout cache updates were produced by this
    /// frame and must either be committed or explicitly reconciled.
    case workerCustomLayoutCacheUpdate

    /// Committing the frame refreshes the retained layout baseline
    /// used by later incremental placement.
    case retainedLayoutBaseline

    /// Committing the frame refreshes the retained raster baseline
    /// used by later incremental presentation damage.
    case retainedRasterBaseline

    /// The frame participates in full text repaint recovery.
    case presentationFullRepaint

    /// The frame carries graphics invalidation or full graphics
    /// replay requirements.
    case graphicsReplay

    /// Runtime diagnostics are configured to require an explicit
    /// committed-frame record for this completed frame.
    case diagnosticsFullRecord

    /// No specific blocker was observed in this frame's artifacts, but
    /// the runtime keeps the frame on the ordered-commit path because
    /// some candidate-level effects are still not visible from the
    /// current classifier.  Future stages will refine this away as the
    /// runtime learns to detect each missing barrier.
    case unobservable
  }

  /// Inputs for candidate-level classification.
  public struct Candidate: Equatable, Sendable {
    /// The completed frame artifacts to classify.
    public var artifacts: FrameArtifacts

    /// Runtime-context blockers that are not stored directly in
    /// `FrameArtifacts`.
    public var additionalBlockers: Set<Blocker>

    /// Whether every formerly `.unobservable` barrier has an explicit signal in
    /// `artifacts` or `additionalBlockers`.
    public var hasCompleteBarrierSignals: Bool

    public init(
      artifacts: FrameArtifacts,
      additionalBlockers: Set<Blocker> = [],
      hasCompleteBarrierSignals: Bool = false
    ) {
      self.artifacts = artifacts
      self.additionalBlockers = additionalBlockers
      self.hasCompleteBarrierSignals = hasCompleteBarrierSignals
    }
  }

  /// The candidate-level decision.
  public let decision: Decision

  /// The set of barriers this frame's artifacts surface.  Observational
  /// classifiers keep this non-empty by inserting `.unobservable`; fully
  /// classified candidates can return an empty set.
  public var blockers: Set<Blocker> {
    switch decision {
    case .mustCommit(let blockers):
      blockers
    case .canDropVisualOnly:
      []
    }
  }

  public init(blockers: Set<Blocker>) {
    if blockers.isEmpty {
      decision = .canDropVisualOnly
    } else {
      decision = .mustCommit(blockers: blockers)
    }
  }

  public init(decision: Decision) {
    self.decision = decision
  }

  /// Whether this frame is safe to drop.
  ///
  /// Currently always `false`. Runtime code should use the explicit
  /// completed-frame policy and reconciliation result, not this compatibility
  /// flag, before skipping commit.
  public var canDrop: Bool {
    false
  }

  /// Classifies a completed frame.
  ///
  /// This is a pure function of the frame's artifacts and does not
  /// observe runtime state outside of `FrameArtifacts`.  The verdict
  /// for any given artifact value is therefore stable and testable
  /// in isolation.
  public static func classify(_ artifacts: FrameArtifacts) -> Self {
    classify(artifacts, additionalBlockers: [])
  }

  /// Classifies a completed frame with runtime-context blockers that are not
  /// stored directly in `FrameArtifacts`.
  public static func classify(
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
  public static func classify(_ candidate: Candidate) -> Self {
    let artifacts = candidate.artifacts
    var blockers: Set<Blocker> = []
    for entry in artifacts.commitPlan.lifecycle {
      switch entry.operation {
      case .appear:
        blockers.insert(.lifecycleAppear)
      case .disappear:
        blockers.insert(.lifecycleDisappear)
      case .change:
        blockers.insert(.lifecycleChange)
      case .taskStart:
        blockers.insert(.taskStart)
      case .taskCancel:
        blockers.insert(.taskCancel)
      }
    }
    if !artifacts.commitPlan.handlerInstallations.isEmpty {
      blockers.insert(.handlerInstallations)
    }
    if artifacts.diagnostics.customLayoutFallbackCount > 0 {
      blockers.insert(.customLayoutFallback)
    }
    blockers.formUnion(candidate.additionalBlockers)
    blockers.formUnion(artifacts.diagnostics.dropEligibilityBlockers)
    if let damage = artifacts.diagnostics.presentationDamage {
      if damage.requiresFullTextRepaint {
        blockers.insert(.presentationFullRepaint)
      }
      if damage.requiresFullGraphicsReplay || damage.graphicsInvalidationCount > 0 {
        blockers.insert(.graphicsReplay)
      }
    }
    if blockers.isEmpty {
      if candidate.hasCompleteBarrierSignals {
        return Self(decision: .canDropVisualOnly)
      }
      blockers.insert(.unobservable)
    }
    return Self(blockers: blockers)
  }
}
