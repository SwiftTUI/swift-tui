@_exported import EmbeddedFonts
@_exported import SwiftTUICore
@_exported import SwiftTUIViews

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
  let viewGraph: ViewGraph
  private let frameState: FrameResolveState
  private let frameInputs: FrameResolveInputBox
  private let presentationPortalState: PresentationPortalState
  private let committedPresentationDismissStack: CommittedPresentationDismissStack
  private let debugObservationBridgeTracker: DebugObservationBridgeTracker
  private let animationController: AnimationController
  private let renderGenerationSequencer: RenderGenerationSequencer

  let frameTailRenderer: FrameTailRenderer
  private var frameTailCoordinator: DefaultRendererFrameTailCoordinator {
    .init(
      frameTailRenderer: frameTailRenderer,
      latePreferenceReconciliationPolicy: Self.latePreferenceReconciliationPolicy
    )
  }
  @MainActor
  private var frameHeadCoordinator: DefaultRendererFrameHeadCoordinator {
    let observationBridgeTracker = debugObservationBridgeTracker
    return .init(
      resolver: resolver,
      imageRepository: imageRepository,
      viewGraph: viewGraph,
      frameState: frameState,
      frameInputs: frameInputs,
      presentationPortalState: presentationPortalState,
      animationController: animationController,
      renderGenerationSequencer: renderGenerationSequencer,
      frameTailRenderer: frameTailRenderer,
      storeObservationBridge: { bridge in
        observationBridgeTracker.store(bridge)
      },
      renderPipelineContentTree: renderPipelineTree(from:)
    )
  }

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
    debugObservationBridgeTracker = .init()
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
  /// `ViewGraph.registrationAliasDiagnostics`, to let tests measure the alias layer's
  /// actual workload against the hypothesis that divergences come from a
  /// small, enumerable set of view patterns.
  @MainActor
  package var debugRegistrationAliasDiagnostics: RegistrationAliasDiagnostics {
    viewGraph.registrationAliasDiagnostics
  }

  @MainActor
  package func debugRuntimeSubsystemSnapshot() -> RuntimeSubsystemSnapshot {
    let presentationEntries = presentationPortalState.overlayEntries().map {
      RuntimeSubsystemSnapshot.PresentationPortalSnapshot.EntrySnapshot(
        id: $0.id,
        ordering: $0.ordering,
        kindName: $0.kindName,
        modalPolicy: $0.modalPolicy,
        acceptsEscape: $0.acceptsEscape,
        hasDismissAction: $0.dismiss != nil
      )
    }
    let observationBridgeSnapshot = debugObservationBridgeTracker.bridge.map { bridge in
      let checkpoint = bridge.makeCheckpoint()
      return RuntimeSubsystemSnapshot.ObservationBridgeSnapshot(
        currentPass: checkpoint.currentPass,
        observedPasses: checkpoint.observedPasses,
        invalidatorID: checkpoint.invalidator.map(ObjectIdentifier.init),
        viewGraphID: checkpoint.viewGraph.map(ObjectIdentifier.init)
      )
    }
    return RuntimeSubsystemSnapshot(
      viewGraph: viewGraph.debugTotalStateSnapshot(),
      frameState: frameState.debugStateSnapshot(),
      frameInputs: frameInputs.debugStateSnapshot(),
      presentationPortalState: .init(overlayEntries: presentationEntries),
      observationBridge: observationBridgeSnapshot,
      animationController: animationController.debugStateSnapshot()
    )
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
    draft.transaction.discard()
  }

  @MainActor
  package func renderPreparedFrameTailForCancellationTesting(
    _ draft: FrameHeadDraft
  ) async {
    _ = await frameTailCoordinator.renderFrameTailDraft(draft)
  }

  @MainActor
  package func discardPreparedFrameTailForReconciliationTesting(
    _ draft: FrameHeadDraft,
    decision: CompletedFrameDropDecision
  ) async -> Bool {
    guard decision.canSkipCompletedFrame else {
      return false
    }

    let tailOutput = await frameTailCoordinator.renderFrameTailDraft(draft)
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
    let tailOutput = await frameTailCoordinator.renderFrameTailDraft(draft)
    let candidate = makeCompletedFrameCandidate(
      draft: draft,
      tailOutput: tailOutput,
      newestDesiredGeneration: draft.renderGeneration
    )
    return candidate.dropDecision
  }

  @MainActor
  package func commitCompletedFrameCandidateForTesting(
    _ draft: FrameHeadDraft
  ) async -> CompletedFrameCandidateCommitPlanComparison {
    let tailOutput = await frameTailCoordinator.renderFrameTailDraft(draft)
    let candidate = makeCompletedFrameCandidate(
      draft: draft,
      tailOutput: tailOutput,
      newestDesiredGeneration: draft.renderGeneration
    )
    let artifacts = commitCompletedFrameCandidate(candidate)
    return CompletedFrameCandidateCommitPlanComparison(
      previewCommit: candidate.previewArtifacts.commitPlan,
      committedCommit: artifacts.commitPlan,
      committedArtifacts: artifacts
    )
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
    awaitQueuedCancellationSignal: @escaping @MainActor @Sendable () async -> Void = {},
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
      handlers: CancellableRenderStageHandlers(
        animationInjection: { draft in
          renderer.injectAnimations(
            into: draft,
            mode: .abortable
          )
        },
        latePreferenceReconciliation: { draft in
          switch await renderer.frameTailCoordinator.renderFrameTailLayoutStage(
            draft,
            cancellation: FrameTailCancellationStrategy(
              awaitQueuedCancellationSignal: awaitQueuedCancellationSignal,
              shouldCancelQueued: shouldCancelQueued
            )
          ) {
          case .cancelledBeforeStart:
            return .cancelledBeforeStart
          case .output(let layoutStage, let cancellationToken):
            guard let cancellationToken else {
              preconditionFailure("Cancellable layout stage completed without a token.")
            }
            return .output(
              CancellableFrameTailLayoutStageOutput(
                layoutStage: layoutStage,
                cancellationToken: cancellationToken
              )
            )
          }
        },
        fusedFrameTail: { draft, layoutStage in
          await renderer.frameTailCoordinator.renderFrameTailRasterStage(
            draft: draft,
            layoutStage: layoutStage.layoutStage,
            completionToken: layoutStage.cancellationToken
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
          switch renderer.resolveCompletedFrameCandidate(
            draft: draft,
            tailOutput: tailOutput,
            newestDesiredGeneration: newestGeneration,
            completedFramePolicy: completedFramePolicy,
            additionalBlockers: completedFrameAdditionalBlockers
          ) {
          case .dropped(let runtimeIssues, let dropDecision):
            return CancellableRenderOutcome(
              artifacts: nil,
              runtimeIssues: runtimeIssues,
              renderGeneration: draft.renderGeneration,
              newestDesiredGeneration: newestGeneration,
              tailJobState: .droppedCompleted,
              tailCancelReason: nil,
              completedFrameDropDecision: dropDecision
            )
          case .committed(let artifacts, let dropDecision):
            return CancellableRenderOutcome(
              artifacts: artifacts,
              runtimeIssues: artifacts.diagnostics.runtime.issues,
              renderGeneration: draft.renderGeneration,
              newestDesiredGeneration: newestGeneration,
              tailJobState: .completed,
              tailCancelReason: nil,
              completedFrameDropDecision: dropDecision
            )
          }
        }
      )
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
      handlers: OneShotRenderStageHandlers(
        animationInjection: { draft in
          renderer.injectAnimations(
            into: draft,
            mode: .oneShot
          )
        },
        latePreferenceReconciliation: { input, clock in
          renderer.frameTailCoordinator.renderLayoutResolvingLatePreferences(
            input,
            clock: clock
          )
        },
        fusedFrameTail: { draft, reconciledTailLayout in
          renderer.frameTailCoordinator.renderFusedFrameTail(
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
    let workerTimings = CommittedFrameArtifactBuilder.workerTimings(
      draft: draft,
      tail: tail
    )
    let effects = commitFrameEffects(
      draft: draft,
      resolved: resolved,
      placed: tail.placed,
      semantics: tail.semantics,
      workerCustomLayoutCacheUpdates: layout.workerCustomLayoutCacheUpdates
    )
    let artifacts = CommittedFrameArtifactBuilder.makeOneShotArtifacts(
      draft: draft,
      reconciledTailLayout: reconciledTailLayout,
      tail: tail,
      commit: effects.commitPlan,
      commitDuration: effects.commitDuration,
      workerTimings: workerTimings,
      runtimeRegistrationDiagnostics: effects.runtimeRegistrationDiagnostics
    )
    publishCommittedFrame(
      artifacts,
      draft: draft,
      baselinePlacedTree: tail.baselinePlaced
    )
    return artifacts
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
      handlers: AsyncRenderStageHandlers(
        animationInjection: { draft in
          renderer.injectAnimations(
            into: draft,
            mode: .abortable
          )
        },
        latePreferenceReconciliation: { draft in
          switch await renderer.frameTailCoordinator.renderFrameTailLayoutStage(draft) {
          case .cancelledBeforeStart:
            return nil
          case .output(let layoutStage, _):
            return layoutStage
          }
        },
        fusedFrameTail: { draft, layoutStage in
          await renderer.frameTailCoordinator.renderFrameTailRasterStage(
            draft: draft,
            layoutStage: layoutStage
          )
        },
        commit: { draft, tailOutput in
          switch renderer.resolveCompletedFrameCandidate(
            draft: draft,
            tailOutput: tailOutput,
            newestDesiredGeneration: draft.renderGeneration
          ) {
          case .committed(let artifacts, _):
            return artifacts
          case .dropped:
            preconditionFailure("Non-cancellable frame unexpectedly dropped.")
          }
        }
      )
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
    frameHeadCoordinator.computeFrameHead(
      root,
      context: context,
      proposal: proposal,
      mode: mode
    )
  }

  @MainActor
  private func injectAnimations(
    into draft: FrameHeadDraft,
    mode: FrameHeadMode
  ) -> FrameHeadDraft {
    frameHeadCoordinator.injectAnimations(
      into: draft,
      mode: mode
    )
  }

  @MainActor
  private func prepareFrameHead<V: View>(
    _ root: V,
    context: ResolveContext,
    proposal: ProposedSize
  ) -> FrameHeadDraft {
    frameHeadCoordinator.prepareFrameHead(
      root,
      context: context,
      proposal: proposal
    )
  }

  @MainActor
  func storeCommittedPresentationPortalState() {
    committedPresentationDismissStack.store(presentationPortalState.dismissStack())
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
