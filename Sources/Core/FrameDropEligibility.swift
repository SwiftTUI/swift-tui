/// Reports whether a completed frame can safely be dropped or must commit.
///
/// This is a **conservative observational classifier**.  It looks at the
/// signals available on a `FrameArtifacts` value and reports which
/// commit-blocking effects this particular frame carries.  It does not
/// drive any drop behavior on its own — the runtime still commits every
/// frame.  See `docs/proposals/ASYNC_FRAME_STALE_POLICY.md` Stage 4 for
/// the eventual behavior change this is staging for.
///
/// The classifier intentionally errs on the side of `mustCommit`: every
/// frame whose artifacts surface no specific blocker is still tagged
/// with the catch-all `.unobservable` blocker, because some commit-time
/// effects (animation completions firing during `applyInterpolations`,
/// focus binding drift relative to the previous frame, retained layout
/// baseline updates) are not visible from a single frame's artifacts.
///
/// As later stages teach the runtime to drop specific narrow cases —
/// say, a superseded animation tick with no lifecycle, focus, task,
/// preference, or handler transitions — this classifier will gain more
/// specific signals so `.unobservable` shrinks and `canDrop` can flip
/// to `true` for frames that genuinely have nothing the runtime needs.
public struct FrameDropEligibility: Equatable, Sendable {
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

    /// No specific blocker was observed in this frame's artifacts, but
    /// the runtime keeps the frame on the ordered-commit path because
    /// some commit-time effects are not visible from `FrameArtifacts`
    /// alone (animation completions, preference observation deltas,
    /// retained-layout baseline updates, focus-binding drift relative
    /// to the previous frame).  Future stages will refine this away
    /// as the classifier learns to detect each missing barrier.
    case unobservable
  }

  /// The set of barriers this frame's artifacts surface.  Always
  /// non-empty: when no specific blocker is detected, `.unobservable`
  /// is inserted so the runtime stays on the ordered-commit path.
  public let blockers: Set<Blocker>

  public init(blockers: Set<Blocker>) {
    self.blockers = blockers
  }

  /// Whether this frame is safe to drop.
  ///
  /// Currently always `false`.  The classifier inserts `.unobservable`
  /// when it cannot find a specific signal, so `blockers` is never
  /// empty.  Reserved for future stages that will both teach the
  /// classifier to detect more barriers and selectively allow drops
  /// for narrow visual-only cases.
  public var canDrop: Bool {
    blockers.isEmpty
  }

  /// Classifies a completed frame.
  ///
  /// This is a pure function of the frame's artifacts and does not
  /// observe runtime state outside of `FrameArtifacts`.  The verdict
  /// for any given artifact value is therefore stable and testable
  /// in isolation.
  public static func classify(_ artifacts: FrameArtifacts) -> Self {
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
    if blockers.isEmpty {
      blockers.insert(.unobservable)
    }
    return Self(blockers: blockers)
  }
}
