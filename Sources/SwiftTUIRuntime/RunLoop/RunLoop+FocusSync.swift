import SwiftTUICore
import SwiftTUIViews

extension RunLoop {
  /// A keyboard focus traversal (Tab / Shift+Tab / arrow move) recorded when
  /// it lands, together with the region list it traversed. Held until the
  /// next input event so the runtime can recognize a landing region that
  /// vanishes as a consequence of the traversal itself and continue in the
  /// traversal direction. See ``RunLoop/pendingFocusTraversal``.
  package struct PendingFocusTraversal {
    /// Document-order direction of the traversal: `+1` forward, `-1` backward.
    var step: Int
    /// The focus region identity the traversal landed on.
    var landedIdentity: Identity
    /// The tracker's region list at the moment of the traversal — the only
    /// record of the vanished region's document-order neighbors.
    var regionsAtTraversal: [FocusRegion]
  }

  /// Runs `move` (a `FocusTracker` traversal) and records it as the pending
  /// focus traversal, replacing any previous record.
  package func performFocusTraversal(
    step: Int,
    _ move: () -> Identity?
  ) {
    let regionsAtTraversal = focusTracker.focusRegions
    let previousFocus = focusTracker.currentFocusIdentity
    guard let landedIdentity = move(), landedIdentity != previousFocus else {
      // A traversal that did not move focus needs no continuation record.
      pendingFocusTraversal = nil
      return
    }
    pendingFocusTraversal = PendingFocusTraversal(
      step: step,
      landedIdentity: landedIdentity,
      regionsAtTraversal: regionsAtTraversal
    )
  }

  /// Resolves where a traversal whose landing region vanished should continue:
  /// the first region after (or before, for a backward step) the vanished one
  /// in the traversed list's document order that still exists in `regions`.
  private func focusTraversalContinuationIdentity(
    for pending: PendingFocusTraversal,
    in regions: [FocusRegion]
  ) -> Identity? {
    let traversed = pending.regionsAtTraversal
    guard
      let vanishedIndex = traversed.firstIndex(where: {
        $0.identity == pending.landedIdentity
      })
    else {
      return nil
    }
    let count = traversed.count
    var candidate = vanishedIndex
    for _ in 1..<count {
      candidate = (candidate + pending.step + count) % count
      let identity = traversed[candidate].identity
      if regions.contains(where: { $0.identity == identity }) {
        return identity
      }
    }
    return nil
  }

  /// Accumulated focus/scroll convergence state threaded through single-pass
  /// focus-sync (the at-most-one eager re-render) and into the shared
  /// post-acquisition body.
  package struct FocusSyncConvergenceState {
    var rerenderedForFocusSync = false
    var focusGraphChanged = false
    var focusBindingChanged = false
    var focusedValuesChanged = false
    var scrollPositionChanged = false
    /// Whether the one deterministic eager re-render that applies a focus-location
    /// change to the committed frame has already run this frame. Caps eager
    /// location application at a single extra pass — focus location cannot
    /// oscillate, so one pass suffices; any residual change after it lags to the
    /// next frame. This single-pass cap is the convergence guarantee (there is no
    /// loop and no budget to exhaust).
    var didEagerFocusLocationRerender = false
    var lifecycleCarryForward: [LifecycleCommitEntry] = []
    /// The scheduler's pending invalidations snapshotted by the driver right
    /// before each render pass. The rerender branch diffs against this to
    /// name every identity invalidated since the pass began.
    var pendingInvalidationsAtPassStart: Set<Identity> = []
    /// Identities invalidated after the previous render pass started — by
    /// resolve-time side effects the pass could not see at its head
    /// (default-focus seeding through a `@FocusState` request) and by the
    /// relocation side effects of focus-sync processing (`@FocusState` flips
    /// applied by the binding sync, the focus tracker's old/new notification,
    /// scroll-reveal offset writes). The eager rerender folds them into its
    /// invalidation set: they are already queued as graph-local dirty work,
    /// but without an invalidation cone their structural descendants would
    /// take retained reuse of pre-relocation content.
    var midFrameRelocationInvalidations: Set<Identity> = []

    /// Focus-sync eager re-renders this frame (0 or 1). Surfaced as the
    /// `focusSyncRerenders` frame diagnostic.
    var rerenderCount: Int {
      didEagerFocusLocationRerender ? 1 : 0
    }
  }

