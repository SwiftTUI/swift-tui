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
      portal: portal,
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
    let rawInvalidatedIdentities = resolveInputs.invalidatedIdentities
    translatePresentationPortalInvalidations(
      in: &resolveInputs,
      contentRootIdentity: resolveContext.identity,
      portalRootIdentity: presentationPortalIdentity(for: resolveContext.identity)
    )
    // Diagnostic (inert unless SWIFTTUI_INVAL_TRACE): decompose how this frame's
    // invalidation set was assembled — raw scheduler set vs portal-translation
    // rewrite vs the force-root decision — to pin what injects an ancestor of a
    // reused subtree (e.g. the content root) on a presentation open/close.
    InvalidationSourceTrace.recordFrame(
      raw: rawInvalidatedIdentities,
      translated: resolveInputs.invalidatedIdentities,
      usesSelectiveEvaluation: resolveInputs.usesSelectiveEvaluation,
      disabledReasons: resolveInputs.selectiveEvaluationDisabledReasons.map(\.rawValue)
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
    if resolveInputs.usesSelectiveEvaluation {
      resolveInputs.selectiveEvaluationDisabledReasons = []
    } else if !translatedIdentities.contains(contentRootIdentity) {
      resolveInputs.selectiveEvaluationDisabledReasons.removeAll {
        $0 == .rootInvalidated
      }
    }
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
    // Fresh observation window per head attempt: declaration emitters report
    // every resolve into the live-state log, and the post-evaluation portal
    // escalation reads it (see `resolveGraphHead`). The observer rides the
    // propagated context so evaluator closures captured on earlier frames
    // keep reporting into the current frame's log.
    presentationPortalState.triggerObservations.reset()
    resolveContext.presentationTriggerObserver = presentationPortalState.triggerObservations
    viewGraph.beginFrame()
    if resolveInputs.usesSelectiveEvaluation {
      viewGraph.invalidateAndQueueDirty(resolveInputs.invalidatedIdentities)
      queueRetainedReuseSuppressionScope(resolveInputs.retainedReuseSuppressionScope)
    } else {
      viewGraph.invalidate(resolveInputs.invalidatedIdentities)
    }
    resolveContext.viewGraph = viewGraph
    return resolveContext.observationBridge?.makeDraft(
      attaching: viewGraph
    )
  }

  private func queueRetainedReuseSuppressionScope(
    _ scope: RetainedReuseSuppressionScope
  ) {
    guard !scope.isEmpty,
      !scope.suppressesAll
    else {
      return
    }
    viewGraph.invalidateAndQueueDirtyDescendants(of: scope.identities)
  }

  /// Whether this frame's narrow evaluation may have changed the
  /// overlay-entry set, requiring the portal root to re-reconcile:
  ///
  /// - an emitter observed ACTIVE (open, or item change while presented —
  ///   conservative: re-reconciling an unchanged declaration is idempotent),
  /// - an emitter observed INACTIVE whose source is still declared (close),
  /// - a declared source whose graph node departed this frame (prune —
  ///   the emitter is gone, so no observation can report the close).
  private func presentationPortalRequiresReconcileEscalation(
    portal: PresentationPortalPreparation
  ) -> Bool {
    let observations = presentationPortalState.triggerObservations.observations
    let declaredSources = portal.draft.declaredSourceIdentities()
    if observations.contains(where: { observation in
      observation.isActive || declaredSources.contains(observation.sourceIdentity)
    }) {
      return true
    }
    guard !declaredSources.isEmpty else {
      return false
    }
    return declaredSources.contains { !viewGraph.containsNode(for: $0) }
  }

  private func escalateToPresentationPortalReconcile(
    portal: PresentationPortalPreparation,
    graphDraft: ViewGraphFrameDraft,
    resolveInputs: FrameResolveInputs
  ) {
    viewGraph.queueDirty([portal.graphRootIdentity])
    let escalation:
      (
        plan: DirtyEvaluationPlan?,
        diagnostics: DirtyEvaluationPlanDiagnostics?
      )
    if RuntimeRegistrationPublicationDiagnosticsConfiguration.isEnabled {
      let evaluation = viewGraph.selectiveDirtyEvaluationPlanWithDiagnostics(
        invalidatedIdentities: resolveInputs.invalidatedIdentities
      )
      escalation = (evaluation.plan, evaluation.diagnostics)
    } else {
      escalation = (viewGraph.selectiveDirtyEvaluationPlan(), nil)
    }
    // Accumulates onto the first plan's publication roots; a nil escalation
    // plan falls back to `.all` and the full root evaluation below.
    graphDraft.recordDirtyEvaluationPlan(
      escalation.plan,
      diagnostics: escalation.diagnostics
    )
    graphDraft.recordPresentationPortalEscalation()
    _ = viewGraph.evaluateDirtyNodes(using: escalation.plan)
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
    // F08 step 4: a selective frame with invalidations no longer queues the
    // portal root eagerly (the removed third condition,
    // `!resolveInputs.invalidatedIdentities.isEmpty`, made every interaction
    // frame's frontier root-rooted). Declarative activation flips are
    // observed by the declaration emitters during subtree evaluation and
    // escalate to a portal-root re-resolve after the narrow plan runs
    // (`escalateToPresentationPortalReconcile`), so open/close/prune keep
    // their same-frame semantics. Stale overlay-entry identities that the
    // portal translation leaves unmapped resolve onto their nearest live
    // ancestor at the queue boundary (`ViewGraph.nodeIDsForInvalidation`,
    // F10 slice 1) — for an absent overlay host that is the portal root
    // itself, whose re-resolve recomposes the overlay.
    let shouldQueuePresentationPortalRoot =
      !hasExistingPresentationPortalRoot
      || !resolveInputs.usesSelectiveEvaluation
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
    portal: PresentationPortalPreparation,
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
              invalidatedIdentities: resolveInputs.invalidatedIdentities,
              selectiveEvaluationDisabledReasons: resolveInputs
                .diagnosticSelectiveEvaluationDisabledReasonNames
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
          _ = viewGraph.evaluateDirtyNodes(
            using: dirtyEvaluationPlan
          )
          // Portal reconcile escalation: a narrow plan cannot consume the
          // presentation declaration preference (only the portal root's own
          // resolve reconciles it), so when this frame's emitter
          // observations — or a departed declared source — prove the
          // overlay-entry set may have changed, re-evaluate from the portal
          // root within the same frame. The accumulated `.subtrees`
          // publication becomes root-rooted and routes onto the
          // fingerprint-delta commit body.
          if dirtyEvaluationPlan != nil,
            !portal.queuedRoot,
            presentationPortalRequiresReconcileEscalation(portal: portal)
          {
            escalateToPresentationPortalReconcile(
              portal: portal,
              graphDraft: graphDraft,
              resolveInputs: resolveInputs
            )
          }
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
