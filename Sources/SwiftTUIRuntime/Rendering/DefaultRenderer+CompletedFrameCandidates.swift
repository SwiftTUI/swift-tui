import SwiftTUICore

extension DefaultRenderer {
  @MainActor
  func makeCompletedFrameCandidate(
    draft: FrameHeadDraft,
    tailOutput: AsyncFrameTailDraftOutput,
    newestDesiredGeneration: RenderGeneration,
    completedFramePolicy: CompletedFramePolicy? = nil,
    additionalBlockers:
      @MainActor @Sendable (FrameArtifacts) -> Set<FrameDropEligibility.Blocker> = { _ in [] },
    redundantHandlerInstallationsAreVisualOnly:
      @MainActor @Sendable (FrameArtifacts) -> Bool = { _ in false }
  ) -> CompletedFrameCandidate {
    let resolved = tailOutput.resolved
    let workerTimings = CommittedFrameArtifactBuilder.workerTimings(
      draft: draft,
      tailOutput: tailOutput
    )
    let preview = previewCompletedFrameCommit(
      draft: draft,
      tailOutput: tailOutput,
      resolved: resolved
    )
    let artifacts = CommittedFrameArtifactBuilder.makeCompletedFrameArtifacts(
      draft: draft,
      tailOutput: tailOutput,
      resolved: resolved,
      commit: preview.commit,
      commitDuration: preview.duration,
      workerTimings: workerTimings
    )
    let eligibility = CommittedFrameArtifactBuilder.eligibility(
      artifacts: artifacts,
      draft: draft,
      additionalBlockers: additionalBlockers(artifacts),
      redundantHandlerInstallationsAreVisualOnly:
        redundantHandlerInstallationsAreVisualOnly(artifacts)
    )
    return CompletedFrameCandidate(
      draft: draft,
      tailOutput: tailOutput,
      resolved: resolved,
      workerTimings: workerTimings,
      previewArtifacts: artifacts,
      previewLifecyclePlan: preview.lifecyclePlan,
      eligibility: eligibility,
      newestDesiredGeneration: newestDesiredGeneration,
      dropDecision: (completedFramePolicy ?? .dropCompletedVisualOnly).decide(
        candidateGeneration: draft.renderGeneration,
        newestDesiredGeneration: newestDesiredGeneration,
        eligibility: eligibility,
        consecutiveVisualOnlyDrops: visualOnlyDropRun.count
      )
    )
  }

  @MainActor
  func resolveCompletedFrameCandidate(
    draft: FrameHeadDraft,
    tailOutput: AsyncFrameTailDraftOutput,
    newestDesiredGeneration: RenderGeneration,
    completedFramePolicy: CompletedFramePolicy? = nil,
    additionalBlockers:
      @MainActor @Sendable (FrameArtifacts) -> Set<FrameDropEligibility.Blocker> = { _ in [] },
    redundantHandlerInstallationsAreVisualOnly:
      @MainActor @Sendable (FrameArtifacts) -> Bool = { _ in false }
  ) -> CompletedFrameCandidateResolution {
    // Stale-baseline guard: a sibling frame committed after this head's
    // baseline checkpoints were captured. Every candidate outcome from here —
    // the preview's materialize/suspend round-trip, an ordered commit
    // (materializing the stale prepared checkpoint), or a visual-only drop
    // (restoring the stale baseline) — would rewind that sibling's committed
    // effects: the checkpoint's whole-index restore evicts subtrees the
    // sibling minted, orphaning their running tasks and `@State` (the gallery
    // Life-tab revisit freeze). Skip before any checkpoint touch; the caller
    // replays the frame intent against the post-commit graph.
    if draft.transaction.baselineIsStale {
      draft.transaction.discard()
      return .skippedStaleBaseline(runtimeIssues: draft.runtimeIssues)
    }
    let candidate = makeCompletedFrameCandidate(
      draft: draft,
      tailOutput: tailOutput,
      newestDesiredGeneration: newestDesiredGeneration,
      completedFramePolicy: completedFramePolicy,
      additionalBlockers: additionalBlockers,
      redundantHandlerInstallationsAreVisualOnly: redundantHandlerInstallationsAreVisualOnly
    )
    if candidate.dropDecision.canSkipCompletedFrame {
      visualOnlyDropRun.recordDrop()
      discardCompletedFrameCandidate(
        candidate,
        reconciliation: candidate.dropDecision.reconciliation
      )
      return .dropped(
        runtimeIssues: candidate.previewArtifacts.diagnostics.runtime.issues,
        dropDecision: candidate.dropDecision
      )
    }
    visualOnlyDropRun.recordCommit()
    let artifacts = commitCompletedFrameCandidate(candidate)
    return .committed(artifacts, candidate.dropDecision)
  }

