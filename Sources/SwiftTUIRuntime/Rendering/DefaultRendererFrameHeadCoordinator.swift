import SwiftTUICore
import SwiftTUIViews

/// Coordinates the renderer stages that prepare a frame head before frame-tail
/// work starts.
///
/// The live state still belongs to `DefaultRenderer`. This helper only gives
/// the preparation pass named steps: generation, draft setup, resolve-input
/// checkpointing, graph evaluation, portal wrapping, retained tail input, and
/// animation injection.
@MainActor
struct DefaultRendererFrameHeadCoordinator {
  var resolver: Resolver
  var imageRepository: ImageAssetRepository
  var viewGraph: ViewGraph
  var frameState: FrameResolveState
  var frameInputs: FrameResolveInputBox
  var presentationPortalState: PresentationPortalState
  var animationController: AnimationController
  var renderGenerationSequencer: RenderGenerationSequencer
  var elidedFrameTimingRecorder: ElidedFrameTimingRecorder
  var frameTailRenderer: FrameTailRenderer
  var storeObservationBridge: @MainActor (ObservationBridge?) -> Void
  var renderPipelineContentTree: (ResolvedNode) -> ResolvedNode

  func computeFrameHead<V: View>(
    _ root: V,
    context: ResolveContext,
    proposal: ProposedSize,
    mode: FrameHeadMode
  ) -> FrameHeadDraft {
    let clock = ContinuousClock()
    let frameHeadTimingRecorder = FrameHeadTimingRecorder()
    elidedFrameTimingRecorder.reset()
    let headStart = elidedFrameTimingRecorder.start()
    let prepareStart = frameHeadTimingRecorder.start()
    defer {
      elidedFrameTimingRecorder.record(.headTotal, since: headStart)
      frameHeadTimingRecorder.record(.prepare, since: prepareStart)
    }
    let renderGeneration = renderGenerationSequencer.next()

    var resolveContext = preparedResolveContext(context)
    let registrationDraft = FrameHeadRegistrationDraft()
    let graphCheckpoint: ViewGraph.Checkpoint?
    switch mode {
    case .oneShot:
      graphCheckpoint = nil
    case .abortable:
      graphCheckpoint = elidedFrameTimingRecorder.measure(
        .graphCheckpointCreate
      ) {
        frameHeadTimingRecorder.measure(.graphCheckpointCreate) {
          viewGraph.makeCheckpoint()
        }
      }
    }
    let graphDraft = ViewGraphFrameDraft(
      liveRegistrations: resolveContext.runtimeRegistrations,
      checkpoint: graphCheckpoint
    )
    let animationDraft = animationController.makeFrameDraft()
    resolveContext = resolveContext.replacingRuntimeRegistrations(
      registrationDraft.draftRegistrations
    )
    resolveContext.imageAssetResolver = imageRepository.resolver()

    let baselineCheckpoints = baselineCheckpoints(for: mode)
    let resolveInputs = storeResolveInputs(
      in: &resolveContext,
      proposal: proposal
    )
    let observationDraft = beginGraphEvaluation(
      resolveContext: &resolveContext,
      resolveInputs: resolveInputs
    )
    let portal = installPresentationPortalEvaluator(
      root,
      resolveContext: resolveContext,
      resolveInputs: resolveInputs
    )
    graphDraft.recordPresentationPortalRootQueued(portal.queuedRoot)
    let resolvedHead = resolveGraphHead(
      resolveContext: resolveContext,
      graphDraft: graphDraft,
      animationDraft: animationDraft,
      resolveInputs: resolveInputs,
      canUseSelectiveEvaluation: resolveInputs.usesSelectiveEvaluation,
      clock: clock
    )
    let frameProducts = makeFrameTailProducts(
      renderGeneration: renderGeneration,
      resolveContext: resolveContext,
      resolveInputs: resolveInputs,
      resolved: resolvedHead.resolved
    )
    let checkpoints = preparedCheckpoints(
      for: mode,
      graphDraft: graphDraft,
      baseline: baselineCheckpoints,
      frameHeadTimingRecorder: frameHeadTimingRecorder
    )
    let transaction = FrameHeadTransaction(
      viewGraph: viewGraph,
      frameState: frameState,
      frameInputs: frameInputs,
      graphDraft: graphDraft,
      registrationDraft: registrationDraft,
      presentationPortalDraft: portal.draft,
      observationDraft: observationDraft,
      animationDraft: animationDraft,
      elidedFrameTimingRecorder: elidedFrameTimingRecorder,
      frameHeadTimingRecorder: frameHeadTimingRecorder,
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
      graphRootIdentity: portal.graphRootIdentity,
      frameContext: frameProducts.frameContext,
      resolved: resolvedHead.resolved,
      frameTailInput: frameProducts.frameTailInput,
      runtimeIssues: [],
      animationTimestamp: MonotonicInstant.now(),
      resolveDuration: resolvedHead.resolveDuration
    )
  }

