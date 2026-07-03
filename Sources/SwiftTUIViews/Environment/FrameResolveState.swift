package import SwiftTUICore

package struct RetainedReuseSuppressionScope: Equatable, Sendable {
  package var suppressesAll: Bool
  package var identities: Set<Identity>

  package static let none = Self()
  package static let all = Self(suppressesAll: true)

  package init(
    suppressesAll: Bool = false,
    identities: Set<Identity> = []
  ) {
    self.suppressesAll = suppressesAll
    self.identities = identities
  }

  package var isEmpty: Bool {
    !suppressesAll && identities.isEmpty
  }

  package mutating func formUnion(_ newIdentities: Set<Identity>) {
    guard !suppressesAll else {
      return
    }
    identities.formUnion(newIdentities)
  }

  package mutating func insert(_ identity: Identity) {
    guard !suppressesAll else {
      return
    }
    identities.insert(identity)
  }

  package func suppresses(identity: Identity) -> Bool {
    if suppressesAll {
      return true
    }
    return identities.contains { suppressedIdentity in
      identity == suppressedIdentity
        || identity.isAncestor(of: suppressedIdentity)
        || identity.isDescendant(of: suppressedIdentity)
    }
  }
}

/// Runtime gate that prevented selective dirty evaluation for a frame.
package enum SelectiveEvaluationDisabledReason: String, Sendable {
  case selectiveEvaluationNotEnabled = "selective_evaluation_not_enabled"
  case frameStateForceRoot = "frame_state_force_root"
  case contextForceRoot = "context_force_root"
  case focusChanged = "focus_changed"
  case pressedChanged = "pressed_changed"
  case proposalChanged = "proposal_changed"
  case rootInvalidated = "root_invalidated"

  package var diagnosticName: String {
    rawValue
  }
}

/// Attribution for a pending `forceRootEvaluation()` request. Root-forced
/// frames surface as `frame_state_force_root` in selective-evaluation
/// diagnostics; the source set says who asked, so dirty-frontier narrowing
/// decisions can attribute the remaining root-forced frames instead of
/// guessing.
package enum ForceRootEvaluationSource: String, Sendable, CaseIterable {
  case focusSyncRerender = "focus_sync_rerender"
  case animationPropertySafety = "animation_property_safety"
  case animationPendingWorkSafety = "animation_pending_work_safety"
  case identityAgnosticAnimationSafety = "identity_agnostic_animation_safety"
  case unattributed = "unattributed"
}

/// Value-owned inputs for one resolve pass.
///
/// Stored evaluator closures can outlive the frame where they were first
/// captured. The renderer updates a shared ``FrameResolveInputBox`` with this
/// value before graph evaluation so reused evaluators can observe the current
/// frame's invalidation and proposal inputs without owning the renderer's
/// previous-frame selector state.
package struct FrameResolveInputs {
  package var invalidatedIdentities: Set<Identity>
  package var invalidationSummary: InvalidationSummary
  package var environmentValues: EnvironmentValues
  package var environment: EnvironmentSnapshot
  package var focusedValues: FocusedValues
  package var transaction: TransactionSnapshot
  package var resolveWorkTracker: ResolveWorkTracker?
  package var proposal: ProposedSize
  package var usesSelectiveEvaluation: Bool
  package var environmentRequiresRootEvaluation: Bool
  package var selectiveEvaluationDisabledReasons: [SelectiveEvaluationDisabledReason]
  /// Attribution for this frame's `frame_state_force_root` disabled reason,
  /// sorted for deterministic diagnostics. Empty when nothing forced root.
  package var forceRootEvaluationSources: [ForceRootEvaluationSource]
  /// Retained-reuse suppression for reuse-unsafe identities this frame.
  ///
  /// The run loop sets this on frames where some reached nodes must recompute
  /// even if they are disjoint from ordinary invalidation: focus/press runtime
  /// readers and active property-animation identities. The run-loop policy
  /// decides separately whether that safety scope also needs root evaluation.
  package var retainedReuseSuppressionScope: RetainedReuseSuppressionScope

  package init(
    invalidatedIdentities: Set<Identity>,
    invalidationSummary: InvalidationSummary,
    environmentValues: EnvironmentValues,
    environment: EnvironmentSnapshot,
    focusedValues: FocusedValues,
    transaction: TransactionSnapshot,
    resolveWorkTracker: ResolveWorkTracker?,
    proposal: ProposedSize,
    usesSelectiveEvaluation: Bool,
    environmentRequiresRootEvaluation: Bool,
    selectiveEvaluationDisabledReasons: [SelectiveEvaluationDisabledReason] = [],
    forceRootEvaluationSources: [ForceRootEvaluationSource] = [],
    retainedReuseSuppressionScope: RetainedReuseSuppressionScope = .none
  ) {
    self.invalidatedIdentities = invalidatedIdentities
    self.invalidationSummary = invalidationSummary
    self.environmentValues = environmentValues
    self.environment = environment
    self.focusedValues = focusedValues
    self.transaction = transaction
    self.resolveWorkTracker = resolveWorkTracker
    self.proposal = proposal
    self.usesSelectiveEvaluation = usesSelectiveEvaluation
    self.environmentRequiresRootEvaluation = environmentRequiresRootEvaluation
    self.selectiveEvaluationDisabledReasons = selectiveEvaluationDisabledReasons
    self.forceRootEvaluationSources = forceRootEvaluationSources
    self.retainedReuseSuppressionScope = retainedReuseSuppressionScope
  }

  /// Disabled-reason diagnostic names with `frame_state_force_root` enriched
  /// by its attribution, e.g. `frame_state_force_root(focus_sync_rerender)`.
  /// Consumers matching on the plain reason substring keep matching.
  package var diagnosticSelectiveEvaluationDisabledReasonNames: [String] {
    selectiveEvaluationDisabledReasons.map { reason in
      guard reason == .frameStateForceRoot, !forceRootEvaluationSources.isEmpty
      else {
        return reason.diagnosticName
      }
      let sources = forceRootEvaluationSources.map(\.rawValue).joined(separator: "+")
      return "\(reason.diagnosticName)(\(sources))"
    }
  }
}

