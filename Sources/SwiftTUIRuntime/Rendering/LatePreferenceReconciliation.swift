import SwiftTUICore
import SwiftTUIViews

struct LatePreferenceReconciliationPolicy: Sendable {
  enum BoundExceededBehavior: Sendable {
    /// Emit a runtime warning and perform one final relayout of the latest
    /// reconciled tree before committing.
    case warnAndCommitLatestReconciledLayout
  }

  static let toolbarHostRuntimeBound = Self(
    boundExceededBehavior: .warnAndCommitLatestReconciledLayout
  )

  var boundExceededBehavior: BoundExceededBehavior

  /// ADR-0018 now derives the pass budget from the current resolved tree:
  /// every relayout must be justified by at least one finite node producing a
  /// changed late-preference consumer output, plus one pass to confirm
  /// stability. A non-converging author cycle therefore scales with the current
  /// tree instead of a historical toolbar constant.
  func relayoutPassBudget(for input: FrameTailInput) -> Int {
    max(1, input.resolved.subtreeNodeCount + 1)
  }
}

struct AsyncFrameTailLayoutPass {
  var layout: FrameTailLayoutOutput?
  var suspensionDuration: Duration
}

struct AsyncLatePreferenceReconciliationOutput {
  var layout: ReconciledFrameTailLayout?
  var suspensionDuration: Duration
}

private enum LatePreferenceReconciliationStep {
  case finished(ReconciledFrameTailLayout)
  case needsRelayout(FrameTailInput)
}

/// Loop-bearing stage that reconciles preferences emitted by realized
/// layout-realized content before semantics, draw, raster, and commit.
struct LatePreferenceReconciliationStage {
  var policy: LatePreferenceReconciliationPolicy
  /// Purely reapplies presentation values already sampled by the animation
  /// stage. It must not advance curves or mutate animation bookkeeping.
  var projectResolvedPresentation: @MainActor (ResolvedNode) -> ResolvedNode

  init(
    policy: LatePreferenceReconciliationPolicy,
    projectResolvedPresentation: @escaping @MainActor (ResolvedNode) -> ResolvedNode = { $0 }
  ) {
    self.policy = policy
    self.projectResolvedPresentation = projectResolvedPresentation
  }

  @MainActor
  func run(
    initialInput: FrameTailInput,
    renderLayout: (FrameTailInput) -> FrameTailLayoutOutput
  ) -> ReconciledFrameTailLayout {
    var input = initialInput
    var layout = renderLayout(input)

    let budget = policy.relayoutPassBudget(for: initialInput)
    for _ in 0..<budget {
      switch reconciliationStep(input: input, layout: layout) {
      case .finished(let reconciled):
        return reconciled
      case .needsRelayout(let nextInput):
        input = nextInput
        let previousShadow = layout.layoutShadow
        layout = renderLayout(input)
        foldLayoutShadow(previousShadow, into: &layout)
      }
    }

    return reconciliationLimitExceeded(
      input: input,
      layout: layout,
      budget: budget,
      renderLayout: renderLayout
    )
  }

  @MainActor
  func runAsync(
    initialInput: FrameTailInput,
    shouldRelayoutLayoutRealizationSnapshot: (FrameTailInput) -> Bool = { _ in false },
    renderLayout: (FrameTailInput) async -> AsyncFrameTailLayoutPass
  ) async -> AsyncLatePreferenceReconciliationOutput {
    var input = initialInput
    var totalSuspensionDuration = Duration.zero
    var layoutPassCount = 0
    var accumulatedLayoutWork = LayoutWorkMetrics()

    func recordLayoutWork(_ layout: FrameTailLayoutOutput) {
      layoutPassCount += 1
      accumulatedLayoutWork.merge(layout.layoutWork)
    }

    func applyingAccumulatedLayoutWork(
      to reconciled: ReconciledFrameTailLayout
    ) -> ReconciledFrameTailLayout {
      guard layoutPassCount > 1 else {
        return reconciled
      }
      var reconciled = reconciled
      reconciled.layout.layoutWork = accumulatedLayoutWork
      return reconciled
    }

    var layoutPass = await renderLayout(input)
    totalSuspensionDuration += layoutPass.suspensionDuration
    guard var layout = layoutPass.layout else {
      return .init(layout: nil, suspensionDuration: totalSuspensionDuration)
    }
    recordLayoutWork(layout)

    let budget = policy.relayoutPassBudget(for: initialInput)
    for _ in 0..<budget {
      switch reconciliationStep(
        input: input,
        layout: layout,
        shouldRelayoutLayoutRealizationSnapshot: shouldRelayoutLayoutRealizationSnapshot
      ) {
      case .finished(let reconciled):
        return .init(
          layout: applyingAccumulatedLayoutWork(to: reconciled),
          suspensionDuration: totalSuspensionDuration
        )
      case .needsRelayout(let nextInput):
        input = nextInput
        let previousShadow = layout.layoutShadow
        layoutPass = await renderLayout(input)
        totalSuspensionDuration += layoutPass.suspensionDuration
        guard let nextLayout = layoutPass.layout else {
          return .init(layout: nil, suspensionDuration: totalSuspensionDuration)
        }
        layout = nextLayout
        foldLayoutShadow(previousShadow, into: &layout)
        recordLayoutWork(layout)
      }
    }

    let exceeded = await reconciliationLimitExceededAsync(
      input: input,
      layout: layout,
      budget: budget,
      renderLayout: renderLayout
    )
    totalSuspensionDuration += exceeded.suspensionDuration
    return .init(layout: exceeded.layout, suspensionDuration: totalSuspensionDuration)
  }

