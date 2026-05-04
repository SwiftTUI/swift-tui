package import SwiftTUICore

/// Mutable per-frame state shared by all evaluator closures in a single
/// render pass.  Before evaluating dirty frontier nodes, the renderer
/// updates this object with the current frame's environment and
/// invalidation data so that re-used evaluators see fresh values.
@MainActor
package final class FrameResolveState {
  package var invalidatedIdentities: Set<Identity>
  package var invalidationSummary: InvalidationSummary
  package var environmentValues: EnvironmentValues
  package var environment: EnvironmentSnapshot
  package var focusedValues: FocusedValues
  package var transaction: TransactionSnapshot
  package var proposal: ProposedSize
  package var selectiveEvaluationEnabled: Bool

  /// When true, the next call to ``update(from:)`` will force root evaluation
  /// regardless of whether environment values changed.  The RunLoop sets this
  /// when the view builder's input changed (state mutation) or during focus
  /// sync re-renders.
  package var forceRootEvaluation: Bool = false

  private var previousFocusedIdentity: Identity?
  private var previousPressedIdentity: Identity?
  private var previousProposal: ProposedSize?

  /// Whether the per-frame environment values changed in a way that
  /// requires root re-evaluation (e.g., focus, pressed identity, or
  /// proposal changed).
  package private(set) var environmentRequiresRootEvaluation: Bool = false

  package init() {
    invalidatedIdentities = []
    invalidationSummary = .init(invalidatedIdentities: [])
    environmentValues = .init()
    environment = .init()
    focusedValues = .init()
    transaction = .init()
    proposal = .unspecified
    selectiveEvaluationEnabled = false
  }

  package func update(from context: ResolveContext, proposal: ProposedSize) {
    let newFocused = context.environmentValues.focusedIdentity
    let newPressed = context.environmentValues.pressedIdentity
    environmentRequiresRootEvaluation =
      forceRootEvaluation
      || newFocused != previousFocusedIdentity
      || newPressed != previousPressedIdentity
      || proposal != previousProposal
    previousFocusedIdentity = newFocused
    previousPressedIdentity = newPressed
    previousProposal = proposal
    forceRootEvaluation = false

    invalidatedIdentities = context.invalidatedIdentities
    invalidationSummary = context.invalidationSummary
    environmentValues = context.environmentValues
    environment = context.environment
    focusedValues = context.focusedValues
    transaction = context.transaction
    self.proposal = proposal
  }
}

extension FrameResolveState {
  package struct Checkpoint {
    package var invalidatedIdentities: Set<Identity>
    package var invalidationSummary: InvalidationSummary
    package var environmentValues: EnvironmentValues
    package var environment: EnvironmentSnapshot
    package var focusedValues: FocusedValues
    package var transaction: TransactionSnapshot
    package var proposal: ProposedSize
    package var selectiveEvaluationEnabled: Bool
    package var forceRootEvaluation: Bool
    package var previousFocusedIdentity: Identity?
    package var previousPressedIdentity: Identity?
    package var previousProposal: ProposedSize?
    package var environmentRequiresRootEvaluation: Bool
  }

  package func makeCheckpoint() -> Checkpoint {
    Checkpoint(
      invalidatedIdentities: invalidatedIdentities,
      invalidationSummary: invalidationSummary,
      environmentValues: environmentValues,
      environment: environment,
      focusedValues: focusedValues,
      transaction: transaction,
      proposal: proposal,
      selectiveEvaluationEnabled: selectiveEvaluationEnabled,
      forceRootEvaluation: forceRootEvaluation,
      previousFocusedIdentity: previousFocusedIdentity,
      previousPressedIdentity: previousPressedIdentity,
      previousProposal: previousProposal,
      environmentRequiresRootEvaluation: environmentRequiresRootEvaluation
    )
  }

  package func restoreCheckpoint(_ checkpoint: Checkpoint) {
    invalidatedIdentities = checkpoint.invalidatedIdentities
    invalidationSummary = checkpoint.invalidationSummary
    environmentValues = checkpoint.environmentValues
    environment = checkpoint.environment
    focusedValues = checkpoint.focusedValues
    transaction = checkpoint.transaction
    proposal = checkpoint.proposal
    selectiveEvaluationEnabled = checkpoint.selectiveEvaluationEnabled
    forceRootEvaluation = checkpoint.forceRootEvaluation
    previousFocusedIdentity = checkpoint.previousFocusedIdentity
    previousPressedIdentity = checkpoint.previousPressedIdentity
    previousProposal = checkpoint.previousProposal
    environmentRequiresRootEvaluation = checkpoint.environmentRequiresRootEvaluation
  }
}
