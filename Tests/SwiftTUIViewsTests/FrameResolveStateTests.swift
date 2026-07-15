import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite
struct FrameResolveStateTests {
  @Test("runtime gate: graph-local child invalidation can use selective evaluation")
  func graphLocalChildInvalidationCanUseSelectiveEvaluation() {
    let rootIdentity = testIdentity("Root")
    let childIdentity = testIdentity("Root", "Child")
    let state = warmedSelectiveState(rootIdentity: rootIdentity)

    let inputs = state.prepareInputs(
      from: resolveContext(
        rootIdentity: rootIdentity,
        invalidatedIdentities: [childIdentity]
      ),
      proposal: baselineProposal
    )

    #expect(inputs.usesSelectiveEvaluation)
    #expect(!inputs.environmentRequiresRootEvaluation)
    #expect(inputs.selectiveEvaluationDisabledReasons == [])
  }

  @Test("runtime gate: root invalidation disables selective evaluation")
  func rootInvalidationDisablesSelectiveEvaluation() {
    let rootIdentity = testIdentity("Root")
    let state = warmedSelectiveState(rootIdentity: rootIdentity)

    let inputs = state.prepareInputs(
      from: resolveContext(
        rootIdentity: rootIdentity,
        invalidatedIdentities: [rootIdentity]
      ),
      proposal: baselineProposal
    )

    #expect(!inputs.usesSelectiveEvaluation)
    #expect(!inputs.environmentRequiresRootEvaluation)
    #expect(inputs.selectiveEvaluationDisabledReasons == [.rootInvalidated])
  }

  @Test("runtime gate: forced root evaluation disables selective evaluation")
  func forcedRootEvaluationDisablesSelectiveEvaluation() {
    let rootIdentity = testIdentity("Root")
    let state = warmedSelectiveState(rootIdentity: rootIdentity)
    state.forceRootEvaluation = true

    let inputs = state.prepareInputs(
      from: resolveContext(
        rootIdentity: rootIdentity,
        invalidatedIdentities: [testIdentity("Root", "Child")]
      ),
      proposal: baselineProposal
    )

    #expect(!inputs.usesSelectiveEvaluation)
    #expect(inputs.environmentRequiresRootEvaluation)
    #expect(inputs.selectiveEvaluationDisabledReasons == [.frameStateForceRoot])
  }

  @Test("runtime gate: context root evaluation request disables selective evaluation")
  func contextRootEvaluationRequestDisablesSelectiveEvaluation() {
    let rootIdentity = testIdentity("Root")
    let state = warmedSelectiveState(rootIdentity: rootIdentity)

    let inputs = state.prepareInputs(
      from: resolveContext(
        rootIdentity: rootIdentity,
        invalidatedIdentities: [testIdentity("Root", "Child")],
        forceRootEvaluation: true
      ),
      proposal: baselineProposal
    )

    #expect(!inputs.usesSelectiveEvaluation)
    #expect(inputs.environmentRequiresRootEvaluation)
    #expect(inputs.selectiveEvaluationDisabledReasons == [.contextForceRoot])
  }

  @Test("runtime gate: focus change disables selective evaluation")
  func focusChangeDisablesSelectiveEvaluation() {
    let rootIdentity = testIdentity("Root")
    let state = warmedSelectiveState(rootIdentity: rootIdentity)

    let inputs = state.prepareInputs(
      from: resolveContext(
        rootIdentity: rootIdentity,
        invalidatedIdentities: [testIdentity("Root", "Child")],
        focusedIdentity: testIdentity("Root", "Focusable")
      ),
      proposal: baselineProposal
    )

    #expect(!inputs.usesSelectiveEvaluation)
    #expect(inputs.environmentRequiresRootEvaluation)
    #expect(inputs.selectiveEvaluationDisabledReasons == [.focusChanged])
  }

