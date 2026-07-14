package import SwiftTUICore

package struct RetainedReuseSuppressionScope: Equatable, Sendable {
  package var suppressesAll: Bool
  package var identities: Set<Identity>
  /// Focus/press-leg members (runtime focus readers plus the old/new
  /// focus/press identities). They match exactly like `identities` — self,
  /// ancestors, and descendants — except that a descendant sitting below a
  /// focus-presentation-inert slot *declared by the matched member itself* is
  /// exempt (see `suppresses(identity:isFocusPresentationDescendantExempt:)`).
  /// Animation cones stay in `identities`: an animating subtree needs its
  /// registrations re-established regardless of presentation promises.
  package var focusPresentationMembers: Set<Identity>
  /// Old/new focus/press identities whose root path carries NO runtime-focus
  /// side-field reader: nothing that resolves on that path can vary with the
  /// move (descendant readers compare at-or-below themselves; bake/wrapper
  /// readers ride the wholesale readers union), so these members deny no
  /// reuse and queue no dirty work. They still count toward `isEmpty` —
  /// a frame whose focus move produced only chrome-only members must keep
  /// its finite focus/press coverage instead of falling back to the
  /// root-forced path.
  package var chromeOnlyFocusMembers: Set<Identity>
  /// `true` when the run loop certifies that every identity this frame's
  /// forced evaluation must recompute is named in `identities` — INCLUDING
  /// the case where that set is empty. A pending stranded-batch completion
  /// drain forces a frame (its deadline must reach `applyInterpolations`)
  /// but requires no subtree to recompute, so its scope is a *named empty*
  /// one: without this bit an empty scope is indistinguishable from "frame
  /// forced for an unnamed reason", and the empty-invalidation reuse guard
  /// would conservatively recompute the whole tree on every drain frame.
  package var namesForcedEvaluation: Bool

  package static let none = Self()
  package static let all = Self(suppressesAll: true)

  package init(
    suppressesAll: Bool = false,
    identities: Set<Identity> = [],
    focusPresentationMembers: Set<Identity> = [],
    chromeOnlyFocusMembers: Set<Identity> = [],
    namesForcedEvaluation: Bool = false
  ) {
    self.suppressesAll = suppressesAll
    self.identities = identities
    self.focusPresentationMembers = focusPresentationMembers
    self.chromeOnlyFocusMembers = chromeOnlyFocusMembers
    self.namesForcedEvaluation = namesForcedEvaluation
  }

  package var isEmpty: Bool {
    !suppressesAll && identities.isEmpty && focusPresentationMembers.isEmpty
      && chromeOnlyFocusMembers.isEmpty
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

  package mutating func formUnionFocusPresentationMembers(
    _ newIdentities: Set<Identity>
  ) {
    guard !suppressesAll else {
      return
    }
    focusPresentationMembers.formUnion(newIdentities)
  }

  package mutating func insertFocusPresentationMember(_ identity: Identity) {
    guard !suppressesAll else {
      return
    }
    focusPresentationMembers.insert(identity)
  }

  package mutating func insertChromeOnlyFocusMember(_ identity: Identity) {
    guard !suppressesAll else {
      return
    }
    chromeOnlyFocusMembers.insert(identity)
  }

  /// Conservative matching: focus-presentation members behave exactly like
  /// cone members. Callers with graph access should prefer
  /// ``suppresses(identity:isFocusPresentationDescendantExempt:)``.
  package func suppresses(identity: Identity) -> Bool {
    suppresses(identity: identity) { _, _ in false }
  }

  /// Whether retained reuse is suppressed for `identity`.
  ///
  /// Cone members (`identities`) match self, ancestors, and descendants.
  /// Focus-presentation members match the same way, except a *descendant-only*
  /// match may be exempted by the predicate — called as
  /// `(member, identity)` — when the identity sits below a
  /// focus-presentation-inert slot the member itself declared. A match as
  /// self-or-ancestor is never exempt (the member must recompute, and its
  /// ancestor chain must stay denied so evaluation reaches it), and one
  /// non-exempting matching member keeps the identity suppressed.
  package func suppresses(
    identity: Identity,
    isFocusPresentationDescendantExempt: (Identity, Identity) -> Bool
  ) -> Bool {
    if suppressesAll {
      return true
    }
    if identities.contains(where: { suppressedIdentity in
      identity.isAncestor(of: suppressedIdentity)
        || identity.isDescendant(of: suppressedIdentity)
    }) {
      return true
    }
    var descendantOnlyMembers: [Identity] = []
    for member in focusPresentationMembers {
      if identity.isAncestor(of: member) {
        // Self-inclusive: covers `identity == member` too.
        return true
      }
      if identity.isDescendant(of: member) {
        descendantOnlyMembers.append(member)
      }
    }
    guard !descendantOnlyMembers.isEmpty else {
      return false
    }
    return descendantOnlyMembers.contains { member in
      !isFocusPresentationDescendantExempt(member, identity)
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
  case runtimeEnvironmentChanged = "runtime_environment_changed"

  package var diagnosticName: String {
    rawValue
  }
}

/// The runtime-owned root environment values the run loop refreshes into every
/// frame's root context (see `RunLoop.resolveContext(for:)`), excluding
/// focus/press/focused-values (which have their own dirty-frontier machinery)
/// and terminal size (covered by the proposal comparison). A change here must
/// force root evaluation: environment readers anywhere in the tree may depend
/// on these values, selective frames have no reader-invalidation path for
/// them, and such changes (theme flips, appearance reloads, capability
/// renegotiation) are far too rare to justify one.
package struct RuntimeRootEnvironmentSignature: Equatable, Sendable {
  package var terminalAppearance: TerminalAppearance
  package var theme: Theme?
  package var cellPixelMetrics: CellPixelMetrics
  package var pointerInputCapabilities: PointerInputCapabilities
  package var accessibilityReduceMotion: Bool
  package var suppressesProgress: Bool
  package var cursorFollowsFocus: Bool

  package init(environmentValues: EnvironmentValues) {
    terminalAppearance = environmentValues.terminalAppearance
    theme = environmentValues.theme
    cellPixelMetrics = environmentValues.cellPixelMetrics
    pointerInputCapabilities = environmentValues.pointerInputCapabilities
    accessibilityReduceMotion = environmentValues.accessibilityReduceMotion
    suppressesProgress = environmentValues.suppressesProgress
    cursorFollowsFocus = environmentValues.cursorFollowsFocus
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
  private var previousRuntimeRootEnvironment: RuntimeRootEnvironmentSignature?

  package init() {
    selectiveEvaluationEnabled = false
  }

  /// The single selective-evaluation eligibility formula (F177). Both the
  /// frame-head input preparation below and the portal-translation recompute
  /// (`DefaultRendererFrameHeadCoordinator.translatePresentationPortalInvalidations`)
  /// must agree on these three terms; hand-duplication let them drift
  /// silently. `rootInvalidated` is the caller's root-membership check
  /// against ITS invalidation currency — the raw set at prepare time, the
  /// portal-translated set at recompute time.
  package static func selectiveEvaluationDecision(
    enabled: Bool,
    environmentRequiresRoot: Bool,
    rootInvalidated: Bool
  ) -> Bool {
    enabled && !environmentRequiresRoot && !rootInvalidated
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
    let runtimeRootEnvironment = RuntimeRootEnvironmentSignature(
      environmentValues: context.environmentValues
    )
    let runtimeEnvironmentChanged =
      previousRuntimeRootEnvironment != nil
      && runtimeRootEnvironment != previousRuntimeRootEnvironment
    let environmentRequiresRootEvaluation =
      frameStateForceRoot
      || contextForceRoot
      || focusChangeRequiresRoot
      || pressedChangeRequiresRoot
      || proposalChanged
      || runtimeEnvironmentChanged
    let frameStateForceRootSources =
      forceRootEvaluationSources
      .sorted { $0.rawValue < $1.rawValue }
    previousFocusedIdentity = newFocused
    previousPressedIdentity = newPressed
    previousProposal = proposal
    previousRuntimeRootEnvironment = runtimeRootEnvironment
    forceRootEvaluation = false
    forceRootEvaluationSources.removeAll()
    retainedReuseSuppressionScope = .none

    let usesSelectiveEvaluation = Self.selectiveEvaluationDecision(
      enabled: selectiveEvaluationEnabled,
      environmentRequiresRoot: environmentRequiresRootEvaluation,
      rootInvalidated: rootInvalidated
    )

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
    if runtimeEnvironmentChanged {
      disabledReasons.append(.runtimeEnvironmentChanged)
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
    package var previousRuntimeRootEnvironment: RuntimeRootEnvironmentSignature?
  }

  package func makeCheckpoint() -> Checkpoint {
    Checkpoint(
      forceRootEvaluation: forceRootEvaluation,
      forceRootEvaluationSources: forceRootEvaluationSources,
      retainedReuseSuppressionScope: retainedReuseSuppressionScope,
      previousFocusedIdentity: previousFocusedIdentity,
      previousPressedIdentity: previousPressedIdentity,
      previousProposal: previousProposal,
      previousRuntimeRootEnvironment: previousRuntimeRootEnvironment
    )
  }

  package func restoreCheckpoint(_ checkpoint: Checkpoint) {
    forceRootEvaluation = checkpoint.forceRootEvaluation
    forceRootEvaluationSources = checkpoint.forceRootEvaluationSources
    retainedReuseSuppressionScope = checkpoint.retainedReuseSuppressionScope
    previousFocusedIdentity = checkpoint.previousFocusedIdentity
    previousPressedIdentity = checkpoint.previousPressedIdentity
    previousProposal = checkpoint.previousProposal
    previousRuntimeRootEnvironment = checkpoint.previousRuntimeRootEnvironment
  }

  package struct DebugStateSnapshot: Equatable {
    package var forceRootEvaluation: Bool
    package var forceRootEvaluationSources: Set<ForceRootEvaluationSource>
    package var retainedReuseSuppressionScope: RetainedReuseSuppressionScope
    package var previousFocusedIdentity: Identity?
    package var previousPressedIdentity: Identity?
    package var previousProposal: ProposedSize?
    package var previousRuntimeRootEnvironment: RuntimeRootEnvironmentSignature?
  }

  package func debugStateSnapshot() -> DebugStateSnapshot {
    let checkpoint = makeCheckpoint()
    return DebugStateSnapshot(
      forceRootEvaluation: checkpoint.forceRootEvaluation,
      forceRootEvaluationSources: checkpoint.forceRootEvaluationSources,
      retainedReuseSuppressionScope: checkpoint.retainedReuseSuppressionScope,
      previousFocusedIdentity: checkpoint.previousFocusedIdentity,
      previousPressedIdentity: checkpoint.previousPressedIdentity,
      previousProposal: checkpoint.previousProposal,
      previousRuntimeRootEnvironment: checkpoint.previousRuntimeRootEnvironment
    )
  }
}
