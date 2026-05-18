import SwiftTUICore
import SwiftTUIViews

package struct FocusSyncRerenderBudget: Equatable, Sendable {
  package let maximumRerenders: Int
  package private(set) var rerenderCount: Int

  package init(maximumRerenders: Int) {
    precondition(maximumRerenders > 0)
    self.maximumRerenders = maximumRerenders
    rerenderCount = 0
  }

  /// Derives the convergence budget from the semantic graph that can
  /// participate in focus/scroll synchronization. Each rerender must be
  /// justified by a visible sync candidate, plus one final pass to confirm the
  /// synchronized tree.
  package static func derived(from semanticSnapshot: SemanticSnapshot) -> Self {
    let syncCandidateCount =
      semanticSnapshot.focusRegions.count
      + semanticSnapshot.scrollRoutes.count
      + semanticSnapshot.scrollTargets.count
      + semanticSnapshot.accessibilityNodes.count
    return Self(maximumRerenders: max(1, syncCandidateCount + 1))
  }

  package mutating func expandIfNeeded(for semanticSnapshot: SemanticSnapshot) {
    let derived = Self.derived(from: semanticSnapshot)
    guard derived.maximumRerenders > maximumRerenders else {
      return
    }
    self = Self(
      maximumRerenders: derived.maximumRerenders,
      rerenderCount: rerenderCount
    )
  }

  private init(
    maximumRerenders: Int,
    rerenderCount: Int
  ) {
    precondition(maximumRerenders > 0)
    self.maximumRerenders = maximumRerenders
    self.rerenderCount = rerenderCount
  }

  /// Returns `true` when another focus-sync rerender is still allowed.
  package mutating func recordRerender() -> Bool {
    rerenderCount += 1
    return rerenderCount < maximumRerenders
  }
}

extension RunLoop {
  package struct RenderIntentCoalescingDiagnostics: Equatable, Sendable {
    package var desiredGeneration: UInt64
    package var coalescedEventBatches: Int
    package var coalescedWakeCauses: Set<WakeCause>
    /// Number of `request*` calls (input, invalidation, signal,
    /// external, deadline) the scheduler coalesced into the active
    /// frame.  When > 1, multiple intents merged — a Stage 3D
    /// pre-start cancellation could have superseded the older
    /// in-flight tail job.
    package var intentRequestCount: Int
  }

  private enum AnimationWakeTiming {
    // When a frame overruns its nominal 33 ms budget, the controller's
    // requested deadline can already be in the past by the time the
    // run loop reaches the scheduling site below. Re-queuing an already
    // due deadline would make `renderPendingFrames` spin inside the same
    // call; failing to schedule anything would stall the animation until
    // unrelated input arrives. Clamp overdue deadlines slightly into the
    // future so the next tick runs "as soon as possible" on the next
    // event-loop turn without busy-looping in-place.
    static var minimumLeadTime: Duration { .milliseconds(1) }
  }

  package func nextRenderIntentDiagnostics(
    for scheduledFrame: ScheduledFrame
  ) -> RenderIntentCoalescingDiagnostics {
    defer {
      nextRenderIntentGeneration &+= 1
      pendingCoalescedEventBatches = 0
      pendingCoalescedWakeCauses.removeAll(keepingCapacity: true)
    }

    return RenderIntentCoalescingDiagnostics(
      desiredGeneration: nextRenderIntentGeneration,
      coalescedEventBatches: pendingCoalescedEventBatches,
      coalescedWakeCauses: pendingCoalescedWakeCauses.union(scheduledFrame.causes),
      intentRequestCount: scheduledFrame.intentRequestCount
    )
  }

  package func formattedWakeCauses(
    _ causes: Set<WakeCause>
  ) -> String {
    let values = causes.map(\.rawValue).sorted()
    return values.isEmpty ? "-" : values.joined(separator: "+")
  }

  private func appendLifecycleCarryForward(
    _ lifecycle: [LifecycleCommitEntry],
    into carryForward: inout [LifecycleCommitEntry]
  ) {
    for entry in lifecycle where !carryForward.contains(entry) {
      carryForward.append(entry)
    }
  }

  private func mergeLifecycleCarryForward(
    _ carryForward: [LifecycleCommitEntry],
    into lifecycle: inout [LifecycleCommitEntry]
  ) {
    guard !carryForward.isEmpty else {
      return
    }
    let retainedCurrent = lifecycle.filter { !carryForward.contains($0) }
    lifecycle = carryForward + retainedCurrent
  }

  // MARK: - Frame driver (F2: unified sync/async per-frame body, ADR-0021)

  /// Accumulated focus/scroll convergence state threaded through the
  /// focus-sync rerender loop and into the shared post-acquisition body.
  private struct FocusSyncConvergenceState {
    var rerenderedForFocusSync = false
    var budget: FocusSyncRerenderBudget?
    var budgetExceeded = false
    var focusGraphChanged = false
    var focusBindingChanged = false
    var focusedValuesChanged = false
    var scrollPositionChanged = false
    var lifecycleCarryForward: [LifecycleCommitEntry] = []

    var rerenderCount: Int {
      budget?.rerenderCount ?? 0
    }

    mutating func recordRerender(for semanticSnapshot: SemanticSnapshot) -> Bool {
      if budget == nil {
        budget = .derived(from: semanticSnapshot)
      } else {
        budget?.expandIfNeeded(for: semanticSnapshot)
      }
      return budget?.recordRerender() ?? false
    }
  }

  /// Result of processing one rendered tree inside the focus-sync loop:
  /// whether the runtime must rerender to converge, and (when it must not)
  /// the final artifacts to commit.
  private enum FocusSyncIterationOutcome {
    /// The rendered tree changed focus/scroll state — rerender to converge.
    case rerender
    /// The rendered tree is converged; commit it.
    case converged
  }

  /// Strategy state describing how the async path acquired a frame; the
  /// synchronous path always supplies `.completed` / `nil`.
  private struct FrameAcquisitionState {
    var tailJobState: FrameTailJobState = .completed
    var completedFrameDropDecision: CompletedFrameDropDecision?
  }

  private func scheduledFrameByReconcilingExternalState(
    _ scheduledFrame: ScheduledFrame,
    currentState: State
  ) -> ScheduledFrame {
    guard previousRenderedState != currentState else {
      return scheduledFrame
    }
    var reconciled = scheduledFrame
    reconciled.causes.insert(.invalidation)
    reconciled.invalidatedIdentities.insert(rootIdentity)
    reconciled.forceRootEvaluation = true
    return reconciled
  }

