@_exported import EmbeddedFonts
@_exported import SwiftTUICore
@_exported import SwiftTUIViews

/// Renders authored terminal views through the full frame pipeline.
///
/// `DefaultRenderer` is the public one-shot entry point for turning a `View`
/// into a committed-frame `RenderSnapshot` for previews, snapshot tests,
/// diagnostics, or custom presentation.
public struct DefaultRenderer {
  private static let latePreferenceReconciliationPolicy =
    LatePreferenceReconciliationPolicy.toolbarHostRuntimeBound

  package let resolver: Resolver
  package let layoutEngine: LayoutEngine
  package let semanticExtractor: SemanticExtractor
  package let drawExtractor: DrawExtractor
  package let rasterizer: Rasterizer
  package let commitPlanner: CommitPlanner
  private let imageRepository: ImageAssetRepository
  let viewGraph: ViewGraph
  private let frameState: FrameResolveState
  private let frameInputs: FrameResolveInputBox
  private let presentationPortalState: PresentationPortalState
  private let committedPresentationDismissStack: CommittedPresentationDismissStack
  private let debugObservationBridgeTracker: DebugObservationBridgeTracker
  private let animationController: AnimationController
  private let renderGenerationSequencer: RenderGenerationSequencer
  private let elidedFrameCounter: ElidedFrameCounter
  private let elidedFrameTimingRecorder: ElidedFrameTimingRecorder

