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
/// layout-dependent content before semantics, draw, raster, and commit.
struct LatePreferenceReconciliationStage {
  var policy: LatePreferenceReconciliationPolicy

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
        layout = renderLayout(input)
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
    renderLayout: (FrameTailInput) async -> AsyncFrameTailLayoutPass
  ) async -> AsyncLatePreferenceReconciliationOutput {
    var input = initialInput
    var totalSuspensionDuration = Duration.zero
    var layoutPass = await renderLayout(input)
    totalSuspensionDuration += layoutPass.suspensionDuration
    guard var layout = layoutPass.layout else {
      return .init(layout: nil, suspensionDuration: totalSuspensionDuration)
    }

    let budget = policy.relayoutPassBudget(for: initialInput)
    for _ in 0..<budget {
      switch reconciliationStep(input: input, layout: layout) {
      case .finished(let reconciled):
        return .init(
          layout: reconciled,
          suspensionDuration: totalSuspensionDuration
        )
      case .needsRelayout(let nextInput):
        input = nextInput
        layoutPass = await renderLayout(input)
        totalSuspensionDuration += layoutPass.suspensionDuration
        guard let nextLayout = layoutPass.layout else {
          return .init(layout: nil, suspensionDuration: totalSuspensionDuration)
        }
        layout = nextLayout
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
    layout: FrameTailLayoutOutput
  ) -> LatePreferenceReconciliationStep {
    let realized = input.resolved.applyingLayoutDependentRealizations(
      input.layoutPassContext.layoutDependentRealizationsByIdentity
    )
    let reconciliation = reconcileLatePreferenceConsumers(in: realized)
    let runtimeIssues = layoutRuntimeIssues(input: input, resolved: reconciliation.resolved)

    guard reconciliation.requiresRelayout else {
      var finalInput = input
      finalInput.resolved = reconciliation.resolved
      return .finished(
        ReconciledFrameTailLayout(
          input: finalInput,
          layout: layout,
          resolved: reconciliation.resolved,
          runtimeIssues: runtimeIssues
        )
      )
    }

    return .needsRelayout(
      relayoutInput(
        basedOn: input,
        resolved: reconciliation.resolved
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
    let realized = input.resolved.applyingLayoutDependentRealizations(
      input.layoutPassContext.layoutDependentRealizationsByIdentity
    )
    let reconciliation = reconcileLatePreferenceConsumers(in: realized)
    if !reconciliation.requiresRelayout {
      var finalInput = input
      finalInput.resolved = reconciliation.resolved
      return ReconciledFrameTailLayout(
        input: finalInput,
        layout: layout,
        resolved: reconciliation.resolved,
        runtimeIssues: layoutRuntimeIssues(input: input, resolved: reconciliation.resolved)
      )
    }

    switch policy.boundExceededBehavior {
    case .warnAndCommitLatestReconciledLayout:
      let finalInput = relayoutInput(
        basedOn: input,
        resolved: reconciliation.resolved
      )
      let finalLayout = renderLayout(finalInput)
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
    let realized = input.resolved.applyingLayoutDependentRealizations(
      input.layoutPassContext.layoutDependentRealizationsByIdentity
    )
    let reconciliation = reconcileLatePreferenceConsumers(in: realized)
    if !reconciliation.requiresRelayout {
      var finalInput = input
      finalInput.resolved = reconciliation.resolved
      return .init(
        layout: ReconciledFrameTailLayout(
          input: finalInput,
          layout: layout,
          resolved: reconciliation.resolved,
          runtimeIssues: layoutRuntimeIssues(input: input, resolved: reconciliation.resolved)
        ),
        suspensionDuration: .zero
      )
    }

    let finalInput = relayoutInput(
      basedOn: input,
      resolved: reconciliation.resolved
    )
    let finalLayoutPass = await renderLayout(finalInput)
    guard let finalLayout = finalLayoutPass.layout else {
      return .init(layout: nil, suspensionDuration: finalLayoutPass.suspensionDuration)
    }
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
    let realized = input.resolved.applyingLayoutDependentRealizations(
      input.layoutPassContext.layoutDependentRealizationsByIdentity
    )
    let reconciliation = reconcileLatePreferenceConsumers(in: realized)
    var finalInput = input
    finalInput.resolved = reconciliation.resolved
    return ReconciledFrameTailLayout(
      input: finalInput,
      layout: layout,
      resolved: reconciliation.resolved,
      runtimeIssues: layoutRuntimeIssues(input: input, resolved: reconciliation.resolved) + [
        latePreferenceReconciliationLimitIssue(
          rootIdentity: input.rootIdentity,
          relayoutPassBudget: budget
        )
      ]
    )
  }

  private func relayoutInput(
    basedOn input: FrameTailInput,
    resolved: ResolvedNode
  ) -> FrameTailInput {
    FrameTailInput(
      generation: input.generation,
      resolved: resolved,
      proposal: input.proposal,
      rootIdentity: input.rootIdentity,
      retained: input.retained,
      layoutPassContext: LayoutPassContext(
        retainedLayout: input.retained.retainedLayout,
        invalidatedIdentities: input.layoutPassContext.invalidatedIdentities
      )
    )
  }
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
  let unhostedToolbarItems = resolved.preferenceValues[ToolbarItemsPreferenceKey.self]
  guard !unhostedToolbarItems.isEmpty else {
    return []
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
  return [
    RuntimeIssue(
      severity: .warning,
      code: "toolbar.unhostedItems",
      message:
        "\(unhostedToolbarItems.count) toolbar item(s) reached the scene root without an enclosing `.toolbar(style:)` on an `ActionScope`; the item(s) were not rendered.\(titleSummary)",
      identity: sourceIdentity,
      source: ".toolbarItem(...)"
    )
  ]
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