  @Test("runtime gate: finite suppression scope covers focus change")
  func finiteSuppressionScopeCoversFocusChange() {
    let rootIdentity = testIdentity("Root")
    let focusedIdentity = testIdentity("Root", "Focusable")
    let state = warmedSelectiveState(rootIdentity: rootIdentity)
    state.retainedReuseSuppressionScope = .init(identities: [focusedIdentity])

    let inputs = state.prepareInputs(
      from: resolveContext(
        rootIdentity: rootIdentity,
        invalidatedIdentities: [testIdentity("Root", "Child")],
        focusedIdentity: focusedIdentity
      ),
      proposal: baselineProposal
    )

    #expect(inputs.usesSelectiveEvaluation)
    #expect(!inputs.environmentRequiresRootEvaluation)
    #expect(inputs.selectiveEvaluationDisabledReasons == [])
    #expect(inputs.retainedReuseSuppressionScope.identities == [focusedIdentity])
  }

  @Test("runtime gate: full suppression scope keeps focus change root-forced")
  func fullSuppressionScopeKeepsFocusChangeRootForced() {
    let rootIdentity = testIdentity("Root")
    let state = warmedSelectiveState(rootIdentity: rootIdentity)
    state.retainedReuseSuppressionScope = .all

    let inputs = state.prepareInputs(
      from: resolveContext(
        rootIdentity: rootIdentity,
        invalidatedIdentities: [testIdentity("Root", "Child")],
        focusedIdentity: testIdentity("Root", "Focusable")
      ),
      proposal: baselineProposal
    )

    #expect(!inputs.usesSelectiveEvaluation)
    #expect(inputs.environmentRequiresRootEvaluation)
    #expect(inputs.selectiveEvaluationDisabledReasons == [.focusChanged])
    #expect(inputs.retainedReuseSuppressionScope.suppressesAll)
  }

  @Test("runtime gate: pressed change disables selective evaluation")
  func pressedChangeDisablesSelectiveEvaluation() {
    let rootIdentity = testIdentity("Root")
    let state = warmedSelectiveState(rootIdentity: rootIdentity)

    let inputs = state.prepareInputs(
      from: resolveContext(
        rootIdentity: rootIdentity,
        invalidatedIdentities: [testIdentity("Root", "Child")],
        pressedIdentity: testIdentity("Root", "Pressed")
      ),
      proposal: baselineProposal
    )

    #expect(!inputs.usesSelectiveEvaluation)
    #expect(inputs.environmentRequiresRootEvaluation)
    #expect(inputs.selectiveEvaluationDisabledReasons == [.pressedChanged])
  }

  @Test("runtime gate: finite suppression scope covers pressed change")
  func finiteSuppressionScopeCoversPressedChange() {
    let rootIdentity = testIdentity("Root")
    let pressedIdentity = testIdentity("Root", "Pressed")
    let state = warmedSelectiveState(rootIdentity: rootIdentity)
    state.retainedReuseSuppressionScope = .init(identities: [pressedIdentity])

    let inputs = state.prepareInputs(
      from: resolveContext(
        rootIdentity: rootIdentity,
        invalidatedIdentities: [testIdentity("Root", "Child")],
        pressedIdentity: pressedIdentity
      ),
      proposal: baselineProposal
    )

    #expect(inputs.usesSelectiveEvaluation)
    #expect(!inputs.environmentRequiresRootEvaluation)
    #expect(inputs.selectiveEvaluationDisabledReasons == [])
    #expect(inputs.retainedReuseSuppressionScope.identities == [pressedIdentity])
  }

  @Test("runtime gate: proposal change disables selective evaluation")
  func proposalChangeDisablesSelectiveEvaluation() {
    let rootIdentity = testIdentity("Root")
    let state = warmedSelectiveState(rootIdentity: rootIdentity)

    let inputs = state.prepareInputs(
      from: resolveContext(
        rootIdentity: rootIdentity,
        invalidatedIdentities: [testIdentity("Root", "Child")]
      ),
      proposal: ProposedSize(width: 120, height: 30)
    )

    #expect(!inputs.usesSelectiveEvaluation)
    #expect(inputs.environmentRequiresRootEvaluation)
    #expect(inputs.selectiveEvaluationDisabledReasons == [.proposalChanged])
  }