  let frameTailRenderer: FrameTailRenderer
  // Visibility note: `frameTailCoordinator` and `prepareFrameHead` are
  // file-internal rather than `private` so the test-only hooks in
  // `DefaultRenderer+TestingHooks.swift` can reach them.
  var frameTailCoordinator: DefaultRendererFrameTailCoordinator {
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
      elidedFrameTimingRecorder: elidedFrameTimingRecorder,
      frameTailRenderer: frameTailRenderer,
      storeObservationBridge: { bridge in
        observationBridgeTracker.store(bridge)
      },
      renderPipelineContentTree: renderPipelineTree(from:)
    )
  }

  /// Creates a renderer with default pipeline components.
  @MainActor
  public init() {
    self.init(
      resolver: .init(),
      layoutEngine: .init(cache: MeasurementCache()),
      semanticExtractor: .init(),
      drawExtractor: .init(),
      rasterizer: .init(),
      commitPlanner: .init()
    )
  }

  /// Creates a renderer with the supplied pipeline components.
  @MainActor
  package init(
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
    elidedFrameCounter = .init()
    elidedFrameTimingRecorder = .init()
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

  // Test-only pipeline-stage hooks live in
  // `DefaultRenderer+TestingHooks.swift`.

  /// Renders `root` into a committed frame snapshot.
  ///
  /// This is a one-shot snapshot/preview entry point. It is **not focus/press
  /// reuse-safe across successive calls on the same renderer**: focus and press
  /// state are runtime side-fields excluded from the reuse-equality snapshot, and
  /// their correctness under memoized-body reuse depends on the run loop's
  /// retained-reuse suppression scope, which the one-shot path does not compute.
  /// So an `Equatable`/``SwiftUICore/View/equatable()`` boundary wrapping a
  /// focus/press-reading control can serve a stale pressed/focused visual across
  /// one-shot frames where focus/press changed and an ancestor was invalidated.
  /// For interactive rendering, drive frames through the run loop
  /// (`TerminalRunner`/host integration), which suppresses reuse of focus/press
  /// cones; use `render(_:)` for snapshots, previews, and tests.
  @MainActor
  public func render<V: View>(
    _ root: V,
    context: ResolveContext = .init(),
    proposal: ProposedSize = .unspecified
  ) -> RenderSnapshot {
    renderArtifacts(
      root,
      context: context,
      proposal: proposal
    ).renderSnapshot
  }

  /// Renders `root` into complete frame artifacts for package tests and runtime
  /// internals that intentionally inspect phase IR.
  @MainActor
  package func renderArtifacts<V: View>(
    _ root: V,
    context: ResolveContext = .init(),
    proposal: ProposedSize = .unspecified
  ) -> FrameArtifacts {
    switch renderView(
      root,
      context: context,
      proposal: proposal,
      elisionCauses: [],
      elisionAnimationRequest: .inherit
    ) {
    case .rendered(let artifacts):
      return artifacts
    case .elided:
      preconditionFailure(
        "Off-screen elision must never fire for the public one-shot renderer (empty causes)."
      )
    }
  }

  /// Renders `root` into a committed frame snapshot, suspending while the
  /// frame-tail worker computes the Sendable semantics, draw, and raster phases.
  @MainActor
  public func renderAsync<V: View>(
    _ root: V,
    context: ResolveContext = .init(),
    proposal: ProposedSize = .unspecified
  ) async -> RenderSnapshot {
    await renderArtifactsAsync(
      root,
      context: context,
      proposal: proposal
    ).renderSnapshot
  }

  /// Renders `root` into complete frame artifacts for package tests and runtime
  /// internals that intentionally inspect phase IR.
  @MainActor
  package func renderArtifactsAsync<V: View>(
    _ root: V,
    context: ResolveContext = .init(),
    proposal: ProposedSize = .unspecified
  ) async -> FrameArtifacts {
    switch await renderViewAsync(
      root,
      context: context,
      proposal: proposal,
      elisionCauses: [],
      elisionAnimationRequest: .inherit
    ) {
    case .rendered(let artifacts):
      return artifacts
    case .elided:
      preconditionFailure(
        "Off-screen elision must never fire for the public async renderer (empty causes)."
      )
    }
  }

  /// Run-loop entry point for the synchronous one-shot path that may elide an
  /// off-screen-only animation tick. Returns ``RenderExecutionResult/elided``
  /// when the gate fires (the reduced commit has already run); otherwise the
  /// committed artifacts.
  @MainActor
  package func renderEliding<V: View>(
    _ root: V,
    context: ResolveContext,
    proposal: ProposedSize,
    elisionCauses: Set<WakeCause>,
    elisionAnimationRequest: AnimationRequest
  ) -> RenderExecutionResult {
    renderView(
      root,
      context: context,
      proposal: proposal,
      elisionCauses: elisionCauses,
      elisionAnimationRequest: elisionAnimationRequest
    )
  }

  /// Run-loop entry point for the abortable async path that may elide an
  /// off-screen-only animation tick. See ``renderEliding(_:context:proposal:elisionCauses:elisionAnimationRequest:)``.
  @MainActor
  package func renderAsyncEliding<V: View>(
    _ root: V,
    context: ResolveContext,
    proposal: ProposedSize,
    elisionCauses: Set<WakeCause>,
    elisionAnimationRequest: AnimationRequest
  ) async -> RenderExecutionResult {
    await renderViewAsync(
      root,
      context: context,
      proposal: proposal,
      elisionCauses: elisionCauses,
      elisionAnimationRequest: elisionAnimationRequest
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
    redundantHandlerInstallationsAreVisualOnly:
      @escaping @MainActor @Sendable (FrameArtifacts) -> Bool = { _ in false },
    awaitQueuedCancellationSignal: @escaping @MainActor @Sendable () async -> Void = {},
    shouldCancelQueued: @escaping @MainActor @Sendable () async -> Bool
  ) async -> CancellableRenderOutcome {
    switch await renderCancellableExecution(
      root,
      context: context,
      proposal: proposal,
      elisionCauses: [],
      elisionAnimationRequest: .inherit,
      newestDesiredGeneration: newestDesiredGeneration,
      completedFramePolicy: completedFramePolicy,
      completedFrameAdditionalBlockers: completedFrameAdditionalBlockers,
      redundantHandlerInstallationsAreVisualOnly: redundantHandlerInstallationsAreVisualOnly,
      awaitQueuedCancellationSignal: awaitQueuedCancellationSignal,
      shouldCancelQueued: shouldCancelQueued
    ) {
    case .rendered(let outcome):
      return outcome
    case .elided:
      preconditionFailure(
        "Off-screen elision must never fire for renderAsyncCancellable (empty causes)."
      )
    }
  }

  /// Run-loop entry point for the cancellable async path that may elide an
  /// off-screen-only animation tick. Returns
  /// ``CancellableRenderExecutionResult/elided`` when the gate fires (the
  /// reduced commit has already run); otherwise the cancellable outcome.
  @MainActor
  package func renderAsyncCancellableEliding<V: View>(
    _ root: V,
    context: ResolveContext,
    proposal: ProposedSize,
    elisionCauses: Set<WakeCause>,
    elisionAnimationRequest: AnimationRequest,
    newestDesiredGeneration: @escaping @MainActor @Sendable () -> RenderGeneration? = { nil },
    completedFramePolicy: CompletedFramePolicy? = nil,
    completedFrameAdditionalBlockers:
      @escaping @MainActor @Sendable (FrameArtifacts) -> Set<FrameDropEligibility.Blocker> = {
        _ in []
      },
    redundantHandlerInstallationsAreVisualOnly:
      @escaping @MainActor @Sendable (FrameArtifacts) -> Bool = { _ in false },
    awaitQueuedCancellationSignal: @escaping @MainActor @Sendable () async -> Void = {},
    shouldCancelQueued: @escaping @MainActor @Sendable () async -> Bool
  ) async -> CancellableRenderExecutionResult {
    await renderCancellableExecution(
      root,
      context: context,
      proposal: proposal,
      elisionCauses: elisionCauses,
      elisionAnimationRequest: elisionAnimationRequest,
      newestDesiredGeneration: newestDesiredGeneration,
      completedFramePolicy: completedFramePolicy,
      completedFrameAdditionalBlockers: completedFrameAdditionalBlockers,
      redundantHandlerInstallationsAreVisualOnly: redundantHandlerInstallationsAreVisualOnly,
      awaitQueuedCancellationSignal: awaitQueuedCancellationSignal,
      shouldCancelQueued: shouldCancelQueued
    )
  }

  @MainActor
  private func renderCancellableExecution<V: View>(
    _ root: V,
    context: ResolveContext,
    proposal: ProposedSize,
    elisionCauses: Set<WakeCause>,
    elisionAnimationRequest: AnimationRequest,
    newestDesiredGeneration: @escaping @MainActor @Sendable () -> RenderGeneration?,
    completedFramePolicy: CompletedFramePolicy?,
    completedFrameAdditionalBlockers:
      @escaping @MainActor @Sendable (FrameArtifacts) -> Set<FrameDropEligibility.Blocker>,
    redundantHandlerInstallationsAreVisualOnly:
      @escaping @MainActor @Sendable (FrameArtifacts) -> Bool,
    awaitQueuedCancellationSignal: @escaping @MainActor @Sendable () async -> Void,
    shouldCancelQueued: @escaping @MainActor @Sendable () async -> Bool
  ) async -> CancellableRenderExecutionResult {
    let renderer = self
    if renderer.elideOffscreenAnimationBeforeFrameHeadIfPossible(
      elisionCauses: elisionCauses,
      elisionAnimationRequest: elisionAnimationRequest
    ) {
      return .elided
    }
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
        commitElidedFrameIfOffscreen: renderer.makeCommitElidedFrameIfOffscreen(
          elisionCauses: elisionCauses,
          elisionAnimationRequest: elisionAnimationRequest
        ),
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
            additionalBlockers: completedFrameAdditionalBlockers,
            redundantHandlerInstallationsAreVisualOnly:
              redundantHandlerInstallationsAreVisualOnly
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

  /// Builds the executor-stage off-screen elision closure. The closure runs
  /// the gate predicate against the post-animation-injection draft tick and,
  /// when it fires, performs the reduced commit (``commitElidedFrame(draft:)``)
  /// before returning `true`. When `elisionCauses` is empty (the public
  /// preview entry points) the predicate can never fire.
  @MainActor
  private func makeCommitElidedFrameIfOffscreen(
    elisionCauses: Set<WakeCause>,
    elisionAnimationRequest: AnimationRequest
  ) -> (FrameHeadDraft) -> Bool {
    { [self] draft in
      let tick = draft.animationDraft.controller.lastTickResult
      guard
        OffscreenFrameElision.shouldElide(
          causes: elisionCauses,
          animationRequest: elisionAnimationRequest,
          redrawIdentities: tick.redrawIdentities,
          drawnIdentities: frameTailRenderer.previousDrawnIdentities
        )
      else {
        return false
      }
      commitElidedFrame(draft: draft)
      return true
    }
  }

  @MainActor
  private func elideOffscreenAnimationBeforeFrameHeadIfPossible(
    elisionCauses: Set<WakeCause>,
    elisionAnimationRequest: AnimationRequest
  ) -> Bool {
    guard
      let redrawIdentities =
        animationController.preFrameHeadOffscreenPropertyAnimationRedrawIdentities
    else {
      return false
    }
    guard
      OffscreenFrameElision.shouldElide(
        causes: elisionCauses,
        animationRequest: elisionAnimationRequest,
        redrawIdentities: redrawIdentities,
        drawnIdentities: frameTailRenderer.previousDrawnIdentities
      )
    else {
      return false
    }

    elidedFrameTimingRecorder.reset()
    let tickStart = elidedFrameTimingRecorder.start()
    animationController.advancePreFrameHeadOffscreenPropertyAnimationTick(
      at: MonotonicInstant.now()
    )
    elidedFrameTimingRecorder.record(.animationTick, since: tickStart)
    recordElidedFrame()
    return true
  }

  @MainActor
  private func renderView<V: View>(
    _ root: V,
    context: ResolveContext,
    proposal: ProposedSize,
    elisionCauses: Set<WakeCause>,
    elisionAnimationRequest: AnimationRequest
  ) -> RenderExecutionResult {
    let renderer = self
    if renderer.elideOffscreenAnimationBeforeFrameHeadIfPossible(
      elisionCauses: elisionCauses,
      elisionAnimationRequest: elisionAnimationRequest
    ) {
      return .elided
    }
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
        commitElidedFrameIfOffscreen: renderer.makeCommitElidedFrameIfOffscreen(
          elisionCauses: elisionCauses,
          elisionAnimationRequest: elisionAnimationRequest
        ),
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
    proposal: ProposedSize,
    elisionCauses: Set<WakeCause>,
    elisionAnimationRequest: AnimationRequest
  ) async -> RenderExecutionResult {
    let renderer = self
    if renderer.elideOffscreenAnimationBeforeFrameHeadIfPossible(
      elisionCauses: elisionCauses,
      elisionAnimationRequest: elisionAnimationRequest
    ) {
      return .elided
    }
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
        commitElidedFrameIfOffscreen: renderer.makeCommitElidedFrameIfOffscreen(
          elisionCauses: elisionCauses,
          elisionAnimationRequest: elisionAnimationRequest
        ),
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

  // Visibility: file-internal (see note on `frameTailCoordinator`) so the
  // test-only hooks can prepare a frame head directly.
  @MainActor
  func prepareFrameHead<V: View>(
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
  package func forceRootEvaluation(
    source: ForceRootEvaluationSource = .unattributed
  ) {
    frameState.forceRootEvaluation = true
    frameState.forceRootEvaluationSources.insert(source)
  }

  /// Suppresses retained reuse for a scoped set of identities on the next
  /// render. Finite focus/press scopes may be queued as graph-local dirty work
  /// during frame head preparation; animation and identity-agnostic safety
  /// scopes are paired with root evaluation by run-loop policy.
  @MainActor
  package func suppressRetainedReuseForNextFrame(
    _ scope: RetainedReuseSuppressionScope
  ) {
    frameState.retainedReuseSuppressionScope = scope
  }

  /// Suppresses retained reuse for every reached node on the next render.
  @MainActor
  package func suppressRetainedReuseForNextFrame() {
    suppressRetainedReuseForNextFrame(.all)
  }

  @MainActor
  package func runtimeFocusStateDependentIdentities() -> Set<Identity> {
    viewGraph.environmentDependentIdentities(
      for: EnvironmentValues.runtimeFocusStateDependencyKeys
    )
  }

  /// Identities of the `@FocusedValue`/`@FocusedBinding` readers, derived from the
  /// focused-value reader attribution recorded during resolve. Single-pass
  /// focus-sync invalidates exactly these on a pure focused-value change so the
  /// readers re-resolve next frame while sibling subtrees stay reused.
  @MainActor
  package func focusedValuesDependentIdentities() -> Set<Identity> {
    viewGraph.environmentDependentIdentities(
      for: EnvironmentValues.focusedValuesDependencyKeys
    )
  }

  @MainActor
  package func liveIdentitySnapshot() -> Set<Identity> {
    viewGraph.liveIdentitySnapshot()
  }

  /// Resolves a rerender pass's invalidation set onto live graph targets:
  /// identities are first translated through the presentation-portal mapping
  /// (an overlay-hosted identity resolves to its live host, exactly as the
  /// frame head would translate them), then filtered to existing graph
  /// nodes. A raw liveness filter would silently drop portal-translatable
  /// identities; see ``RunLoop`` `rerenderScheduledFrame(from:convergence:)`
  /// for why dropping the untranslatable remainder is sound there.
  @MainActor
  package func rerenderInvalidationTargets(
    _ identities: Set<Identity>,
    contentRootIdentity: Identity
  ) -> Set<Identity> {
    let translated = viewGraph.translatePresentationPortalInvalidations(
      identities,
      portalRootIdentity: presentationPortalIdentity(for: contentRootIdentity)
    )
    return translated.filter { viewGraph.containsNode(for: $0) }
  }

  @MainActor
  package func liveNodeIDSnapshot() -> Set<ViewNodeID> {
    viewGraph.liveNodeIDSnapshot()
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

  /// The number of frames that have been recorded as elided (off-screen).
  /// Starts at zero; incremented by ``recordElidedFrame()``.
  @MainActor
  package var elidedFrameCount: Int {
    elidedFrameCounter.count
  }

  /// Records one elided frame, incrementing ``elidedFrameCount``.
  /// Called from the run loop's elided-frame path (the `.elided` arm in
  /// `renderPendingFramesAsync`) when a frame is skipped because all drawn
  /// identities are off-screen.
  @MainActor
  package func recordElidedFrame() {
    elidedFrameCounter.increment()
  }

  @MainActor
  package func setElidedFrameTimingDiagnosticsEnabled(_ isEnabled: Bool) {
    elidedFrameTimingRecorder.isEnabled = isEnabled
  }

  @MainActor
  package var elidedFrameTimings: ElidedFrameTimings {
    elidedFrameTimingRecorder.snapshot
  }
}