  package func renderPendingFrames(renderedFrames: inout Int) throws {
    observationBridge.attachInvalidator(scheduler)

    let hasDiagnosticsLogger = diagnosticsLogger != nil
    while var scheduledFrame = scheduler.consumeReadyFrame(at: .now()) {
      let currentState = stateContainer.state
      scheduledFrame = scheduledFrameByReconcilingExternalState(
        scheduledFrame,
        currentState: currentState
      )
      let renderIntentDiagnostics = nextRenderIntentDiagnostics(for: scheduledFrame)
      progressProbe?.record(
        .frameIntent,
        frameNumber: renderedFrames + 1,
        desiredGeneration: renderIntentDiagnostics.desiredGeneration,
        coalescedEventBatches: renderIntentDiagnostics.coalescedEventBatches
      )
      drainGestureDeadlinesIfNeeded(for: scheduledFrame)
      var convergence = FocusSyncConvergenceState()
      convergence.lifecycleCarryForward = deferredLifecycleCarryForward
      deferredLifecycleCarryForward.removeAll(keepingCapacity: true)

      var artifacts: FrameArtifacts?
      while true {
        if convergence.rerenderedForFocusSync {
          renderer.forceRootEvaluation()
        }
        let renderedArtifacts = renderer.render(
          viewBuilder(
            (
              state: currentState,
              focusedIdentity: focusTracker.currentFocusIdentity
            )),
          context: resolveContext(for: scheduledFrame),
          proposal: proposal()
        )
        artifacts = renderedArtifacts
        let outcome = try processFocusSyncIteration(
          renderedArtifacts,
          convergence: &convergence
        )
        switch outcome {
        case .rerender:
          if convergence.budgetExceeded {
            break
          }
          continue
        case .converged:
          break
        }
        break
      }

      guard let artifacts else {
        preconditionFailure("Focus synchronization produced no frame artifacts.")
      }
      try applyAcquiredFrame(
        artifacts,
        scheduledFrame: scheduledFrame,
        renderIntentDiagnostics: renderIntentDiagnostics,
        convergence: convergence,
        acquisition: FrameAcquisitionState(),
        hasDiagnosticsLogger: hasDiagnosticsLogger,
        renderedFrames: &renderedFrames
      )
      previousRenderedState = currentState
    }
    progressProbe?.record(.schedulerIdle, frameNumber: renderedFrames)
  }

  /// Drains gesture recognizer deadlines for a frame woken by a `.deadline`
  /// cause so recognizers that transition on this wake see their new phase
  /// reflected in the upcoming render pass.
  private func drainGestureDeadlinesIfNeeded(for scheduledFrame: ScheduledFrame) {
    guard scheduledFrame.causes.contains(.deadline) else {
      return
    }
    if let triggeredDeadline = scheduledFrame.triggeredDeadline {
      drainGestureDeadlines(at: triggeredDeadline)
    } else {
      assertionFailure(
        "FrameScheduler produced .deadline cause without a triggeredDeadline; "
          + "gesture deadlines will not drain this frame."
      )
    }
  }

  /// Shared per-iteration body of the focus-sync convergence loop. Applies
  /// the side effects that must run for every rendered tree (snapshot
  /// publication, gesture pruning, pointer-hover mode, pointer-capture
  /// release, focus/scroll/focused-value sync) and folds the resulting
  /// change flags into `convergence`. Returns whether the runtime must
  /// rerender to converge.
  private func processFocusSyncIteration(
    _ renderedArtifacts: FrameArtifacts,
    convergence: inout FocusSyncConvergenceState
  ) throws -> FocusSyncIterationOutcome {
    latestSemanticSnapshot = renderedArtifacts.semanticSnapshot
    runtimeRegistrations.pruneOrphanedGestures(
      keeping: renderer.liveIdentitySnapshot()
    )
    try updateTerminalPointerHoverModeIfNeeded()

    // Release pointer capture if the captured region disappeared from
    // the rendered tree (e.g. a view with an active gesture was removed
    // mid-interaction).
    if let capturedID = capturedPointerRouteID,
      interactionRegion(routeID: capturedID) == nil
    {
      capturedPointerRouteID = nil
      armedPointerRouteID = nil
      armedPointerRouteUsesPointerHandler = false
    }
    if let hoveredPointerRouteID,
      interactionRegion(routeID: hoveredPointerRouteID) == nil
    {
      self.hoveredPointerRouteID = nil
    }

    let shouldApplyInitialDefaultFocus =
      focusTracker.currentFocusIdentity == nil && !focusTracker.isPreservingNoFocus
    let focusChanged = focusTracker.updateRegions(
      renderedArtifacts.semanticSnapshot.focusRegions)
    let desiredFocusRequest = localFocusBindingRegistry.desiredFocusRequest(
      allowedIdentities: Set(renderedArtifacts.semanticSnapshot.focusRegions.map(\.identity))
    )
    let appliedFocusRequest = applyDesiredFocusRequest(desiredFocusRequest)
    let defaultFocusRequest = localDefaultFocusRegistry.desiredFocusRequest(
      focusRegions: renderedArtifacts.semanticSnapshot.focusRegions,
      shouldApplyInitialDefault: desiredFocusRequest == .none && shouldApplyInitialDefaultFocus
    )
    let appliedDefaultFocusRequest = applyDesiredFocusRequest(defaultFocusRequest)
    let focusStateChanged = localFocusBindingRegistry.sync(
      actualFocusedIdentity: focusTracker.currentFocusIdentity
    )
    let resolvedFocusedValues = localFocusedValuesRegistry.focusedValues(
      for: focusTracker.currentFocusIdentity,
      in: renderedArtifacts.resolvedTree
    )
    let focusedValuesChanged = resolvedFocusedValues != currentFocusedValues
    if focusedValuesChanged {
      currentFocusedValues = resolvedFocusedValues
    }
    let scrollPositionChanged = localScrollPositionRegistry.sync(
      focusedIdentity: focusTracker.currentFocusIdentity,
      focusRegions: renderedArtifacts.semanticSnapshot.focusRegions,
      scrollRoutes: renderedArtifacts.semanticSnapshot.scrollRoutes,
      scrollTargets: renderedArtifacts.semanticSnapshot.scrollTargets,
      accessibilityNodes: renderedArtifacts.semanticSnapshot.accessibilityNodes
    )
    convergence.focusGraphChanged = convergence.focusGraphChanged || focusChanged
    convergence.focusBindingChanged =
      convergence.focusBindingChanged || appliedFocusRequest || appliedDefaultFocusRequest
      || focusStateChanged
    convergence.focusedValuesChanged =
      convergence.focusedValuesChanged || focusedValuesChanged
    convergence.scrollPositionChanged =
      convergence.scrollPositionChanged || scrollPositionChanged

    if focusChanged || appliedFocusRequest || appliedDefaultFocusRequest || focusStateChanged
      || focusedValuesChanged || scrollPositionChanged
    {
      appendLifecycleCarryForward(
        renderedArtifacts.commitPlan.lifecycle,
        into: &convergence.lifecycleCarryForward
      )
      convergence.rerenderedForFocusSync = true
      if !convergence.recordRerender(for: renderedArtifacts.semanticSnapshot) {
        convergence.budgetExceeded = true
      }
      return .rerender
    }
    return .converged
  }