@MainActor
package final class FrameResolveInputBox {
  package private(set) var inputs: FrameResolveInputs?

  package init() {}

  package func store(_ inputs: FrameResolveInputs) {
    self.inputs = inputs
  }

  package func clear() {
    inputs = nil
  }
}

extension FrameResolveInputBox {
  package struct Checkpoint {
    package var inputs: FrameResolveInputs?
  }

  package struct DebugStateSnapshot: Equatable {
    package struct InputSnapshot: Equatable {
      package var invalidatedIdentities: Set<Identity>
      package var invalidationSummary: InvalidationSummary
      package var environment: EnvironmentSnapshot
      package var focusedValues: FocusedValues
      package var transaction: TransactionSnapshot
      package var proposal: ProposedSize
      package var usesSelectiveEvaluation: Bool
      package var environmentRequiresRootEvaluation: Bool
      package var selectiveEvaluationDisabledReasons: [SelectiveEvaluationDisabledReason]
      package var forceRootEvaluationSources: [ForceRootEvaluationSource]
      package var retainedReuseSuppressionScope: RetainedReuseSuppressionScope
    }

    package var inputs: InputSnapshot?
  }

  package func makeCheckpoint() -> Checkpoint {
    Checkpoint(inputs: inputs)
  }

  package func restoreCheckpoint(_ checkpoint: Checkpoint) {
    inputs = checkpoint.inputs
  }

  package func debugStateSnapshot() -> DebugStateSnapshot {
    DebugStateSnapshot(
      inputs: inputs.map {
        DebugStateSnapshot.InputSnapshot(
          invalidatedIdentities: $0.invalidatedIdentities,
          invalidationSummary: $0.invalidationSummary,
          environment: $0.environment,
          focusedValues: $0.focusedValues,
          transaction: $0.transaction,
          proposal: $0.proposal,
          usesSelectiveEvaluation: $0.usesSelectiveEvaluation,
          environmentRequiresRootEvaluation: $0.environmentRequiresRootEvaluation,
          selectiveEvaluationDisabledReasons: $0.selectiveEvaluationDisabledReasons,
          forceRootEvaluationSources: $0.forceRootEvaluationSources,
          retainedReuseSuppressionScope: $0.retainedReuseSuppressionScope
        )
      }
    )
  }
}

