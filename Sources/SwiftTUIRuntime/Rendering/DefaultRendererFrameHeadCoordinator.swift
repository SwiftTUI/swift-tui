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
    let renderGeneration = renderGenerationSequencer.next()

    var resolveContext = preparedResolveContext(context)
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
    let resolvedHead = resolveGraphHead(
      resolveContext: resolveContext,
      graphDraft: graphDraft,
      animationDraft: animationDraft,
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
      baseline: baselineCheckpoints
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
    let resolveInputs = frameState.prepareInputs(
      from: resolveContext,
      proposal: proposal
    )
    frameInputs.store(resolveInputs)
    resolveContext.frameInputs = frameInputs
    return resolveInputs
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
    if !hasExistingPresentationPortalRoot
      || !resolveInputs.usesSelectiveEvaluation
      || !resolveInputs.invalidatedIdentities.isEmpty
    {
      viewGraph.queueDirty([presentationPortalContext.identity])
    }

    return PresentationPortalPreparation(
      graphRootIdentity: presentationPortalContext.identity,
      draft: presentationPortalDraft
    )
  }

  private func resolveGraphHead(
    resolveContext: ResolveContext,
    graphDraft: ViewGraphFrameDraft,
    animationDraft: AnimationFrameDraft,
    canUseSelectiveEvaluation: Bool,
    clock: ContinuousClock
  ) -> (resolved: ResolvedNode, resolveDuration: Duration) {
    let (_, resolveDuration): (Void, Duration)
    animationDraft.controller.beginTransitionCollection()
    if canUseSelectiveEvaluation, !viewGraph.hasDirtyWork {
      // Nothing is dirty: keep the existing snapshot and leave root evaluator
      // registrations untouched for this frame.
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
    baseline: FrameHeadBaselineCheckpoints?
  ) -> FrameHeadCheckpoints? {
    switch mode {
    case .oneShot:
      return nil
    case .abortable:
      guard let baseline else {
        preconditionFailure("Abortable frame heads require baseline checkpoints.")
      }
      graphDraft.recordPreparedCheckpoint(from: viewGraph)
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