  /// Shared post-acquisition per-frame body. Both `renderPendingFrames` and
  /// `renderPendingFramesAsync` delegate to this once their (differing)
  /// artifact-acquisition strategy has produced a converged frame. Every
  /// line here is classified `structural` in ADR-0021: lifecycle
  /// carry-forward merge, accessibility announcements, focus presentation,
  /// frame presentation, preference-observation reconciliation,
  /// animation-deadline rescheduling, observation pruning, and the full
  /// `FrameDiagnosticRecord` construction.
  private func applyAcquiredFrame(
    _ acquiredArtifacts: FrameArtifacts,
    scheduledFrame: ScheduledFrame,
    renderIntentDiagnostics: RenderIntentCoalescingDiagnostics,
    convergence: FocusSyncConvergenceState,
    acquisition: FrameAcquisitionState,
    hasDiagnosticsLogger: Bool,
    renderedFrames: inout Int
  ) throws {
    var artifacts = acquiredArtifacts
    reportRuntimeIssues(artifacts.diagnostics.runtime.issues)
    mergeLifecycleCarryForward(
      convergence.lifecycleCarryForward,
      into: &artifacts.commitPlan.lifecycle
    )
    appendPendingAccessibilityAnnouncements(to: &artifacts)
    latestSemanticSnapshot = artifacts.semanticSnapshot
    if convergence.budgetExceeded {
      let causes = scheduledFrame.causes.map(\.rawValue).sorted().joined(separator: "+")
      assertionFailure(
        "Focus synchronization did not converge after \(convergence.rerenderCount) rerenders for frame causes \(causes). The rerender budget was derived from the frame semantic graph."
      )
    }

    let focusPresentation = artifacts.semanticSnapshot.focusPresentation(
      for: focusTracker.currentFocusIdentity
    )
    let presentationDamage: PresentationDamage? =
      if convergence.rerenderedForFocusSync {
        nil
      } else {
        artifacts.presentationDamage
      }
    let presentStart: ContinuousClock.Instant?
    let presentClock: ContinuousClock?
    if hasDiagnosticsLogger {
      let clock = ContinuousClock()
      presentClock = clock
      presentStart = clock.now
    } else {
      presentClock = nil
      presentStart = nil
    }
    let presentationMetrics = try presentCommittedFrame(
      artifacts,
      damage: presentationDamage
    )
    let presentationDuration: Duration =
      if let presentStart, let presentClock {
        presentStart.duration(to: presentClock.now)
      } else {
        .zero
      }
    lifecycleCoordinator.applyCommittedFrame(
      plan: artifacts.commitPlan,
      currentLifecycleRegistry: localLifecycleRegistry,
      currentTaskRegistry: localTaskRegistry
    )
    updateFocusPresentation(focusPresentation)
    let preferenceObservationChanged = localPreferenceObservationRegistry.applyChanges(
      since: previousPreferenceObservations
    )
    previousPreferenceObservations = localPreferenceObservationRegistry.snapshot()
    if !postActionInvalidationIdentities.isEmpty {
      scheduler.requestInvalidation(of: postActionInvalidationIdentities)
      postActionInvalidationIdentities.removeAll(keepingCapacity: true)
    }
    // After rendering, request the next animation frame deadline
    // whenever the tick reported pending work.  Phase 4 split the
    // tick result so ``hasPendingWork`` is the unambiguous "schedule
    // another frame" signal — including for stranded-batch drains
    // that aren't tied to any visible identity.
    //
    // The viewport gate that used to guard this path
    // (``redrawIdentities.isDisjoint(with: drawnIdentities)``) is
    // gone: its purpose was to quiesce ticks driving animations into
    // clipped subtrees, but the gate had a one-way trap — once a
    // tick produced an empty redraw set the only thing that could
    // restart the loop was another tick.  ``redrawIdentities`` is
    // still consulted by the incremental presentation diff for
    // dirty-region calculation; only the wake-up decision is
    // unconditional now.
    let animationTick = renderer.internalAnimationController.lastTickResult
    if runtimeConfiguration.motion == .normal,
      animationTick.hasPendingWork,
      let nextDeadline = animationTick.nextDeadline
    {
      let now = MonotonicInstant.now()
      let scheduledDeadline =
        if nextDeadline > now {
          nextDeadline
        } else {
          now.advanced(by: AnimationWakeTiming.minimumLeadTime)
        }
      scheduler.requestDeadline(scheduledDeadline)
    }
    observationBridge.prune(
      keeping: renderer.liveIdentitySnapshot()
    )
    renderedFrames += 1
    progressProbe?.record(
      .frameCommitted,
      frameNumber: renderedFrames,
      desiredGeneration: renderIntentDiagnostics.desiredGeneration,
      renderGeneration: artifacts.diagnostics.timing.renderGenerations.render.rawValue,
      tailJobState: acquisition.tailJobState
    )

    if let diagnosticsLogger {
      let diag = artifacts.diagnostics
      let damageDiagnostics = diag.presentation.damage
      let geometryDiagnostics = diag.geometryResolutionDiagnostics
      let cacheMetrics = diag.work.measurementCache
      let cacheHitRate: Double? =
        if let cacheMetrics, cacheMetrics.lookups > 0 {
          Double(cacheMetrics.hits) / Double(cacheMetrics.lookups)
        } else {
          nil
        }
      let pipelineTotal = diag.timing.phaseTimings?.total ?? .zero
      let causeSummary = scheduledFrame.causes
        .map(\.rawValue)
        .sorted()
        .joined(separator: "+")
      let inputEventsQueuedDuringRenderSuspension =
        renderSuspensionDiagnostics.drainInputEventsQueuedDuringSuspension()
      let dropEligibilityBlockers = frameDropEligibilityBlockers(
        artifacts: artifacts,
        scheduledFrame: scheduledFrame,
        focusGraphChanged: convergence.focusGraphChanged,
        focusBindingChanged: convergence.focusBindingChanged,
        focusedValuesChanged: convergence.focusedValuesChanged,
        scrollPositionChanged: convergence.scrollPositionChanged,
        preferenceObservationChanged: preferenceObservationChanged,
        diagnosticsRequireFullRecord: true
      )
      diagnosticsLogger.log(
        FrameDiagnosticRecord(
          frameNumber: renderedFrames,
          causeSummary: causeSummary,
          focusSyncRerenders: convergence.rerenderCount,
          invalidatedIdentityCount: diag.input.invalidatedIdentities.count,
          resolvedNodeCount: diag.counts.resolvedNodes,
          resolvedNodesComputed: diag.work.resolvedNodesComputed,
          resolvedNodesReused: diag.work.resolvedNodesReused,
          measuredNodeCount: diag.counts.measuredNodes,
          measuredNodesComputed: diag.work.measuredNodesComputed,
          measuredNodesReused: diag.work.measuredNodesReused,
          placedNodeCount: diag.counts.placedNodes,
          drawNodeCount: diag.counts.drawNodes,
          interactionRegionCount: diag.counts.interactionRegions,
          focusRegionCount: diag.counts.focusRegions,
          phaseTimings: diag.timing.phaseTimings,
          renderGenerations: diag.timing.renderGenerations,
          desiredGeneration: renderIntentDiagnostics.desiredGeneration,
          coalescedEventBatches: renderIntentDiagnostics.coalescedEventBatches,
          coalescedWakeCauses: formattedWakeCauses(
            renderIntentDiagnostics.coalescedWakeCauses
          ),
          coalescedIntentRequests: renderIntentDiagnostics.intentRequestCount,
          scheduledAnimationRequest: formattedAnimationRequest(
            scheduledFrame.animationRequest
          ),
          scheduledAnimationBatchID: scheduledFrame.animationBatchID?.value,
          animationControllerActiveAnimationCount: renderer
            .internalAnimationController.activeAnimationCount,
          animationControllerHasPendingWork: animationTick.hasPendingWork,
          workerTimings: diag.timing.workerTimings,
          mainActorTimings: diag.timing.mainActorTimings,
          customLayoutFallbackCount: diag.work.customLayoutFallbackCount,
          firstCustomLayoutFallbackIdentity: diag.work.firstCustomLayoutFallbackIdentity?.path,
          layoutDependentRealizations: diag.work.layoutDependentRealizations,
          layoutDependentRealizationCacheHits: diag.work.layoutDependentRealizationCacheHits,
          layoutDependentMainActorFallbacks: diag.work.layoutDependentMainActorFallbacks,
          geometryAnchorResolutionMissCount: geometryDiagnostics.anchorResolutionMissCount,
          firstGeometryAnchorResolutionMissIdentity: geometryDiagnostics
            .firstAnchorResolutionMissIdentity?.path,
          geometryMissingNamedCoordinateSpaceCount: geometryDiagnostics
            .missingNamedCoordinateSpaceCount,
          firstGeometryMissingNamedCoordinateSpaceName: geometryDiagnostics
            .firstMissingNamedCoordinateSpaceName,
          geometryDuplicateNamedCoordinateSpaceCount: geometryDiagnostics
            .duplicateNamedCoordinateSpaceCount,
          firstGeometryDuplicateNamedCoordinateSpaceName: geometryDiagnostics
            .firstDuplicateNamedCoordinateSpaceName,
          runtimePointerHandlerCount: diag.runtime.registrations.pointerHandlerCount,
          runtimePointerHoverHandlerCount: diag.runtime.registrations.pointerHoverHandlerCount,
          runtimeGestureRecognizerCount: diag.runtime.registrations.gestureRecognizerCount,
          runtimeGestureStateBindingCount: diag.runtime.registrations.gestureStateBindingCount,
          runtimeIssues: diag.runtime.issues,
          staleFramePolicy: "commit_ordered",
          tailJobState: acquisition.tailJobState.rawValue,
          tailCancelReason: "-",
          cancelledRenderCount: cancelledRenderCount,
          newestDesiredAtTailStart: renderIntentDiagnostics.desiredGeneration,
          newestDesiredAtTailResult: renderIntentDiagnostics.desiredGeneration,
          dropEligibilityBlockers: dropEligibilityBlockers,
          dropDecision: acquisition.completedFrameDropDecision?.action.rawValue
            ?? CompletedFrameDropDecision.Action.commitOrdered.rawValue,
          dropGeneration: nil,
          newestDesiredAtDrop: nil,
          dropReconciliationMode: acquisition.completedFrameDropDecision?.reconciliation.mode
            .rawValue ?? "-",
          dropReconciliationEffects: acquisition.completedFrameDropDecision?.reconciliation
            .effectSummary ?? "-",
          presentationRecoveryAfterDrop: false,
          inputEventsQueuedDuringRenderSuspension:
            inputEventsQueuedDuringRenderSuspension,
          presentationStrategy: presentationMetrics.strategy == .fullRepaint
            ? "full" : "incremental",
          presentationBytesWritten: presentationMetrics.bytesWritten,
          presentationLinesTouched: presentationMetrics.linesTouched,
          presentationCellsChanged: presentationMetrics.cellsChanged,
          presentationDuration: presentationDuration,
          damageRowCount: damageDiagnostics?.textRowCount,
          damageRangeAwareRowCount: damageDiagnostics?.rangeAwareTextRowCount,
          damageTextSpanCount: damageDiagnostics?.textSpanCount,
          damageTextCellCount: damageDiagnostics?.textCellCount,
          damageGraphicsInvalidationCount: damageDiagnostics?.graphicsInvalidationCount,
          damageRequiresFullTextRepaint: damageDiagnostics?.requiresFullTextRepaint ?? false,
          damageRequiresFullGraphicsReplay: damageDiagnostics?.requiresFullGraphicsReplay
            ?? false,
          presentationUsedSynchronizedOutput: presentationMetrics.usedSynchronizedOutput,
          presentationGraphicsReplayScope: presentationMetrics.graphicsReplayScope.rawValue,
          presentationGraphicsAttachmentsReplayed: presentationMetrics
            .graphicsAttachmentsReplayed,
          presentationEditOperationLowering: presentationMetrics.editOperationLowering.rawValue,
          presentationEditOperationCount: presentationMetrics.editOperationCount,
          measurementCacheHitRate: cacheHitRate,
          totalFrameDuration: pipelineTotal + presentationDuration
        )
      )
    }

    if let transientPressedIdentity,
      transientPressedIdentity == pressedIdentity
    {
      self.transientPressedIdentity = nil
      setPressedIdentity(nil, transient: false)
    }
  }

