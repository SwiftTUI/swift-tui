package import SwiftTUICore

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
  /// When true, `resolveView` must not take the retained-reuse fast path this
  /// frame even for subtrees disjoint from the invalidation set. The run loop
  /// sets this (alongside `forceRootEvaluation`) on frames that are unsafe to
  /// reuse — a focus move (focus is excluded from `EnvironmentSnapshot`
  /// equality, so a reused focus-reading subtree shows stale focus) or an
  /// in-flight property-scope animation (a reused subtree's body never re-runs,
  /// so its `repeatForever` registration decays). See
  /// ``ResolveContext/effectiveSuppressesRetainedReuse``.
  package var suppressRetainedReuse: Bool

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
    suppressRetainedReuse: Bool = false
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
    self.suppressRetainedReuse = suppressRetainedReuse
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
          environmentRequiresRootEvaluation: $0.environmentRequiresRootEvaluation
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

  /// When true, the next call to ``prepareInputs(from:proposal:)`` will mark the
  /// frame's inputs to skip retained reuse in `resolveView`. The RunLoop sets
  /// this on reuse-unsafe frames (focus move or in-flight property animation).
  /// One-shot: consumed and reset by ``prepareInputs(from:proposal:)``.
  package var suppressRetainedReuse: Bool = false

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
    let environmentRequiresRootEvaluation =
      forceRootEvaluation
      || context.forceRootEvaluation
      || newFocused != previousFocusedIdentity
      || newPressed != previousPressedIdentity
      || proposal != previousProposal
    previousFocusedIdentity = newFocused
    previousPressedIdentity = newPressed
    previousProposal = proposal
    forceRootEvaluation = false
    let suppressReuse = suppressRetainedReuse
    suppressRetainedReuse = false

    let usesSelectiveEvaluation =
      selectiveEvaluationEnabled
      && !environmentRequiresRootEvaluation
      && !context.invalidatedIdentities.contains(context.identity)

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
      suppressRetainedReuse: suppressReuse
    )
  }
}

extension FrameResolveState {
  package struct Checkpoint {
    package var forceRootEvaluation: Bool
    package var previousFocusedIdentity: Identity?
    package var previousPressedIdentity: Identity?
    package var previousProposal: ProposedSize?
  }

  package func makeCheckpoint() -> Checkpoint {
    Checkpoint(
      forceRootEvaluation: forceRootEvaluation,
      previousFocusedIdentity: previousFocusedIdentity,
      previousPressedIdentity: previousPressedIdentity,
      previousProposal: previousProposal
    )
  }

  package func restoreCheckpoint(_ checkpoint: Checkpoint) {
    forceRootEvaluation = checkpoint.forceRootEvaluation
    previousFocusedIdentity = checkpoint.previousFocusedIdentity
    previousPressedIdentity = checkpoint.previousPressedIdentity
    previousProposal = checkpoint.previousProposal
  }

  package struct DebugStateSnapshot: Equatable {
    package var forceRootEvaluation: Bool
    package var previousFocusedIdentity: Identity?
    package var previousPressedIdentity: Identity?
    package var previousProposal: ProposedSize?
  }

  package func debugStateSnapshot() -> DebugStateSnapshot {
    let checkpoint = makeCheckpoint()
    return DebugStateSnapshot(
      forceRootEvaluation: checkpoint.forceRootEvaluation,
      previousFocusedIdentity: checkpoint.previousFocusedIdentity,
      previousPressedIdentity: checkpoint.previousPressedIdentity,
      previousProposal: checkpoint.previousProposal
    )
  }
}