  @MainActor
  func commitCompletedFrameCandidate(
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
      workerCustomLayoutCacheUpdates: layout.workerCustomLayoutCacheUpdates,
      preview: (
        lifecyclePlan: candidate.previewLifecyclePlan,
        commitPlan: candidate.previewArtifacts.commitPlan
      )
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

  /// Commits a frame's graph and registration effects and produces its
  /// commit plan.
  ///
  /// When `preview` is supplied (the async ordered-commit path), the
  /// lifecycle plan and commit plan computed for the drop-eligibility
  /// preview are reused instead of recomputed: nothing runs on the main
  /// actor between preview and commit, `CommitPlanner.plan` is a pure
  /// function of inputs that are identical across the two calls, and
  /// `finalizeFrame` DEBUG-asserts the previewed lifecycle plan against a
  /// recompute (F61). The one-shot/sync path passes no preview and plans
  /// here as before.
  @MainActor
  func commitFrameEffects(
    draft: FrameHeadDraft,
    resolved: ResolvedNode,
    placed: PlacedNode,
    semantics: SemanticSnapshot,
    workerCustomLayoutCacheUpdates: [WorkerCustomLayoutCacheUpdate],
    preview: (lifecyclePlan: ViewGraphFrameLifecycleEventPlan, commitPlan: CommitPlan)? = nil
  ) -> CommittedFrameEffects {
    var runtimeRegistrationDiagnostics = RuntimeRegistrationDiagnostics()
    let (commit, commitDuration) = measurePhase(clock: draft.clock) {
      let lifecycleEvents = viewGraph.finalizeFrame(
        rootIdentity: draft.graphRootIdentity,
        resolved: resolved,
        placed: placed.viewportVisibilitySummary,
        previewedPlan: preview?.lifecyclePlan
      )
      runtimeRegistrationDiagnostics = commitFrameHeadDraftEffects(draft)
      if let preview {
        return preview.commitPlan
      }
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
      keeping: viewGraph.liveNodeIDSnapshot()
    )
    return CommittedFrameEffects(
      commitPlan: commit,
      commitDuration: commitDuration,
      runtimeRegistrationDiagnostics: runtimeRegistrationDiagnostics
    )
  }

  @MainActor
  func publishCommittedFrame(
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
      baselinePlacedTree: baselinePlacedTree,
      proposal: draft.frameTailInput.proposal
    )
    storeCommittedPresentationPortalState()
  }

  @MainActor
  func commitFrameHeadDraftEffects(
    _ draft: FrameHeadDraft
  ) -> RuntimeRegistrationDiagnostics {
    draft.transaction.commit()
  }

  /// Commits a prepared frame head for an ELIDED frame: fires deferred
  /// animation completions on real-time schedule and publishes the advanced
  /// animation/observation/portal/graph state to live — WITHOUT running the
  /// rendering tail (place → raster) or presenting a frame.
  ///
  /// Materializes prepared state first, mirroring
  /// ``commitCompletedFrameCandidate(_:)``: the abortable executor may have
  /// suspended prepared state during the animation-injection worker-snapshot
  /// branch, so the prepared head must be restored before the sub-drafts
  /// commit. After this returns the caller must NOT run the frame tail or
  /// present — ``FrameHeadTransaction/commitElided()`` has already advanced
  /// live state.
  @MainActor
  func commitElidedFrame(draft: FrameHeadDraft) {
    draft.transaction.measureElidedCommit {
      draft.transaction.materializePreparedState()
      // Registration diagnostics are not propagated for elided frames; no FrameArtifacts is produced.
      _ = draft.transaction.commitElided()
      recordElidedFrame()
    }
  }

  @MainActor
  func previewCompletedFrameCommit(
    draft: FrameHeadDraft,
    tailOutput: AsyncFrameTailDraftOutput,
    resolved: ResolvedNode
  ) -> (
    commit: CommitPlan, lifecyclePlan: ViewGraphFrameLifecycleEventPlan, duration: Duration
  ) {
    let tail = tailOutput.tail
    draft.transaction.materializePreparedState()
    defer {
      draft.transaction.suspendPreparedState()
    }

    let (planned, duration) = measurePhase(clock: draft.clock) {
      let lifecyclePlan = viewGraph.previewLifecycleEventPlan(
        resolved: resolved,
        placed: tail.placed.viewportVisibilitySummary
      )
      let commit = commitPlanner.plan(
        resolved: resolved,
        placed: tail.placed,
        semantics: tail.semantics,
        transaction: draft.frameContext.transaction,
        lifecycleEvents: lifecyclePlan.events
      )
      return (commit: commit, lifecyclePlan: lifecyclePlan)
    }
    return (commit: planned.commit, lifecyclePlan: planned.lifecyclePlan, duration: duration)
  }

  @MainActor
  func discardCompletedFrameCandidate(
    _ candidate: CompletedFrameCandidate,
    reconciliation: SkippedFrameReconciliation
  ) {
    precondition(reconciliation.isAvailableToRuntimePolicy)
    abortPreparedFrameHead(candidate.draft)
  }

  @MainActor
  func applyWorkerCustomLayoutCacheUpdates(
    _ updates: [WorkerCustomLayoutCacheUpdate]
  ) {
    for update in updates {
      update.apply()
    }
  }

  @MainActor
  func measurePhase<Value>(
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
}
