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