  /// Result of processing one rendered tree in single-pass focus-sync: whether
  /// the runtime must run the one eager focus-location re-render, or (when it
  /// must not) commit the rendered tree as-is.
  package enum FocusSyncIterationOutcome {
    /// A focus-location change needs the single eager re-render to land on the
    /// committed frame.
    case rerender
    /// Nothing further to render this frame; commit it. (A pure focused-value
    /// change schedules precise reader invalidation for the next frame.)
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

  /// Shared body of single-pass focus-sync. Applies the side effects that must
  /// run for every rendered tree (snapshot publication, gesture pruning,
  /// pointer-hover mode, pointer-capture release, focus/scroll/focused-value
  /// sync) and folds the resulting change flags into `convergence`. Returns
  /// whether the runtime must run the one eager focus-location re-render.
  package func processFocusSyncIteration(
    _ renderedArtifacts: FrameArtifacts,
    convergence: inout FocusSyncConvergenceState
  ) throws -> FocusSyncIterationOutcome {
    latestSemanticSnapshot = renderedArtifacts.semanticSnapshot
    // Order is load-bearing (F101): gesture pruning first, then the pointer
    // capture/hover paired-region pass below. The pointer registry does not
    // participate in `prune(keeping:)` — this sequencing IS its node-liveness
    // cleanup: a captured/hovered route whose region genuinely departed is
    // released here, and a re-minted one is re-keyed. Reordering these (or
    // pruning pointer state before the paired-region check) would release
    // live captures that the re-key path exists to preserve.
    runtimeRegistrations.pruneOrphanedGestures(
      keeping: renderer.liveNodeIDSnapshot()
    )
    try updateTerminalPointerHoverModeIfNeeded()

    // Release pointer capture only if the captured control genuinely left the
    // rendered tree (e.g. a view with an active gesture was removed
    // mid-interaction). A churn frame that merely re-minted the control's
    // chrome keeps a region at the same identity + kind under a fresh
    // `ownerNodeID` — re-key the capture to it instead of force-releasing a
    // live gesture.
    if let capturedID = pointerInteraction.capturedRouteID {
      if let paired = pairedInteractionRegion(for: capturedID) {
        if paired.routeID != capturedID {
          pointerInteraction.rekeyCapturedRoute(to: paired.routeID)
        }
      } else {
        pointerInteraction.clearRouting()
      }
    }
    // Same re-mint tolerance for hover continuity: only a genuinely departed
    // region ends the hover; a re-minted one re-keys so the next move stays a
    // `.moved`, not a spurious exit/enter pair.
    if let hoveredPointerRouteID {
      if let paired = pairedInteractionRegion(for: hoveredPointerRouteID) {
        if paired.routeID != hoveredPointerRouteID {
          self.hoveredPointerRouteID = paired.routeID
        }
      } else {
        self.hoveredPointerRouteID = nil
      }
    }

    let previousModalFocusScopePath = currentModalFocusScopePath()
    let nextModalFocusScopePath = activeModalFocusScopePath(
      in: renderedArtifacts.semanticSnapshot.focusRegions
    )
    let shouldApplyDefaultFocus =
      focusTracker.currentFocusIdentity == nil && !focusTracker.isPreservingNoFocus
      || (nextModalFocusScopePath != nil && nextModalFocusScopePath != previousModalFocusScopePath)
    let hadFocusBeforeRegionUpdate = focusTracker.currentFocusIdentity != nil
    var focusChanged = focusTracker.updateRegions(
      renderedArtifacts.semanticSnapshot.focusRegions)
    // A traversal's landing region vanished before any further input: the
    // control revoked its own focusability as a consequence of receiving
    // focus (e.g. `.disabled` reading a `@FocusedValue` that the traversal
    // un-published). The tracker's scope-replacement re-seat points backward
    // and would trap the Tab cycle, so continue the traversal instead: focus
    // the vanished region's next surviving document-order neighbor in the
    // traversal direction. Consumed one-shot; any explicit focus request
    // below still overrides.
    if let pending = pendingFocusTraversal,
      !renderedArtifacts.semanticSnapshot.focusRegions.contains(where: {
        $0.identity == pending.landedIdentity
      })
    {
      pendingFocusTraversal = nil
      if let continuation = focusTraversalContinuationIdentity(
        for: pending,
        in: renderedArtifacts.semanticSnapshot.focusRegions
      ) {
        focusChanged = focusTracker.setFocus(to: continuation) || focusChanged
      }
    }
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

      // Single-pass convergence, split by node kind — no loop, no budget.
      //
      // Focus *location* (focus moved / a focus request applied / a `@FocusState`
      // flip / scroll-to-reveal) is not a feedback edge — it is determined by the
      // event plus the rendered regions, then applied, and cannot oscillate. Apply
      // it eagerly with exactly **one** extra render so the committed frame shows
      // the correct focus. `currentFocusedValues` was updated just above, so the
      // focused values ride along on that same re-render. Capped at one pass by
      // `didEagerFocusLocationRerender` (the termination guarantee); any residual
      // change after it lags a frame.
      let focusLocationChanged =
        focusChanged || focusJustEstablished || appliedFocusRequest
        || appliedDefaultFocusRequest || focusStateChanged || scrollPositionChanged
      if focusLocationChanged, !convergence.didEagerFocusLocationRerender {
        convergence.didEagerFocusLocationRerender = true
        convergence.rerenderedForFocusSync = true
        convergence.midFrameRelocationInvalidations.formUnion(
          schedulerPendingInvalidations().subtracting(
            convergence.pendingInvalidationsAtPassStart
          )
        )
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