/// Previous-frame selector memory used to prepare ``FrameResolveInputs``.
@MainActor
package final class FrameResolveState {
  package var selectiveEvaluationEnabled: Bool

  /// When true, the next call to ``prepareInputs(from:proposal:)`` will force
  /// root evaluation regardless of whether environment values changed. The
  /// RunLoop sets this when the view builder's input changed (state mutation)
  /// or during focus sync re-renders.
  package var forceRootEvaluation: Bool = false

  /// Attribution for the pending ``forceRootEvaluation`` request, cleared with
  /// it by ``prepareInputs(from:proposal:)``.
  package var forceRootEvaluationSources: Set<ForceRootEvaluationSource> = []

  /// One-shot retained-reuse suppression consumed by
  /// ``prepareInputs(from:proposal:)``.
  package var retainedReuseSuppressionScope: RetainedReuseSuppressionScope = .none

  private var previousFocusedIdentity: Identity?
  private var previousPressedIdentity: Identity?
  private var previousProposal: ProposedSize?

  package init() {
    selectiveEvaluationEnabled = false
  }

  package func prepareInputs(
    from context: ResolveContext,
    proposal: ProposedSize
  ) -> FrameResolveInputs {
    let newFocused = context.environmentValues.focusedIdentity
    let newPressed = context.environmentValues.pressedIdentity
    let frameStateForceRoot = forceRootEvaluation
    let contextForceRoot = context.forceRootEvaluation
    let focusChanged = newFocused != previousFocusedIdentity
    let pressedChanged = newPressed != previousPressedIdentity
    let proposalChanged = proposal != previousProposal
    let rootInvalidated = context.invalidatedIdentities.contains(context.identity)
    let suppressionScope = retainedReuseSuppressionScope
    let finiteSuppressionCoversFocusPress =
      !suppressionScope.isEmpty && !suppressionScope.suppressesAll
    let focusChangeRequiresRoot = focusChanged && !finiteSuppressionCoversFocusPress
    let pressedChangeRequiresRoot = pressedChanged && !finiteSuppressionCoversFocusPress
    let environmentRequiresRootEvaluation =
      frameStateForceRoot
      || contextForceRoot
      || focusChangeRequiresRoot
      || pressedChangeRequiresRoot
      || proposalChanged
    let frameStateForceRootSources = forceRootEvaluationSources
      .sorted { $0.rawValue < $1.rawValue }
    previousFocusedIdentity = newFocused
    previousPressedIdentity = newPressed
    previousProposal = proposal
    forceRootEvaluation = false
    forceRootEvaluationSources.removeAll()
    retainedReuseSuppressionScope = .none

    let usesSelectiveEvaluation =
      selectiveEvaluationEnabled
      && !environmentRequiresRootEvaluation
      && !rootInvalidated

    var disabledReasons: [SelectiveEvaluationDisabledReason] = []
    if !selectiveEvaluationEnabled {
      disabledReasons.append(.selectiveEvaluationNotEnabled)
    }
    if frameStateForceRoot {
      disabledReasons.append(.frameStateForceRoot)
    }
    if contextForceRoot {
      disabledReasons.append(.contextForceRoot)
    }
    if focusChangeRequiresRoot {
      disabledReasons.append(.focusChanged)
    }
    if pressedChangeRequiresRoot {
      disabledReasons.append(.pressedChanged)
    }
    if proposalChanged {
      disabledReasons.append(.proposalChanged)
    }
    if rootInvalidated {
      disabledReasons.append(.rootInvalidated)
    }

    return FrameResolveInputs(
      invalidatedIdentities: context.invalidatedIdentities,
      invalidationSummary: context.invalidationSummary,
      environmentValues: context.environmentValues,
      environment: context.environment,
      focusedValues: context.focusedValues,
      transaction: context.transaction,
      resolveWorkTracker: context.resolveWorkTracker,
      proposal: proposal,
      usesSelectiveEvaluation: usesSelectiveEvaluation,
      environmentRequiresRootEvaluation: environmentRequiresRootEvaluation,
      selectiveEvaluationDisabledReasons: usesSelectiveEvaluation ? [] : disabledReasons,
      forceRootEvaluationSources: frameStateForceRoot ? frameStateForceRootSources : [],
      retainedReuseSuppressionScope: suppressionScope
    )
  }
}

extension FrameResolveState {
  package struct Checkpoint {
    package var forceRootEvaluation: Bool
    package var forceRootEvaluationSources: Set<ForceRootEvaluationSource>
    package var retainedReuseSuppressionScope: RetainedReuseSuppressionScope
    package var previousFocusedIdentity: Identity?
    package var previousPressedIdentity: Identity?
    package var previousProposal: ProposedSize?
  }

  package func makeCheckpoint() -> Checkpoint {
    Checkpoint(
      forceRootEvaluation: forceRootEvaluation,
      forceRootEvaluationSources: forceRootEvaluationSources,
      retainedReuseSuppressionScope: retainedReuseSuppressionScope,
      previousFocusedIdentity: previousFocusedIdentity,
      previousPressedIdentity: previousPressedIdentity,
      previousProposal: previousProposal
    )
  }

  package func restoreCheckpoint(_ checkpoint: Checkpoint) {
    forceRootEvaluation = checkpoint.forceRootEvaluation
    forceRootEvaluationSources = checkpoint.forceRootEvaluationSources
    retainedReuseSuppressionScope = checkpoint.retainedReuseSuppressionScope
    previousFocusedIdentity = checkpoint.previousFocusedIdentity
    previousPressedIdentity = checkpoint.previousPressedIdentity
    previousProposal = checkpoint.previousProposal
  }

  package struct DebugStateSnapshot: Equatable {
    package var forceRootEvaluation: Bool
    package var forceRootEvaluationSources: Set<ForceRootEvaluationSource>
    package var retainedReuseSuppressionScope: RetainedReuseSuppressionScope
    package var previousFocusedIdentity: Identity?
    package var previousPressedIdentity: Identity?
    package var previousProposal: ProposedSize?
  }

  package func debugStateSnapshot() -> DebugStateSnapshot {
    let checkpoint = makeCheckpoint()
    return DebugStateSnapshot(
      forceRootEvaluation: checkpoint.forceRootEvaluation,
      forceRootEvaluationSources: checkpoint.forceRootEvaluationSources,
      retainedReuseSuppressionScope: checkpoint.retainedReuseSuppressionScope,
      previousFocusedIdentity: checkpoint.previousFocusedIdentity,
      previousPressedIdentity: checkpoint.previousPressedIdentity,
      previousProposal: checkpoint.previousProposal
    )
  }
}
