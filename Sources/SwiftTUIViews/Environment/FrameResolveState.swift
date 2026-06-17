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
  package var proposal: ProposedSize
  package var usesSelectiveEvaluation: Bool
  package var environmentRequiresRootEvaluation: Bool
  package var selectiveEvaluationDisabledReasons: [SelectiveEvaluationDisabledReason]
  /// Retained-reuse suppression for reuse-unsafe identities this frame.
  ///
  /// The run loop sets this alongside `forceRootEvaluation` on frames where
  /// some reached nodes must recompute even if they are disjoint from ordinary
  /// invalidation: focus/press runtime readers and active property-animation
  /// identities. The scope may still conservatively suppress all reached nodes
  /// when animation work is identity-agnostic.
  package var retainedReuseSuppressionScope: RetainedReuseSuppressionScope

  package init(
    invalidatedIdentities: Set<Identity>,
    invalidationSummary: InvalidationSummary,
    environmentValues: EnvironmentValues,
    environment: EnvironmentSnapshot,
    focusedValues: FocusedValues,
    transaction: TransactionSnapshot,
    proposal: ProposedSize,
    usesSelectiveEvaluation: Bool,
    environmentRequiresRootEvaluation: Bool,
    selectiveEvaluationDisabledReasons: [SelectiveEvaluationDisabledReason] = [],
    retainedReuseSuppressionScope: RetainedReuseSuppressionScope = .none
  ) {
    self.invalidatedIdentities = invalidatedIdentities
    self.invalidationSummary = invalidationSummary
    self.environmentValues = environmentValues
    self.environment = environment
    self.focusedValues = focusedValues
    self.transaction = transaction
    self.proposal = proposal
    self.usesSelectiveEvaluation = usesSelectiveEvaluation
    self.environmentRequiresRootEvaluation = environmentRequiresRootEvaluation
    self.selectiveEvaluationDisabledReasons = selectiveEvaluationDisabledReasons
    self.retainedReuseSuppressionScope = retainedReuseSuppressionScope
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
    let environmentRequiresRootEvaluation =
      frameStateForceRoot
      || contextForceRoot
      || focusChanged
      || pressedChanged
      || proposalChanged
    previousFocusedIdentity = newFocused
    previousPressedIdentity = newPressed
    previousProposal = proposal
    forceRootEvaluation = false
    let suppressionScope = retainedReuseSuppressionScope
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
    if focusChanged {
      disabledReasons.append(.focusChanged)
    }
    if pressedChanged {
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
      proposal: proposal,
      usesSelectiveEvaluation: usesSelectiveEvaluation,
      environmentRequiresRootEvaluation: environmentRequiresRootEvaluation,
      selectiveEvaluationDisabledReasons: usesSelectiveEvaluation ? [] : disabledReasons,
      retainedReuseSuppressionScope: suppressionScope
    )
  }
}

extension FrameResolveState {
  package struct Checkpoint {
    package var forceRootEvaluation: Bool
    package var retainedReuseSuppressionScope: RetainedReuseSuppressionScope
    package var previousFocusedIdentity: Identity?
    package var previousPressedIdentity: Identity?
    package var previousProposal: ProposedSize?
  }

  package func makeCheckpoint() -> Checkpoint {
    Checkpoint(
      forceRootEvaluation: forceRootEvaluation,
      retainedReuseSuppressionScope: retainedReuseSuppressionScope,
      previousFocusedIdentity: previousFocusedIdentity,
      previousPressedIdentity: previousPressedIdentity,
      previousProposal: previousProposal
    )
  }

  package func restoreCheckpoint(_ checkpoint: Checkpoint) {
    forceRootEvaluation = checkpoint.forceRootEvaluation
    retainedReuseSuppressionScope = checkpoint.retainedReuseSuppressionScope
    previousFocusedIdentity = checkpoint.previousFocusedIdentity
    previousPressedIdentity = checkpoint.previousPressedIdentity
    previousProposal = checkpoint.previousProposal
  }

  package struct DebugStateSnapshot: Equatable {
    package var forceRootEvaluation: Bool
    package var retainedReuseSuppressionScope: RetainedReuseSuppressionScope
    package var previousFocusedIdentity: Identity?
    package var previousPressedIdentity: Identity?
    package var previousProposal: ProposedSize?
  }

  package func debugStateSnapshot() -> DebugStateSnapshot {
    let checkpoint = makeCheckpoint()
    return DebugStateSnapshot(
      forceRootEvaluation: checkpoint.forceRootEvaluation,
      retainedReuseSuppressionScope: checkpoint.retainedReuseSuppressionScope,
      previousFocusedIdentity: checkpoint.previousFocusedIdentity,
      previousPressedIdentity: checkpoint.previousPressedIdentity,
      previousProposal: checkpoint.previousProposal
    )
  }
}
