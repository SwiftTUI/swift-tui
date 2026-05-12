import SwiftTUICore
import SwiftTUIViews

package struct FocusSyncRerenderBudget: Equatable, Sendable {
  package let maximumRerenders: Int
  package private(set) var rerenderCount: Int

  package init(maximumRerenders: Int = 16) {
    precondition(maximumRerenders > 0)
    self.maximumRerenders = maximumRerenders
    rerenderCount = 0
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

  package func renderPendingFrames(renderedFrames: inout Int) throws {
    observationBridge.attachInvalidator(scheduler)

    let hasDiagnosticsLogger = diagnosticsLogger != nil
    while let scheduledFrame = scheduler.consumeReadyFrame(at: .now()) {
      let renderIntentDiagnostics = nextRenderIntentDiagnostics(for: scheduledFrame)
      // Drain gesture recognizer deadlines before rendering so that
      // recognizers that transition on this wake see their new phase
      // reflected in the upcoming render pass.
      if scheduledFrame.causes.contains(.deadline) {
        if let triggeredDeadline = scheduledFrame.triggeredDeadline {
          drainGestureDeadlines(at: triggeredDeadline)
        } else {
          assertionFailure(
            "FrameScheduler produced .deadline cause without a triggeredDeadline; "
              + "gesture deadlines will not drain this frame."
          )
        }
      }
      var rerenderedForFocusSync = false
      var focusSyncBudget = FocusSyncRerenderBudget()
      var focusSyncBudgetExceeded = false
      var focusGraphChangedDuringFrame = false
      var focusBindingChangedDuringFrame = false
      var focusedValuesChangedDuringFrame = false
      var scrollPositionChangedDuringFrame = false
      var artifacts: FrameArtifacts?
      var focusSyncLifecycleCarryForward = deferredLifecycleCarryForward
      deferredLifecycleCarryForward.removeAll(keepingCapacity: true)
      let currentState = stateContainer.state
      if previousRenderedState != currentState {
        renderer.forceRootEvaluation()
        previousRenderedState = currentState
      }
      while true {
        if rerenderedForFocusSync {
          renderer.forceRootEvaluation()
        }
        let renderedArtifacts = renderer.render(
          viewBuilder(
            (
              state: currentState,
              focusedIdentity: focusTracker.currentFocusIdentity
            )),
          context: resolveContext(for: scheduledFrame),
          proposal: proposal(),
          collectsDiagnostics: hasDiagnosticsLogger
        )
        artifacts = renderedArtifacts

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
          accessibilityNodes: renderedArtifacts.semanticSnapshot.accessibilityNodes
        )
        focusGraphChangedDuringFrame = focusGraphChangedDuringFrame || focusChanged
        focusBindingChangedDuringFrame =
          focusBindingChangedDuringFrame || appliedFocusRequest || appliedDefaultFocusRequest
          || focusStateChanged
        focusedValuesChangedDuringFrame =
          focusedValuesChangedDuringFrame || focusedValuesChanged
        scrollPositionChangedDuringFrame =
          scrollPositionChangedDuringFrame || scrollPositionChanged

        if focusChanged || appliedFocusRequest || appliedDefaultFocusRequest || focusStateChanged
          || focusedValuesChanged || scrollPositionChanged
        {
          appendLifecycleCarryForward(
            renderedArtifacts.commitPlan.lifecycle,
            into: &focusSyncLifecycleCarryForward
          )
          rerenderedForFocusSync = true
          if !focusSyncBudget.recordRerender() {
            focusSyncBudgetExceeded = true
            break
          }
          continue
        }
        break
      }

      guard var artifacts else {
        preconditionFailure("Focus synchronization produced no frame artifacts.")
      }
      mergeLifecycleCarryForward(
        focusSyncLifecycleCarryForward,
        into: &artifacts.commitPlan.lifecycle
      )
      appendPendingAccessibilityAnnouncements(to: &artifacts)
      latestSemanticSnapshot = artifacts.semanticSnapshot
      if focusSyncBudgetExceeded {
        let causes = scheduledFrame.causes.map(\.rawValue).sorted().joined(separator: "+")
        assertionFailure(
          "Focus synchronization did not converge after \(focusSyncBudget.rerenderCount) rerenders for frame causes \(causes). The runtime will present the latest available tree and continue."
        )
      }

      let focusPresentation = artifacts.semanticSnapshot.focusPresentation(
        for: focusTracker.currentFocusIdentity
      )
      let presentationDamage: PresentationDamage? =
        if rerenderedForFocusSync {
          nil
        } else {
          artifacts.presentationDamage
        }
      var presentationMetrics = TerminalPresentationMetrics()
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
      presentationMetrics = try presentCommittedFrame(
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

      if let diagnosticsLogger {
        let diag = artifacts.diagnostics
        let damageDiagnostics = diag.presentationDamage
        let geometryDiagnostics = diag.geometryResolutionDiagnostics
        let cacheMetrics = diag.measurementCache
        let cacheHitRate: Double? =
          if let cacheMetrics, cacheMetrics.lookups > 0 {
            Double(cacheMetrics.hits) / Double(cacheMetrics.lookups)
          } else {
            nil
          }
        let pipelineTotal = diag.phaseTimings?.total ?? .zero
        let causeSummary = scheduledFrame.causes
          .map(\.rawValue)
          .sorted()
          .joined(separator: "+")
        let inputEventsQueuedDuringRenderSuspension =
          renderSuspensionDiagnostics.drainInputEventsQueuedDuringSuspension()
        let dropEligibilityBlockers = frameDropEligibilityBlockers(
          artifacts: artifacts,
          scheduledFrame: scheduledFrame,
          focusGraphChanged: focusGraphChangedDuringFrame,
          focusBindingChanged: focusBindingChangedDuringFrame,
          focusedValuesChanged: focusedValuesChangedDuringFrame,
          scrollPositionChanged: scrollPositionChangedDuringFrame,
          preferenceObservationChanged: preferenceObservationChanged,
          diagnosticsRequireFullRecord: true
        )
        diagnosticsLogger.log(
          FrameDiagnosticRecord(
            frameNumber: renderedFrames,
            causeSummary: causeSummary,
            focusSyncRerenders: focusSyncBudget.rerenderCount,
            invalidatedIdentityCount: diag.invalidatedIdentities.count,
            resolvedNodeCount: diag.resolvedNodeCount,
            resolvedNodesComputed: diag.resolvedNodesComputed,
            resolvedNodesReused: diag.resolvedNodesReused,
            measuredNodeCount: diag.measuredNodeCount,
            measuredNodesComputed: diag.measuredNodesComputed,
            measuredNodesReused: diag.measuredNodesReused,
            placedNodeCount: diag.placedNodeCount,
            drawNodeCount: diag.drawNodeCount,
            interactionRegionCount: diag.interactionRegionCount,
            focusRegionCount: diag.focusRegionCount,
            phaseTimings: diag.phaseTimings,
            renderGenerations: diag.renderGenerations,
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
            workerTimings: diag.workerTimings,
            mainActorTimings: diag.mainActorTimings,
            customLayoutFallbackCount: diag.customLayoutFallbackCount,
            firstCustomLayoutFallbackIdentity: diag.firstCustomLayoutFallbackIdentity?.path,
            layoutDependentRealizations: diag.layoutDependentRealizations,
            layoutDependentRealizationCacheHits: diag.layoutDependentRealizationCacheHits,
            layoutDependentMainActorFallbacks: diag.layoutDependentMainActorFallbacks,
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
            runtimePointerHandlerCount: diag.runtimeRegistrations.pointerHandlerCount,
            runtimePointerHoverHandlerCount: diag.runtimeRegistrations.pointerHoverHandlerCount,
            runtimeGestureRecognizerCount: diag.runtimeRegistrations.gestureRecognizerCount,
            runtimeGestureStateBindingCount: diag.runtimeRegistrations.gestureStateBindingCount,
            staleFramePolicy: "commit_ordered",
            tailJobState: FrameTailJobState.completed.rawValue,
            tailCancelReason: "-",
            cancelledRenderCount: cancelledRenderCount,
            newestDesiredAtTailStart: renderIntentDiagnostics.desiredGeneration,
            newestDesiredAtTailResult: renderIntentDiagnostics.desiredGeneration,
            dropEligibilityBlockers: dropEligibilityBlockers,
            dropDecision: CompletedFrameDropDecision.Action.commitOrdered.rawValue,
            dropGeneration: nil,
            newestDesiredAtDrop: nil,
            dropReconciliationMode: "-",
            dropReconciliationEffects: "-",
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
  }

  package func updateTerminalPointerHoverModeIfNeeded() throws {
    let shouldEnable = localPointerHandlerRegistry.hasHoverSubscribers
    guard shouldEnable != terminalPointerHoverEnabled else {
      return
    }
    try presentationSurface.setPointerHoverEnabled(shouldEnable)
    terminalPointerHoverEnabled = shouldEnable
  }

  @MainActor
  private func logCancelledFrameTail(
    diagnosticsLogger: FrameDiagnosticsLogger?,
    renderedFrames: Int,
    scheduledFrame: ScheduledFrame,
    renderIntentDiagnostics: RenderIntentCoalescingDiagnostics,
    renderGeneration: RenderGeneration,
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

  package func renderPendingFramesAsync(
    renderedFrames: inout Int,
    eventPump: EventPump?
  ) async throws -> RunLoopExitReason? {
    observationBridge.attachInvalidator(scheduler)

    let hasDiagnosticsLogger = diagnosticsLogger != nil
    frameLoop: while let scheduledFrame = scheduler.consumeReadyFrame(at: .now()) {
      let renderIntentDiagnostics = nextRenderIntentDiagnostics(for: scheduledFrame)
      // Drain gesture recognizer deadlines before rendering so that
      // recognizers that transition on this wake see their new phase
      // reflected in the upcoming render pass.
      if scheduledFrame.causes.contains(.deadline) {
        if let triggeredDeadline = scheduledFrame.triggeredDeadline {
          drainGestureDeadlines(at: triggeredDeadline)
        } else {
          assertionFailure(
            "FrameScheduler produced .deadline cause without a triggeredDeadline; "
              + "gesture deadlines will not drain this frame."
          )
        }
      }
      var rerenderedForFocusSync = false
      var focusSyncBudget = FocusSyncRerenderBudget()
      var focusSyncBudgetExceeded = false
      var focusGraphChangedDuringFrame = false
      var focusBindingChangedDuringFrame = false
      var focusedValuesChangedDuringFrame = false
      var scrollPositionChangedDuringFrame = false
      var artifacts: FrameArtifacts?
      var tailJobState: FrameTailJobState = .completed
      var completedFrameDropDecision: CompletedFrameDropDecision?
      var focusSyncLifecycleCarryForward = deferredLifecycleCarryForward
      deferredLifecycleCarryForward.removeAll(keepingCapacity: true)
      let currentState = stateContainer.state
      if previousRenderedState != currentState {
        renderer.forceRootEvaluation()
        previousRenderedState = currentState
      }

      @MainActor
      func shouldCancelQueuedTail() async -> Bool {
        scheduler.hasPendingFrame(at: .now())
      }

      @MainActor
      func shouldCancelQueuedTailForMode() async -> Bool {
        guard renderMode != .asyncNoCancel else {
          return false
        }
        return await shouldCancelQueuedTail()
      }

      while true {
        if rerenderedForFocusSync {
          renderer.forceRootEvaluation()
        }
        let renderedArtifacts: FrameArtifacts
        if renderMode == .sync {
          renderedArtifacts = renderer.render(
            viewBuilder(
              (
                state: currentState,
                focusedIdentity: focusTracker.currentFocusIdentity
              )),
            context: resolveContext(for: scheduledFrame),
            proposal: proposal(),
            collectsDiagnostics: hasDiagnosticsLogger
          )
          tailJobState = .completed
        } else if eventPump == nil {
          renderedArtifacts = await renderer.renderAsync(
            viewBuilder(
              (
                state: currentState,
                focusedIdentity: focusTracker.currentFocusIdentity
              )),
            context: resolveContext(for: scheduledFrame),
            proposal: proposal(),
            collectsDiagnostics: hasDiagnosticsLogger
          )
          tailJobState = .completed
        } else {
          let renderOutcome = await renderer.renderAsyncCancellable(
            viewBuilder(
              (
                state: currentState,
                focusedIdentity: focusTracker.currentFocusIdentity
              )),
            context: resolveContext(for: scheduledFrame),
            proposal: proposal(),
            collectsDiagnostics: hasDiagnosticsLogger,
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
            shouldCancelQueued: shouldCancelQueuedTailForMode
          )
          if renderOutcome.tailJobState == .cancelledBeforeStart {
            appendLifecycleCarryForward(
              focusSyncLifecycleCarryForward,
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
              tailJobState: renderOutcome.tailJobState,
              tailCancelReason: renderOutcome.tailCancelReason ?? "-",
              animationControllerActiveAnimationCount: renderer
                .internalAnimationController.activeAnimationCount,
              animationControllerHasPendingWork: renderer
                .internalAnimationController.lastTickResult.hasPendingWork
            )
            continue frameLoop
          }
          if renderOutcome.tailJobState == .droppedCompleted {
            appendLifecycleCarryForward(
              focusSyncLifecycleCarryForward,
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
              animationControllerActiveAnimationCount: renderer
                .internalAnimationController.activeAnimationCount,
              animationControllerHasPendingWork: renderer
                .internalAnimationController.lastTickResult.hasPendingWork
            )
            continue frameLoop
          }
          tailJobState = renderOutcome.tailJobState
          completedFrameDropDecision = renderOutcome.completedFrameDropDecision
          guard let artifacts = renderOutcome.artifacts else {
            preconditionFailure("Completed render outcome did not include frame artifacts.")
          }
          renderedArtifacts = artifacts
        }
        artifacts = renderedArtifacts

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
          accessibilityNodes: renderedArtifacts.semanticSnapshot.accessibilityNodes
        )
        focusGraphChangedDuringFrame = focusGraphChangedDuringFrame || focusChanged
        focusBindingChangedDuringFrame =
          focusBindingChangedDuringFrame || appliedFocusRequest || appliedDefaultFocusRequest
          || focusStateChanged
        focusedValuesChangedDuringFrame =
          focusedValuesChangedDuringFrame || focusedValuesChanged
        scrollPositionChangedDuringFrame =
          scrollPositionChangedDuringFrame || scrollPositionChanged

        if focusChanged || appliedFocusRequest || appliedDefaultFocusRequest || focusStateChanged
          || focusedValuesChanged || scrollPositionChanged
        {
          appendLifecycleCarryForward(
            renderedArtifacts.commitPlan.lifecycle,
            into: &focusSyncLifecycleCarryForward
          )
          rerenderedForFocusSync = true
          if !focusSyncBudget.recordRerender() {
            focusSyncBudgetExceeded = true
            break
          }
          continue
        }
        break
      }

      guard var artifacts else {
        preconditionFailure("Focus synchronization produced no frame artifacts.")
      }
      mergeLifecycleCarryForward(
        focusSyncLifecycleCarryForward,
        into: &artifacts.commitPlan.lifecycle
      )
      appendPendingAccessibilityAnnouncements(to: &artifacts)
      latestSemanticSnapshot = artifacts.semanticSnapshot
      if focusSyncBudgetExceeded {
        let causes = scheduledFrame.causes.map(\.rawValue).sorted().joined(separator: "+")
        assertionFailure(
          "Focus synchronization did not converge after \(focusSyncBudget.rerenderCount) rerenders for frame causes \(causes). The runtime will present the latest available tree and continue."
        )
      }

      let focusPresentation = artifacts.semanticSnapshot.focusPresentation(
        for: focusTracker.currentFocusIdentity
      )
      let presentationDamage: PresentationDamage? =
        if rerenderedForFocusSync {
          nil
        } else {
          artifacts.presentationDamage
        }
      var presentationMetrics = TerminalPresentationMetrics()
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
      presentationMetrics = try presentCommittedFrame(
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

      if let diagnosticsLogger {
        let diag = artifacts.diagnostics
        let damageDiagnostics = diag.presentationDamage
        let geometryDiagnostics = diag.geometryResolutionDiagnostics
        let cacheMetrics = diag.measurementCache
        let cacheHitRate: Double? =
          if let cacheMetrics, cacheMetrics.lookups > 0 {
            Double(cacheMetrics.hits) / Double(cacheMetrics.lookups)
          } else {
            nil
          }
        let pipelineTotal = diag.phaseTimings?.total ?? .zero
        let causeSummary = scheduledFrame.causes
          .map(\.rawValue)
          .sorted()
          .joined(separator: "+")
        let inputEventsQueuedDuringRenderSuspension =
          renderSuspensionDiagnostics.drainInputEventsQueuedDuringSuspension()
        let dropEligibilityBlockers = frameDropEligibilityBlockers(
          artifacts: artifacts,
          scheduledFrame: scheduledFrame,
          focusGraphChanged: focusGraphChangedDuringFrame,
          focusBindingChanged: focusBindingChangedDuringFrame,
          focusedValuesChanged: focusedValuesChangedDuringFrame,
          scrollPositionChanged: scrollPositionChangedDuringFrame,
          preferenceObservationChanged: preferenceObservationChanged,
          diagnosticsRequireFullRecord: true
        )
        diagnosticsLogger.log(
          FrameDiagnosticRecord(
            frameNumber: renderedFrames,
            causeSummary: causeSummary,
            focusSyncRerenders: focusSyncBudget.rerenderCount,
            invalidatedIdentityCount: diag.invalidatedIdentities.count,
            resolvedNodeCount: diag.resolvedNodeCount,
            resolvedNodesComputed: diag.resolvedNodesComputed,
            resolvedNodesReused: diag.resolvedNodesReused,
            measuredNodeCount: diag.measuredNodeCount,
            measuredNodesComputed: diag.measuredNodesComputed,
            measuredNodesReused: diag.measuredNodesReused,
            placedNodeCount: diag.placedNodeCount,
            drawNodeCount: diag.drawNodeCount,
            interactionRegionCount: diag.interactionRegionCount,
            focusRegionCount: diag.focusRegionCount,
            phaseTimings: diag.phaseTimings,
            renderGenerations: diag.renderGenerations,
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
            workerTimings: diag.workerTimings,
            mainActorTimings: diag.mainActorTimings,
            customLayoutFallbackCount: diag.customLayoutFallbackCount,
            firstCustomLayoutFallbackIdentity: diag.firstCustomLayoutFallbackIdentity?.path,
            layoutDependentRealizations: diag.layoutDependentRealizations,
            layoutDependentRealizationCacheHits: diag.layoutDependentRealizationCacheHits,
            layoutDependentMainActorFallbacks: diag.layoutDependentMainActorFallbacks,
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
            runtimePointerHandlerCount: diag.runtimeRegistrations.pointerHandlerCount,
            runtimePointerHoverHandlerCount: diag.runtimeRegistrations.pointerHoverHandlerCount,
            runtimeGestureRecognizerCount: diag.runtimeRegistrations.gestureRecognizerCount,
            runtimeGestureStateBindingCount: diag.runtimeRegistrations.gestureStateBindingCount,
            staleFramePolicy: "commit_ordered",
            tailJobState: tailJobState.rawValue,
            tailCancelReason: "-",
            cancelledRenderCount: cancelledRenderCount,
            newestDesiredAtTailStart: renderIntentDiagnostics.desiredGeneration,
            newestDesiredAtTailResult: renderIntentDiagnostics.desiredGeneration,
            dropEligibilityBlockers: dropEligibilityBlockers,
            dropDecision: completedFrameDropDecision?.action.rawValue
              ?? CompletedFrameDropDecision.Action.commitOrdered.rawValue,
            dropGeneration: nil,
            newestDesiredAtDrop: nil,
            dropReconciliationMode: completedFrameDropDecision?.reconciliation.mode.rawValue
              ?? "-",
            dropReconciliationEffects: completedFrameDropDecision?.reconciliation.effectSummary
              ?? "-",
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

      // Interactive rendering may enqueue more frames while a key or
      // pointer event is already buffered. Yield between committed frames
      // so task/animation invalidations cannot run ahead of user input.
      if eventPump?.hasPendingEvents() == true {
        break
      }
    }
    return nil
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

  private func applyTerminalCursorFocusPolicy(
    semanticSnapshot: SemanticSnapshot
  ) throws {
    guard runtimeConfiguration.output == .tui else {
      return
    }
    guard
      let terminalSurface = presentationSurface as? any TerminalCursorFocusPresentationSurface
    else {
      return
    }

    let focusedNode = focusedAccessibilityNode(in: semanticSnapshot)
    let usesTextInputCursor =
      focusedNode?.cursorAnchor != nil
      || currentFocusPresentation.prefersTextInput
    guard runtimeConfiguration.cursorFollowsFocus || usesTextInputCursor else {
      return
    }

    let cursorPoint =
      if runtimeConfiguration.cursorFollowsFocus {
        AccessibilityRuntimePolicy().focusedCursorPoint(
          in: semanticSnapshot,
          focusedIdentity: focusTracker.currentFocusIdentity
        )
      } else {
        focusedNode?.cursorAnchor
      }
    try terminalSurface.presentAccessibilityCursorFocus(at: cursorPoint)
  }

  private var usesTerminalCursorForTextInput: Bool {
    runtimeConfiguration.output == .tui
      && presentationSurface is any TerminalCursorFocusPresentationSurface
  }

  private func focusedAccessibilityNode(
    in semanticSnapshot: SemanticSnapshot
  ) -> AccessibilityNode? {
    guard let focusedIdentity = focusTracker.currentFocusIdentity else {
      return nil
    }
    return semanticSnapshot.accessibilityNodes.first { node in
      node.identity == focusedIdentity
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

  private func presentCommittedFrame(
    _ artifacts: FrameArtifacts,
    damage: PresentationDamage?
  ) throws -> TerminalPresentationMetrics {
    if runtimeConfiguration.output == .json {
      return try presentJSONFrame(
        artifacts,
        focusedIdentity: focusTracker.currentFocusIdentity
      )
    }

    if runtimeConfiguration.output == .accessible {
      return try presentLinearAccessibilityFrame(
        semanticSnapshot: artifacts.semanticSnapshot
      )
    }

    let metrics: TerminalPresentationMetrics
    if let semanticHost = presentationSurface as? any SemanticPresentationSurface {
      metrics = try semanticHost.present(
        artifacts.rasterSurface,
        semanticSnapshot: artifacts.semanticSnapshot,
        focusedIdentity: focusTracker.currentFocusIdentity
      )
    } else if let damageAwareHost = presentationSurface as? any DamageAwarePresentationSurface {
      metrics = try damageAwareHost.present(
        artifacts.rasterSurface,
        damage: damage
      )
    } else {
      metrics = try presentationSurface.present(artifacts.rasterSurface)
    }
    try applyTerminalCursorFocusPolicy(semanticSnapshot: artifacts.semanticSnapshot)
    return metrics
  }

  private func presentJSONFrame(
    _ artifacts: FrameArtifacts,
    focusedIdentity: Identity?
  ) throws -> TerminalPresentationMetrics {
    let output = JSONFrameRenderer().render(
      surface: artifacts.rasterSurface,
      semanticSnapshot: artifacts.semanticSnapshot,
      focusedIdentity: focusedIdentity
    )
    try presentationSurface.write(output)
    return metrics(forWrittenOutput: output)
  }

  private func presentLinearAccessibilityFrame(
    semanticSnapshot: SemanticSnapshot
  ) throws -> TerminalPresentationMetrics {
    let output =
      LinearAccessibilityRenderer().render(semanticSnapshot)
      + liveRegionAnnouncer.renderAnnouncements(for: semanticSnapshot)
    guard !output.isEmpty else {
      return TerminalPresentationMetrics()
    }

    try presentationSurface.write(output)
    return metrics(forWrittenOutput: output)
  }

  private func metrics(
    forWrittenOutput output: String
  ) -> TerminalPresentationMetrics {
    let bytesWritten = output.utf8.count
    let linesTouched = output.utf8.reduce(0) { partial, byte in
      partial + (byte == 0x0A ? 1 : 0)
    }
    return TerminalPresentationMetrics(
      bytesWritten: bytesWritten,
      linesTouched: linesTouched,
      cellsChanged: max(0, bytesWritten - linesTouched),
      strategy: .fullRepaint
    )
  }
}