  @MainActor
  private func reconciliationStep(
    input: FrameTailInput,
    layout: FrameTailLayoutOutput,
    shouldRelayoutLayoutRealizationSnapshot: (FrameTailInput) -> Bool = { _ in false }
  ) -> LatePreferenceReconciliationStep {
    let realizations = input.layoutPassContext.layoutDependentRealizationsByIdentity
    let canonicalRealized = input.canonicalResolved.applyingLayoutDependentRealizations(realizations)
    let reconciliation = reconcileLatePreferenceConsumers(in: canonicalRealized)
    let presented = projectResolvedPresentation(reconciliation.resolved)
    let runtimeIssues = layoutRuntimeIssues(input: input, resolved: presented)

    if reconciliation.requiresRelayout {
      return .needsRelayout(
        relayoutInput(
          basedOn: input,
          canonicalResolved: reconciliation.resolved
        )
      )
    }

    if let workerSnapshot = reconciliation.resolved.layoutRealizationWorkerSnapshot(
      using: realizations
    ) {
      let nextInput = relayoutInput(
        basedOn: input,
        canonicalResolved: workerSnapshot
      )
      if shouldRelayoutLayoutRealizationSnapshot(nextInput) {
        return .needsRelayout(nextInput)
      }
    }

    var finalInput = input
    finalInput.canonicalResolved = reconciliation.resolved
    finalInput.resolved = presented
    return .finished(
      ReconciledFrameTailLayout(
        input: finalInput,
        layout: layout,
        resolved: presented,
        runtimeIssues: runtimeIssues
      )
    )
  }

  @MainActor
  private func reconciliationLimitExceeded(
    input: FrameTailInput,
    layout: FrameTailLayoutOutput,
    budget: Int,
    renderLayout: (FrameTailInput) -> FrameTailLayoutOutput
  ) -> ReconciledFrameTailLayout {
    let realized = input.canonicalResolved.applyingLayoutDependentRealizations(
      input.layoutPassContext.layoutDependentRealizationsByIdentity
    )
    let reconciliation = reconcileLatePreferenceConsumers(in: realized)
    let presented = projectResolvedPresentation(reconciliation.resolved)
    if !reconciliation.requiresRelayout {
      var finalInput = input
      finalInput.canonicalResolved = reconciliation.resolved
      finalInput.resolved = presented
      return ReconciledFrameTailLayout(
        input: finalInput,
        layout: layout,
        resolved: presented,
        runtimeIssues: layoutRuntimeIssues(input: input, resolved: presented)
      )
    }

    switch policy.boundExceededBehavior {
    case .warnAndCommitLatestReconciledLayout:
      let finalInput = relayoutInput(
        basedOn: input,
        canonicalResolved: reconciliation.resolved
      )
      var finalLayout = renderLayout(finalInput)
      foldLayoutShadow(layout.layoutShadow, into: &finalLayout)
      return finalLayoutAfterBoundExceeded(
        input: finalInput,
        layout: finalLayout,
        budget: budget
      )
    }
  }

  @MainActor
  private func reconciliationLimitExceededAsync(
    input: FrameTailInput,
    layout: FrameTailLayoutOutput,
    budget: Int,
    renderLayout: (FrameTailInput) async -> AsyncFrameTailLayoutPass
  ) async -> AsyncLatePreferenceReconciliationOutput {
    let realized = input.canonicalResolved.applyingLayoutDependentRealizations(
      input.layoutPassContext.layoutDependentRealizationsByIdentity
    )
    let reconciliation = reconcileLatePreferenceConsumers(in: realized)
    let presented = projectResolvedPresentation(reconciliation.resolved)
    if !reconciliation.requiresRelayout {
      var finalInput = input
      finalInput.canonicalResolved = reconciliation.resolved
      finalInput.resolved = presented
      return .init(
        layout: ReconciledFrameTailLayout(
          input: finalInput,
          layout: layout,
          resolved: presented,
          runtimeIssues: layoutRuntimeIssues(input: input, resolved: presented)
        ),
        suspensionDuration: .zero
      )
    }

    let finalInput = relayoutInput(
      basedOn: input,
      canonicalResolved: reconciliation.resolved
    )
    let finalLayoutPass = await renderLayout(finalInput)
    guard var finalLayout = finalLayoutPass.layout else {
      return .init(layout: nil, suspensionDuration: finalLayoutPass.suspensionDuration)
    }
    foldLayoutShadow(layout.layoutShadow, into: &finalLayout)
    return .init(
      layout: finalLayoutAfterBoundExceeded(
        input: finalInput,
        layout: finalLayout,
        budget: budget
      ),
      suspensionDuration: finalLayoutPass.suspensionDuration
    )
  }

