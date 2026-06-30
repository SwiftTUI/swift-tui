import SwiftTUICore
import SwiftTUIViews

extension RunLoop {
  /// Accumulated focus/scroll convergence state threaded through the
  /// focus-sync rerender loop and into the shared post-acquisition body.
  package struct FocusSyncConvergenceState {
    var rerenderedForFocusSync = false
    var budget: FocusSyncRerenderBudget?
    var budgetExceeded = false
    var focusGraphChanged = false
    var focusBindingChanged = false
    var focusedValuesChanged = false
    var scrollPositionChanged = false
    /// Single-pass mode only: whether the one deterministic eager re-render that
    /// applies a focus-location change to the committed frame has already run
    /// this frame. Caps eager location application at a single extra pass (no
    /// budget) — focus location cannot oscillate, so one pass suffices; any
    /// residual change after it lags to the next frame.
    var didEagerFocusLocationRerender = false
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
  package enum FocusSyncIterationOutcome {
    /// The rendered tree changed focus/scroll state — rerender to converge.
    case rerender
    /// The rendered tree is converged; commit it.
    case converged
  }

  package func appendLifecycleCarryForward(
    _ lifecycle: [LifecycleCommitEntry],
    into carryForward: inout [LifecycleCommitEntry]
  ) {
    for entry in lifecycle where !carryForward.contains(entry) {
      carryForward.append(entry)
    }
  }

  /// Shared per-iteration body of the focus-sync convergence loop. Applies
  /// the side effects that must run for every rendered tree (snapshot
  /// publication, gesture pruning, pointer-hover mode, pointer-capture
  /// release, focus/scroll/focused-value sync) and folds the resulting
  /// change flags into `convergence`. Returns whether the runtime must
  /// rerender to converge.
  package func processFocusSyncIteration(
    _ renderedArtifacts: FrameArtifacts,
    convergence: inout FocusSyncConvergenceState
  ) throws -> FocusSyncIterationOutcome {
    latestSemanticSnapshot = renderedArtifacts.semanticSnapshot
    runtimeRegistrations.pruneOrphanedGestures(
      keeping: renderer.liveNodeIDSnapshot()
    )
    try updateTerminalPointerHoverModeIfNeeded()

    // Release pointer capture if the captured region disappeared from
    // the rendered tree (e.g. a view with an active gesture was removed
    // mid-interaction).
    if let capturedID = pointerInteraction.capturedRouteID,
      interactionRegion(routeID: capturedID) == nil
    {
      pointerInteraction.clearRouting()
    }
    if let hoveredPointerRouteID,
      interactionRegion(routeID: hoveredPointerRouteID) == nil
    {
      self.hoveredPointerRouteID = nil
    }

    let previousModalFocusScopePath = currentModalFocusScopePath()
    let nextModalFocusScopePath = activeModalFocusScopePath(
      in: renderedArtifacts.semanticSnapshot.focusRegions
    )
    let shouldApplyDefaultFocus =
      focusTracker.currentFocusIdentity == nil && !focusTracker.isPreservingNoFocus
      || (nextModalFocusScopePath != nil && nextModalFocusScopePath != previousModalFocusScopePath)
    let hadFocusBeforeRegionUpdate = focusTracker.currentFocusIdentity != nil
    let focusChanged = focusTracker.updateRegions(
      renderedArtifacts.semanticSnapshot.focusRegions)
    // Initial focus auto-adoption (nil → a control) is deliberately *not* flagged
    // as a change by `updateRegions` (it avoids forcing a second frame in the
    // legacy loop). It is still a focus-location establishment: in single-pass
    // mode the focused subtree it adopts may publish focused values, so the
    // committed frame must reflect it. Treat the nil → focused transition as a
    // location change for the eager re-render below.
    let focusJustEstablished =
      !hadFocusBeforeRegionUpdate && focusTracker.currentFocusIdentity != nil
    let desiredFocusRequest = localFocusBindingRegistry.desiredFocusRequest(
      allowedIdentities: Set(renderedArtifacts.semanticSnapshot.focusRegions.map(\.identity))
    )
    let appliedFocusRequest = applyDesiredFocusRequest(desiredFocusRequest)
    let defaultFocusRequest = localDefaultFocusRegistry.desiredFocusRequest(
      focusRegions: renderedArtifacts.semanticSnapshot.focusRegions,
      shouldApplyInitialDefault: desiredFocusRequest == .none && shouldApplyDefaultFocus
    )
    let appliedDefaultFocusRequest = applyDesiredFocusRequest(defaultFocusRequest)
    let focusStateChanged = localFocusBindingRegistry.sync(
      actualFocusedIdentity: focusTracker.currentFocusIdentity
    )
    let resolvedFocusedValues = localFocusedValuesRegistry.focusedValues(
      for: focusTracker.currentFocusIdentity,
      in: renderedArtifacts.resolvedTree
    )
    // Main-actor semantic comparison: a focused `Binding` is compared by its
    // current value, not identity (it has none across renders), so a stable
    // focused binding converges this loop instead of comparing unequal forever.
    let focusedValuesChanged = !resolvedFocusedValues.focusSyncEquals(currentFocusedValues)
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

      if SinglePassFocusConvergenceConfiguration.isEnabled {
        // Single-pass convergence, split by node kind (no budget):
        //
        // Focus *location* (focus moved / a focus request applied / a `@FocusState`
        // flip / scroll-to-reveal) is not a feedback edge — it is determined by the
        // event plus the rendered regions, then applied, and cannot oscillate. Apply
        // it eagerly with exactly **one** extra render so the committed frame shows
        // the correct focus. `currentFocusedValues` was updated just above, so the
        // focused values ride along on that same re-render. Capped at one pass by
        // `didEagerFocusLocationRerender`; any residual change after it lags a frame.
        let focusLocationChanged =
          focusChanged || focusJustEstablished || appliedFocusRequest
          || appliedDefaultFocusRequest || focusStateChanged || scrollPositionChanged
        if focusLocationChanged, !convergence.didEagerFocusLocationRerender {
          convergence.didEagerFocusLocationRerender = true
          convergence.rerenderedForFocusSync = true
          return .rerender
        }

        // A *pure* focused-value change (the focused subtree republished without
        // focus moving) is the genuine output→input feedback edge. Do not loop on
        // it: it lags one frame via reader invalidation. Invalidate exactly the
        // `@FocusedValue`/`@FocusedBinding` readers — found via the reader
        // attribution recorded during resolve — rather than the whole tree. The
        // readers re-resolve next frame (selective evaluation) and read the
        // just-updated `currentFocusedValues`, while sibling subtrees stay reused.
        // The dependency index persists across reuse, so a reader reused since its
        // last resolve is still found and never left stale. An empty set means
        // nothing reads the focused value, so there is nothing to invalidate.
        if focusedValuesChanged {
          let focusedValueReaders = renderer.focusedValuesDependentIdentities()
          if !focusedValueReaders.isEmpty {
            scheduler.requestInvalidation(of: focusedValueReaders)
          }
        }
        return .converged
      }

      convergence.rerenderedForFocusSync = true
      if !convergence.recordRerender(for: renderedArtifacts.semanticSnapshot) {
        convergence.budgetExceeded = true
      }
      return .rerender
    }
    return .converged
  }

  private func applyDesiredFocusRequest(
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

  private func currentModalFocusScopePath() -> [Identity]? {
    guard
      let focusedIdentity = focusTracker.currentFocusIdentity,
      let focusedRegion = focusTracker.focusRegions.first(where: { $0.identity == focusedIdentity })
    else {
      return nil
    }
    return focusedRegion.modalFocusScopePath
  }

  private func activeModalFocusScopePath(
    in regions: [FocusRegion]
  ) -> [Identity]? {
    guard
      let firstRegion = regions.first,
      let firstModalFocusScopePath = firstRegion.modalFocusScopePath
    else {
      return nil
    }
    return regions.allSatisfy { $0.modalFocusScopePath == firstModalFocusScopePath }
      ? firstModalFocusScopePath
      : nil
  }
}
