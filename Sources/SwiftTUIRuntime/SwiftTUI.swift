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

@MainActor
private final class DebugObservationBridgeTracker {
  weak var bridge: ObservationBridge?

  func store(_ bridge: ObservationBridge?) {
    self.bridge = bridge
  }
}

package struct RuntimeSubsystemSnapshot: Equatable {
  package struct PresentationPortalSnapshot: Equatable {
    package struct EntrySnapshot: Equatable {
      package var id: String
      package var ordering: PortalOrdering
      package var kindName: String
      package var modalPolicy: PortalModalPolicy
      package var acceptsEscape: Bool
      package var hasDismissAction: Bool
    }

    package var overlayEntries: [EntrySnapshot]
  }

  package struct ObservationBridgeSnapshot: Equatable {
    package var currentPass: UInt64
    package var observedPasses: [Identity: UInt64]
    package var invalidatorID: ObjectIdentifier?
    package var viewGraphID: ObjectIdentifier?
  }

  package var viewGraph: ViewGraph.DebugTotalStateSnapshot
  package var frameState: FrameResolveState.DebugStateSnapshot
  package var frameInputs: FrameResolveInputBox.DebugStateSnapshot
  package var presentationPortalState: PresentationPortalSnapshot
  package var observationBridge: ObservationBridgeSnapshot?
  package var animationController: AnimationController.DebugStateSnapshot
}

private struct FrameTailCancellationStrategy {
  var awaitQueuedCancellationSignal: @MainActor @Sendable () async -> Void
  var shouldCancelQueued: @MainActor @Sendable () async -> Bool
}

private enum FrameTailLayoutStageResult {
  case output(AsyncFrameTailLayoutStageOutput, cancellationToken: FrameTailJobCancellationToken?)
  case cancelledBeforeStart
}

private enum CompletedFrameCandidateResolution {
  case committed(FrameArtifacts, CompletedFrameDropDecision)
  case dropped(runtimeIssues: [RuntimeIssue], dropDecision: CompletedFrameDropDecision)
}

private struct CommittedFrameEffects {
  var commitPlan: CommitPlan
  var commitDuration: Duration
  var runtimeRegistrationDiagnostics: RuntimeRegistrationDiagnostics
}

