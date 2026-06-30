/// Gate for **single-pass focus-sync convergence**. **On by default**; set
/// `SWIFTTUI_SINGLE_PASS_FOCUS=0` to opt back into the legacy loop.
///
/// Legacy behavior (gate off) reconciles focus by re-rendering: each frame runs
/// a `render → processFocusSyncIteration → if changed, force a whole-tree
/// re-render` loop until a fixed point or a `FocusSyncRerenderBudget` is
/// exhausted (then `assertionFailure`). The loop exists because focus location
/// and `currentFocusedValues` are computed *after* a render while readers consume
/// them at the *start* of a render — a one-render feedback edge the loop closes
/// within the frame. The budget is the tell that focus is not modeled as a
/// dependency.
///
/// When enabled, the frame renders **once**: focus state read at frame start is
/// last frame's. `processFocusSyncIteration` still updates runtime focus state
/// (focus location, `currentFocusedValues`, scroll), but instead of looping it
/// **invalidates exactly the readers** of what changed and commits — so the
/// change propagates on the next frame through the ordinary precise-invalidation
/// system. `@FocusState` readers already self-invalidate
/// (`FocusState`'s `applyRuntimeValue` → `ViewNode.requestInvalidation()`);
/// focus styling is a commit-time presentation handler (no re-resolve); and
/// `@FocusedValue`/`@FocusedBinding` readers are invalidated via the focused-value
/// reader attribution recorded during resolve. No loop, no budget — a focus
/// change schedules one update and terminates (the dependency cascade is
/// acyclic), at the cost of one frame of propagation lag.
///
/// Test-settable; defaults from `SWIFTTUI_SINGLE_PASS_FOCUS` at first access.
@MainActor
package enum SinglePassFocusConvergenceConfiguration {
  package static let environmentVariableName =
    FeatureGate.singlePassFocusConvergence.environmentVariableName

  /// Whether focus-sync converges in a single pass with one-frame-lag reader
  /// invalidation rather than the render-until-fixpoint loop. On by default;
  /// `SWIFTTUI_SINGLE_PASS_FOCUS=0` opts back into the legacy loop. The run loop
  /// sets it from the environment before the first render, and tests set it directly.
  package static var isEnabled: Bool =
    FeatureGate.singlePassFocusConvergence.initialIsEnabled()
}
