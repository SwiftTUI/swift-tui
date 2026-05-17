@_exported import EmbeddedFonts
@_exported import SwiftTUICore
@_exported import SwiftTUIViews

/// Mutates the resolved tree with in-flight animation values after resolve and
/// before measure.
///
/// This is the runtime's explicit animation-injection stage. It is not a new
/// public phase product; it is the single insertion point where resolved
/// animatable values are rewritten before the measure/place tail observes them.
private struct AnimationInjectionStage {
  var animationDraft: AnimationFrameDraft

  @MainActor
  func apply(
    to resolved: inout ResolvedNode,
    transaction: TransactionSnapshot,
    timestamp: MonotonicInstant
  ) {
    let controller = animationDraft.controller
    controller.processResolvedTree(
      resolved,
      transaction: transaction,
      timestamp: timestamp
    )
    _ = controller.applyInterpolations(
      to: &resolved,
      at: timestamp
    )
  }
}

@MainActor
private func withAnimationDraftSinks<Result>(
  _ animationDraft: AnimationFrameDraft,
  operation: () -> Result
) -> Result {
  let controller = animationDraft.controller
  return AnimationRegistrationStorage.$currentTaskSink.withValue(controller) {
    TransitionRegistrationStorage.$currentTaskSink.withValue(controller) {
      AnimationCompletionStorage.$currentTaskSink.withValue(controller) {
        operation()
      }
    }
  }
}

private struct LatePreferenceReconciliationPolicy: Sendable {
  enum BoundExceededBehavior: Sendable {
    /// Emit a runtime warning and commit the last fully laid-out tree with the
    /// latest realized layout-dependent content.
    case warnAndCommitLastLayout
  }

  /// The toolbar-only shipped reconciler can need a first layout plus bounded
  /// relayouts when toolbar chrome changes available geometry. Keep the
  /// historical runtime bound explicit until more late-preference consumers
  /// justify a derived dependency-depth bound.
  static let toolbarHostRuntimeBound = Self(
    maximumRelayoutPasses: 4,
    boundExceededBehavior: .warnAndCommitLastLayout
  )

  var maximumRelayoutPasses: Int
  var boundExceededBehavior: BoundExceededBehavior
}

@MainActor
private final class CommittedPresentationDismissStack {
  private var stack = DismissStack()

  func topmostEscapeDismissAction() -> (@MainActor @Sendable () -> Void)? {
    stack.topmostEscapeDismissAction()
  }

  func store(_ stack: DismissStack) {
    self.stack = stack
  }
}

private struct AsyncFrameTailLayoutPass {
  var layout: FrameTailLayoutOutput?
  var suspensionDuration: Duration
}

private struct AsyncLatePreferenceReconciliationOutput {
  var layout: ReconciledFrameTailLayout?
  var suspensionDuration: Duration
}

private enum LatePreferenceReconciliationStep {
  case finished(ReconciledFrameTailLayout)
  case needsRelayout(FrameTailInput)
}

/// Loop-bearing stage that reconciles preferences emitted by realized
/// layout-dependent content before semantics, draw, raster, and commit.
private struct LatePreferenceReconciliationStage {
  var policy: LatePreferenceReconciliationPolicy