package struct CompletedFrameCandidateCommitPlanComparison {
  package var previewCommit: CommitPlan
  package var committedCommit: CommitPlan
  package var committedArtifacts: FrameArtifacts
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
  private let debugObservationBridgeTracker: DebugObservationBridgeTracker
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
    _ = await renderFrameTailDraft(draft)
  }

  @MainActor
  package func discardPreparedFrameTailForReconciliationTesting(
    _ draft: FrameHeadDraft,
    decision: CompletedFrameDropDecision
  ) async -> Bool {
    guard decision.canSkipCompletedFrame else {
      return false
    }

    let tailOutput = await renderFrameTailDraft(draft)
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
    let tailOutput = await renderFrameTailDraft(draft)
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
    let tailOutput = await renderFrameTailDraft(draft)
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
          switch await renderer.renderFrameTailLayoutStage(
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
          await renderer.renderFrameTailRasterStage(
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
    )
  }

  /// Shared fused-frame-tail head: captures the baseline placed tree for the
  /// animation controller and snapshots any pending placed-level animation
  /// overlays.
  ///
  /// Both the synchronous (`renderFusedFrameTail`) and asynchronous
  /// (`renderFrameTailRasterStage`) tail strategies run exactly this work before
  /// they diverge — the sync path calls `renderRaster`, the async path calls
  /// `renderRasterAsync`. Extracting it keeps the two strategies from
  /// duplicating the placed-tree capture / overlay-snapshot orchestration
  /// (F11).
  ///
  /// Capture the BASELINE placed tree (pre-overlay) for two things:
  /// 1. The animation controller's removal-snapshot lookup on the next frame
  ///    (`capturePlacedTree`).
  /// 2. The retained-layout store, so future tick frames reuse the canonical
  ///    layout and not an animation-decorated tree.
  ///
  /// If we used the post-overlay placed tree, subsequent ticks would hit
  /// retainedPlacement and return the cached tree including the stale transient
  /// overlay — then overlay snapshot application would inject another overlay
  /// on top, growing the tree each tick and leaving ghosted artefacts visible
  /// after the animation completes.
  @MainActor
  private func prepareAnimationOverlaySnapshot(
    draft: FrameHeadDraft,
    layout: FrameTailLayoutOutput
  ) -> (placed: PlacedNode, overlay: PlacedAnimationOverlaySnapshot) {
    let placed = layout.baselinePlaced
    let animationController = draft.animationDraft.controller
    animationController.capturePlacedTree(layout.baselinePlaced)
    // Snapshot any pending placed-level animation overlays. The snapshot
    // advances controller-owned animation state on the main actor, then the
    // frame-tail worker applies the value data before semantics/draw/raster.
    let animationOverlaySnapshot = animationController.placedAnimationOverlaySnapshot(
      for: placed,
      at: draft.animationTimestamp
    )
    return (placed, animationOverlaySnapshot)
  }

  @MainActor
  private func renderFusedFrameTail(
    draft: FrameHeadDraft,
    reconciledTailLayout: ReconciledFrameTailLayout
  ) -> FrameTailOutput {
    let layout = reconciledTailLayout.layout
    let (placed, animationOverlaySnapshot) = prepareAnimationOverlaySnapshot(
      draft: draft,
      layout: layout
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
      handlers: AsyncRenderStageHandlers(
        animationInjection: { draft in
          renderer.injectAnimations(
            into: draft,
            mode: .abortable
          )
        },
        latePreferenceReconciliation: { draft in
          switch await renderer.renderFrameTailLayoutStage(draft) {
          case .cancelledBeforeStart:
            return nil
          case .output(let layoutStage, _):
            return layoutStage
          }
        },
        fusedFrameTail: { draft, layoutStage in
          await renderer.renderFrameTailRasterStage(
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
    let clock = ContinuousClock()
    let renderGeneration = renderGenerationSequencer.next()

    var resolveContext = context
    debugObservationBridgeTracker.store(resolveContext.observationBridge)
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
    let frameInputsCheckpoint: FrameResolveInputBox.Checkpoint?
    switch mode {
    case .oneShot:
      frameStateCheckpoint = nil
      frameInputsCheckpoint = nil
    case .abortable:
      frameStateCheckpoint = frameState.makeCheckpoint()
      frameInputsCheckpoint = frameInputs.makeCheckpoint()
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
      graphDraft.recordPreparedCheckpoint(from: viewGraph)
      checkpoints = FrameHeadCheckpoints(
        baselineFrameState: frameStateCheckpoint!,
        baselineFrameInputs: frameInputsCheckpoint!,
        preparedFrameState: frameState.makeCheckpoint(),
        preparedFrameInputs: frameInputs.makeCheckpoint()
      )
    }

    let transaction = FrameHeadTransaction(
      viewGraph: viewGraph,
      frameState: frameState,
      frameInputs: frameInputs,
      graphDraft: graphDraft,
      registrationDraft: registrationDraft,
      presentationPortalDraft: presentationPortalDraft,
      observationDraft: observationDraft,
      animationDraft: animationDraft,
      checkpoints: checkpoints
    )
    if mode == .abortable {
      transaction.suspendPreparedState()
    }

    return FrameHeadDraft(
      clock: clock,
      renderGeneration: renderGeneration,
      transaction: transaction,
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
      draft.transaction.materializePreparedState()
      resolved = indexedChildSourceWorkerSnapshot(of: resolved)
      frameTailInput.resolved = resolved
      draft.transaction.recordPreparedGraphState()
      draft.transaction.suspendPreparedState()
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
  private func renderFrameTailDraft(
    _ draft: FrameHeadDraft
  ) async -> AsyncFrameTailDraftOutput {
    let layoutResult = await renderFrameTailLayoutStage(draft)
    guard case .output(let layoutStage, _) = layoutResult else {
      preconditionFailure("Non-cancellable frame tail unexpectedly cancelled.")
    }
    return await renderFrameTailRasterStage(
      draft: draft,
      layoutStage: layoutStage
    )
  }

  @MainActor
  private func renderFrameTailLayoutStage(
    _ draft: FrameHeadDraft,
    cancellation: FrameTailCancellationStrategy? = nil
  ) async -> FrameTailLayoutStageResult {
    if let cancellation {
      let cancellationToken = FrameTailJobCancellationToken()
      let layoutTask = Task { @MainActor in
        await renderLayoutResolvingLatePreferencesAsync(
          draft,
          cancellationToken: cancellationToken
        )
      }

      @MainActor
      func waitForQueuedCancellationSignal() async -> FrameTailJobState {
        await cancellation.awaitQueuedCancellationSignal()
        if !Task.isCancelled,
          await cancellation.shouldCancelQueued(),
          cancellationToken.cancelBeforeStart()
        {
          layoutTask.cancel()
          return .cancelledBeforeStart
        }
        return await cancellationToken.waitUntilLeavesQueue()
      }

      let queueExitState = await withTaskGroup(of: FrameTailJobState.self) { group in
        group.addTask {
          await cancellationToken.waitUntilLeavesQueue()
        }
        group.addTask {
          await waitForQueuedCancellationSignal()
        }
        let state = await group.next() ?? cancellationToken.currentState
        group.cancelAll()
        return state
      }

      if queueExitState == .cancelledBeforeStart {
        layoutTask.cancel()
        return .cancelledBeforeStart
      }

      let layoutResult = await layoutTask.value
      guard let reconciledLayout = layoutResult.layout else {
        return .cancelledBeforeStart
      }
      return .output(
        AsyncFrameTailLayoutStageOutput(
          frameTailInput: reconciledLayout.input,
          layout: reconciledLayout.layout,
          resolved: reconciledLayout.resolved,
          runtimeIssues: reconciledLayout.runtimeIssues,
          suspensionDuration: layoutResult.suspensionDuration
        ),
        cancellationToken: cancellationToken
      )
    }

    if frameTailRenderer.canOffloadLayout(draft.frameTailInput) {
      let layoutPass = await renderFrameTailLayoutAsync(
        draft.frameTailInput,
        clock: draft.clock,
        cancellationToken: nil
      )
      guard let layout = layoutPass.layout else {
        return .cancelledBeforeStart
      }
      return .output(
        AsyncFrameTailLayoutStageOutput(
          frameTailInput: draft.frameTailInput,
          layout: layout,
          resolved: draft.resolved,
          runtimeIssues: layoutRuntimeIssues(input: draft.frameTailInput, resolved: draft.resolved),
          suspensionDuration: layoutPass.suspensionDuration
        ),
        cancellationToken: nil
      )
    }

    let layoutResult = await renderLayoutResolvingLatePreferencesAsync(
      draft,
      cancellationToken: nil
    )
    guard let reconciledLayout = layoutResult.layout else {
      return .cancelledBeforeStart
    }
    return .output(
      AsyncFrameTailLayoutStageOutput(
        frameTailInput: reconciledLayout.input,
        layout: reconciledLayout.layout,
        resolved: reconciledLayout.resolved,
        runtimeIssues: reconciledLayout.runtimeIssues,
        suspensionDuration: layoutResult.suspensionDuration
      ),
      cancellationToken: nil
    )
  }

  @MainActor
  private func renderFrameTailRasterStage(
    draft: FrameHeadDraft,
    layoutStage: AsyncFrameTailLayoutStageOutput,
    completionToken: FrameTailJobCancellationToken? = nil
  ) async -> AsyncFrameTailDraftOutput {
    let layout = layoutStage.layout
    let (placed, animationOverlaySnapshot) = prepareAnimationOverlaySnapshot(
      draft: draft,
      layout: layout
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

    let output = AsyncFrameTailDraftOutput(
      frameTailInput: layoutStage.frameTailInput,
      layout: layout,
      tail: tail,
      resolved: layoutStage.resolved,
      runtimeIssues: layoutStage.runtimeIssues,
      renderSuspensionDuration: layoutStage.suspensionDuration + rasterSuspensionDuration
    )
    completionToken?.markCompleted()
    return output
  }

  @MainActor
  private func renderLayoutResolvingLatePreferencesAsync(
    _ draft: FrameHeadDraft,
    cancellationToken: FrameTailJobCancellationToken?
  ) async -> AsyncLatePreferenceReconciliationOutput {
    guard frameTailRenderer.needsPreparedGraphDuringLayout(draft.frameTailInput) else {
      return await renderLayoutResolvingLatePreferencesAsync(
        draft.frameTailInput,
        clock: draft.clock,
        cancellationToken: cancellationToken
      )
    }

    draft.transaction.materializePreparedState()
    defer {
      draft.transaction.suspendPreparedState()
    }
    let layoutResult = await renderLayoutResolvingLatePreferencesAsync(
      draft.frameTailInput,
      clock: draft.clock,
      cancellationToken: cancellationToken
    )
    if layoutResult.layout != nil {
      draft.transaction.recordPreparedGraphState()
    }
    return layoutResult
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
    let workerTimings = CommittedFrameArtifactBuilder.workerTimings(
      draft: draft,
      tailOutput: tailOutput
    )
    let (commit, commitDuration) = previewCompletedFrameCommit(
      draft: draft,
      tailOutput: tailOutput,
      resolved: resolved
    )
    let artifacts = CommittedFrameArtifactBuilder.makeCompletedFrameArtifacts(
      draft: draft,
      tailOutput: tailOutput,
      resolved: resolved,
      commit: commit,
      commitDuration: commitDuration,
      workerTimings: workerTimings
    )
    let eligibility = CommittedFrameArtifactBuilder.eligibility(
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
  private func resolveCompletedFrameCandidate(
    draft: FrameHeadDraft,
    tailOutput: AsyncFrameTailDraftOutput,
    newestDesiredGeneration: RenderGeneration,
    completedFramePolicy: CompletedFramePolicy? = nil,
    additionalBlockers:
      @MainActor @Sendable (FrameArtifacts) -> Set<FrameDropEligibility.Blocker> = { _ in [] }
  ) -> CompletedFrameCandidateResolution {
    let candidate = makeCompletedFrameCandidate(
      draft: draft,
      tailOutput: tailOutput,
      newestDesiredGeneration: newestDesiredGeneration,
      completedFramePolicy: completedFramePolicy,
      additionalBlockers: additionalBlockers
    )
    if candidate.dropDecision.canSkipCompletedFrame {
      discardCompletedFrameCandidate(
        candidate,
        reconciliation: candidate.dropDecision.reconciliation
      )
      return .dropped(
        runtimeIssues: candidate.previewArtifacts.diagnostics.runtime.issues,
        dropDecision: candidate.dropDecision
      )
    }
    let artifacts = commitCompletedFrameCandidate(candidate)
    return .committed(artifacts, candidate.dropDecision)
  }

  @MainActor
  private func commitCompletedFrameCandidate(
    _ candidate: CompletedFrameCandidate
  ) -> FrameArtifacts {
    let layout = candidate.tailOutput.layout
    let tail = candidate.tailOutput.tail
    candidate.draft.transaction.materializePreparedState()
    let effects = commitFrameEffects(
      draft: candidate.draft,
      resolved: candidate.resolved,
      placed: tail.placed,
      semantics: tail.semantics,
      workerCustomLayoutCacheUpdates: layout.workerCustomLayoutCacheUpdates
    )
    let artifacts = CommittedFrameArtifactBuilder.makeCompletedFrameArtifacts(
      draft: candidate.draft,
      tailOutput: candidate.tailOutput,
      resolved: candidate.resolved,
      commit: effects.commitPlan,
      commitDuration: effects.commitDuration,
      workerTimings: candidate.workerTimings,
      runtimeRegistrationDiagnostics: effects.runtimeRegistrationDiagnostics
    )

    publishCommittedFrame(
      artifacts,
      draft: candidate.draft,
      baselinePlacedTree: tail.baselinePlaced
    )
    return artifacts
  }

  @MainActor
  private func commitFrameEffects(
    draft: FrameHeadDraft,
    resolved: ResolvedNode,
    placed: PlacedNode,
    semantics: SemanticSnapshot,
    workerCustomLayoutCacheUpdates: [WorkerCustomLayoutCacheUpdate]
  ) -> CommittedFrameEffects {
    var runtimeRegistrationDiagnostics = RuntimeRegistrationDiagnostics()
    let (commit, commitDuration) = measurePhase(clock: draft.clock) {
      let lifecycleEvents = viewGraph.finalizeFrame(
        rootIdentity: draft.graphRootIdentity,
        resolved: resolved,
        placed: placed
      )
      runtimeRegistrationDiagnostics = commitFrameHeadDraftEffects(draft)
      return commitPlanner.plan(
        resolved: resolved,
        placed: placed,
        semantics: semantics,
        transaction: draft.frameContext.transaction,
        lifecycleEvents: lifecycleEvents
      )
    }
    applyWorkerCustomLayoutCacheUpdates(workerCustomLayoutCacheUpdates)
    frameTailRenderer.pruneMeasurementCache(
      keeping: viewGraph.liveIdentitySnapshot()
    )
    return CommittedFrameEffects(
      commitPlan: commit,
      commitDuration: commitDuration,
      runtimeRegistrationDiagnostics: runtimeRegistrationDiagnostics
    )
  }

  @MainActor
  private func publishCommittedFrame(
    _ artifacts: FrameArtifacts,
    draft: FrameHeadDraft,
    baselinePlacedTree: PlacedNode
  ) {
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
      baselinePlacedTree: baselinePlacedTree
    )
    storeCommittedPresentationPortalState()
  }

  @MainActor
  private func storeCommittedPresentationPortalState() {
    committedPresentationDismissStack.store(presentationPortalState.dismissStack())
  }

  @MainActor
  private func commitFrameHeadDraftEffects(
    _ draft: FrameHeadDraft
  ) -> RuntimeRegistrationDiagnostics {
    draft.transaction.commit()
  }

  @MainActor
  private func previewCompletedFrameCommit(
    draft: FrameHeadDraft,
    tailOutput: AsyncFrameTailDraftOutput,
    resolved: ResolvedNode
  ) -> (commit: CommitPlan, duration: Duration) {
    let tail = tailOutput.tail
    draft.transaction.materializePreparedState()
    defer {
      draft.transaction.suspendPreparedState()
    }

    return measurePhase(clock: draft.clock) {
      let lifecycleEvents = viewGraph.previewLifecycleEvents(
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
