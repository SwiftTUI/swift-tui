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
    let candidate = makeCompletedFrameCandidate(
      draft: draft,
      tailOutput: tailOutput,
      newestDesiredGeneration: newestDesiredGeneration,
      completedFramePolicy: completedFramePolicy,
      additionalBlockers: additionalBlockers,
      redundantHandlerInstallationsAreVisualOnly: redundantHandlerInstallationsAreVisualOnly
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
  func commitFrameEffects(
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
    draft.transaction.materializePreparedState()
    // Registration diagnostics are not propagated for elided frames; no FrameArtifacts is produced.
    _ = draft.transaction.commitElided()
    recordElidedFrame()
  }

  @MainActor
  func previewCompletedFrameCommit(
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