  package func updateTerminalPointerHoverModeIfNeeded() throws {
    let shouldEnable = localPointerHandlerRegistry.hasHoverSubscribers
    guard shouldEnable != terminalPointerHoverEnabled else {
      return
    }
    if let terminalCommandSurface =
      presentationSurface as? any TerminalCommandPresentationSurface
    {
      try terminalCommandSurface.setPointerHoverEnabled(shouldEnable)
    }
    terminalPointerHoverEnabled = shouldEnable
  }

  @MainActor
  private func logCancelledFrameTail(
    diagnosticsLogger: FrameDiagnosticsLogger?,
    renderedFrames: Int,
    scheduledFrame: ScheduledFrame,
    renderIntentDiagnostics: RenderIntentCoalescingDiagnostics,
    renderGeneration: RenderGeneration,
    runtimeIssues: [RuntimeIssue],
    tailJobState: FrameTailJobState,
    tailCancelReason: String,
    animationControllerActiveAnimationCount: Int,
    animationControllerHasPendingWork: Bool
  ) {
    guard let diagnosticsLogger else {
      return
    }
    let causeSummary = scheduledFrame.causes
      .map(\.rawValue)
      .sorted()
      .joined(separator: "+")
    diagnosticsLogger.log(
      FrameDiagnosticRecord(
        frameNumber: renderedFrames + 1,
        causeSummary: causeSummary,
        focusSyncRerenders: 0,
        invalidatedIdentityCount: scheduledFrame.invalidatedIdentities.count,
        resolvedNodeCount: 0,
        resolvedNodesComputed: 0,
        resolvedNodesReused: 0,
        measuredNodeCount: 0,
        measuredNodesComputed: 0,
        measuredNodesReused: 0,
        placedNodeCount: 0,
        drawNodeCount: 0,
        interactionRegionCount: 0,
        focusRegionCount: 0,
        phaseTimings: nil,
        renderGenerations: .init(render: renderGeneration),
        desiredGeneration: renderIntentDiagnostics.desiredGeneration,
        coalescedEventBatches: renderIntentDiagnostics.coalescedEventBatches,
        coalescedWakeCauses: formattedWakeCauses(
          renderIntentDiagnostics.coalescedWakeCauses
        ),
        coalescedIntentRequests: renderIntentDiagnostics.intentRequestCount,
        scheduledAnimationRequest: formattedAnimationRequest(
          scheduledFrame.animationRequest
        ),
        scheduledAnimationBatchID: scheduledFrame.animationBatchID?.value,
        animationControllerActiveAnimationCount: animationControllerActiveAnimationCount,
        animationControllerHasPendingWork: animationControllerHasPendingWork,
        workerTimings: nil,
        mainActorTimings: nil,
        customLayoutFallbackCount: 0,
        firstCustomLayoutFallbackIdentity: nil,
        layoutDependentRealizations: 0,
        layoutDependentRealizationCacheHits: 0,
        layoutDependentMainActorFallbacks: 0,
        geometryAnchorResolutionMissCount: 0,
        firstGeometryAnchorResolutionMissIdentity: nil,
        geometryMissingNamedCoordinateSpaceCount: 0,
        firstGeometryMissingNamedCoordinateSpaceName: nil,
        geometryDuplicateNamedCoordinateSpaceCount: 0,
        firstGeometryDuplicateNamedCoordinateSpaceName: nil,
        runtimePointerHandlerCount: 0,
        runtimePointerHoverHandlerCount: 0,
        runtimeGestureRecognizerCount: 0,
        runtimeGestureStateBindingCount: 0,
        runtimeIssues: runtimeIssues,
        staleFramePolicy: "cancel_pending_before_start",
        tailJobState: tailJobState.rawValue,
        tailCancelReason: tailCancelReason,
        cancelledRenderCount: cancelledRenderCount,
        newestDesiredAtTailStart: renderIntentDiagnostics.desiredGeneration,
        newestDesiredAtTailResult: nextRenderIntentGeneration,
        dropEligibilityBlockers: [],
        dropDecision: "-",
        dropGeneration: nil,
        newestDesiredAtDrop: nil,
        dropReconciliationMode: "-",
        dropReconciliationEffects: "-",
        presentationRecoveryAfterDrop: false,
        inputEventsQueuedDuringRenderSuspension:
          renderSuspensionDiagnostics
          .drainInputEventsQueuedDuringSuspension(),
        presentationStrategy: "-",
        presentationBytesWritten: 0,
        presentationLinesTouched: 0,
        presentationCellsChanged: 0,
        presentationDuration: .zero,
        damageRowCount: nil,
        damageRangeAwareRowCount: nil,
        damageTextSpanCount: nil,
        damageTextCellCount: nil,
        damageGraphicsInvalidationCount: nil,
        damageRequiresFullTextRepaint: false,
        damageRequiresFullGraphicsReplay: false,
        presentationUsedSynchronizedOutput: false,
        presentationGraphicsReplayScope: "-",
        presentationGraphicsAttachmentsReplayed: 0,
        presentationEditOperationLowering: "-",
        presentationEditOperationCount: 0,
        measurementCacheHitRate: nil,
        totalFrameDuration: .zero
      )
    )
  }

