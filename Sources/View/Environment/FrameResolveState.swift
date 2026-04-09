package import Core

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
  package var selectiveEvaluationEnabled: Bool

  /// When true, the next call to ``update(from:)`` will force root evaluation
  /// regardless of whether environment values changed.  The RunLoop sets this
  /// when the view builder's input changed (state mutation) or during focus
  /// sync re-renders.
  package var forceRootEvaluation: Bool = false

  private var previousFocusedIdentity: Identity?
  private var previousPressedIdentity: Identity?

  /// Whether the per-frame environment values changed in a way that
  /// requires root re-evaluation (e.g., focus or pressed identity changed).
  package private(set) var environmentRequiresRootEvaluation: Bool = false

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
      forceRootEvaluation
      || newFocused != previousFocusedIdentity
      || newPressed != previousPressedIdentity
    previousFocusedIdentity = newFocused
    previousPressedIdentity = newPressed
    forceRootEvaluation = false

    invalidatedIdentities = context.invalidatedIdentities
    invalidationSummary = context.invalidationSummary
    environmentValues = context.environmentValues
    environment = context.environment
    focusedValues = context.focusedValues
    transaction = context.transaction
  }
}