  @MainActor
  private func finalLayoutAfterBoundExceeded(
    input: FrameTailInput,
    layout: FrameTailLayoutOutput,
    budget: Int
  ) -> ReconciledFrameTailLayout {
    let realized = input.canonicalResolved.applyingLayoutDependentRealizations(
      input.layoutPassContext.layoutDependentRealizationsByIdentity
    )
    let reconciliation = reconcileLatePreferenceConsumers(in: realized)
    let presented = projectResolvedPresentation(reconciliation.resolved)
    var finalInput = input
    finalInput.canonicalResolved = reconciliation.resolved
    finalInput.resolved = presented
    return ReconciledFrameTailLayout(
      input: finalInput,
      layout: layout,
      resolved: presented,
      runtimeIssues: layoutRuntimeIssues(input: input, resolved: presented) + [
        latePreferenceReconciliationLimitIssue(
          rootIdentity: input.rootIdentity,
          relayoutPassBudget: budget
        )
      ]
    )
  }

  @MainActor
  private func relayoutInput(
    basedOn input: FrameTailInput,
    canonicalResolved: ResolvedNode
  ) -> FrameTailInput {
    let presented = projectResolvedPresentation(canonicalResolved)
    return FrameTailInput(
      generation: input.generation,
      canonicalResolved: canonicalResolved,
      resolved: presented,
      proposal: input.proposal,
      rootIdentity: input.rootIdentity,
      retained: input.retained,
      layoutPassContext: LayoutPassContext(
        customLayoutCacheStore: input.layoutPassContext.customLayoutCacheStore,
        retainedLayout: input.retained.retainedLayout,
        invalidatedIdentities: input.layoutPassContext.invalidatedIdentities,
        customLayoutCompatibilityDepthLimit:
          LayoutPassContext.mainActorCustomLayoutCompatibilityDepthLimit
      ),
      graphAnimationInputToken: input.graphAnimationInputToken,
      evaluatedNodeIDs: input.evaluatedNodeIDs,
      animationRedrawIdentities: input.animationRedrawIdentities,
      animationSegmentTargetIdentities: input.animationSegmentTargetIdentities,
      verifyLayoutShadow: input.verifyLayoutShadow
    )
  }
}

/// Every reconciliation pass runs its own sampled shadow comparison; a
/// divergence caught by an intermediate pass must survive to the recording
/// point even though only the final pass's layout output ships.
private func foldLayoutShadow(
  _ previous: LayoutShadowComparisonSummary?,
  into layout: inout FrameTailLayoutOutput
) {
  guard var merged = previous else {
    return
  }
  if let current = layout.layoutShadow {
    merged.merge(current)
  }
  layout.layoutShadow = merged
}

@MainActor
func layoutRuntimeIssues(
  input: FrameTailInput,
  resolved: ResolvedNode
) -> [RuntimeIssue] {
  input.layoutPassContext.runtimeIssues + rootRuntimeIssues(in: resolved)
}

@MainActor
private func rootRuntimeIssues(
  in resolved: ResolvedNode
) -> [RuntimeIssue] {
  var issues = resolved.duplicateEntityIdentityRuntimeIssues()
  for issue in resolved.preferenceValues[RuntimeIssuePreferenceKey.self]
  where !issues.contains(issue) {
    issues.append(issue)
  }
  let unhostedToolbarItems = resolved.preferenceValues[ToolbarItemsPreferenceKey.self]
  guard !unhostedToolbarItems.isEmpty else {
    return issues
  }

  let titles =
    unhostedToolbarItems
    .map(\.title)
    .filter { !$0.isEmpty }
  let titleSummary =
    if titles.isEmpty {
      ""
    } else {
      " Items: \(titles.joined(separator: ", "))."
    }
  let sourceIdentity =
    unhostedToolbarItems.compactMap(\.sourceIdentity).first ?? resolved.identity
  let unhostedIssue = RuntimeIssue(
    severity: .warning,
    code: "toolbar.unhostedItems",
    message:
      "\(unhostedToolbarItems.count) toolbar item(s) reached the scene root without an enclosing `.toolbar()` on an `ActionScope`; the item(s) were not rendered.\(titleSummary)",
    identity: sourceIdentity,
    source: ".toolbarItem(...)"
  )
  if !issues.contains(unhostedIssue) {
    issues.append(unhostedIssue)
  }
  return issues
}

private func latePreferenceReconciliationLimitIssue(
  rootIdentity: Identity,
  relayoutPassBudget: Int
) -> RuntimeIssue {
  RuntimeIssue(
    severity: .warning,
    code: "latePreference.reconciliationLimitExceeded",
    message:
      "Late preference reconciliation did not converge within the \(relayoutPassBudget)-pass tree-derived budget; the frame was committed after one final relayout of the latest reconciled tree.",
    identity: rootIdentity,
    source: "late preference reconciliation"
  )
}