  @MainActor
  private func logDroppedCompletedFrame(
    diagnosticsLogger: FrameDiagnosticsLogger?,
    renderedFrames: Int,
    scheduledFrame: ScheduledFrame,
    renderIntentDiagnostics: RenderIntentCoalescingDiagnostics,
    renderGeneration: RenderGeneration,
    newestDesiredGeneration: RenderGeneration,
    decision: CompletedFrameDropDecision?,
    runtimeIssues: [RuntimeIssue],
    animationControllerActiveAnimationCount: Int,
    animationControllerHasPendingWork: Bool
  ) {
    guard let diagnosticsLogger else {
      return
    }
    let causeSummary = scheduledFrame.causes
      .map(\.rawValue)
      .sorted()
      .joined(separator: "+")
    let reconciliation =
      decision?.reconciliation
      ?? .blocked(
        reason: .dropEligibilityBlockers
      )
    diagnosticsLogger.log(
      FrameDiagnosticRecord(
        frameNumber: renderedFrames + 1,
        causeSummary: causeSummary,
        focusSyncRerenders: 0,
        invalidatedIdentityCount: scheduledFrame.invalidatedIdentities.count,
        resolvedNodeCount: 0,
        resolvedNodesComputed: 0,
        resolvedNodesReused: 0,
        measuredNodeCount: 0,
        measuredNodesComputed: 0,
        measuredNodesReused: 0,
        placedNodeCount: 0,
        drawNodeCount: 0,
        interactionRegionCount: 0,
        focusRegionCount: 0,
        phaseTimings: nil,
        renderGenerations: .init(render: renderGeneration),
        desiredGeneration: renderIntentDiagnostics.desiredGeneration,
        coalescedEventBatches: renderIntentDiagnostics.coalescedEventBatches,
        coalescedWakeCauses: formattedWakeCauses(
          renderIntentDiagnostics.coalescedWakeCauses
        ),
        coalescedIntentRequests: renderIntentDiagnostics.intentRequestCount,
        scheduledAnimationRequest: formattedAnimationRequest(
          scheduledFrame.animationRequest
        ),
        scheduledAnimationBatchID: scheduledFrame.animationBatchID?.value,
        animationControllerActiveAnimationCount: animationControllerActiveAnimationCount,
        animationControllerHasPendingWork: animationControllerHasPendingWork,
        workerTimings: nil,
        mainActorTimings: nil,
        customLayoutFallbackCount: 0,
        firstCustomLayoutFallbackIdentity: nil,
        layoutDependentRealizations: 0,
        layoutDependentRealizationCacheHits: 0,
        layoutDependentMainActorFallbacks: 0,
        geometryAnchorResolutionMissCount: 0,
        firstGeometryAnchorResolutionMissIdentity: nil,
        geometryMissingNamedCoordinateSpaceCount: 0,
        firstGeometryMissingNamedCoordinateSpaceName: nil,
        geometryDuplicateNamedCoordinateSpaceCount: 0,
        firstGeometryDuplicateNamedCoordinateSpaceName: nil,
        runtimePointerHandlerCount: 0,
        runtimePointerHoverHandlerCount: 0,
        runtimeGestureRecognizerCount: 0,
        runtimeGestureStateBindingCount: 0,
        runtimeIssues: runtimeIssues,
        staleFramePolicy: "drop_completed_visual_only",
        tailJobState: FrameTailJobState.droppedCompleted.rawValue,
        tailCancelReason: "-",
        cancelledRenderCount: cancelledRenderCount,
        newestDesiredAtTailStart: renderIntentDiagnostics.desiredGeneration,
        newestDesiredAtTailResult: newestDesiredGeneration.rawValue,
        dropEligibilityBlockers: droppedFrameBlockers(from: decision),
        dropDecision: decision?.action.rawValue ?? "-",
        dropGeneration: renderGeneration.rawValue,
        newestDesiredAtDrop: newestDesiredGeneration.rawValue,
        dropReconciliationMode: reconciliation.mode.rawValue,
        dropReconciliationEffects: reconciliation.effectSummary,
        presentationRecoveryAfterDrop: false,
        inputEventsQueuedDuringRenderSuspension:
          renderSuspensionDiagnostics
          .drainInputEventsQueuedDuringSuspension(),
        presentationStrategy: "-",
        presentationBytesWritten: 0,
        presentationLinesTouched: 0,
        presentationCellsChanged: 0,
        presentationDuration: .zero,
        damageRowCount: nil,
        damageRangeAwareRowCount: nil,
        damageTextSpanCount: nil,
        damageTextCellCount: nil,
        damageGraphicsInvalidationCount: nil,
        damageRequiresFullTextRepaint: false,
        damageRequiresFullGraphicsReplay: false,
        presentationUsedSynchronizedOutput: false,
        presentationGraphicsReplayScope: "-",
        presentationGraphicsAttachmentsReplayed: 0,
        presentationEditOperationLowering: "-",
        presentationEditOperationCount: 0,
        measurementCacheHitRate: nil,
        totalFrameDuration: .zero
      )
    )
  }

