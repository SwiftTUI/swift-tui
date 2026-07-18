@MainActor
/// Draft-owned graph frame state that can be committed or discarded as a unit.
///
/// ViewGraph still applies node mutations while preparing the frame. This draft
/// owns the rollback checkpoint and the committed runtime-registration
/// publication plan so the frame-head registration draft never has to reset live
/// registries as part of its own commit.
package final class ViewGraphFrameDraft {
  package enum RuntimeRegistrationPublication: Equatable {
    case unchanged
    case all
    case subtrees([Identity])
  }

  private let liveRegistrations: RuntimeRegistrationSet
  private let checkpoint: ViewGraph.Checkpoint?
  private var preparedCheckpoint: ViewGraph.Checkpoint?
  private var dirtyEvaluationPlan: DirtyEvaluationPlan?
  /// The node count the most recent restore actually rewrote (the
  /// generation-gated restore skips nodes whose live generation matches the
  /// image). `nil` until a restore ran. Read by tests asserting restore
  /// precision.
  private(set) package var debugLastRestoreRestoredNodeCount: Int?
  private(set) package var runtimeRegistrationPublication: RuntimeRegistrationPublication =
    .unchanged
  private let publicationDiagnosticsEnabled: Bool
  private var publicationDiagnostics = RuntimeRegistrationPublicationDiagnostics()
  private var graphCheckpointRestoreCount = 0
  private var didCommit = false
  private var didDiscard = false

  package init(
    liveRegistrations: RuntimeRegistrationSet,
    checkpoint: ViewGraph.Checkpoint?,
    publicationDiagnosticsEnabled: Bool =
      RuntimeRegistrationPublicationDiagnosticsConfiguration.isEnabled
  ) {
    self.liveRegistrations = liveRegistrations
    self.checkpoint = checkpoint
    self.publicationDiagnosticsEnabled = publicationDiagnosticsEnabled
    // Cheap context (O(1) reads) is captured regardless of the diagnostics
    // flag, so a publication-oracle violation never arrives context-free
    // (F92). The flag now gates only the expensive census metrics (subtree
    // walks, identity censuses) and the downstream diagnostics exposure.
    publicationDiagnostics.graphCheckpointBaselineNodeCount =
      checkpoint?.index.nodesByNodeID.count
    publicationDiagnostics.nonGraphCheckpointPresent = checkpoint != nil
  }

  package func recordDirtyEvaluationPlan(
    _ plan: DirtyEvaluationPlan?,
    diagnostics dirtyPlanDiagnostics: DirtyEvaluationPlanDiagnostics? = nil
  ) {
    precondition(!didCommit && !didDiscard)
    dirtyEvaluationPlan = plan
    if let plan {
      recordSubtreePublication(rootedAt: plan.frontierIdentities)
    } else {
      runtimeRegistrationPublication = .all
    }
    recordDirtyPlanDiagnostics(dirtyPlanDiagnostics)
  }

  package func recordUnchangedDirtyEvaluation(
    diagnostics dirtyPlanDiagnostics: DirtyEvaluationPlanDiagnostics?
  ) {
    precondition(!didCommit && !didDiscard)
    recordDirtyPlanDiagnostics(dirtyPlanDiagnostics)
  }

  package func recordPresentationPortalRootQueued(
    _ queued: Bool,
    predicted: Bool
  ) {
    publicationDiagnostics.presentationPortalRootQueued = queued
    publicationDiagnostics.presentationPortalRootPredicted = predicted
    publicationDiagnostics.presentationPortalEscalated = false
  }

  package func recordPresentationPortalEscalation() {
    publicationDiagnostics.presentationPortalEscalated = true
  }

  package func recordPreparedCheckpoint(from viewGraph: ViewGraph) {
    precondition(!didCommit && !didDiscard)
    guard checkpoint != nil else {
      return
    }
    preparedCheckpoint = viewGraph.makeCheckpoint()
    publicationDiagnostics.graphCheckpointPreparedNodeCount =
      preparedCheckpoint?.index.nodesByNodeID.count
    publicationDiagnostics.graphCheckpointStrategy = "gen_gated_store"
    if publicationDiagnosticsEnabled {
      // The candidate count walks frontier subtrees — census-tier cost,
      // opt-in only.
      publicationDiagnostics.graphCheckpointDirtySubtreeCandidateNodeCount =
        graphCheckpointDirtySubtreeCandidateNodeCount(in: viewGraph)
    }
  }

  package func materializePreparedState(
    in viewGraph: ViewGraph,
    preservingCurrentStateMutations: Bool = false
  ) {
    precondition(!didCommit && !didDiscard)
    guard let preparedCheckpoint else {
      return
    }
    restoreGraphState(
      targetCheckpoint: preparedCheckpoint,
      in: viewGraph,
      preservingCurrentStateMutations: preservingCurrentStateMutations
    )
  }

  package func restoreBaselineState(
    in viewGraph: ViewGraph,
    preservingCurrentStateMutations: Bool = false
  ) {
    precondition(!didCommit && !didDiscard)
    guard let checkpoint else {
      return
    }
    restoreGraphState(
      targetCheckpoint: checkpoint,
      in: viewGraph,
      preservingCurrentStateMutations: preservingCurrentStateMutations
    )
  }

  @discardableResult
  package func commitRuntimeRegistrations(
    from viewGraph: ViewGraph
  ) -> RuntimeRegistrationDiagnostics {
    precondition(!didCommit && !didDiscard)
    var restoredNodeCount: Int?
    // On `.all` frames the publication-delta check below already builds the
    // current fingerprint; reuse it for the commit record instead of rebuilding
    // the full O(liveNodeIDs) fingerprint a second time. Other branches leave
    // this nil and the record call rebuilds.
    var committedFingerprint: RuntimeRegistrationGraphFingerprint?
    var usedScopedRestore = false
    var publicationIsUnchanged = false
    // In-place registration refreshes (a reused toolbar strip re-capturing its
    // item actions in the late-preference stage) mutate node records outside
    // any dirty plan; their refreshed records reach the live registry only
    // through this publication. Merge them in — on a plan-less frame this
    // escalates `.unchanged` to a narrow `.subtrees` publication, keeping the
    // `.unchanged` commit's byte-stable-fingerprint premise (the F63 DEBUG
    // oracle) true by construction.
    let refreshRoots = viewGraph.takePendingRuntimeRegistrationRefreshRoots()
    if !refreshRoots.isEmpty {
      recordSubtreePublication(rootedAt: refreshRoots)
    }
    switch runtimeRegistrationPublication {
    case .unchanged:
      // Nothing was re-evaluated, so no node's registrations changed. The live
      // registry usually already holds the last committed (canonical) state.
      // Still refresh the low-volume effect registries from all live nodes:
      // one-shot/fresh caller registries may be empty even when the graph is
      // unchanged, and preference/lifecycle/task effects need matching live
      // handlers. Keep high-volume and order-sensitive registries untouched so
      // unchanged commits do not duplicate focus candidates or handlers.
      restoredNodeCount = 0
      publicationIsUnchanged = true
      viewGraph.republishAllEffectRegistrations(into: liveRegistrations)
    case .all:
      commitFingerprintDeltaPublication(
        from: viewGraph,
        restoredNodeCount: &restoredNodeCount,
        committedFingerprint: &committedFingerprint,
        usedScopedRestore: &usedScopedRestore
      )
    case .subtrees(let roots):
      // Two escalations route onto the fingerprint-delta body (the `.all`-frame
      // publication), which restores only the entries whose registrations
      // actually changed and never consumes the frontier roots:
      //
      // 1. Root-rooted covers: a publication whose roots cover the graph root
      //    cannot take the identity-prefix scoped restore — the reset/restore
      //    axes diverge from the structural cover at the portal-host seam (see
      //    ``ViewGraph/runtimeRegistrationRootsRequireFullPublication(_:)``).
      //    The delta body is immune: its roots are fingerprint-entry
      //    identities, so capture-island entries are reached in their own
      //    authored identity space, and it self-escalates to the full
      //    reset-and-rebuild when the delta itself demands one (or when no
      //    committed fingerprint exists to diff against). F08's focus/press
      //    dirty frontier includes the graph root on every interaction frame
      //    (the root node is a dirty focus reader's nearest evaluator
      //    ancestor), so an unconditional full rebuild here costs O(live)
      //    commit per interaction frame — the sheet-scenario regression that
      //    held the 2026-07-03 reland.
      //
      // 2. Wide covers: a frontier that covers most of the live tree makes
      //    the per-node scoped restore O(live) even when almost no
      //    registration actually changed. Narrow, non-root frontiers keep the
      //    O(cover) scoped restore.
      let liveNodeCount = viewGraph.runtimeRegistrationLiveNodeCount
      if viewGraph.runtimeRegistrationRootsRequireFullPublication(roots)
        || viewGraph.runtimeRegistrationSubtreeCoverReaches(
          (liveNodeCount + 1) / 2,
          rootedAt: roots
        )
      {
        commitFingerprintDeltaPublication(
          from: viewGraph,
          restoredNodeCount: &restoredNodeCount,
          committedFingerprint: &committedFingerprint,
          usedScopedRestore: &usedScopedRestore
        )
        break
      }
      // The reset is scoped to `roots`; scope the restore to match instead of
      // re-publishing the whole tree. Untouched subtrees' registrations stay in
      // place, so the result equals a full rebuild for the changed subtrees —
      // this is the O(tree) commit win (the reset already removed exactly these
      // subtrees). See the registration-restore fix plan.
      if publicationDiagnosticsEnabled {
        restoredNodeCount = viewGraph.runtimeRegistrationSubtreeNodeCount(rootedAt: roots)
      }
      liveRegistrations.removeSubtrees(rootedAt: roots)
      viewGraph.restoreRuntimeRegistrationSubtrees(
        rootedAt: roots,
        into: liveRegistrations
      )
      // The scoped restore re-appends the changed subtree's focus registrations
      // at the end; normalize the order-sensitive focus lists back to canonical
      // identity order so the live registry is byte-identical to a full rebuild.
      liveRegistrations.normalizeScopedRestoreOrder()
      // The scoped restore above walks frontier-root ViewNode subtrees, which
      // cannot reach capture-hosted island nodes (lazy tab bodies, portal
      // attachments, lazy viewport entries) that resolved this frame outside any
      // frontier root, and reused stable subtrees are intentionally not walked.
      // Low-volume side-effect handlers on such nodes must still reach the
      // live registries or runtime commit/observation effects cannot invoke
      // them.
      viewGraph.republishAllEffectRegistrations(into: liveRegistrations)
      usedScopedRestore = true
    }
    // F04 publication oracle: on sampled probe frames, a scoped restore must
    // leave the live registries equal (keys + stacked-handler counts) to a
    // scratch full rebuild of the current frame's registrations. The scratch
    // set receives the same effect republication the live set got so the two
    // constructions are comparable.
    if usedScopedRestore, SoundnessProbeConfiguration.isSampledFrame {
      let scratch = RuntimeRegistrationSet.scratch()
      viewGraph.restoreCurrentFrameRuntimeRegistrations(into: scratch)
      viewGraph.republishAllEffectRegistrations(into: scratch)
      let live = liveRegistrations.publicationOracleFingerprint()
      let rebuilt = scratch.publicationOracleFingerprint()
      if live != rebuilt {
        // Mid-interaction preservation is part of the full-rebuild contract,
        // not a divergence: every publication teardown (`resetAll`,
        // `removeSubtrees`) spares ACTIVE recognizers and their paired
        // pointer/hover/gesture-state entries (`preservedGestureIdentities`,
        // F101 — a press-departed row's records vanish WITH the row while
        // the live registries deliberately keep the in-flight interaction).
        // The scratch is rebuilt from node records alone and cannot carry
        // that state, so live-side extras keyed exactly by a currently-
        // ACTIVE recognizer's identity are the designed one-interaction
        // window, not a publication bug. The excuse dies with the
        // interaction: the focus-sync liveness passes release a genuinely
        // departed recognizer (and its paired routes) right after commit,
        // so wrongful retention past the interaction still trips the oracle
        // on the next sampled scoped restore.
        let excusableKeys = excusableActiveInteractionKeys()
        let divergedKeys = Set(rebuilt.keys).union(live.keys)
          .filter { live[$0] != rebuilt[$0] }
          .filter { key in
            !(excusableKeys.contains(key) && rebuilt[key] == nil)
          }
          .sorted()
        if !divergedKeys.isEmpty {
          let diverged =
            divergedKeys
            .prefix(4)
            .map { "\($0) live=\(live[$0] ?? 0) rebuilt=\(rebuilt[$0] ?? 0)" }
          // The forensic context rides the violation itself (F92): the cheap
          // per-frame fields are captured regardless of the publication-
          // diagnostics flag, so a wild violation explains which plan and
          // checkpoint strategy produced it without a pre-set second opt-in.
          let disabledReasons = publicationDiagnostics.selectiveEvaluationDisabledReasons
          SoundnessProbeConfiguration.recordRegistrationPublicationViolation(
            """
            registration publication: scoped restore diverged from full \
            rebuild: \(diverged.joined(separator: ", ")) \
            [mode=\(publicationModeName) roots=\(publicationSubtreeRootCount) \
            dirty_plan=\(publicationDiagnostics.dirtyPlanResult) \
            selective_off=\(disabledReasons.isEmpty ? "-" : disabledReasons.joined(separator: "|")) \
            ckpt=\(publicationDiagnostics.graphCheckpointStrategy ?? "none") \
            portal_queued=\(publicationDiagnostics.presentationPortalRootQueued.map(String.init(describing:)) ?? "-") \
            portal_escalated=\(publicationDiagnostics.presentationPortalEscalated.map(String.init(describing:)) ?? "-")]
            """
          )
        }
      }
    }
    // Committed-handler resolution oracle (2026-07-17 campaign §5): every
    // appear/disappear handler ID the committed tree names must resolve in
    // the just-published live lifecycle registry. A hollow node record — a
    // re-minted or never-applied node adopted in place of the recording
    // owner — leaves the committed tree naming handlers no store can
    // dispatch, and the F04 oracle cannot see it (scoped restore and full
    // rebuild read the same hollowed records). Change handlers ride node
    // dispatch queues rather than committed metadata, so the appear and
    // disappear legs carry the class here.
    if SoundnessProbeConfiguration.isSampledFrame,
      let lifecycleRegistry = liveRegistrations.lifecycleRegistry,
      let committedRoot = viewGraph.committedRootSnapshotIfAvailable()
    {
      var missing: [String] = []
      var stack = [committedRoot]
      while let node = stack.popLast(), missing.count < 4 {
        for handlerID in node.lifecycleMetadata.appearHandlerIDs
        where lifecycleRegistry.appearHandler(for: handlerID) == nil {
          missing.append("appear:\(handlerID)")
        }
        for handlerID in node.lifecycleMetadata.disappearHandlerIDs
        where lifecycleRegistry.disappearHandler(for: handlerID) == nil {
          missing.append("disappear:\(handlerID)")
        }
        stack.append(contentsOf: node.children)
      }
      if !missing.isEmpty {
        SoundnessProbeConfiguration.recordCommittedHandlerResolutionViolation(
          """
          committed handler resolution: committed tree names handlers absent \
          from the published lifecycle registry: \(missing.joined(separator: ", ")) \
          [mode=\(publicationModeName) roots=\(publicationSubtreeRootCount)]
          """
        )
      }
    }
    if publicationIsUnchanged {
      viewGraph.recordCommittedRuntimeRegistrationFingerprintForUnchangedFrame()
    } else {
      viewGraph.recordCommittedRuntimeRegistrationFingerprint(committedFingerprint)
    }
    didCommit = true
    var diagnostics = liveRegistrations.diagnostics()
    publicationDiagnostics.publicationMode = publicationModeName
    publicationDiagnostics.subtreeRootCount = publicationSubtreeRootCount
    publicationDiagnostics.graphCheckpointDeltaRestoreCount = graphCheckpointRestoreCount
    publicationDiagnostics.graphCheckpointFallbackRestoreCount = 0
    if publicationDiagnosticsEnabled {
      publicationDiagnostics.restoredNodeCount = restoredNodeCount
      diagnostics.publication = publicationDiagnostics
    }
    return diagnostics
  }

  package func updateCommittedScrollGeometry(
    scrollRoutes: [ScrollRoute],
    scrollTargets: [ScrollTarget]
  ) {
    liveRegistrations.scrollPositionRegistry?.updateGeometry(
      scrollRoutes: scrollRoutes,
      scrollTargets: scrollTargets
    )
  }

  package func discard(
    from viewGraph: ViewGraph,
    preservingCurrentStateMutations: Bool = false
  ) {
    precondition(!didCommit && !didDiscard)
    restoreBaselineState(
      in: viewGraph,
      preservingCurrentStateMutations: preservingCurrentStateMutations
    )
    didDiscard = true
  }

  /// Discards the draft without restoring the baseline checkpoint. For heads
  /// whose baseline predates a sibling frame's commit (a stale baseline): the
  /// head is suspended, so live graph state is the baseline plus the sibling
  /// commits, and restoring the captured baseline would rewind those commits
  /// (the checkpoint's whole-index restore evicts subtrees the sibling
  /// minted). Dropping the pending draft is the only sound action.
  package func discardWithoutRestore() {
    precondition(!didCommit && !didDiscard)
    didDiscard = true
  }

  /// The `.all`-frame publication body: fingerprint-delta scoped restore when
  /// the delta is publishable, full reset-and-rebuild otherwise. Also the
  /// escalation target for `.subtrees` frames whose frontier covers the graph
  /// root or most of the live tree.
  private func commitFingerprintDeltaPublication(
    from viewGraph: ViewGraph,
    restoredNodeCount: inout Int?,
    committedFingerprint: inout RuntimeRegistrationGraphFingerprint?,
    usedScopedRestore: inout Bool
  ) {
    let publication = viewGraph.runtimeRegistrationPublicationDeltaForCurrentFrame()
    committedFingerprint = publication?.current
    if let delta = publication?.delta,
      !viewGraph.runtimeRegistrationDeltaRequiresFullPublication(delta)
    {
      if publicationDiagnosticsEnabled {
        restoredNodeCount = viewGraph.runtimeRegistrationSubtreeNodeCount(
          rootedAt: delta.restorationRoots
        )
      }
      if !delta.isEmpty {
        liveRegistrations.removeSubtrees(rootedAt: delta.removalRoots)
        viewGraph.restoreRuntimeRegistrationSubtrees(
          rootedAt: delta.restorationRoots,
          into: liveRegistrations
        )
        liveRegistrations.normalizeScopedRestoreOrder()
        usedScopedRestore = true
      }
      viewGraph.republishAllEffectRegistrations(into: liveRegistrations)
    } else {
      if publicationDiagnosticsEnabled {
        restoredNodeCount = viewGraph.runtimeRegistrationLiveNodeCount
      }
      liveRegistrations.resetAll()
      viewGraph.restoreCurrentFrameRuntimeRegistrations(into: liveRegistrations)
    }
  }

  private func recordSubtreePublication(rootedAt roots: [Identity]) {
    guard !roots.isEmpty else {
      return
    }
    switch runtimeRegistrationPublication {
    case .unchanged:
      runtimeRegistrationPublication = .subtrees(roots)
    case .subtrees(let existing):
      runtimeRegistrationPublication = .subtrees(existing + roots)
    case .all:
      break
    }
  }

  private func graphCheckpointDirtySubtreeCandidateNodeCount(
    in viewGraph: ViewGraph
  ) -> Int? {
    switch runtimeRegistrationPublication {
    case .unchanged:
      return 0
    case .subtrees:
      guard let dirtyEvaluationPlan else {
        return nil
      }
      return viewGraph.runtimeRegistrationSubtreeNodeCount(
        rootedAt: dirtyEvaluationPlan.frontierIdentities
      )
    case .all:
      return nil
    }
  }

  private func recordDirtyPlanDiagnostics(
    _ dirtyPlanDiagnostics: DirtyEvaluationPlanDiagnostics?
  ) {
    guard let dirtyPlanDiagnostics else {
      return
    }
    publicationDiagnostics.dirtyPlanResult = dirtyPlanDiagnostics.result
    publicationDiagnostics.invalidatedIdentityCount =
      dirtyPlanDiagnostics.invalidatedIdentityCount
    publicationDiagnostics.unmappedInvalidatedIdentityCount =
      dirtyPlanDiagnostics.unmappedInvalidatedIdentityCount
    publicationDiagnostics.unmappedInvalidatedIdentitySample =
      dirtyPlanDiagnostics.unmappedInvalidatedIdentitySample
    publicationDiagnostics.remappedInvalidatedIdentityCount =
      dirtyPlanDiagnostics.remappedInvalidatedIdentityCount
    publicationDiagnostics.droppedInvalidatedIdentityCount =
      dirtyPlanDiagnostics.droppedInvalidatedIdentityCount
    publicationDiagnostics.reconciledInvalidatedNodeCount =
      dirtyPlanDiagnostics.reconciledInvalidatedNodeCount
    publicationDiagnostics.selectiveEvaluationDisabledReasons =
      dirtyPlanDiagnostics.selectiveEvaluationDisabledReasons
  }

  private func restoreGraphState(
    targetCheckpoint: ViewGraph.Checkpoint,
    in viewGraph: ViewGraph,
    preservingCurrentStateMutations: Bool
  ) {
    let stateMutations =
      preservingCurrentStateMutations
      ? viewGraph.stateMutationOverlay(restorableInto: targetCheckpoint) : nil
    // The restore is generation-gated inside ViewGraph (only nodes whose live
    // generation differs from the image are rewritten) and carries its own
    // gated-vs-ungated soundness oracle — no plan/fallback machinery here.
    let restoredNodeCount = viewGraph.restoreCheckpoint(targetCheckpoint)
    recordRestoreResult(restoredNodeCount: restoredNodeCount)
    if let stateMutations, !stateMutations.isEmpty {
      viewGraph.applyStateMutationOverlay(stateMutations)
    }
  }

  private func recordRestoreResult(restoredNodeCount: Int) {
    debugLastRestoreRestoredNodeCount = restoredNodeCount
    graphCheckpointRestoreCount += 1

    guard publicationDiagnosticsEnabled else {
      return
    }
    publicationDiagnostics.graphCheckpointRestoreStrategy = "gen_gated"
    publicationDiagnostics.graphCheckpointRestoreFallbackReason = nil
    publicationDiagnostics.graphDeltaCheckpointNodeCount = restoredNodeCount
    publicationDiagnostics.graphCheckpointDeltaRestoreCount = graphCheckpointRestoreCount
    publicationDiagnostics.graphCheckpointFallbackRestoreCount = 0
  }

  private var publicationModeName: String {
    switch runtimeRegistrationPublication {
    case .unchanged:
      "unchanged"
    case .all:
      "all"
    case .subtrees:
      "subtrees"
    }
  }

  private var publicationSubtreeRootCount: Int {
    switch runtimeRegistrationPublication {
    case .unchanged, .all:
      0
    case .subtrees(let roots):
      roots.count
    }
  }

  /// The oracle-fingerprint keys the live registries may legitimately hold
  /// beyond a node-record rebuild: entries keyed by a currently-ACTIVE
  /// recognizer's identity, exactly the families the publication teardowns
  /// spare through `preservedGestureIdentities` (the recognizer itself, its
  /// paired pointer/hover routes, and its gesture-state bindings). Built
  /// from the LIVE registries so only keys that actually survived a spare
  /// can be excused — and only in the live-extra direction (the caller
  /// additionally requires the rebuilt side to lack the key entirely).
  private func excusableActiveInteractionKeys() -> Set<String> {
    guard let gestureRegistry = liveRegistrations.gestureRegistry else {
      return []
    }
    let activeIdentities = Set(
      gestureRegistry.snapshot().compactMap { identity, recognizer in
        recognizer.isActive ? identity : nil
      }
    )
    guard !activeIdentities.isEmpty else {
      return []
    }
    var keys: Set<String> = []
    for identity in activeIdentities {
      keys.insert("gesture|\(identity.path)")
      keys.insert("gestureState|\(identity.path)")
    }
    if let pointerRegistry = liveRegistrations.pointerHandlerRegistry {
      for routeID in pointerRegistry.snapshot().keys
      where activeIdentities.contains(routeID.identity) {
        keys.insert("pointer|\(routeID)")
      }
      for routeID in pointerRegistry.snapshotHover().keys
      where activeIdentities.contains(routeID.identity) {
        keys.insert("hover|\(routeID)")
      }
    }
    return keys
  }

}
