// Bulk operations over the runtime registration set.
//
// `RuntimeRegistrationSet.swift` defines the aggregate and how it is
// constructed; this file owns the operations the run loop drives across every
// member registry each frame: full reset, subtree removal, orphaned-gesture
// pruning, restoration from committed node handlers, diagnostics, and
// frame-drop eligibility blockers.
//
// Every operation is a loop over `allRegistries` through the `RuntimeRegistry`
// lifecycle contract, so a member registry participates in each fan-out by
// construction. Cross-registry inputs (the mid-interaction gesture identities
// the pointer/gesture/gesture-state teardown spares) are snapshotted into the
// context BEFORE the loop so no registry observes another's partial teardown.
extension RuntimeRegistrationSet {
  package func resetAll() {
    let context = RuntimeRegistrationLifetimeContext(
      preservedGestureIdentities: gestureRegistry?.activeIdentitySnapshot() ?? []
    )
    for registry in allRegistries {
      registry.reset(context: context)
    }
  }

  package func removeSubtrees(
    rootedAt roots: [Identity]
  ) {
    guard !roots.isEmpty else {
      return
    }

    let context = RuntimeRegistrationLifetimeContext(
      preservedGestureIdentities: gestureRegistry?.activeIdentities(rootedAt: roots) ?? []
    )
    for registry in allRegistries {
      registry.removeSubtrees(rootedAt: roots, context: context)
    }
  }

  /// After a scoped `.subtrees` restore, re-sorts the only registries whose
  /// cross-node restore order is observable — the global append-ordered focus
  /// lists — into canonical identity order, so the result is byte-identical to
  /// a full rebuild. The dict/route-keyed registries are order-independent, and
  /// the per-identity handler lists (key/termination) come from a single node
  /// each (their within-identity order is preserved by the scoped restore and
  /// their cross-identity dispatch order is determined by the focus/identity
  /// path at dispatch time, not restore order), so those normalize as no-ops.
  package func normalizeScopedRestoreOrder() {
    for registry in allRegistries {
      registry.normalizeOrderByIdentity()
    }
  }

  package func pruneOrphanedGestures(
    keeping liveNodeIDs: Set<ViewNodeID>
  ) {
    for registry in allRegistries {
      registry.prune(keeping: liveNodeIDs)
    }
  }

  package func restore(
    from handlers: NodeHandlers,
    recency: UInt64 = 0
  ) {
    let context = RuntimeRegistrationRestoreContext(
      recency: recency,
      activeGestureIdentities: gestureRegistry?.activeIdentitySnapshot() ?? []
    )
    for registry in allRegistries {
      registry.restore(from: handlers, context: context)
    }
  }

  /// Restores ONLY the effect registries (lifecycle, task, and
  /// preference-observation registrations) from a node's handlers. Used by the
  /// always-full effect-registration republication that runs even on
  /// scoped-publication frames, so handlers on a capture-hosted,
  /// viewport-activated, or otherwise reused node are available when the
  /// runtime applies side effects for that node.
  package func restoreEffectRegistrations(from handlers: NodeHandlers) {
    let context = RuntimeRegistrationRestoreContext()
    for registry in allRegistries where registry.isEffectRegistry {
      registry.restore(from: handlers, context: context)
    }
  }

  package func diagnostics() -> RuntimeRegistrationDiagnostics {
    let gestureStateRegistrations = gestureStateRegistry?.snapshot() ?? [:]
    return RuntimeRegistrationDiagnostics(
      pointerHandlerCount: pointerHandlerRegistry?.snapshot().count ?? 0,
      pointerHoverHandlerCount: pointerHandlerRegistry?.snapshotHover().count ?? 0,
      gestureRecognizerCount: gestureRegistry?.snapshot().count ?? 0,
      gestureStateBindingCount: gestureStateRegistrations.values.reduce(0) { count, bindings in
        count + bindings.count
      }
    )
  }

  package func frameDropEligibilityBlockers() -> Set<FrameDropEligibility.Blocker> {
    var blockers: Set<FrameDropEligibility.Blocker> = []
    for registry in allRegistries {
      if let blocker = registry.activeFrameDropEligibilityBlocker {
        blockers.insert(blocker)
      }
    }
    return blockers
  }
}