  package func renderPendingFramesAsync(renderedFrames: inout Int) async throws {
    _ = try await renderPendingFramesAsync(
      renderedFrames: &renderedFrames,
      eventPump: nil
    )
  }

  /// Outcome of the async artifact-acquisition strategy for one focus-sync
  /// iteration. Models the strategy boundary from ADR-0021: `.rendered`
  /// carries a frame plus its tail state; `.skipped` reports that the tail
  /// job was cancelled-before-start or dropped-completed and the enclosing
  /// frame must be abandoned without invoking the shared per-frame body.
  private enum FrameAcquisitionOutcome {
    case rendered(FrameArtifacts, FrameTailJobState, CompletedFrameDropDecision?)
    case skipped
  }

  package func renderPendingFramesAsync(
    renderedFrames: inout Int,
    eventPump: EventPump?
  ) async throws -> RunLoopExitReason? {
    observationBridge.attachInvalidator(scheduler)

    let hasDiagnosticsLogger = diagnosticsLogger != nil
    frameLoop: while var scheduledFrame = scheduler.consumeReadyFrame(at: .now()) {
      let currentState = stateContainer.state
      scheduledFrame = scheduledFrameByReconcilingExternalState(
        scheduledFrame,
        currentState: currentState
      )
      let renderIntentDiagnostics = nextRenderIntentDiagnostics(for: scheduledFrame)
      progressProbe?.record(
        .frameIntent,
        frameNumber: renderedFrames + 1,
        desiredGeneration: renderIntentDiagnostics.desiredGeneration,
        coalescedEventBatches: renderIntentDiagnostics.coalescedEventBatches
      )
      drainGestureDeadlinesIfNeeded(for: scheduledFrame)
      var convergence = FocusSyncConvergenceState()
      convergence.lifecycleCarryForward = deferredLifecycleCarryForward
      deferredLifecycleCarryForward.removeAll(keepingCapacity: true)

      var acquisition = FrameAcquisitionState()
      var artifacts: FrameArtifacts?
      // The focus-sync convergence loop is the one place the runtime must
      // suspend (the async render). Acquisition is the only strategy
      // difference (ADR-0021); the per-iteration side effects
      // (`processFocusSyncIteration`) and post-acquisition body
      // (`applyAcquiredFrame`) are shared with the synchronous driver.
      convergenceLoop: while true {
        if convergence.rerenderedForFocusSync {
          renderer.forceRootEvaluation()
        }
        let acquired = await acquireFrameArtifactsAsync(
          scheduledFrame: scheduledFrame,
          currentState: currentState,
          eventPump: eventPump,
          renderIntentDiagnostics: renderIntentDiagnostics,
          renderedFrames: renderedFrames,
          convergence: convergence
        )
        switch acquired {
        case .skipped:
          // Tail job was cancelled-before-start or dropped-completed; the
          // acquisition step already reported issues, carried lifecycle
          // forward, and logged the tail. Abandon this frame.
          continue frameLoop
        case .rendered(let renderedArtifacts, let tailJobState, let dropDecision):
          acquisition.tailJobState = tailJobState
          acquisition.completedFrameDropDecision = dropDecision
          progressProbe?.record(
            .frameAcquired,
            frameNumber: renderedFrames + 1,
            desiredGeneration: renderIntentDiagnostics.desiredGeneration,
            renderGeneration: renderedArtifacts.diagnostics.timing.renderGenerations.render
              .rawValue,
            tailJobState: tailJobState
          )
          artifacts = renderedArtifacts
          let outcome = try processFocusSyncIteration(
            renderedArtifacts,
            convergence: &convergence
          )
          switch outcome {
          case .rerender:
            if convergence.budgetExceeded {
              break convergenceLoop
            }
            continue convergenceLoop
          case .converged:
            break convergenceLoop
          }
        }
      }

      guard let artifacts else {
        preconditionFailure("Focus synchronization produced no frame artifacts.")
      }
      try applyAcquiredFrame(
        artifacts,
        scheduledFrame: scheduledFrame,
        renderIntentDiagnostics: renderIntentDiagnostics,
        convergence: convergence,
        acquisition: acquisition,
        hasDiagnosticsLogger: hasDiagnosticsLogger,
        renderedFrames: &renderedFrames
      )
      previousRenderedState = currentState

      // Interactive rendering may enqueue more frames while a key or
      // pointer event is already buffered. Yield between committed frames
      // so task/animation invalidations cannot run ahead of user input.
      if eventPump?.hasPendingEvents() == true {
        break
      }
    }
    progressProbe?.record(.schedulerIdle, frameNumber: renderedFrames)
    return nil
  }

  /// Strategy-specific artifact acquisition for the async driver. Renders
  /// one tree according to `renderMode`: a synchronous render for `.sync`,
  /// `renderAsync` when no event pump is attached, otherwise the cancellable
  /// frame-tail renderer. Cancelled-before-start and dropped-completed tail
  /// outcomes are reported, logged, have their accumulated focus-sync
  /// lifecycle carry-forward folded back into `deferredLifecycleCarryForward`,
  /// and are surfaced as `.skipped` here so the shared focus-sync loop and
  /// per-frame body never see them.
  ///
  /// `renderedFrames` is passed by value: cancelled/dropped tails never
  /// increment the committed frame count — only `applyAcquiredFrame` does,
  /// after acquisition succeeds — but the current count is still needed so
  /// the cancelled/dropped diagnostic records carry the correct frame number.
  private func acquireFrameArtifactsAsync(
    scheduledFrame: ScheduledFrame,
    currentState: State,
    eventPump: EventPump?,
    renderIntentDiagnostics: RenderIntentCoalescingDiagnostics,
    renderedFrames: Int,
    convergence: FocusSyncConvergenceState
  ) async -> FrameAcquisitionOutcome {
    await renderFrameArtifactsForCurrentMode(
      scheduledFrame: scheduledFrame,
      currentState: currentState,
      eventPump: eventPump,
      renderIntentDiagnostics: renderIntentDiagnostics,
      renderedFrames: renderedFrames,
      convergence: convergence
    )
  }

  private func renderFrameArtifactsForCurrentMode(
    scheduledFrame: ScheduledFrame,
    currentState: State,
    eventPump: EventPump?,
    renderIntentDiagnostics: RenderIntentCoalescingDiagnostics,
    renderedFrames: Int,
    convergence: FocusSyncConvergenceState
  ) async -> FrameAcquisitionOutcome {
    if renderMode == .sync {
      let renderedArtifacts = renderer.render(
        viewBuilder(
          (
            state: currentState,
            focusedIdentity: focusTracker.currentFocusIdentity
          )),
        context: resolveContext(for: scheduledFrame),
        proposal: proposal()
      )
      return .rendered(renderedArtifacts, .completed, nil)
    }
    if eventPump == nil {
      let renderedArtifacts = await renderer.renderAsync(
        viewBuilder(
          (
            state: currentState,
            focusedIdentity: focusTracker.currentFocusIdentity
          )),
        context: resolveContext(for: scheduledFrame),
        proposal: proposal()
      )
      return .rendered(renderedArtifacts, .completed, nil)
    }

    let renderOutcome = await acquireCancellableFrameArtifacts(
      scheduledFrame: scheduledFrame,
      currentState: currentState,
      renderIntentDiagnostics: renderIntentDiagnostics
    )
    if let skippedFrame = recordSkippedCancellableFrame(
      renderOutcome,
      scheduledFrame: scheduledFrame,
      renderIntentDiagnostics: renderIntentDiagnostics,
      renderedFrames: renderedFrames,
      convergence: convergence
    ) {
      return skippedFrame
    }
    guard let outcomeArtifacts = renderOutcome.artifacts else {
      preconditionFailure("Completed render outcome did not include frame artifacts.")
    }
    return .rendered(
      outcomeArtifacts,
      renderOutcome.tailJobState,
      renderOutcome.completedFrameDropDecision
    )
  }