  @Test("runtime gate: disabled reasons preserve multiple blockers")
  func disabledReasonsPreserveMultipleBlockers() {
    let rootIdentity = testIdentity("Root")
    let state = warmedSelectiveState(rootIdentity: rootIdentity)
    state.forceRootEvaluation = true

    let inputs = state.prepareInputs(
      from: resolveContext(
        rootIdentity: rootIdentity,
        invalidatedIdentities: [rootIdentity],
        pressedIdentity: testIdentity("Root", "Pressed"),
        forceRootEvaluation: true
      ),
      proposal: ProposedSize(width: 120, height: 30)
    )

    #expect(!inputs.usesSelectiveEvaluation)
    #expect(inputs.environmentRequiresRootEvaluation)
    #expect(
      inputs.selectiveEvaluationDisabledReasons == [
        .frameStateForceRoot,
        .contextForceRoot,
        .pressedChanged,
        .proposalChanged,
        .rootInvalidated,
      ]
    )
  }

  @Test("runtime gate: force-root sources surface once and clear")
  func forceRootSourcesSurfaceOnceAndClear() {
    let rootIdentity = testIdentity("Root")
    let state = warmedSelectiveState(rootIdentity: rootIdentity)
    state.forceRootEvaluation = true
    state.forceRootEvaluationSources = [.focusSyncRerender, .unattributed]

    let inputs = state.prepareInputs(
      from: resolveContext(rootIdentity: rootIdentity),
      proposal: baselineProposal
    )

    #expect(
      inputs.forceRootEvaluationSources == [
        .focusSyncRerender, .unattributed,
      ]
    )
    #expect(inputs.selectiveEvaluationDisabledReasons.contains(.frameStateForceRoot))

    let second = state.prepareInputs(
      from: resolveContext(rootIdentity: rootIdentity),
      proposal: baselineProposal
    )
    #expect(second.forceRootEvaluationSources.isEmpty)
    #expect(!second.selectiveEvaluationDisabledReasons.contains(.frameStateForceRoot))
  }

  @Test("diagnostic names enrich frame_state_force_root with sources")
  func diagnosticNamesEnrichFrameStateForceRootWithSources() {
    let rootIdentity = testIdentity("Root")
    let state = warmedSelectiveState(rootIdentity: rootIdentity)
    state.forceRootEvaluation = true
    state.forceRootEvaluationSources = [.focusSyncRerender]

    let inputs = state.prepareInputs(
      from: resolveContext(rootIdentity: rootIdentity),
      proposal: baselineProposal
    )

    #expect(
      inputs.diagnosticSelectiveEvaluationDisabledReasonNames.contains(
        "frame_state_force_root(focus_sync_rerender)"
      )
    )
  }
}

@MainActor
private let baselineProposal = ProposedSize(width: 80, height: 24)

@MainActor
private func warmedSelectiveState(rootIdentity: Identity) -> FrameResolveState {
  let state = FrameResolveState()
  state.selectiveEvaluationEnabled = true
  _ = state.prepareInputs(
    from: resolveContext(rootIdentity: rootIdentity),
    proposal: baselineProposal
  )
  return state
}

@MainActor
private func resolveContext(
  rootIdentity: Identity,
  invalidatedIdentities: Set<Identity> = [],
  focusedIdentity: Identity? = nil,
  pressedIdentity: Identity? = nil,
  forceRootEvaluation: Bool = false
) -> ResolveContext {
  var environmentValues = EnvironmentValues()
  environmentValues.focusedIdentity = focusedIdentity
  environmentValues.pressedIdentity = pressedIdentity
  return ResolveContext(
    identity: rootIdentity,
    environmentValues: environmentValues,
    invalidatedIdentities: invalidatedIdentities,
    forceRootEvaluation: forceRootEvaluation,
    applyEnvironmentValues: true
  )
}

// MARK: - F177: the single selective-evaluation formula

@MainActor
@Suite("Selective-evaluation decision formula (F177)")
struct SelectiveEvaluationDecisionTests {
  @Test(
    "the shared formula is the conjunction of enabled and the two root vetoes",
    arguments: [
      // (enabled, environmentRequiresRoot, rootInvalidated, expected)
      (true, false, false, true),
      (true, true, false, false),
      (true, false, true, false),
      (true, true, true, false),
      (false, false, false, false),
      (false, true, false, false),
      (false, false, true, false),
      (false, true, true, false),
    ])
  func decisionTruthTable(row: (Bool, Bool, Bool, Bool)) {
    #expect(
      FrameResolveState.selectiveEvaluationDecision(
        enabled: row.0,
        environmentRequiresRoot: row.1,
        rootInvalidated: row.2
      ) == row.3
    )
  }
}
