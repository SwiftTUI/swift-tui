package import Core

/// Mutable per-frame state shared by all evaluator closures in a single
/// render pass.  Before evaluating dirty frontier nodes, the renderer
/// updates this object with the current frame's environment and
/// invalidation data so that re-used evaluators see fresh values.
@MainActor
package final class FrameResolveState: @unchecked Sendable {
  package var invalidatedIdentities: Set<Identity>
  package var invalidationSummary: InvalidationSummary
  package var environmentValues: EnvironmentValues
  package var environment: EnvironmentSnapshot
  package var focusedValues: FocusedValues
  package var transaction: TransactionSnapshot
  package var selectiveEvaluationEnabled: Bool
  private var previousFocusedIdentity: Identity?
  private var previousPressedIdentity: Identity?

  /// Whether the per-frame environment values changed in a way that
  /// requires root re-evaluation (e.g., focus or pressed identity changed).
  package var environmentRequiresRootEvaluation: Bool = false

  package init() {
    invalidatedIdentities = []
    invalidationSummary = .init(invalidatedIdentities: [])
    environmentValues = .init()
    environment = .init()
    focusedValues = .init()
    transaction = .init()
    selectiveEvaluationEnabled = false
  }

  package func update(from context: ResolveContext) {
    let newFocused = context.environmentValues.focusedIdentity
    let newPressed = context.environmentValues.pressedIdentity
    environmentRequiresRootEvaluation =
      newFocused != previousFocusedIdentity
      || newPressed != previousPressedIdentity
    previousFocusedIdentity = newFocused
    previousPressedIdentity = newPressed

    invalidatedIdentities = context.invalidatedIdentities
    invalidationSummary = context.invalidationSummary
    environmentValues = context.environmentValues
    environment = context.environment
    focusedValues = context.focusedValues
    transaction = context.transaction
  }
}