  private func acquireCancellableFrameArtifacts(
    scheduledFrame: ScheduledFrame,
    currentState: State,
    renderIntentDiagnostics: RenderIntentCoalescingDiagnostics
  ) async -> CancellableRenderOutcome {
    await renderer.renderAsyncCancellable(
      viewBuilder(
        (
          state: currentState,
          focusedIdentity: focusTracker.currentFocusIdentity
        )),
      context: resolveContext(for: scheduledFrame),
      proposal: proposal(),
      newestDesiredGeneration: {
        RenderGeneration(
          self.scheduler.hasPendingFrame(at: .now())
            ? self.nextRenderIntentGeneration
            : renderIntentDiagnostics.desiredGeneration
        )
      },
      completedFramePolicy: renderMode == .asyncNoDrop ? .orderedCommitOnly : nil,
      completedFrameAdditionalBlockers: { artifacts in
        self.completedFrameAdditionalDropBlockers(
          artifacts: artifacts,
          scheduledFrame: scheduledFrame
        )
      },
      awaitQueuedCancellationSignal: awaitQueuedTailCancellationSignalForMode,
      shouldCancelQueued: shouldCancelQueuedTailForMode
    )
  }

  @MainActor
  private func shouldCancelQueuedTailForMode() async -> Bool {
    guard renderMode != .asyncNoCancel else {
      return false
    }
    return scheduler.hasPendingFrame(at: .now())
  }

  private func awaitQueuedTailCancellationSignalForMode() async {
    guard renderMode != .asyncNoCancel else {
      return
    }
    guard !scheduler.hasPendingFrame(at: .now()) else {
      return
    }
    guard let pendingFrameAwaiter = scheduler as? any PendingFrameAwaiting else {
      return
    }
    await pendingFrameAwaiter.waitForPendingFrame(at: .now())
  }

  private func recordSkippedCancellableFrame(
    _ renderOutcome: CancellableRenderOutcome,
    scheduledFrame: ScheduledFrame,
    renderIntentDiagnostics: RenderIntentCoalescingDiagnostics,
    renderedFrames: Int,
    convergence: FocusSyncConvergenceState
  ) -> FrameAcquisitionOutcome? {
    switch renderOutcome.tailJobState {
    case .cancelledBeforeStart:
      reportRuntimeIssues(renderOutcome.runtimeIssues)
      appendLifecycleCarryForward(
        convergence.lifecycleCarryForward,
        into: &deferredLifecycleCarryForward
      )
      cancelledRenderCount += 1
      replayCancelledFrameIntent(scheduledFrame)
      logCancelledFrameTail(
        diagnosticsLogger: diagnosticsLogger,
        renderedFrames: renderedFrames,
        scheduledFrame: scheduledFrame,
        renderIntentDiagnostics: renderIntentDiagnostics,
        renderGeneration: renderOutcome.renderGeneration,
        runtimeIssues: renderOutcome.runtimeIssues,
        tailJobState: renderOutcome.tailJobState,
        tailCancelReason: renderOutcome.tailCancelReason ?? "-",
        animationControllerActiveAnimationCount: renderer
          .internalAnimationController.activeAnimationCount,
        animationControllerHasPendingWork: renderer
          .internalAnimationController.lastTickResult.hasPendingWork
      )
      progressProbe?.record(
        .frameSkipped,
        frameNumber: renderedFrames + 1,
        desiredGeneration: renderIntentDiagnostics.desiredGeneration,
        renderGeneration: renderOutcome.renderGeneration.rawValue,
        tailJobState: renderOutcome.tailJobState
      )
      return .skipped
    case .droppedCompleted:
      reportRuntimeIssues(renderOutcome.runtimeIssues)
      appendLifecycleCarryForward(
        convergence.lifecycleCarryForward,
        into: &deferredLifecycleCarryForward
      )
      logDroppedCompletedFrame(
        diagnosticsLogger: diagnosticsLogger,
        renderedFrames: renderedFrames,
        scheduledFrame: scheduledFrame,
        renderIntentDiagnostics: renderIntentDiagnostics,
        renderGeneration: renderOutcome.renderGeneration,
        newestDesiredGeneration: renderOutcome.newestDesiredGeneration
          ?? RenderGeneration(nextRenderIntentGeneration),
        decision: renderOutcome.completedFrameDropDecision,
        runtimeIssues: renderOutcome.runtimeIssues,
        animationControllerActiveAnimationCount: renderer
          .internalAnimationController.activeAnimationCount,
        animationControllerHasPendingWork: renderer
          .internalAnimationController.lastTickResult.hasPendingWork
      )
      progressProbe?.record(
        .frameSkipped,
        frameNumber: renderedFrames + 1,
        desiredGeneration: renderIntentDiagnostics.desiredGeneration,
        renderGeneration: renderOutcome.renderGeneration.rawValue,
        tailJobState: renderOutcome.tailJobState
      )
      return .skipped
    case .queued, .started, .completed:
      return nil
    }
  }

  @MainActor
  private func replayCancelledFrameIntent(_ frame: ScheduledFrame) {
    guard let scheduler = scheduler as? any CancelledFrameIntentReplaying else {
      return
    }
    scheduler.replayCancelledFrameIntent(frame)
  }

  package func applyDesiredFocusRequest(
    _ request: FocusBindingRequest
  ) -> Bool {
    switch request {
    case .none:
      return false
    case .clear:
      return focusTracker.clearFocus()
    case .focus(let identity):
      return focusTracker.setFocus(to: identity)
    }
  }

  package func runtimeResetFocusAction() -> ResetFocusAction {
    ResetFocusAction(
      snapshotLabel: "ResetFocusAction.runtime",
      isPlaceholder: false,
      handler: { [weak scheduler, localDefaultFocusRegistry, rootIdentity] namespace in
        localDefaultFocusRegistry.requestReset(in: namespace)
        scheduler?.requestInvalidation(of: [rootIdentity])
        return true
      }
    )
  }