  @MainActor
  func run(
    initialInput: FrameTailInput,
    renderLayout: (FrameTailInput) -> FrameTailLayoutOutput
  ) -> ReconciledFrameTailLayout {
    var input = initialInput
    var layout = renderLayout(input)

    for _ in 0..<policy.maximumRelayoutPasses {
      switch reconciliationStep(input: input, layout: layout) {
      case .finished(let reconciled):
        return reconciled
      case .needsRelayout(let nextInput):
        input = nextInput
        layout = renderLayout(input)
      }
    }

    return reconciliationLimitExceeded(input: input, layout: layout)
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

    for _ in 0..<policy.maximumRelayoutPasses {
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

    return .init(
      layout: reconciliationLimitExceeded(input: input, layout: layout),
      suspensionDuration: totalSuspensionDuration
    )
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
    layout: FrameTailLayoutOutput
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
    case .warnAndCommitLastLayout:
      var finalInput = input
      finalInput.resolved = realized
      return ReconciledFrameTailLayout(
        input: finalInput,
        layout: layout,
        resolved: realized,
        runtimeIssues: input.layoutPassContext.runtimeIssues + [
          latePreferenceReconciliationLimitIssue(
            rootIdentity: input.rootIdentity,
            maximumRelayoutPasses: policy.maximumRelayoutPasses
          )
        ]
      )
    }
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
private func layoutRuntimeIssues(
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
  maximumRelayoutPasses: Int
) -> RuntimeIssue {
  RuntimeIssue(
    severity: .warning,
    code: "latePreference.reconciliationLimitExceeded",
    message:
      "Late preference reconciliation did not converge within \(maximumRelayoutPasses) passes; the frame was committed from the last fully laid-out tree without applying the final late preference changes.",
    identity: rootIdentity,
    source: "late preference reconciliation"
  )
}

/// Renders authored terminal views through the full frame pipeline.
///
/// `DefaultRenderer` is the public one-shot entry point for turning a `View`
/// into `FrameArtifacts` for previews, snapshot tests, diagnostics, or custom
/// presentation.
public struct DefaultRenderer {
  private static let latePreferenceReconciliationPolicy =
    LatePreferenceReconciliationPolicy.toolbarHostRuntimeBound

  public let resolver: Resolver
  public let layoutEngine: LayoutEngine
  public let semanticExtractor: SemanticExtractor
  public let drawExtractor: DrawExtractor
  public let rasterizer: Rasterizer
  public let commitPlanner: CommitPlanner
  private let imageRepository: ImageAssetRepository
  private let viewGraph: ViewGraph
  private let frameState: FrameResolveState
  private let frameInputs: FrameResolveInputBox
  private let presentationPortalState: PresentationPortalState
  private let committedPresentationDismissStack: CommittedPresentationDismissStack
  private let animationController: AnimationController
  private let renderGenerationSequencer: RenderGenerationSequencer

  private let frameTailRenderer: FrameTailRenderer

  /// Creates a renderer with the supplied pipeline components.
  @MainActor
  public init(
    resolver: Resolver = .init(),
    layoutEngine: LayoutEngine = .init(cache: MeasurementCache()),
    semanticExtractor: SemanticExtractor = .init(),
    drawExtractor: DrawExtractor = .init(),
    rasterizer: Rasterizer = .init(),
    commitPlanner: CommitPlanner = .init()
  ) {
    self.resolver = resolver
    self.layoutEngine = layoutEngine
    self.semanticExtractor = semanticExtractor
    self.drawExtractor = drawExtractor
    self.rasterizer = rasterizer
    self.commitPlanner = commitPlanner
    imageRepository = sharedImageAssetRepository
    viewGraph = .init()
    frameState = .init()
    frameInputs = .init()
    presentationPortalState = .init()
    committedPresentationDismissStack = .init()
    animationController = .init()
    renderGenerationSequencer = .init()
    frameTailRenderer = .init(
      layoutEngine: layoutEngine,
      semanticExtractor: semanticExtractor,
      drawExtractor: drawExtractor,
      rasterizer: rasterizer
    )
  }

  /// Package-only accessor so the run loop can register animations
  /// against the renderer's controller before a `withAnimation` body
  /// executes.
  @MainActor
  package var internalAnimationController: AnimationController {
    animationController
  }

  /// Package-only accessor so the run loop can route framework-reserved
  /// single-key events (currently Escape) to the active presentation
  /// dismiss stack. Returns the dismiss closure of the topmost
  /// Escape-dismissible portal entry, or nil when none is active.
  @MainActor
  package func topmostEscapeDismissAction() -> (@MainActor @Sendable () -> Void)? {
    committedPresentationDismissStack.topmostEscapeDismissAction()
  }

  /// Package-only accessor so the run loop can route framework-reserved
  /// Escape handling to the active destination stack after modal presentation
  /// dismissal has had first claim.
  @MainActor
  package func topmostNavigationDestinationPopAction(
    along scopePath: [Identity]
  ) -> (@MainActor @Sendable () -> Void)? {
    let resolved = renderPipelineTree(from: viewGraph.snapshot())
    return navigationDestinationPopAction(
      in: resolved,
      along: scopePath
    )
  }

  /// Package-only accessor exposing the renderer's internal
  /// `ViewGraph.registrationAliasDiagnostics`.  Added for Item 7 of
  /// `docs/proposals/ARCHITECTURE_NOTES.md` to let tests measure the alias layer's
  /// actual workload against the architecture doc's hypothesis.
  @MainActor
  package var debugRegistrationAliasDiagnostics: RegistrationAliasDiagnostics {
    viewGraph.registrationAliasDiagnostics
  }

  @MainActor
  package func prepareFrameHeadForCancellationTesting<V: View>(
    _ root: V,
    context: ResolveContext = .init(),
    proposal: ProposedSize = .unspecified
  ) -> FrameHeadDraft {
    prepareFrameHead(
      root,
      context: context,
      proposal: proposal
    )
  }

  @MainActor
  package func abortPreparedFrameHeadForCancellationTesting(
    _ draft: FrameHeadDraft
  ) {
    abortPreparedFrameHead(draft)
  }

  @MainActor
  package func abortPreparedFrameHead(
    _ draft: FrameHeadDraft
  ) {
    guard let checkpoints = draft.checkpoints else {
      preconditionFailure(
        "Cannot abort a one-shot frame head — it has no checkpoints."
      )
    }
    draft.registrationDraft.discard()
    draft.graphDraft.discard(from: viewGraph)
    draft.presentationPortalDraft.discard()
    draft.observationDraft?.discard()
    draft.animationDraft.discard()
    frameState.restoreCheckpoint(checkpoints.frameState)
    frameInputs.clear()
  }

  @MainActor
  package func renderPreparedFrameTailForCancellationTesting(
    _ draft: FrameHeadDraft
  ) async {
    _ = await renderFrameTailAsync(draft)
  }

  @MainActor
  package func discardPreparedFrameTailForReconciliationTesting(
    _ draft: FrameHeadDraft,
    decision: CompletedFrameDropDecision
  ) async -> Bool {
    guard decision.canSkipCompletedFrame else {
      return false
    }

    let tailOutput = await renderFrameTailAsync(draft)
    let candidate = makeCompletedFrameCandidate(
      draft: draft,
      tailOutput: tailOutput,
      newestDesiredGeneration: draft.renderGeneration
    )
    discardCompletedFrameCandidate(
      candidate,
      reconciliation: decision.reconciliation
    )
    return true
  }

  @MainActor
  package func previewCompletedFrameCandidateForTesting(
    _ draft: FrameHeadDraft
  ) async -> CompletedFrameDropDecision {
    let tailOutput = await renderFrameTailAsync(draft)
    let candidate = makeCompletedFrameCandidate(
      draft: draft,
      tailOutput: tailOutput,
      newestDesiredGeneration: draft.renderGeneration
    )
    return candidate.dropDecision
  }

  @MainActor
  package func runFrameTailLayoutWorkerJobForCancellationTesting(
    _ operation: @escaping @Sendable () -> Void
  ) async {
    await frameTailRenderer.runLayoutWorkerJobForCancellationTesting(operation)
  }

  /// Renders `root` into complete frame artifacts.
  @MainActor
  public func render<V: View>(
    _ root: V,
    context: ResolveContext = .init(),
    proposal: ProposedSize = .unspecified
  ) -> FrameArtifacts {
    renderView(
      root,
      context: context,
      proposal: proposal
    )
  }

  /// Renders `root` into complete frame artifacts, suspending while the
  /// frame-tail worker computes the Sendable semantics, draw, and raster phases.
  @MainActor
  public func renderAsync<V: View>(
    _ root: V,
    context: ResolveContext = .init(),
    proposal: ProposedSize = .unspecified
  ) async -> FrameArtifacts {
    await renderViewAsync(
      root,
      context: context,
      proposal: proposal
    )
  }

  @MainActor
  package func renderAsyncCancellable<V: View>(
    _ root: V,
    context: ResolveContext,
    proposal: ProposedSize,
    newestDesiredGeneration: @escaping @MainActor @Sendable () -> RenderGeneration? = { nil },
    completedFramePolicy: CompletedFramePolicy? = nil,
    completedFrameAdditionalBlockers:
      @escaping @MainActor @Sendable (FrameArtifacts) -> Set<FrameDropEligibility.Blocker> = {
        _ in []
      },
    shouldCancelQueued: @escaping @MainActor @Sendable () async -> Bool
  ) async -> CancellableRenderOutcome {
    let renderer = self
    let draft = renderer.computeFrameHead(
      root,
      context: context,
      proposal: proposal,
      mode: .abortable
    )
    return await RuntimeRenderPipeline().renderCancellable(
      head: draft,
      animationInjection: { draft in
        renderer.injectAnimations(
          into: draft,
          mode: .abortable
        )
      },
      latePreferenceReconciliation: { draft in
        await renderer.renderCancellableFrameTailLayoutStage(
          draft,
          shouldCancelQueued: shouldCancelQueued
        )
      },
      fusedFrameTail: { draft, layoutStage in
        await renderer.renderCancellableFusedFrameTail(
          draft: draft,
          layoutStage: layoutStage
        )
      },
      cancelledBeforeStart: { draft in
        renderer.abortPreparedFrameHead(draft)
        return CancellableRenderOutcome(
          artifacts: nil,
          runtimeIssues: draft.runtimeIssues,
          renderGeneration: draft.renderGeneration,
          newestDesiredGeneration: nil,
          tailJobState: .cancelledBeforeStart,
          tailCancelReason: "newer_render_intent",
          completedFrameDropDecision: nil
        )
      },
      commitOrDrop: { draft, tailOutput in
        let newestGeneration = newestDesiredGeneration() ?? draft.renderGeneration
        let candidate = renderer.makeCompletedFrameCandidate(
          draft: draft,
          tailOutput: tailOutput,
          newestDesiredGeneration: newestGeneration,
          completedFramePolicy: completedFramePolicy,
          additionalBlockers: completedFrameAdditionalBlockers
        )
        if candidate.dropDecision.canSkipCompletedFrame {
          renderer.discardCompletedFrameCandidate(
            candidate,
            reconciliation: candidate.dropDecision.reconciliation
          )
          return CancellableRenderOutcome(
            artifacts: nil,
            runtimeIssues: candidate.previewArtifacts.diagnostics.runtime.issues,
            renderGeneration: draft.renderGeneration,
            newestDesiredGeneration: newestGeneration,
            tailJobState: .droppedCompleted,
            tailCancelReason: nil,
            completedFrameDropDecision: candidate.dropDecision
          )
        }
        let artifacts = renderer.commitCompletedFrameCandidate(candidate)
        return CancellableRenderOutcome(
          artifacts: artifacts,
          runtimeIssues: artifacts.diagnostics.runtime.issues,
          renderGeneration: draft.renderGeneration,
          newestDesiredGeneration: newestGeneration,
          tailJobState: .completed,
          tailCancelReason: nil,
          completedFrameDropDecision: candidate.dropDecision
        )
      }
    )
  }

  @MainActor
  private func renderView<V: View>(
    _ root: V,
    context: ResolveContext,
    proposal: ProposedSize
  ) -> FrameArtifacts {
    let renderer = self
    let draft = renderer.computeFrameHead(
      root,
      context: context,
      proposal: proposal,
      mode: .oneShot
    )
    return RuntimeRenderPipeline().renderOneShot(
      head: draft,
      animationInjection: { draft in
        renderer.injectAnimations(
          into: draft,
          mode: .oneShot
        )
      },
      latePreferenceReconciliation: { input, clock in
        renderer.renderLayoutResolvingLatePreferences(
          input,
          clock: clock
        )
      },
      fusedFrameTail: { draft, reconciledTailLayout in
        renderer.renderFusedFrameTail(
          draft: draft,
          reconciledTailLayout: reconciledTailLayout
        )
      },
      commit: { draft, reconciledTailLayout, tail in
        renderer.commitOneShotFrame(
          draft: draft,
          reconciledTailLayout: reconciledTailLayout,
          tail: tail
        )
      }
    )
  }

  @MainActor
  private func renderFusedFrameTail(
    draft: FrameHeadDraft,
    reconciledTailLayout: ReconciledFrameTailLayout
  ) -> FrameTailOutput {
    let layout = reconciledTailLayout.layout
    let placed = layout.baselinePlaced
    // Capture the BASELINE placed tree (pre-overlay) for two things:
    // 1. The animation controller's removal-snapshot lookup on the
    //    next frame (capturePlacedTree).
    // 2. The retained-layout store below, so future tick frames
    //    reuse the canonical layout and not an animation-decorated
    //    tree.
    //
    // If we stored the post-overlay placed tree, subsequent ticks
    // would hit retainedPlacement and return the cached tree
    // including the stale transient overlay — then overlay snapshot
    // application would inject another overlay on top, growing the tree
    // each tick and leaving ghosted artefacts visible after the animation
    // completes.
    let animationController = draft.animationDraft.controller
    animationController.capturePlacedTree(layout.baselinePlaced)
    // Snapshot any pending placed-level animation overlays. The snapshot
    // advances controller-owned animation state on the main actor, then the
    // frame-tail worker applies the value data before semantics/draw/raster.
    let animationOverlaySnapshot = animationController.placedAnimationOverlaySnapshot(
      for: placed,
      at: draft.animationTimestamp
    )
    return frameTailRenderer.renderRaster(
      reconciledTailLayout.input,
      layout: layout,
      placed: placed,
      animationOverlaySnapshot: animationOverlaySnapshot,
      clock: draft.clock
    )
  }

  @MainActor
  private func commitOneShotFrame(
    draft: FrameHeadDraft,
    reconciledTailLayout: ReconciledFrameTailLayout,
    tail: FrameTailOutput
  ) -> FrameArtifacts {
    let layout = reconciledTailLayout.layout
    let resolved = reconciledTailLayout.resolved
    var workerTimings = tail.diagnostics.workerTimings
    if var timings = workerTimings,
      let clock = draft.clock,
      let workerCompletedAt = tail.workerCompletedAt
    {
      timings.completionToMainCommit = workerCompletedAt.duration(to: clock.now)
      workerTimings = timings
    }
    var runtimeRegistrationDiagnostics = RuntimeRegistrationDiagnostics()
    let (commit, commitDuration) = measurePhase(clock: draft.clock) {
      let lifecycleEvents = viewGraph.finalizeFrame(
        rootIdentity: draft.graphRootIdentity,
        resolved: resolved,
        placed: tail.placed
      )
      runtimeRegistrationDiagnostics = draft.graphDraft.commitRuntimeRegistrations(
        from: viewGraph
      )
      commitFrameHeadDraftEffects(draft)
      return commitPlanner.plan(
        resolved: resolved,
        placed: tail.placed,
        semantics: tail.semantics,
        transaction: draft.frameContext.transaction,
        lifecycleEvents: lifecycleEvents
      )
    }
    draft.animationDraft.commit()
    applyWorkerCustomLayoutCacheUpdates(layout.workerCustomLayoutCacheUpdates)
    frameTailRenderer.pruneMeasurementCache(
      keeping: viewGraph.liveIdentitySnapshot()
    )
    let dropEligibilityBlockers = frameTailCommitDropBlockers(
      workerCustomLayoutCacheUpdates: layout.workerCustomLayoutCacheUpdates
    )
    let phaseTimings = FramePhaseTimings(
      resolve: draft.resolveDuration,
      measure: tail.diagnostics.measureDuration,
      place: tail.diagnostics.placeDuration,
      semantics: tail.diagnostics.semanticsDuration,
      draw: tail.diagnostics.drawDuration,
      raster: tail.diagnostics.rasterDuration,
      commit: commitDuration
    )
    let mainActorTimings = FrameMainActorTimings(
      blocked: phaseTimings.total,
      suspended: .zero
    )
    var diagnostics = FrameDiagnostics.summarize(
      resolved: resolved,
      measured: tail.measured,
      placed: tail.placed,
      semantics: tail.semantics,
      draw: tail.draw,
      invalidatedIdentities: draft.frameContext.invalidatedIdentities,
      resolveWork: draft.resolveContext.resolveWorkTracker?.snapshot,
      layoutWork: tail.diagnostics.layoutWork,
      presentationDamage: tail.presentationDamage,
      presentationSurfaceWidth: tail.raster.size.width,
      phaseTimings: phaseTimings,
      renderGenerations: .init(
        render: draft.renderGeneration,
        layoutInput: reconciledTailLayout.input.generation,
        layoutOutput: layout.generation,
        rasterInput: reconciledTailLayout.input.generation,
        rasterOutput: tail.generation
      ),
      workerTimings: workerTimings,
      mainActorTimings: mainActorTimings,
      measurementCache: tail.diagnostics.measurementCache,
      runtimeIssues: reconciledTailLayout.runtimeIssues,
      dropEligibilityBlockers: dropEligibilityBlockers
    )
    diagnostics.runtime.registrations = runtimeRegistrationDiagnostics
    let artifacts = FrameArtifacts(
      resolvedTree: resolved,
      measuredTree: tail.measured,
      placedTree: tail.placed,
      semanticSnapshot: tail.semantics,
      drawTree: tail.draw,
      rasterSurface: tail.raster,
      presentationDamage: tail.presentationDamage,
      drawnIdentities: tail.drawnIdentities,
      commitPlan: commit,
      diagnostics: diagnostics
    )

    draft.resolveContext.localScrollPositionRegistry?.updateGeometry(
      scrollRoutes: artifacts.semanticSnapshot.scrollRoutes,
      scrollTargets: artifacts.semanticSnapshot.scrollTargets
    )
    draft.graphDraft.updateCommittedScrollGeometry(
      scrollRoutes: artifacts.semanticSnapshot.scrollRoutes,
      scrollTargets: artifacts.semanticSnapshot.scrollTargets
    )
    frameTailRenderer.storeCommittedFrame(
      artifacts,
      baselinePlacedTree: tail.baselinePlaced
    )
    storeCommittedPresentationPortalState()
    return artifacts
  }

  @MainActor
  private func renderLayoutResolvingLatePreferences(
    _ initialInput: FrameTailInput,
    clock: ContinuousClock?
  ) -> ReconciledFrameTailLayout {
    LatePreferenceReconciliationStage(
      policy: Self.latePreferenceReconciliationPolicy
    ).run(initialInput: initialInput) { input in
      frameTailRenderer.renderLayout(
        input,
        clock: clock
      )
    }
  }

  @MainActor
  private func renderViewAsync<V: View>(
    _ root: V,
    context: ResolveContext,
    proposal: ProposedSize
  ) async -> FrameArtifacts {
    let renderer = self
    let draft = renderer.computeFrameHead(
      root,
      context: context,
      proposal: proposal,
      mode: .abortable
    )
    return await RuntimeRenderPipeline().renderAsync(
      head: draft,
      animationInjection: { draft in
        renderer.injectAnimations(
          into: draft,
          mode: .abortable
        )
      },
      latePreferenceReconciliation: { draft in
        await renderer.renderAsyncFrameTailLayoutStage(draft)
      },
      fusedFrameTail: { draft, layoutStage in
        await renderer.renderAsyncFusedFrameTail(
          draft: draft,
          layoutStage: layoutStage
        )
      },
      commit: { draft, tailOutput in
        let candidate = renderer.makeCompletedFrameCandidate(
          draft: draft,
          tailOutput: tailOutput,
          newestDesiredGeneration: draft.renderGeneration
        )
        return renderer.commitCompletedFrameCandidate(candidate)
      }
    )
  }

  /// Resolves `root` and prepares the shared frame head consumed by both the
  /// synchronous one-shot renderer and the abortable async renderer.
  ///
  /// `mode` selects execution-strategy-specific head work: `.abortable`
  /// captures the five-subsystem checkpoint bundle before each subsystem is
  /// mutated, while `.oneShot` skips the checkpoint cost. Worker-safe indexed
  /// child snapshotting happens after the animation-injection stage.
  @MainActor
  private func computeFrameHead<V: View>(
    _ root: V,
    context: ResolveContext,
    proposal: ProposedSize,
    mode: FrameHeadMode
  ) -> FrameHeadDraft {
    let clock = ContinuousClock()
    let renderGeneration = renderGenerationSequencer.next()

    var resolveContext = context
    let registrationDraft = FrameHeadRegistrationDraft()
    let graphDraft = ViewGraphFrameDraft(
      liveRegistrations: resolveContext.runtimeRegistrations,
      checkpoint: mode == .abortable ? viewGraph.makeCheckpoint() : nil
    )
    let animationDraft = animationController.makeFrameDraft()
    resolveContext = resolveContext.replacingRuntimeRegistrations(
      registrationDraft.draftRegistrations
    )
    resolveContext.imageAssetResolver = imageRepository.resolver()

    // Abortable heads checkpoint previous-frame selector state before preparing
    // current-frame resolve inputs. One-shot heads never abort, so skip.
    let frameStateCheckpoint: FrameResolveState.Checkpoint?
    switch mode {
    case .oneShot:
      frameStateCheckpoint = nil
    case .abortable:
      frameStateCheckpoint = frameState.makeCheckpoint()
    }
    let resolveInputs = frameState.prepareInputs(
      from: resolveContext,
      proposal: proposal
    )
    frameInputs.store(resolveInputs)
    resolveContext.frameInputs = frameInputs

    // The graph draft owns the viewGraph checkpoint captured before
    // `beginFrame`, for the same abort reason.
    viewGraph.beginFrame()
    let canUseSelectiveEvaluation = resolveInputs.usesSelectiveEvaluation
    if canUseSelectiveEvaluation {
      viewGraph.invalidateAndQueueDirty(resolveInputs.invalidatedIdentities)
    } else {
      viewGraph.invalidate(resolveInputs.invalidatedIdentities)
    }
    resolveContext.viewGraph = viewGraph
    let observationDraft = resolveContext.observationBridge?.makeDraft(
      attaching: viewGraph
    )
    let presentationPortalContext = resolveContext.replacingIdentity(
      with: presentationPortalIdentity(for: resolveContext.identity)
    )
    let hasExistingPresentationPortalRoot = viewGraph.containsNode(
      for: presentationPortalContext.identity
    )
    let presentationPortalDraft = presentationPortalState.makeDraft()
    let wrappedRoot = PresentationPortalRoot(
      content: root,
      portalState: presentationPortalDraft,
      contentRootIdentity: resolveContext.identity
    )
    viewGraph.setRootEvaluator(rootIdentity: presentationPortalContext.identity) {
      _ = resolver.resolve(wrappedRoot, in: presentationPortalContext)
    }
    viewGraph.setEvaluator(for: presentationPortalContext.identity) {
      _ = resolver.resolve(wrappedRoot, in: presentationPortalContext)
    }
    if !hasExistingPresentationPortalRoot
      || !canUseSelectiveEvaluation
      || !resolveInputs.invalidatedIdentities.isEmpty
    {
      viewGraph.queueDirty([presentationPortalContext.identity])
    }
    let (_, resolveDuration): (Void, Duration)
    animationDraft.controller.beginTransitionCollection()
    if canUseSelectiveEvaluation, !viewGraph.hasDirtyWork {
      // Nothing is dirty — skip evaluation entirely and reuse the existing
      // tree snapshot. The root evaluator and registrations are untouched.
      resolveDuration = .zero
    } else {
      let dirtyEvaluationPlan = viewGraph.selectiveDirtyEvaluationPlan()
      graphDraft.recordDirtyEvaluationPlan(dirtyEvaluationPlan)

      (_, resolveDuration) = measurePhase(clock: clock) {
        withAnimationDraftSinks(animationDraft) {
          viewGraph.evaluateDirtyNodes(
            using: dirtyEvaluationPlan
          )
        }
      }
    }
    animationDraft.controller.finishTransitionCollection()
    let resolved = wrapInContainerSafeArea(
      renderPipelineTree(from: viewGraph.snapshot()),
      context: resolveContext
    )

    let frameTailRetainedInput = frameTailRenderer.retainedInput(
      invalidatedIdentities: resolveInputs.invalidatedIdentities
    )
    let layoutPassContext = LayoutPassContext(
      retainedLayout: frameTailRetainedInput.retainedLayout,
      invalidatedIdentities: resolveInputs.invalidatedIdentities
    )
    let frameContext = FrameContext(
      environment: resolveInputs.environment,
      transaction: resolveInputs.transaction,
      invalidatedIdentities: resolveInputs.invalidatedIdentities
    )
    let frameTailInput = FrameTailInput(
      generation: renderGeneration,
      resolved: resolved,
      proposal: resolveInputs.proposal,
      rootIdentity: resolveContext.identity,
      retained: frameTailRetainedInput,
      layoutPassContext: layoutPassContext
    )

    let checkpoints: FrameHeadCheckpoints?
    switch mode {
    case .oneShot:
      checkpoints = nil
    case .abortable:
      // Force-unwraps are safe: every `.abortable` branch above assigned its
      // checkpoint non-nil.
      checkpoints = FrameHeadCheckpoints(
        frameState: frameStateCheckpoint!
      )
    }

    return FrameHeadDraft(
      clock: clock,
      renderGeneration: renderGeneration,
      graphDraft: graphDraft,
      registrationDraft: registrationDraft,
      presentationPortalDraft: presentationPortalDraft,
      observationDraft: observationDraft,
      animationDraft: animationDraft,
      checkpoints: checkpoints,
      resolveContext: resolveContext,
      graphRootIdentity: presentationPortalContext.identity,
      frameContext: frameContext,
      resolved: resolved,
      frameTailInput: frameTailInput,
      runtimeIssues: [],
      animationTimestamp: MonotonicInstant.now(),
      resolveDuration: resolveDuration
    )
  }

  @MainActor
  private func injectAnimations(
    into draft: FrameHeadDraft,
    mode: FrameHeadMode
  ) -> FrameHeadDraft {
    var draft = draft
    var resolved = draft.resolved
    let animationTimestamp = MonotonicInstant.now()
    AnimationInjectionStage(animationDraft: draft.animationDraft).apply(
      to: &resolved,
      transaction: draft.frameContext.transaction,
      timestamp: animationTimestamp
    )

    var frameTailInput = draft.frameTailInput
    frameTailInput.resolved = resolved
    // Worker-safe snapshotting of lazy indexed child sources is only needed
    // when the frame tail runs off-main. One-shot renders run the tail
    // synchronously on the main actor, so they skip it.
    if mode == .abortable,
      frameTailRenderer.needsIndexedChildSourceWorkerSnapshot(frameTailInput)
    {
      resolved = indexedChildSourceWorkerSnapshot(of: resolved)
      frameTailInput.resolved = resolved
    }

    draft.resolved = resolved
    draft.frameTailInput = frameTailInput
    draft.animationTimestamp = animationTimestamp
    return draft
  }

  @MainActor
  private func prepareFrameHead<V: View>(
    _ root: V,
    context: ResolveContext,
    proposal: ProposedSize
  ) -> FrameHeadDraft {
    let draft = computeFrameHead(
      root,
      context: context,
      proposal: proposal,
      mode: .abortable
    )
    return injectAnimations(
      into: draft,
      mode: .abortable
    )
  }

  @MainActor
  private func renderFrameTailAsync(
    _ draft: FrameHeadDraft
  ) async -> AsyncFrameTailDraftOutput {
    guard let layoutStage = await renderAsyncFrameTailLayoutStage(draft) else {
      preconditionFailure("Non-cancellable frame tail unexpectedly cancelled.")
    }
    return await renderAsyncFusedFrameTail(
      draft: draft,
      layoutStage: layoutStage
    )
  }

  @MainActor
  private func renderAsyncFrameTailLayoutStage(
    _ draft: FrameHeadDraft
  ) async -> AsyncFrameTailLayoutStageOutput? {
    if frameTailRenderer.canOffloadLayout(draft.frameTailInput) {
      let layoutPass = await renderFrameTailLayoutAsync(
        draft.frameTailInput,
        clock: draft.clock,
        cancellationToken: nil
      )
      guard let layout = layoutPass.layout else {
        return nil
      }
      return AsyncFrameTailLayoutStageOutput(
        frameTailInput: draft.frameTailInput,
        layout: layout,
        resolved: draft.resolved,
        runtimeIssues: layoutRuntimeIssues(input: draft.frameTailInput, resolved: draft.resolved),
        suspensionDuration: layoutPass.suspensionDuration
      )
    }

    let layoutResult = await renderLayoutResolvingLatePreferencesAsync(
      draft.frameTailInput,
      clock: draft.clock,
      cancellationToken: nil
    )
    guard let reconciledLayout = layoutResult.layout else {
      return nil
    }
    return AsyncFrameTailLayoutStageOutput(
      frameTailInput: reconciledLayout.input,
      layout: reconciledLayout.layout,
      resolved: reconciledLayout.resolved,
      runtimeIssues: reconciledLayout.runtimeIssues,
      suspensionDuration: layoutResult.suspensionDuration
    )
  }

  @MainActor
  private func renderAsyncFusedFrameTail(
    draft: FrameHeadDraft,
    layoutStage: AsyncFrameTailLayoutStageOutput
  ) async -> AsyncFrameTailDraftOutput {
    let layout = layoutStage.layout
    let placed = layout.baselinePlaced
    let animationController = draft.animationDraft.controller
    animationController.capturePlacedTree(layout.baselinePlaced)
    let animationOverlaySnapshot = animationController.placedAnimationOverlaySnapshot(
      for: placed,
      at: draft.animationTimestamp
    )
    let suspensionHooks = frameTailRenderer.renderSuspensionHooksSnapshot()
    let rasterSuspensionStart = draft.clock?.now
    suspensionHooks?.onBegin?()
    let tail = await frameTailRenderer.renderRasterAsync(
      layoutStage.frameTailInput,
      layout: layout,
      placed: placed,
      animationOverlaySnapshot: animationOverlaySnapshot,
      clock: draft.clock
    )
    suspensionHooks?.onEnd?()
    let rasterSuspensionDuration =
      if let rasterSuspensionStart, let clock = draft.clock {
        rasterSuspensionStart.duration(to: clock.now)
      } else {
        Duration.zero
      }

    return AsyncFrameTailDraftOutput(
      frameTailInput: layoutStage.frameTailInput,
      layout: layout,
      tail: tail,
      resolved: layoutStage.resolved,
      runtimeIssues: layoutStage.runtimeIssues,
      renderSuspensionDuration: layoutStage.suspensionDuration + rasterSuspensionDuration
    )
  }

  @MainActor
  private func renderCancellableFrameTailLayoutStage(
    _ draft: FrameHeadDraft,
    shouldCancelQueued: @escaping @MainActor @Sendable () async -> Bool
  ) async -> CancellableFrameTailLayoutStageResult {
    let cancellationToken = FrameTailJobCancellationToken()
    let layoutTask = Task { @MainActor in
      await renderLayoutResolvingLatePreferencesAsync(
        draft.frameTailInput,
        clock: draft.clock,
        cancellationToken: cancellationToken
      )
    }

    while cancellationToken.currentState == .queued {
      if await shouldCancelQueued(), cancellationToken.cancelBeforeStart() {
        layoutTask.cancel()
        return .cancelledBeforeStart
      }
      try? await Task.sleep(for: .milliseconds(1))
    }

    let layoutResult = await layoutTask.value
    guard let reconciledLayout = layoutResult.layout else {
      return .cancelledBeforeStart
    }
    let layoutStage = AsyncFrameTailLayoutStageOutput(
      frameTailInput: reconciledLayout.input,
      layout: reconciledLayout.layout,
      resolved: reconciledLayout.resolved,
      runtimeIssues: reconciledLayout.runtimeIssues,
      suspensionDuration: layoutResult.suspensionDuration
    )
    return .output(
      CancellableFrameTailLayoutStageOutput(
        layoutStage: layoutStage,
        cancellationToken: cancellationToken
      )
    )
  }

  @MainActor
  private func renderCancellableFusedFrameTail(
    draft: FrameHeadDraft,
    layoutStage: CancellableFrameTailLayoutStageOutput
  ) async -> AsyncFrameTailDraftOutput {
    let tailOutput = await renderAsyncFusedFrameTail(
      draft: draft,
      layoutStage: layoutStage.layoutStage
    )
    layoutStage.cancellationToken.markCompleted()
    return tailOutput
  }

  @MainActor
  private func renderLayoutResolvingLatePreferencesAsync(
    _ initialInput: FrameTailInput,
    clock: ContinuousClock?,
    cancellationToken: FrameTailJobCancellationToken?
  ) async -> AsyncLatePreferenceReconciliationOutput {
    await LatePreferenceReconciliationStage(
      policy: Self.latePreferenceReconciliationPolicy
    ).runAsync(initialInput: initialInput) { input in
      await renderFrameTailLayoutAsync(
        input,
        clock: clock,
        cancellationToken: cancellationToken
      )
    }
  }

  @MainActor
  private func renderFrameTailLayoutAsync(
    _ input: FrameTailInput,
    clock: ContinuousClock?,
    cancellationToken: FrameTailJobCancellationToken?
  ) async -> AsyncFrameTailLayoutPass {
    let suspensionHooks = frameTailRenderer.renderSuspensionHooksSnapshot()
    let layoutSuspends = frameTailRenderer.canOffloadLayout(input)
    let layoutSuspensionStart = layoutSuspends ? clock?.now : nil
    if layoutSuspends {
      suspensionHooks?.onBegin?()
    }
    let layout = await frameTailRenderer.renderLayoutAsync(
      input,
      clock: clock,
      cancellationToken: cancellationToken
    )
    if layoutSuspends {
      suspensionHooks?.onEnd?()
    }
    let layoutSuspensionDuration =
      if let layoutSuspensionStart, let clock {
        layoutSuspensionStart.duration(to: clock.now)
      } else {
        Duration.zero
      }
    return AsyncFrameTailLayoutPass(
      layout: layout,
      suspensionDuration: layoutSuspensionDuration
    )
  }

  @MainActor
  private func makeCompletedFrameCandidate(
    draft: FrameHeadDraft,
    tailOutput: AsyncFrameTailDraftOutput,
    newestDesiredGeneration: RenderGeneration,
    completedFramePolicy: CompletedFramePolicy? = nil,
    additionalBlockers:
      @MainActor @Sendable (FrameArtifacts) -> Set<FrameDropEligibility.Blocker> = { _ in [] }
  ) -> CompletedFrameCandidate {
    let resolved = tailOutput.resolved
    let workerTimings = completedFrameWorkerTimings(
      draft: draft,
      tailOutput: tailOutput
    )
    let (commit, commitDuration) = previewCompletedFrameCommit(
      draft: draft,
      tailOutput: tailOutput,
      resolved: resolved
    )
    let artifacts = makeCompletedFrameArtifacts(
      draft: draft,
      tailOutput: tailOutput,
      resolved: resolved,
      commit: commit,
      commitDuration: commitDuration,
      workerTimings: workerTimings
    )
    let eligibility = completedFrameEligibility(
      artifacts: artifacts,
      draft: draft,
      additionalBlockers: additionalBlockers(artifacts)
    )
    return CompletedFrameCandidate(
      draft: draft,
      tailOutput: tailOutput,
      resolved: resolved,
      workerTimings: workerTimings,
      previewArtifacts: artifacts,
      eligibility: eligibility,
      newestDesiredGeneration: newestDesiredGeneration,
      dropDecision: (completedFramePolicy ?? .dropCompletedVisualOnly).decide(
        candidateGeneration: draft.renderGeneration,
        newestDesiredGeneration: newestDesiredGeneration,
        eligibility: eligibility
      )
    )
  }

  @MainActor
  private func commitCompletedFrameCandidate(
    _ candidate: CompletedFrameCandidate
  ) -> FrameArtifacts {
    let layout = candidate.tailOutput.layout
    let tail = candidate.tailOutput.tail
    var runtimeRegistrationDiagnostics = RuntimeRegistrationDiagnostics()
    let (commit, commitDuration) = measurePhase(clock: candidate.draft.clock) {
      let lifecycleEvents = viewGraph.finalizeFrame(
        rootIdentity: candidate.draft.graphRootIdentity,
        resolved: candidate.resolved,
        placed: tail.placed
      )
      runtimeRegistrationDiagnostics = candidate.draft.graphDraft.commitRuntimeRegistrations(
        from: viewGraph
      )
      commitFrameHeadDraftEffects(candidate.draft)
      return commitPlanner.plan(
        resolved: candidate.resolved,
        placed: tail.placed,
        semantics: tail.semantics,
        transaction: candidate.draft.frameContext.transaction,
        lifecycleEvents: lifecycleEvents
      )
    }
    candidate.draft.animationDraft.commit()
    applyWorkerCustomLayoutCacheUpdates(layout.workerCustomLayoutCacheUpdates)
    frameTailRenderer.pruneMeasurementCache(
      keeping: viewGraph.liveIdentitySnapshot()
    )
    let artifacts = makeCompletedFrameArtifacts(
      draft: candidate.draft,
      tailOutput: candidate.tailOutput,
      resolved: candidate.resolved,
      commit: commit,
      commitDuration: commitDuration,
      workerTimings: candidate.workerTimings,
      runtimeRegistrationDiagnostics: runtimeRegistrationDiagnostics
    )

    candidate.draft.resolveContext.localScrollPositionRegistry?.updateGeometry(
      scrollRoutes: artifacts.semanticSnapshot.scrollRoutes,
      scrollTargets: artifacts.semanticSnapshot.scrollTargets
    )
    candidate.draft.graphDraft.updateCommittedScrollGeometry(
      scrollRoutes: artifacts.semanticSnapshot.scrollRoutes,
      scrollTargets: artifacts.semanticSnapshot.scrollTargets
    )
    frameTailRenderer.storeCommittedFrame(
      artifacts,
      baselinePlacedTree: tail.baselinePlaced
    )
    storeCommittedPresentationPortalState()
    return artifacts
  }

  @MainActor
  private func storeCommittedPresentationPortalState() {
    committedPresentationDismissStack.store(presentationPortalState.dismissStack())
  }

  @MainActor
  private func commitFrameHeadDraftEffects(
    _ draft: FrameHeadDraft
  ) {
    draft.observationDraft?.commit()
    draft.presentationPortalDraft.commit()
  }

  @MainActor
  private func previewCompletedFrameCommit(
    draft: FrameHeadDraft,
    tailOutput: AsyncFrameTailDraftOutput,
    resolved: ResolvedNode
  ) -> (commit: CommitPlan, duration: Duration) {
    let tail = tailOutput.tail
    let checkpoint = viewGraph.makeCheckpoint()
    defer {
      viewGraph.restoreCheckpoint(checkpoint)
    }

    return measurePhase(clock: draft.clock) {
      let lifecycleEvents = viewGraph.finalizeFrame(
        rootIdentity: draft.graphRootIdentity,
        resolved: resolved,
        placed: tail.placed
      )
      return commitPlanner.plan(
        resolved: resolved,
        placed: tail.placed,
        semantics: tail.semantics,
        transaction: draft.frameContext.transaction,
        lifecycleEvents: lifecycleEvents
      )
    }
  }

  private func completedFrameWorkerTimings(
    draft: FrameHeadDraft,
    tailOutput: AsyncFrameTailDraftOutput
  ) -> FrameWorkerTimings? {
    var workerTimings = tailOutput.tail.diagnostics.workerTimings
    if var timings = workerTimings,
      let clock = draft.clock,
      let workerCompletedAt = tailOutput.tail.workerCompletedAt
    {
      timings.completionToMainCommit = workerCompletedAt.duration(to: clock.now)
      workerTimings = timings
    }
    return workerTimings
  }

  private func makeCompletedFrameArtifacts(
    draft: FrameHeadDraft,
    tailOutput: AsyncFrameTailDraftOutput,
    resolved: ResolvedNode,
    commit: CommitPlan,
    commitDuration: Duration,
    workerTimings: FrameWorkerTimings?,
    runtimeRegistrationDiagnostics: RuntimeRegistrationDiagnostics = .init()
  ) -> FrameArtifacts {
    let layout = tailOutput.layout
    let tail = tailOutput.tail
    let dropEligibilityBlockers = frameTailCommitDropBlockers(
      workerCustomLayoutCacheUpdates: layout.workerCustomLayoutCacheUpdates
    )
    let phaseTimings = FramePhaseTimings(
      resolve: draft.resolveDuration,
      measure: tail.diagnostics.measureDuration,
      place: tail.diagnostics.placeDuration,
      semantics: tail.diagnostics.semanticsDuration,
      draw: tail.diagnostics.drawDuration,
      raster: tail.diagnostics.rasterDuration,
      commit: commitDuration
    )
    let mainActorTimings = FrameMainActorTimings(
      blocked: draft.resolveDuration
        + (layout.ranOffMain
          ? .zero : tail.diagnostics.measureDuration + tail.diagnostics.placeDuration)
        + commitDuration,
      suspended: tailOutput.renderSuspensionDuration
    )
    var diagnostics = FrameDiagnostics.summarize(
      resolved: resolved,
      measured: tail.measured,
      placed: tail.placed,
      semantics: tail.semantics,
      draw: tail.draw,
      invalidatedIdentities: draft.frameContext.invalidatedIdentities,
      resolveWork: draft.resolveContext.resolveWorkTracker?.snapshot,
      layoutWork: tail.diagnostics.layoutWork,
      presentationDamage: tail.presentationDamage,
      presentationSurfaceWidth: tail.raster.size.width,
      phaseTimings: phaseTimings,
      renderGenerations: .init(
        render: draft.renderGeneration,
        layoutInput: tailOutput.frameTailInput.generation,
        layoutOutput: layout.generation,
        rasterInput: tailOutput.frameTailInput.generation,
        rasterOutput: tail.generation
      ),
      workerTimings: workerTimings,
      mainActorTimings: mainActorTimings,
      measurementCache: tail.diagnostics.measurementCache,
      runtimeIssues: tailOutput.runtimeIssues,
      dropEligibilityBlockers: dropEligibilityBlockers
    )
    diagnostics.runtime.registrations = runtimeRegistrationDiagnostics
    let artifacts = FrameArtifacts(
      resolvedTree: resolved,
      measuredTree: tail.measured,
      placedTree: tail.placed,
      semanticSnapshot: tail.semantics,
      drawTree: tail.draw,
      rasterSurface: tail.raster,
      presentationDamage: tail.presentationDamage,
      drawnIdentities: tail.drawnIdentities,
      commitPlan: commit,
      diagnostics: diagnostics
    )

    return artifacts
  }

  @MainActor
  private func completedFrameEligibility(
    artifacts: FrameArtifacts,
    draft: FrameHeadDraft,
    additionalBlockers: Set<FrameDropEligibility.Blocker>
  ) -> FrameDropEligibility {
    var classificationArtifacts = artifacts
    classificationArtifacts.diagnostics.drop.eligibilityBlockers.subtract([
      .retainedLayoutBaseline,
      .retainedRasterBaseline,
    ])
    return FrameDropEligibility.classify(
      FrameDropEligibility.Candidate(
        artifacts: classificationArtifacts,
        additionalBlockers: additionalBlockers.union(
          frameHeadDropBlockers(draft)
        ),
        hasCompleteBarrierSignals: true
      ))
  }

  @MainActor
  private func frameHeadDropBlockers(
    _ draft: FrameHeadDraft
  ) -> Set<FrameDropEligibility.Blocker> {
    draft.registrationDraft.draftDropEligibilityBlockers()
      .union(draft.animationDraft.frameDropEligibilityBlockers)
  }

  @MainActor
  private func discardCompletedFrameCandidate(
    _ candidate: CompletedFrameCandidate,
    reconciliation: SkippedFrameReconciliation
  ) {
    precondition(reconciliation.isAvailableToRuntimePolicy)
    abortPreparedFrameHead(candidate.draft)
  }

  @MainActor
  private func applyWorkerCustomLayoutCacheUpdates(
    _ updates: [WorkerCustomLayoutCacheUpdate]
  ) {
    for update in updates {
      update.apply()
    }
  }

  private func frameTailCommitDropBlockers(
    workerCustomLayoutCacheUpdates: [WorkerCustomLayoutCacheUpdate]
  ) -> Set<FrameDropEligibility.Blocker> {
    var blockers: Set<FrameDropEligibility.Blocker> = [
      .retainedLayoutBaseline,
      .retainedRasterBaseline,
    ]
    if !workerCustomLayoutCacheUpdates.isEmpty {
      blockers.insert(.workerCustomLayoutCacheUpdate)
    }
    return blockers
  }

  @MainActor
  private func indexedChildSourceWorkerSnapshot(
    of node: ResolvedNode
  ) -> ResolvedNode {
    var node = node
    node.children = node.children.map(indexedChildSourceWorkerSnapshot(of:))

    guard let source = node.indexedChildSource,
      !source.canRunOnWorker
    else {
      return node
    }

    let children = (0..<source.count).map { index in
      indexedChildSourceWorkerSnapshot(of: source.child(at: index))
    }
    node.indexedChildSource = IndexedChildSourceSnapshot(
      identityRoot: source.identityRoot,
      measurementSignature: source.measurementSignature,
      children: children
    )
    return node
  }

  private func measurePhase<Value>(
    clock: ContinuousClock?,
    _ operation: () -> Value
  ) -> (Value, Duration) {
    guard let clock else {
      return (operation(), .zero)
    }
    let start = clock.now
    let value = operation()
    return (value, start.duration(to: clock.now))
  }

  private func wrapInContainerSafeArea(
    _ resolved: ResolvedNode,
    context: ResolveContext
  ) -> ResolvedNode {
    let safeAreaInsets = context.environmentValues.safeAreaInsets
    guard !safeAreaInsets.isZero else {
      return resolved
    }

    return ResolvedNode(
      identity: resolved.identity.child(.named("ContainerSafeArea")),
      kind: .view("ContainerSafeArea"),
      children: [resolved],
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      layoutBehavior: .padding(safeAreaInsets)
    )
  }

  private func renderPipelineTree(
    from graphRoot: ResolvedNode
  ) -> ResolvedNode {
    guard graphRoot.kind == .view("PresentationPortalRoot"),
      graphRoot.children.count == 1,
      let contentRoot = graphRoot.children.first
    else {
      return graphRoot
    }

    return contentRoot
  }

  /// Enables selective dirty-frontier evaluation for subsequent frames.
  /// Call after the first full render has established the tree and
  /// evaluator closures.
  @MainActor
  package func enableSelectiveEvaluation() {
    frameState.selectiveEvaluationEnabled = true
  }

  /// Forces the next render to use root evaluation regardless of whether
  /// selective evaluation would otherwise apply.
  @MainActor
  package func forceRootEvaluation() {
    frameState.forceRootEvaluation = true
  }

  @MainActor
  package func liveIdentitySnapshot() -> Set<Identity> {
    viewGraph.liveIdentitySnapshot()
  }

  @MainActor
  package func setFrameTailRenderHooks(
    _ hooks: FrameTailRenderHooks?
  ) {
    frameTailRenderer.setRenderHooks(hooks)
  }

  @MainActor
  package func setFrameRenderSuspensionHooks(
    _ hooks: FrameRenderSuspensionHooks?
  ) {
    frameTailRenderer.setRenderSuspensionHooks(hooks)
  }
}