  func injectAnimations(
    into draft: FrameHeadDraft,
    mode: FrameHeadMode
  ) -> FrameHeadDraft {
    var draft = draft
    var resolved = draft.resolved
    let animationTimestamp = MonotonicInstant.now()
    elidedFrameTimingRecorder.measure(.animationTick) {
      AnimationInjectionStage(animationDraft: draft.animationDraft).apply(
        to: &resolved,
        transaction: draft.frameContext.transaction,
        timestamp: animationTimestamp,
        surfaceSize: animationSurfaceSize(for: draft.frameTailInput.proposal),
        frameHeadTransaction: draft.transaction
      )
    }

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

  func prepareFrameHead<V: View>(
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

  private func preparedResolveContext(
    _ context: ResolveContext
  ) -> ResolveContext {
    storeObservationBridge(context.observationBridge)
    return context
  }

  private func baselineCheckpoints(
    for mode: FrameHeadMode
  ) -> FrameHeadBaselineCheckpoints? {
    switch mode {
    case .oneShot:
      nil
    case .abortable:
      FrameHeadBaselineCheckpoints(
        frameState: frameState.makeCheckpoint(),
        frameInputs: frameInputs.makeCheckpoint()
      )
    }
  }

  private func storeResolveInputs(
    in resolveContext: inout ResolveContext,
    proposal: ProposedSize
  ) -> FrameResolveInputs {
    var resolveInputs = frameState.prepareInputs(
      from: resolveContext,
      proposal: proposal
    )
    translatePresentationPortalInvalidations(
      in: &resolveInputs,
      contentRootIdentity: resolveContext.identity,
      portalRootIdentity: presentationPortalIdentity(for: resolveContext.identity)
    )
    frameInputs.store(resolveInputs)
    resolveContext.frameInputs = frameInputs
    return resolveInputs
  }

  private func translatePresentationPortalInvalidations(
    in resolveInputs: inout FrameResolveInputs,
    contentRootIdentity: Identity,
    portalRootIdentity: Identity
  ) {
    guard !resolveInputs.invalidatedIdentities.isEmpty else {
      return
    }

    let translatedIdentities = viewGraph.translatePresentationPortalInvalidations(
      resolveInputs.invalidatedIdentities,
      portalRootIdentity: portalRootIdentity,
      activeOverlayEntryIdentities: activePresentationOverlayEntryIdentities(
        portalRootIdentity: portalRootIdentity
      )
    )
    guard translatedIdentities != resolveInputs.invalidatedIdentities else {
      return
    }

    resolveInputs.invalidatedIdentities = translatedIdentities
    resolveInputs.invalidationSummary = .init(
      invalidatedIdentities: translatedIdentities
    )
    resolveInputs.usesSelectiveEvaluation =
      frameState.selectiveEvaluationEnabled
      && !resolveInputs.environmentRequiresRootEvaluation
      && !translatedIdentities.contains(contentRootIdentity)
  }

  private func activePresentationOverlayEntryIdentities(
    portalRootIdentity: Identity
  ) -> Set<Identity> {
    Set(
      presentationPortalState.overlayEntries().map { entry in
        portalRootIdentity
          .child("PortalHost")
          .child("overlays")
          .child("entry:\(entry.id)")
      }
    )
  }

  private func beginGraphEvaluation(
    resolveContext: inout ResolveContext,
    resolveInputs: FrameResolveInputs
  ) -> ObservationBridgeDraft? {
    viewGraph.beginFrame()
    if resolveInputs.usesSelectiveEvaluation {
      viewGraph.invalidateAndQueueDirty(resolveInputs.invalidatedIdentities)
    } else {
      viewGraph.invalidate(resolveInputs.invalidatedIdentities)
    }
    resolveContext.viewGraph = viewGraph
    return resolveContext.observationBridge?.makeDraft(
      attaching: viewGraph
    )
  }

  private func installPresentationPortalEvaluator<V: View>(
    _ root: V,
    resolveContext: ResolveContext,
    resolveInputs: FrameResolveInputs
  ) -> PresentationPortalPreparation {
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
    let shouldQueuePresentationPortalRoot =
      !hasExistingPresentationPortalRoot
      || !resolveInputs.usesSelectiveEvaluation
      || !resolveInputs.invalidatedIdentities.isEmpty
    if shouldQueuePresentationPortalRoot {
      viewGraph.queueDirty([presentationPortalContext.identity])
    }

    return PresentationPortalPreparation(
      graphRootIdentity: presentationPortalContext.identity,
      queuedRoot: shouldQueuePresentationPortalRoot,
      draft: presentationPortalDraft
    )
  }

  private func resolveGraphHead(
    resolveContext: ResolveContext,
    graphDraft: ViewGraphFrameDraft,
    animationDraft: AnimationFrameDraft,
    resolveInputs: FrameResolveInputs,
    canUseSelectiveEvaluation: Bool,
    clock: ContinuousClock
  ) -> (resolved: ResolvedNode, resolveDuration: Duration) {
    let (_, resolveDuration): (Void, Duration)
    animationDraft.controller.beginTransitionCollection()
    if canUseSelectiveEvaluation, !viewGraph.hasDirtyWork {
      // Nothing is dirty: keep the existing snapshot and leave root evaluator
      // registrations untouched for this frame.
      let diagnostics =
        RuntimeRegistrationPublicationDiagnosticsConfiguration.isEnabled
        ? viewGraph.noDirtyWorkPlanDiagnostics(
          invalidatedIdentities: resolveInputs.invalidatedIdentities
        )
        : nil
      graphDraft.recordUnchangedDirtyEvaluation(diagnostics: diagnostics)
      resolveDuration = .zero
    } else {
      let dirtyEvaluation:
        (
          plan: DirtyEvaluationPlan?,
          diagnostics: DirtyEvaluationPlanDiagnostics?
        )
      if RuntimeRegistrationPublicationDiagnosticsConfiguration.isEnabled {
        if canUseSelectiveEvaluation {
          let evaluation = viewGraph.selectiveDirtyEvaluationPlanWithDiagnostics(
            invalidatedIdentities: resolveInputs.invalidatedIdentities
          )
          dirtyEvaluation = (evaluation.plan, evaluation.diagnostics)
        } else {
          dirtyEvaluation = (
            nil,
            viewGraph.disabledSelectiveEvaluationPlanDiagnostics(
              invalidatedIdentities: resolveInputs.invalidatedIdentities
            )
          )
        }
      } else {
        dirtyEvaluation = (viewGraph.selectiveDirtyEvaluationPlan(), nil)
      }
      let dirtyEvaluationPlan = dirtyEvaluation.plan
      graphDraft.recordDirtyEvaluationPlan(
        dirtyEvaluationPlan,
        diagnostics: dirtyEvaluation.diagnostics
      )

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
      renderPipelineContentTree(viewGraph.snapshot()),
      context: resolveContext
    )
    return (resolved, resolveDuration)
  }

  private func makeFrameTailProducts(
    renderGeneration: RenderGeneration,
    resolveContext: ResolveContext,
    resolveInputs: FrameResolveInputs,
    resolved: ResolvedNode
  ) -> (frameContext: FrameContext, frameTailInput: FrameTailInput) {
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
    return (frameContext, frameTailInput)
  }

  private func preparedCheckpoints(
    for mode: FrameHeadMode,
    graphDraft: ViewGraphFrameDraft,
    baseline: FrameHeadBaselineCheckpoints?,
    frameHeadTimingRecorder: FrameHeadTimingRecorder
  ) -> FrameHeadCheckpoints? {
    switch mode {
    case .oneShot:
      return nil
    case .abortable:
      guard let baseline else {
        preconditionFailure("Abortable frame heads require baseline checkpoints.")
      }
      elidedFrameTimingRecorder.measure(.graphCheckpointCreate) {
        frameHeadTimingRecorder.measure(.graphCheckpointCreate) {
          graphDraft.recordPreparedCheckpoint(from: viewGraph)
        }
      }
      return FrameHeadCheckpoints(
        baselineFrameState: baseline.frameState,
        baselineFrameInputs: baseline.frameInputs,
        preparedFrameState: frameState.makeCheckpoint(),
        preparedFrameInputs: frameInputs.makeCheckpoint()
      )
    }
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
}

private struct FrameHeadBaselineCheckpoints {
  var frameState: FrameResolveState.Checkpoint
  var frameInputs: FrameResolveInputBox.Checkpoint
}

private struct PresentationPortalPreparation {
  var graphRootIdentity: Identity
  var queuedRoot: Bool
  var draft: PresentationPortalDraft
}

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
    timestamp: MonotonicInstant,
    surfaceSize: CellSize?,
    frameHeadTransaction: FrameHeadTransaction
  ) {
    let controller = animationDraft.controller
    frameHeadTransaction.measureHeadTiming(.animationProcessResolvedTree) {
      controller.processResolvedTree(
        resolved,
        transaction: transaction,
        timestamp: timestamp
      )
    }
    frameHeadTransaction.measureHeadTiming(.animationApplyInterpolations) {
      _ = controller.applyInterpolations(
        to: &resolved,
        at: timestamp,
        surfaceSize: surfaceSize
      )
    }
  }
}

private func animationSurfaceSize(for proposal: ProposedSize) -> CellSize? {
  guard
    case .finite(let width) = proposal.width,
    case .finite(let height) = proposal.height
  else {
    return nil
  }

  return CellSize(width: max(0, width), height: max(0, height))
}