  package func resolveContext(
    for scheduledFrame: ScheduledFrame
  ) -> ResolveContext {
    let causeSummary = scheduledFrame.causes
      .map(\.rawValue)
      .sorted()
      .joined(separator: "+")
    var effectiveEnvironmentValues = environmentValues
    effectiveEnvironmentValues.terminalAppearance = presentationSurface.appearance
    effectiveEnvironmentValues.theme = presentationSurface.theme
    effectiveEnvironmentValues.terminalSize = presentationSurface.surfaceSize
    if let cellPixelSize = presentationSurface.graphicsCapabilities.cellPixelSize {
      effectiveEnvironmentValues.cellPixelMetrics = CellPixelMetrics(
        width: cellPixelSize.width,
        height: cellPixelSize.height,
        source: .reported
      )
    } else {
      effectiveEnvironmentValues.cellPixelMetrics = .estimated
    }
    effectiveEnvironmentValues.pointerInputCapabilities =
      presentationSurface.pointerInputCapabilities
    effectiveEnvironmentValues.focusedIdentity = focusTracker.currentFocusIdentity
    effectiveEnvironmentValues.focusedValues = currentFocusedValues
    effectiveEnvironmentValues.pressedIdentity = pressedIdentity
    effectiveEnvironmentValues.accessibilityReduceMotion = runtimeConfiguration.motion == .reduced
    effectiveEnvironmentValues.suppressesProgress = runtimeConfiguration.noProgress
    effectiveEnvironmentValues.cursorFollowsFocus =
      runtimeConfiguration.cursorFollowsFocus
      || usesTerminalCursorForTextInput
    if effectiveEnvironmentValues.openLinkAction.isPlaceholder {
      effectiveEnvironmentValues.openLinkAction = systemOpenLinkAction()
    }
    if effectiveEnvironmentValues.resetFocus.isPlaceholder {
      effectiveEnvironmentValues.resetFocus = runtimeResetFocusAction()
    }
    if effectiveEnvironmentValues.clipboardWriteAction.isPlaceholder {
      effectiveEnvironmentValues.clipboardWriteAction = runtimeClipboardWriteAction()
    }
    if effectiveEnvironmentValues.clipboardReadAction.isPlaceholder {
      effectiveEnvironmentValues.clipboardReadAction = runtimeClipboardReadAction()
    }
    var transactionSnapshot = TransactionSnapshot(debugSignature: causeSummary)
    if runtimeConfiguration.motion == .reduced {
      transactionSnapshot.animationRequest = .disabled
      transactionSnapshot.animationBatchID = nil
    } else {
      transactionSnapshot.animationRequest = scheduledFrame.animationRequest
      transactionSnapshot.animationBatchID = scheduledFrame.animationBatchID
    }
    // Phase 3's ``diffAndEnqueue`` retargets in-flight animations
    // correctly via ``sample(existing, at:)`` + ``effectiveFrom``, so
    // the previous re-injection of the controller's "dominant active
    // request" on tick frames is no longer required.  A `.inherit`
    // tick frame whose resolve diffs an unchanged property won't
    // touch the running animation (the diff bails on ``previous ==
    // current``); a tick frame whose resolve diffs a CHANGED property
    // under `.inherit` correctly purges the obsolete animation, which
    // matches SwiftUI's "untracked write snaps" semantics.  The
    // scheduler stays animation-unaware; all retarget state lives on
    // the controller.
    var context = ResolveContext(
      identity: rootIdentity,
      environment: environment,
      environmentValues: effectiveEnvironmentValues,
      transaction: transactionSnapshot,
      invalidatedIdentities: scheduledFrame.invalidatedIdentities,
      localActionRegistry: localActionRegistry,
      localKeyHandlerRegistry: localKeyHandlerRegistry,
      localLifecycleRegistry: localLifecycleRegistry,
      localTaskRegistry: localTaskRegistry,
      applyEnvironmentValues: true
    )
    context.forceRootEvaluation = scheduledFrame.forceRootEvaluation
    context.localPointerHandlerRegistry = localPointerHandlerRegistry
    context.localTerminationRegistry = localTerminationRegistry
    context.localGestureRegistry = localGestureRegistry
    context.localGestureStateRegistry = localGestureStateRegistry
    context.localDefaultFocusRegistry = localDefaultFocusRegistry
    context.localFocusBindingRegistry = localFocusBindingRegistry
    context.localFocusedValuesRegistry = localFocusedValuesRegistry
    context.localScrollPositionRegistry = localScrollPositionRegistry
    context.localPreferenceObservationRegistry = localPreferenceObservationRegistry
    context.commandRegistry = commandRegistry
    context.dropDestinationRegistry = dropDestinationRegistry
    context.invalidationProxy = .init(invalidator: scheduler)
    context.observationBridge = observationBridge
    context.requestDeadline = { [weak scheduler] instant in
      scheduler?.requestDeadline(instant)
    }
    return context
  }

  package func proposal() -> ProposedSize {
    if let proposalOverride {
      return proposalOverride
    }

    let size = presentationSurface.surfaceSize
    return .init(width: size.width, height: size.height)
  }

  private func frameDropEligibilityBlockers(
    artifacts: FrameArtifacts,
    scheduledFrame: ScheduledFrame,
    focusGraphChanged: Bool,
    focusBindingChanged: Bool,
    focusedValuesChanged: Bool,
    scrollPositionChanged: Bool,
    preferenceObservationChanged: Bool,
    diagnosticsRequireFullRecord: Bool
  ) -> Set<FrameDropEligibility.Blocker> {
    var additionalBlockers = renderer.internalAnimationController.frameDropEligibilityBlockers
    if focusGraphChanged {
      additionalBlockers.insert(.focusGraph)
    }
    if focusBindingChanged {
      additionalBlockers.insert(.focusBindingSync)
    }
    if focusedValuesChanged {
      additionalBlockers.insert(.focusedValueSync)
    }
    if scrollPositionChanged {
      additionalBlockers.insert(.scrollSync)
    }
    if preferenceObservationChanged {
      additionalBlockers.insert(.preferenceObservationDelta)
    }
    if scheduledFrame.animationRequest != .inherit {
      additionalBlockers.insert(.animationTransaction)
    }
    if diagnosticsRequireFullRecord {
      additionalBlockers.insert(.diagnosticsFullRecord)
    }
    return FrameDropEligibility.classify(
      artifacts,
      additionalBlockers: additionalBlockers
    ).blockers
  }

  private func completedFrameAdditionalDropBlockers(
    artifacts: FrameArtifacts,
    scheduledFrame: ScheduledFrame
  ) -> Set<FrameDropEligibility.Blocker> {
    var blockers = renderer.internalAnimationController.frameDropEligibilityBlockers
    if scheduledFrame.animationRequest != .inherit {
      blockers.insert(.animationTransaction)
    }
    if !artifacts.semanticSnapshot.focusRegions.isEmpty {
      blockers.insert(.focusGraph)
    }
    if !artifacts.semanticSnapshot.scrollRoutes.isEmpty {
      blockers.insert(.scrollSync)
    }
    return blockers
  }

  private func droppedFrameBlockers(
    from decision: CompletedFrameDropDecision?
  ) -> Set<FrameDropEligibility.Blocker> {
    guard let decision else {
      return []
    }
    switch decision.eligibility {
    case .mustCommit(let blockers):
      return blockers
    case .canDropVisualOnly:
      return []
    }
  }

  package func formattedAnimationRequest(
    _ request: AnimationRequest
  ) -> String {
    switch request {
    case .inherit:
      "inherit"
    case .disabled:
      "disabled"
    case .animate:
      "animate"
    }
  }

  private func appendPendingAccessibilityAnnouncements(
    to artifacts: inout FrameArtifacts
  ) {
    let announcements = drainPendingAccessibilityAnnouncements()
    guard !announcements.isEmpty else {
      return
    }
    artifacts.semanticSnapshot.accessibilityAnnouncements.append(contentsOf: announcements)
  }
}
