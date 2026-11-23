@_spi(Testing) package import SwiftTUICore
package import SwiftTUIViews

/// The stateful per-renderer animation engine.
///
/// Lives for the lifetime of one renderer and holds the previous frame's
/// animatable snapshots, active animation records, transition bookkeeping,
/// and registered animation/completion closures used by frame ticks.
@MainActor
package final class AnimationController: Sendable {
  /// Snapshots and topology captured at the end of the previous frame.
  private var previousFrame = PreviousFrameState()
  /// `.transition()` registration maps (current / previous / pending).
  private var transitions = TransitionRegistry()
  /// `withAnimation` batch ref-count bookkeeping (counts + empty-batch drains).
  private var batchCompletion = BatchCompletionState()
  /// Frame-head transaction bookkeeping (open flag + deferred completions).
  private var frameHead = FrameHeadTransactionState()
  /// The async-writable registration set — completion closures + animation-box
  /// registrations an async task can grow between frames; carried across an
  /// in-flight publish as a unit. See ``CompletionLedger``.
  private var completionLedger = CompletionLedger()
  /// Targets and per-frame samples of the `Animatable` views and modifiers
  /// (`AnimatableValueSite`). See ``ValueSiteState``.
  private var valueSites = ValueSiteState()
  /// What the frame head decided for the transition bodies inserted on the
  /// frame being prepared. See ``TransitionBodyInsertionRecords``.
  private var bodyInsertions = TransitionBodyInsertionRecords()

  private var activeAnimations: [AnimationKey: ActiveAnimation] = [:]
  private var removingNodes: [ViewNodeID: RemovalEntry] = [:]
  /// Presentation values sampled by the most recent `applyInterpolations`.
  /// Reused by late-preference reconciliation without advancing curves again.
  private var currentResolvedPresentationProjection = ResolvedPresentationProjection()
  package private(set) var lastTickResult: AnimationTickResult = .init()
  /// Nodes visited by the most recent resolved-tree snapshot/diff census.
  /// Deadline-only F149 skips report zero.
  package private(set) var lastResolvedTreeProcessedNodeCount = 0
  /// Nodes visited while applying property interpolation on the most recent
  /// tick. A routed single-property update visits only its ancestor route.
  package private(set) var lastPropertyInterpolationVisitedNodeCount = 0
  /// Monotonic generation bumped by ``reset()``. A frame draft captures this at
  /// creation; if it advances before the draft commits, the reset happened
  /// mid-flight and the draft's pre-reset state must not be republished.
  fileprivate private(set) var resetEpoch = 0

  /// Committed-frame completion dispatch deferral (frame-driver scope).
  ///
  /// A `withAnimation` completion that comes due during a frame fires at that
  /// frame's commit — but the SAME commit also dispatches the frame's planned
  /// lifecycle actions (`onChange`), and no resolve runs between the two. A
  /// completion's state write was therefore observable to a same-frame
  /// `onChange` before any body re-evaluation saw it: the counter demo's
  /// stuck ripple (completion lowers a guard flag, `onChange` re-raises it,
  /// the flag commits "unchanged", the guarded branch never unmounts — an
  /// absorbing state). SwiftUI is immune because each completion's write and
  /// the re-evaluation it causes commit as one unit before the next event
  /// unit runs.
  ///
  /// While a frame driver holds this scope, committed completions queue here
  /// instead of firing inline; the driver fires them AFTER the frame's
  /// lifecycle dispatch, so the completion's writes get their own resolve
  /// before any later lifecycle action can read them. Outside the scope
  /// (bare renders — no lifecycle dispatch exists there) firing stays
  /// inline. ``reset()`` leaves the queue untouched: a queued completion's
  /// batch already completed, and the SwiftUI-shaped guarantee — every
  /// `withAnimation` completion eventually fires — is the driver's to honor
  /// at its next drain site.
  private var isDeferringCommittedCompletionDispatch = false
  private var deferredCommittedCompletions: [@MainActor @Sendable () -> Void] = []

  /// Opens the frame-driver deferral scope. Non-reentrant: the two run-loop
  /// frame drivers are mutually exclusive via the terminal render pass.
  package func beginDeferringCommittedCompletionDispatch() {
    precondition(
      !isDeferringCommittedCompletionDispatch,
      "committed-completion deferral scopes cannot be nested"
    )
    isDeferringCommittedCompletionDispatch = true
  }

  /// Closes the deferral scope and returns any still-queued completions —
  /// the caller must invoke them (the pass-end backstop for paths that throw
  /// before a mid-pass drain site).
  package func endDeferringCommittedCompletionDispatch()
    -> [@MainActor @Sendable () -> Void]
  {
    isDeferringCommittedCompletionDispatch = false
    return takeDeferredCommittedCompletions()
  }

  /// Drains the queue without closing the scope (the mid-pass drain sites:
  /// after a committed frame's lifecycle dispatch, and the elided/skipped
  /// frame branches).
  package func takeDeferredCommittedCompletions()
    -> [@MainActor @Sendable () -> Void]
  {
    guard !deferredCommittedCompletions.isEmpty else {
      return []
    }
    let completions = deferredCommittedCompletions
    deferredCommittedCompletions.removeAll(keepingCapacity: true)
    return completions
  }

  fileprivate func dispatchOrDeferCommittedCompletions(
    _ completions: [@MainActor @Sendable () -> Void]
  ) {
    guard !completions.isEmpty else {
      return
    }
    if isDeferringCommittedCompletionDispatch {
      deferredCommittedCompletions.append(contentsOf: completions)
    } else {
      for completion in completions {
        completion()
      }
    }
  }

  // Computed accessors forwarding to the clustered sub-structs.  These keep the
  // per-tick animation logic below reading and writing the original field names
  // with identical value semantics, while the checkpoint/restore/reset triplet
  // moves whole structs.

  /// Animatable snapshots from the previous frame, keyed by identity.
  private var previousSnapshots: [Identity: AnimatableSnapshot] {
    get { previousFrame.snapshots }
    set { previousFrame.snapshots = newValue }
  }
  /// Full tree from the previous frame, retained so removals can capture
  /// their subtrees.
  private var previousTreeRoot: ResolvedNode? {
    get { previousFrame.treeRoot }
    set { previousFrame.treeRoot = newValue }
  }
  /// Previous frame's placed tree, captured at the end of each frame
  /// via ``capturePlacedTree(_:)``.  Used by removal detection to
  /// look up the disappearing identity's frozen bounds and inject
  /// the overlay at placed level instead of routing it back through
  /// measure/place.
  private var previousPlacedRoot: PlacedNode? {
    get { previousFrame.placedRoot }
    set { previousFrame.placedRoot = newValue }
  }
  /// Placed bounds for every matched-geometry key observed in the
  /// previous frame's placed tree.  Seeded by ``capturePlacedTree``
  /// and consulted by the next frame's match detection.
  private var previousMatchedGeometryBounds: [MatchedGeometryKey: CellRect] {
    get { previousFrame.matchedGeometryBounds }
    set { previousFrame.matchedGeometryBounds = newValue }
  }
  /// Which identity held each matched-geometry key in the previous
  /// frame.  A match fires when the current frame maps the same key
  /// to a *different* identity — regardless of whether either
  /// identity is newly inserted.
  private var previousMatchedKeyIdentities: [MatchedGeometryKey: Identity] {
    get { previousFrame.matchedKeyIdentities }
    set { previousFrame.matchedKeyIdentities = newValue }
  }
  /// Where each co-present non-source was drawn last frame, relative to its
  /// baseline slot. Capture seeds a time-free fallback; placed sampling then
  /// replaces it with the offsets actually drawn, including in-flight sources.
  private var previousAdoptionOffsets: [Identity: PlacedAnimationOverlayOffset] {
    get { previousFrame.adoptionOffsets }
    set { previousFrame.adoptionOffsets = newValue }
  }
  /// Parent identity, as walked from the previous frame's tree.
  private var previousParentByIdentity: [Identity: Identity] {
    get { previousFrame.parentByIdentity }
    set { previousFrame.parentByIdentity = newValue }
  }
  /// Child index within the previous parent's children list.
  private var previousChildIndexByIdentity: [Identity: Int] {
    get { previousFrame.childIndexByIdentity }
    set { previousFrame.childIndexByIdentity = newValue }
  }
  private var previousIdentities: Set<Identity> {
    get { previousFrame.identities }
    set { previousFrame.identities = newValue }
  }
  /// The set of `ViewNodeID`s that were live at the end of the previous frame.
  /// Removal detection subtracts this frame's live set from it to find departed
  /// occurrences (a ViewNodeID that left even while its Identity survives), and
  /// insertion detection consults it to recognize reparented nodes.
  private var previousLiveNodeIDs: Set<ViewNodeID> {
    get { previousFrame.liveNodeIDs }
    set { previousFrame.liveNodeIDs = newValue }
  }

  /// Completion registrations from ``withAnimation`` and
  /// ``Transaction/addAnimationCompletion``, keyed by batch. The controller
  /// fires and removes each once every animation (and every removal
  /// overlay) tagged with the batch ID has passed the registration's
  /// barrier.
  private var completions: [AnimationBatchID: [AnimationCompletionRegistration]] {
    get { completionLedger.completions }
    set { completionLedger.completions = newValue }
  }
  /// Animation boxes registered for the current frame. Forwarded to the
  /// ``CompletionLedger`` so the per-tick logic reads the original name while the
  /// async-writable set checkpoints and carries as a unit.
  private var registeredAnimations: [AnimationBox: Animation] {
    get { completionLedger.registeredAnimations }
    set { completionLedger.registeredAnimations = newValue }
  }
  /// Per-batch active-animation counts.  Incremented on enqueue;
  /// decremented when an animation completes or is superseded.  When
  /// a count hits zero, the matching completion closure fires.
  private var batchRefCounts: [AnimationBatchID: Int] {
    get { batchCompletion.batchRefCounts }
    set { batchCompletion.batchRefCounts = newValue }
  }
  private var batchLogicalRefCounts: [AnimationBatchID: Int] {
    get { batchCompletion.batchLogicalRefCounts }
    set { batchCompletion.batchLogicalRefCounts = newValue }
  }
  /// Batches whose `withAnimation { ... } completion: { ... }` scope
  /// registered a completion closure but produced zero retained
  /// animations during their resolve pass — e.g. because the only
  /// changes in the body touched a property the controller doesn't
  /// expose as an ``AnimatableSlot``.
  ///
  /// Each entry stores the absolute time the controller should fire
  /// the completion.  ``applyInterpolations`` walks this map on every
  /// tick and drains entries whose deadline has elapsed, keeping
  /// stranded completions from leaking indefinitely.  A SwiftUI-shaped
  /// guarantee: every `withAnimation` completion eventually fires,
  /// even when the body changed nothing the controller can
  /// interpolate.
  private var pendingEmptyBatchCompletions: [AnimationBatchID: MonotonicInstant] {
    get { batchCompletion.pendingEmptyBatchCompletions }
    set { batchCompletion.pendingEmptyBatchCompletions = newValue }
  }

  /// Registrations collected during the *current* frame's resolve pass.
  /// Used to look up transitions on INSERTION.
  private var transitionsByNodeID: [ViewNodeID: AnyTransition] {
    get { transitions.byNodeID }
    set { transitions.byNodeID = newValue }
  }
  private var transitionIdentitiesByNodeID: [ViewNodeID: Identity] {
    get { transitions.identitiesByNodeID }
    set { transitions.identitiesByNodeID = newValue }
  }
  /// Registrations that were live at the end of the *previous* frame's
  /// resolve pass.  Used to look up transitions on REMOVAL, because the
  /// disappearing view's `.transition()` modifier is not evaluated in
  /// the current frame — its branch is gone.
  private var previousTransitionsByNodeID: [ViewNodeID: AnyTransition] {
    get { transitions.previousByNodeID }
    set { transitions.previousByNodeID = newValue }
  }
  private var previousTransitionIdentitiesByNodeID: [ViewNodeID: Identity] {
    get { transitions.previousIdentitiesByNodeID }
    set { transitions.previousIdentitiesByNodeID = newValue }
  }
  private var pendingTransitionsByNodeID: [ViewNodeID: AnyTransition] {
    get { transitions.pendingByNodeID }
    set { transitions.pendingByNodeID = newValue }
  }
  private var pendingTransitionIdentitiesByNodeID: [ViewNodeID: Identity] {
    get { transitions.pendingIdentitiesByNodeID }
    set { transitions.pendingIdentitiesByNodeID = newValue }
  }

  private var isFrameHeadTransactionActive: Bool {
    get { frameHead.isActive }
    set { frameHead.isActive = newValue }
  }
  private var deferredFrameHeadCompletions: [@MainActor @Sendable () -> Void] {
    get { frameHead.deferredCompletions }
    set { frameHead.deferredCompletions = newValue }
  }
  private var lastFrameHeadCompletionCount: Int {
    get { frameHead.lastCompletionCount }
    set { frameHead.lastCompletionCount = newValue }
  }

  /// Per-slot rings of values written under `Transaction.tracksVelocity`
  /// (see `PreviousFrameState.velocitySamplers`).
  private var slotVelocitySamplers: [AnimationKey: SlotVelocitySampler] {
    get { previousFrame.velocitySamplers }
    set { previousFrame.velocitySamplers = newValue }
  }

  /// Target frame interval during active animation (30 FPS).
  private let frameInterval: Duration = .milliseconds(33)
  /// Default duration used for transition animations when no explicit
  /// animation is in the transaction.
  private let defaultTransitionDuration: Duration = .milliseconds(250)

  package init() {}

  fileprivate convenience init(restoring checkpoint: Checkpoint) {
    self.init()
    restore(checkpoint)
  }

  package func makeFrameDraft() -> AnimationFrameDraft {
    AnimationFrameDraft(liveController: self)
  }

  package func beginFrameHeadTransaction() -> Checkpoint {
    precondition(
      !isFrameHeadTransactionActive,
      "AnimationController frame-head transactions cannot be nested."
    )
    let checkpoint = makeCheckpoint()
    isFrameHeadTransactionActive = true
    deferredFrameHeadCompletions.removeAll(keepingCapacity: true)
    lastFrameHeadCompletionCount = 0
    return checkpoint
  }

  package func commitFrameHeadTransaction(_ checkpoint: Checkpoint) {
    let completions = finishFrameHeadTransaction(checkpoint)
    dispatchOrDeferCommittedCompletions(completions)
  }

  fileprivate func finishFrameHeadTransaction(
    _ checkpoint: Checkpoint
  ) -> [@MainActor @Sendable () -> Void] {
    precondition(
      isFrameHeadTransactionActive,
      "No AnimationController frame-head transaction is active."
    )
    let completions = deferredFrameHeadCompletions
    lastFrameHeadCompletionCount = completions.count
    isFrameHeadTransactionActive = checkpoint.frameHead.isActive
    deferredFrameHeadCompletions = checkpoint.frameHead.deferredCompletions
    return completions
  }

  package func abortFrameHeadTransaction(_ checkpoint: Checkpoint) {
    precondition(
      isFrameHeadTransactionActive,
      "No AnimationController frame-head transaction is active."
    )
    restore(checkpoint)
  }

  fileprivate func makeCheckpoint() -> Checkpoint {
    Checkpoint(
      previousFrame: previousFrame,
      transitions: transitions,
      batchCompletion: batchCompletion,
      frameHead: frameHead,
      completionLedger: completionLedger,
      valueSites: valueSites,
      bodyInsertions: bodyInsertions,
      activeAnimations: activeAnimations,
      removingNodes: removingNodes,
      currentResolvedPresentationProjection: currentResolvedPresentationProjection,
      lastTickResult: lastTickResult,
      resolvedTreeProcessingSkipCount: resolvedTreeProcessingSkipCount,
      lastResolvedTreeProcessedNodeCount: lastResolvedTreeProcessedNodeCount,
      lastPropertyInterpolationVisitedNodeCount: lastPropertyInterpolationVisitedNodeCount
    )
  }

  private func restore(_ checkpoint: Checkpoint) {
    previousFrame = checkpoint.previousFrame
    transitions = checkpoint.transitions
    batchCompletion = checkpoint.batchCompletion
    frameHead = checkpoint.frameHead
    completionLedger = checkpoint.completionLedger
    valueSites = checkpoint.valueSites
    bodyInsertions = checkpoint.bodyInsertions
    activeAnimations = checkpoint.activeAnimations
    removingNodes = checkpoint.removingNodes
    currentResolvedPresentationProjection = checkpoint.currentResolvedPresentationProjection
    lastTickResult = checkpoint.lastTickResult
    resolvedTreeProcessingSkipCount = checkpoint.resolvedTreeProcessingSkipCount
    lastResolvedTreeProcessedNodeCount = checkpoint.lastResolvedTreeProcessedNodeCount
    lastPropertyInterpolationVisitedNodeCount =
      checkpoint.lastPropertyInterpolationVisitedNodeCount
  }

  fileprivate func publishCommittedState(
    from draftController: AnimationController,
    preservingConcurrentRegistrationsSince baseline: Checkpoint
  ) {
    // A `withAnimation(_:) { … } completion:` invoked by an ASYNC task — e.g. a
    // `PhaseAnimator` loop's `advance`, which awaits each phase's completion —
    // registers its completion closure (and the animation box) on THIS *live*
    // controller, between frames, because the task is not running inside a frame
    // resolve. When that registration lands while an earlier frame's tail is
    // still in flight, that frame's draft was snapshotted from live BEFORE the
    // registration, so the full `restore` below would clobber it — permanently
    // orphaning the completion (its `await` never resumes; the loop stalls). The
    // large gallery tree makes in-flight frames common, which is why the bug
    // reproduces there and not in small trees.
    //
    // Carry forward every completion / animation-box registration the live
    // controller has gained since the draft's baseline. The draft never observed
    // them (it predates them), so it neither references nor fired them; they are
    // pending registrations that must survive the publish.
    //
    // Totality: the async-writable registration set is exactly `CompletionLedger`
    // — the completion-closure and animation-box maps an async task grows between
    // frames via `withAnimation`'s `AnimationCompletionSink` /
    // `AnimationRegistrationSink`. Transitions are deliberately NOT in the ledger:
    // their sink (`TransitionRegistrationSink`, driven by the `.transition()`
    // modifier) only fires during resolve, so they are frame-derived and already
    // live in the draft. Because the carry runs through the ledger's own
    // `concurrentRegistrations(since:)` / `reapply(_:)`, a map added to the ledger
    // is carried automatically — the publish can no longer silently drop one.
    let carried = completionLedger.concurrentRegistrations(since: baseline.completionLedger)
    restore(draftController.makeCheckpoint())
    completionLedger.reapply(carried)
  }

  /// Stores a snapshot of the placed tree at the end of the frame so
  /// the next frame's removal detection can find the disappearing
  /// identity's frozen bounds without re-running layout.  Also
  /// collects matched-geometry bounds + identities so the next
  /// frame can detect key → identity swaps and start matched
  /// geometry animations.
  ///
  /// Called by the render pipeline after ``place`` runs.  When no
  /// removal overlays are pending this is a cheap reference copy.
  ///
  /// Returns the tree's co-present adoption pairs so the same frame's
  /// overlay sampling can reuse the walk (`placedAnimationOverlaySnapshot`'s
  /// `adoption:`).
  @discardableResult
  package func capturePlacedTree(_ placed: PlacedNode) -> [MatchedGeometryAdoptionPair] {
    let capture = AnimationPlacedTreeCapture.capture(placed)
    previousPlacedRoot = capture.root
    previousMatchedGeometryBounds = capture.matchedBounds
    previousMatchedKeyIdentities = capture.matchedIdentities
    previousAdoptionOffsets = capture.adoptionOffsets
    return capture.adoptionPairs
  }

  /// The identities adopted onto a source in the previously captured placed
  /// tree. Test hook.
  package var previousAdoptedIdentities: Set<Identity> {
    Set(previousAdoptionOffsets.keys)
  }

  /// Number of matched-geometry animations currently in flight.
  /// Test hook.
  package var activeMatchedGeometryCount: Int {
    activeAnimations.keys.lazy.filter { $0.scope == .matchedGeometry }.count
  }

  /// Number of matched-geometry keys captured from the previous
  /// frame's placed tree.  Test hook used to verify that
  /// capturePlacedTree is observing the matched-geometry field.
  package var previousMatchedGeometryKeyCount: Int {
    previousMatchedGeometryBounds.count
  }

  package func debugStateSnapshot() -> DebugStateSnapshot {
    DebugStateSnapshot(
      previousSnapshotIdentities: Set(previousSnapshots.keys),
      previousTreeRoot: previousTreeRoot,
      previousPlacedRoot: previousPlacedRoot,
      previousMatchedGeometryBounds: previousMatchedGeometryBounds,
      previousMatchedKeyIdentities: previousMatchedKeyIdentities,
      previousParentByIdentity: previousParentByIdentity,
      previousChildIndexByIdentity: previousChildIndexByIdentity,
      activeAnimationKeys: Set(activeAnimations.keys),
      activeAnimationBoxesByKey: activeAnimations.mapValues(\.animationBox),
      registeredAnimationCount: registeredAnimations.count,
      completionClosureBatchIDs: Set(completions.keys),
      unclaimedCompletionBatchIDs: unclaimedCompletionBatchIDs,
      batchRefCounts: batchRefCounts,
      pendingEmptyBatchCompletions: pendingEmptyBatchCompletions,
      removalAnimationBoxesByNodeID: removingNodes.mapValues(\.animationBox),
      transitionNodeIDs: Set(transitionsByNodeID.keys),
      transitionIdentities: Set(transitionIdentitiesByNodeID.values),
      previousTransitionNodeIDs: Set(previousTransitionsByNodeID.keys),
      previousTransitionIdentities: Set(previousTransitionIdentitiesByNodeID.values),
      pendingTransitionNodeIDs: Set(pendingTransitionsByNodeID.keys),
      pendingTransitionIdentities: Set(pendingTransitionIdentitiesByNodeID.values),
      removingNodeIDs: Set(removingNodes.keys),
      removingIdentities: removingIdentitySet,
      previousIdentities: previousIdentities,
      lastTickHasPendingWork: lastTickResult.hasPendingWork,
      lastTickNextDeadline: lastTickResult.nextDeadline,
      lastTickRedrawIdentities: lastTickResult.redrawIdentities,
      isFrameHeadTransactionActive: isFrameHeadTransactionActive,
      deferredFrameHeadCompletionCount: deferredFrameHeadCompletions.count,
      lastFrameHeadCompletionCount: lastFrameHeadCompletionCount
    )
  }

  /// Runs the placed-level animation pass after layout: injects pending
  /// removal overlays and applies active insertion geometry. Called between
  /// place and semantics in the render pipeline.
  ///
  /// Overlays injected this way never flow through measure or place,
  /// so sibling layout is not disturbed when the removed view lived
  /// inside a VStack or other flow container.  They carry the
  /// transient flag, so semantics/focus/lifecycle skip them.
  ///
  /// Insertion offsets translate the bounds of in-tree placed nodes
  /// by an interpolated delta so `.transition(.move(edge:))` and
  /// friends work on intrinsic-layout leaves (where `applyValue`
  /// can't rewrite the layoutBehavior). Insertion scales resize and clip the
  /// placed bounds around their anchor without changing layout.
  package func applyPlacedOverlays(
    to tree: inout PlacedNode,
    at timestamp: MonotonicInstant,
    surfaceSize: CellSize? = nil
  ) {
    let snapshot = placedAnimationOverlaySnapshot(
      for: tree,
      at: timestamp,
      surfaceSize: surfaceSize
    )
    applyPlacedAnimationOverlaySnapshot(
      snapshot,
      to: &tree
    )
  }

  /// Samples placed-level animation state into an explicit value
  /// snapshot that can be applied away from the main actor.
  ///
  /// This method still owns animation bookkeeping: custom animation
  /// state is advanced, completed keys are released, and batch
  /// completions can fire. The returned snapshot is pure data.
  ///
  /// - Parameter adoption: `tree`'s co-present pairs from this frame's
  ///   ``capturePlacedTree(_:)``; `nil` pairs them here.
  package func placedAnimationOverlaySnapshot(
    for tree: PlacedNode,
    at timestamp: MonotonicInstant,
    surfaceSize: CellSize? = nil,
    adoption: [MatchedGeometryAdoptionPair]? = nil
  ) -> PlacedAnimationOverlaySnapshot {
    // A removal that plays a transition body draws that body around the
    // frozen content. It is laid out here, on the main actor, with the
    // samples the head tick took, when the sampling below finds that the
    // removal draws on this frame: the frame tail then receives a finished
    // placed tree in place of the frozen snapshot, and treats it as it
    // treats any removal overlay.
    //
    // A body with an `Animatable` view or modifier in it is evaluated again
    // first, with this frame's sample of each such site, so what is laid
    // out is the body as those sites present it now. That is the one
    // evaluation of the body for the frame, and a frame that does not draw
    // the removal has none.
    var removalsWithAnimatingBody: Set<ViewNodeID> = []
    for (viewNodeID, entry) in removingNodes {
      guard let body = entry.body, entry.placedSnapshot != nil else { continue }
      if body.drivingKeys.contains(where: { activeAnimations[$0] != nil }) {
        removalsWithAnimatingBody.insert(viewNodeID)
      }
    }
    var refreshedBodies: [ViewNodeID: RemovalBodyState] = [:]
    var bodyEvaluations: RemovalBodyEvaluations = [:]
    let result = PlacedAnimationOverlaySampling.sample(
      removingNodes: removingNodes,
      activeAnimations: activeAnimations,
      registeredAnimations: registeredAnimations,
      tree: tree,
      timestamp: timestamp,
      surfaceSize: surfaceSize,
      adoption: adoption,
      removalsWithAnimatingBody: removalsWithAnimatingBody,
      removalBodySnapshot: { viewNodeID, entry in
        guard var body = entry.body, let frozen = entry.placedSnapshot else { return nil }
        let changed = self.refreshRemovalWorkingTree(
          &body, of: entry, at: timestamp, evaluations: &bodyEvaluations)
        var placed = AnimationTransitionBodyRemoval.compose(body, in: frozen)
        var preparations = body.cellPreparations ?? RemovalCellPreparations(frozen)
        let rebound = preparations.bind(&placed)
        if changed || rebound {
          body.cellPreparations = preparations
          refreshedBodies[viewNodeID] = body
        }
        return placed
      }
    )
    for (viewNodeID, body) in refreshedBodies {
      removingNodes[viewNodeID]?.body = body
    }

    for (viewNodeID, state) in result.removalCustomStates {
      removingNodes[viewNodeID]?.customState = state
    }
    for (key, state) in result.activeAnimationCustomStates {
      activeAnimations[key]?.customState = state
    }
    var completedAnimationBoxes: Set<AnimationBox> = []
    for key in result.completedAnimationKeys {
      if let entry = activeAnimations.removeValue(forKey: key) {
        completedAnimationBoxes.insert(entry.animationBox)
        releaseBatch(entry.batchID, logicalAlreadyReleased: entry.isLogicallyReleased)
      }
    }
    // Keep the final visual for one committed turn so logical completion and
    // overlay removal are observably distinct barriers: the curve's end
    // releases the batch's logical retain here (its `.logicallyComplete`
    // registrations fire); the next head tick purges the overlay and releases
    // the `.removed` one (`applyInterpolations`). The purge lives at the head,
    // not here, because a frame whose surface no longer changes is elided
    // without a placed pass — an exit overlay that had faded out would
    // otherwise never purge, and its `.removed` completion would wait for
    // the next outside input.
    for viewNodeID in result.completedRemovalNodeIDs {
      guard var entry = removingNodes[viewNodeID] else { continue }
      guard entry.completionBatchID != nil else {
        removingNodes.removeValue(forKey: viewNodeID)
        if let box = entry.animationBox { completedAnimationBoxes.insert(box) }
        // An animation of the body that the removal did not drive may still
        // be running. Its view leaves with the overlay.
        if let body = entry.body {
          completedAnimationBoxes.formUnion(endRemovalBodyAnimations(of: body))
        }
        continue
      }
      if !entry.isLogicallyComplete {
        entry.isLogicallyComplete = true
        releaseLogicalBatch(entry.completionBatchID)
        removingNodes[viewNodeID] = entry
      }
    }

    pruneCompletedAnimationRegistrations(completedAnimationBoxes)
    // The frame-tail uses a draft controller: these sampled positions cross
    // the frame boundary only when that draft commits.
    previousAdoptionOffsets = NestedMatchedGeometryPlacement.absoluteOffsets(
      in: tree, applying: result.snapshot.adoptionOffsets)
    if !result.snapshot.adoptionOffsets.isEmpty {
      var presented = tree
      applyPlacedAnimationOverlaySnapshot(result.snapshot, to: &presented)
      var entries: [MatchedGeometryPlacedEntry] = []
      AnimationTreeQueries.collectMatchedGeometryEntries(presented, into: &entries)
      for entry in entries where entry.config.isSource {
        previousMatchedGeometryBounds[entry.config.key] = entry.bounds
      }
    }
    return result.snapshot
  }

  /// `true` while the placed-overlay pass owns animation work that no other
  /// pass can advance: an insertion offset or scale, a matched-geometry
  /// travel, or an exit overlay it has taken ownership of.
  ///
  /// ``placedAnimationOverlaySnapshot(for:at:surfaceSize:adoption:)`` is the
  /// sole evaluator, custom-state advancer, and completer of all four — an
  /// off-screen-elided frame runs the head tick but never reaches that pass,
  /// and the head deliberately declines to touch them (double-sampling a
  /// stateful `CustomAnimation` is the bug that split the ownership). Eliding
  /// such a frame therefore does not defer the work, it freezes it: the sample
  /// on screen never changes, so the animation never lands and never drains.
  ///
  /// The freeze is self-sustaining rather than transient, which is why this is
  /// a hard blocker on off-screen elision rather than an input to the
  /// `drawnIdentities` comparison. All four scopes change a node's placed rect,
  /// so the frozen sample is precisely the one holding the node off the
  /// surface, which keeps the identity out of `drawnIdentities`, which keeps
  /// the next tick elidable. See
  /// ``OffscreenFrameElision/shouldElide(causes:hasExplicitAnimationTransactions:redrawIdentities:drawnIdentities:hasPlacedPassOwnedAnimationWork:)``.
  package var hasPlacedPassOwnedAnimationWork: Bool {
    let hasPlacedGeometryScope = activeAnimations.values.contains { animation in
      switch animation.kind {
      case .insertionOffset, .insertionScale, .matchedGeometry:
        true
      case .property, .value:
        false
      }
    }
    if hasPlacedGeometryScope {
      return true
    }
    // Mirrors `sampleRemovalOverlays`' ownership guard, and the matching skip
    // in `applyInterpolations`, exactly: a removal the placed pass does NOT
    // own still drains at the head, so it must not block elision.
    return removingNodes.values.contains { entry in
      entry.placedSnapshot != nil && entry.parentIdentity != nil
        && entry.animationBox.map { registeredAnimations[$0] != nil } == true
    }
  }

  /// A previous visibility snapshot cannot prove a geometry-changing slot
  /// stays offscreen. Layout must run even when the slot's wrapper was clipped.
  package var hasLayoutAffectingPropertyAnimation: Bool {
    activeAnimations.keys.contains { key in
      guard case .property(let slot) = key.scope else { return false }
      switch slot {
      case .padding, .offset, .position, .frameWidth, .frameHeight, .cellPlacement:
        return true
      case .opacity, .foregroundShapeStyle, .backgroundShapeStyle, .borderShapeStyle,
        .borderBlendPhase, .borderForegroundStyle, .strokeDashPhase, .shapeTrim, .shapeFillStyle,
        .shapeStrokeStyle,
        .shapePath,
        .clipShapePaths,
        .textRoll,
        .tintShapeStyle,
        .shapeData,
        .clipShapeData:
        return false
      }
    }
  }

  /// A clip mask animating toward a mask that encloses area can uncover
  /// content its node never drew. The rasterizer records a masked node as
  /// drawn only through its mask's regions (`Rasterizer+Paint.swift`), and an
  /// empty mask has none, so a previous visibility snapshot cannot prove the
  /// next sample stays hidden, just as it cannot for a geometry slot (T252).
  /// The slot stays draw-only (it never needs layout); only elision consults
  /// this. A mask whose destination encloses no area reveals nothing and keeps
  /// elision (STUI-1318).
  ///
  /// A mask of an `Animatable` shape always counts: its shape decides what
  /// each sample covers, so no end value proves the samples stay empty.
  package var hasRevealingClipMaskAnimation: Bool {
    activeAnimations.contains { key, animation in
      if case .property(.clipShapeData) = key.scope { return true }
      guard key.scope == .property(.clipShapePaths),
        case .property(_, let destination) = animation.kind
      else { return false }
      guard let mask = destination.unwrap(as: ClipMaskPaths.self) else { return true }
      return !mask.enclosesNoArea
    }
  }

  /// Whether the data of some `Animatable` view or modifier is animating.
  ///
  /// Such an animation writes nothing to the tree. Its owner's body runs
  /// again with each sample, and what that body produces is not known before
  /// it runs: it reports no redraw identities, and the previous frame's
  /// drawn identities say nothing about the next one. A deadline frame that
  /// carries it is therefore never elided.
  package var hasValueAnimation: Bool {
    activeAnimations.keys.contains { $0.isValue }
  }

  /// Whether some in-flight animation makes the previous frame's drawn
  /// identities unable to justify eliding a deadline frame: a
  /// layout-affecting slot, a revealing clip mask, or the data of an
  /// `Animatable` view or modifier.
  package var blocksOffscreenFrameElision: Bool {
    hasLayoutAffectingPropertyAnimation || hasRevealingClipMaskAnimation || hasValueAnimation
  }

  /// Number of value animations in flight: the animations of the data of
  /// `Animatable` views and modifiers. Test hook.
  package var activeValueAnimationCount: Int {
    activeAnimations.keys.lazy.filter(\.isValue).count
  }

  /// The sites whose value animation is in flight at `identity`, by
  /// position. Test hook, and the listing a removal needs to take over the
  /// value animations of the views it keeps drawing.
  package func valueAnimationSites(forIdentity identity: Identity) -> [AnimatableValueSite] {
    activeAnimations.keys.compactMap { key in
      guard key.identity == identity, case .value(let ordinal) = key.scope else { return nil }
      return AnimatableValueSite(identity: identity, ordinal: ordinal)
    }.sorted { $0.ordinal < $1.ordinal }
  }

  /// The sites that have resolved at `identity` and are still in the tree,
  /// by position, animating or not. Test hook.
  package func valueSites(forIdentity identity: Identity) -> [AnimatableValueSite] {
    valueSites.targets.keys.compactMap { key in
      guard key.identity == identity, case .value(let ordinal) = key.scope else { return nil }
      return AnimatableValueSite(identity: identity, ordinal: ordinal)
    }.sorted { $0.ordinal < $1.ordinal }
  }

  /// Number of sites the controller holds a target for. Test hook.
  package var valueSiteCount: Int {
    valueSites.targets.count
  }

  /// Number of insertion-offset animations currently in flight.
  /// Test hook so integration tests can pin the enqueue path
  /// without exposing the entire private map.
  package var activeInsertionOffsetCount: Int {
    activeAnimations.keys.lazy.filter { $0.scope == .insertionOffset }.count
  }

  /// Number of insertion-scale animations currently in flight.
  package var activeInsertionScaleCount: Int {
    activeAnimations.keys.lazy.filter { $0.scope == .insertionScale }.count
  }

  /// Number of in-tree (drawMetadata / layoutBehavior) animations
  /// currently in flight.  Test hook.  Counts only ``.property``
  /// scopes so the meaning matches the pre-Phase-4 contract — placed
  /// overlay scopes have their own counters above.
  package var activeAnimationCount: Int {
    activeAnimations.keys.lazy.filter {
      if case .property = $0.scope { return true }
      return false
    }.count
  }

  /// The registration of the body transition whose host registered
  /// `identity`, as of the most recent collection, or `nil` when no body
  /// transition is registered there. Test hook.
  package func transitionBodyRegistration(
    forIdentity identity: Identity
  ) -> TransitionBodyRegistration? {
    for (nodeID, registeredIdentity) in transitionIdentitiesByNodeID
    where registeredIdentity == identity {
      if let registration = transitionsByNodeID[nodeID]?.bodyRegistration {
        return registration
      }
    }
    return nil
  }

  /// The body registration the removal overlay of `identity` carries, or
  /// `nil` when no removal is in flight there or its transition has no
  /// registered body. Test hook.
  package func removalBodyRegistration(
    forIdentity identity: Identity
  ) -> TransitionBodyRegistration? {
    removingNodes.values.first { $0.identity == identity }?.transition.bodyRegistration
  }

  /// The state of the body channel of the removal in flight at `identity`,
  /// or `nil` when no removal there plays a body. Test hook.
  package func removalBodyState(forIdentity identity: Identity) -> RemovalBodyState? {
    removingNodes.values.first { $0.identity == identity }?.body
  }

  private var removingIdentitySet: Set<Identity> {
    Set(removingNodes.values.map(\.identity))
  }

  /// The removal that owns the property animations of each identity of a
  /// transition body in flight. Empty when no removal plays a body.
  ///
  /// A removal that plays a body keeps animating the views of that body,
  /// which are no longer in the live tree. Their animations stay in
  /// ``activeAnimations`` under their `(identity, slot)` keys, so a later
  /// insertion at the same key can retarget them. While the removal lasts
  /// they belong to it: their samples go to its working tree, and the
  /// departed-identity prune leaves them alone.
  private var removalBodyOwners: [Identity: ViewNodeID] {
    var owners: [Identity: ViewNodeID] = [:]
    for (viewNodeID, entry) in removingNodes {
      guard let body = entry.body else { continue }
      for identity in body.ownedIdentities {
        owners[identity] = viewNodeID
      }
    }
    return owners
  }

  /// The value animations that removals in flight own: the animations of
  /// the `Animatable` views and modifiers of the transition bodies they
  /// play (``RemovalBodyState/valueSites``). Empty when no removal plays
  /// such a body.
  ///
  /// These keys are owned by key and not by identity. The identity a site
  /// resolves at need not be an identity of the tree the removal froze (a
  /// view whose body root is a conditional commits its branch's node in its
  /// place), so ``removalBodyOwners`` cannot name them.
  private var removalOwnedValueKeys: Set<AnimationKey> {
    guard !removingNodes.isEmpty else { return [] }
    var keys: Set<AnimationKey> = []
    for entry in removingNodes.values {
      guard let sites = entry.body?.valueSites, !sites.isEmpty else { continue }
      keys.formUnion(sites.keys)
    }
    return keys
  }

  /// What the live `Animatable` views and modifiers show, for a removal that
  /// takes the sites of a departing transition body over.
  ///
  /// A site that resolved has a recorded target. What it shows on screen is
  /// what its body last ran with: the sample its animation presented on the
  /// frame before this one, or its target when none was in flight then.
  /// What it presents on the frame being prepared is this frame's sample of
  /// the animation in flight, or its target.
  ///
  /// `planned` are the sites another removal has taken over on this frame
  /// already, with what they showed then. A body with several roots has a
  /// removal for each root that leaves, and each evaluates the whole body
  /// when it is planned: it has to see what a site showed before the
  /// removal of the root that holds the site took it.
  ///
  /// `isLive` says whether a view of the tree this frame resolved still
  /// resolves a site. A site a removal has taken is not live.
  private func liveSiteData(
    planned: [AnimationKey: AnimationTransitionBodyRemoval.LiveSite],
    isLive: @escaping (AnimationKey) -> Bool
  ) -> AnimationTransitionBodyRemoval.LiveSiteData {
    AnimationTransitionBodyRemoval.LiveSiteData(
      shown: { [valueSites] key in
        if let planned = planned[key] { return planned.shown }
        guard let target = valueSites.targets[key] else { return nil }
        return valueSites.previousSamples[key] ?? target
      },
      presented: { [valueSites, activeAnimations] key in
        if let planned = planned[key] { return planned.presented }
        guard let target = valueSites.targets[key] else { return nil }
        return (activeAnimations[key] != nil ? valueSites.samples[key] : nil) ?? target
      },
      staysLive: { [valueSites] key in
        planned[key] == nil && valueSites.targets[key] != nil && isLive(key)
      }
    )
  }

  /// Ends every removal's ownership of the value animation at `key`: a live
  /// site has taken the animation over. No removal lasts for it any more,
  /// the one that owned it or another removal of the same body
  /// (``shareRemovalValueSiteLifetimes(plannedAt:)``).
  private func releaseRemovalOwnership(ofValueAt key: AnimationKey) {
    for (viewNodeID, entry) in removingNodes {
      guard let body = entry.body else { continue }
      if body.valueSites[key] != nil {
        removingNodes[viewNodeID]?.body?.valueSites.removeValue(forKey: key)
      }
      if body.drivingKeys.contains(key) {
        removingNodes[viewNodeID]?.body?.drivingKeys.remove(key)
      }
    }
  }

  /// Makes every removal of one transition body that was planned at
  /// `timestamp` last while a site of that body animates toward the
  /// `.didDisappear` phase.
  ///
  /// A body with several roots leaves through one removal for each root.
  /// Each of its sites animates once, in the removal of the root that holds
  /// it (``TransitionBodySiteHolders``), and the body leaves as one: a root
  /// with nothing of its own to animate stays on screen until the sites of
  /// the other roots have settled. This runs after every removal of the
  /// frame is planned, so the result does not depend on the order they were
  /// planned in.
  private func shareRemovalValueSiteLifetimes(plannedAt timestamp: MonotonicInstant) {
    guard removingNodes.count > 1 else { return }
    var removalsByBody: [Identity: [ViewNodeID]] = [:]
    var drivingSitesByBody: [Identity: Set<AnimationKey>] = [:]
    for (viewNodeID, entry) in removingNodes where entry.startTime == timestamp {
      guard let body = entry.body, let registration = entry.transition.bodyRegistration else {
        continue
      }
      removalsByBody[registration.identity, default: []].append(viewNodeID)
      let sites = body.drivingKeys.filter(\.isValue)
      if !sites.isEmpty {
        drivingSitesByBody[registration.identity, default: []].formUnion(sites)
      }
    }
    for (identity, sites) in drivingSitesByBody {
      guard let removals = removalsByBody[identity], removals.count > 1 else { continue }
      for viewNodeID in removals {
        removingNodes[viewNodeID]?.body?.drivingKeys.formUnion(sites)
      }
    }
  }

  /// Whether a removal in flight owns the value animation at `key`.
  private func removalOwnsValue(at key: AnimationKey) -> Bool {
    guard !removingNodes.isEmpty else { return false }
    return removingNodes.values.contains { $0.body?.valueSites[key] != nil }
  }

  /// Ends the animations a removal body owns, releasing the batches they
  /// retained so their completions fire: the property animations of its
  /// views and the value animations of its `Animatable` views and
  /// modifiers. Returns their curves for the registration prune.
  @discardableResult
  private func endRemovalBodyAnimations(of body: RemovalBodyState) -> Set<AnimationBox> {
    var finishedBoxes = endRemovalValueAnimations(of: body)
    guard !activeAnimations.isEmpty, !body.ownedIdentities.isEmpty else { return finishedBoxes }
    for key in Array(activeAnimations.keys) where body.ownedIdentities.contains(key.identity) {
      guard case .property = key.scope, let entry = activeAnimations.removeValue(forKey: key)
      else { continue }
      slotVelocitySamplers.removeValue(forKey: key)
      finishedBoxes.insert(entry.animationBox)
      releaseBatch(entry.batchID, logicalAlreadyReleased: entry.isLogicallyReleased)
    }
    return finishedBoxes
  }

  /// Ends the value animations a removal body owns. No live site ends them:
  /// the views at those sites left the graph when the removal began, so they
  /// end with the removal, whichever way it ends.
  @discardableResult
  private func endRemovalValueAnimations(of body: RemovalBodyState) -> Set<AnimationBox> {
    var finishedBoxes: Set<AnimationBox> = []
    for key in body.valueSites.keys {
      valueSites.samples.removeValue(forKey: key)
      guard let entry = activeAnimations.removeValue(forKey: key) else { continue }
      slotVelocitySamplers.removeValue(forKey: key)
      finishedBoxes.insert(entry.animationBox)
      releaseBatch(entry.batchID, logicalAlreadyReleased: entry.isLogicallyReleased)
    }
    return finishedBoxes
  }

  /// Hands the property animations a removal body owned back to the live
  /// tree, for a view that was inserted again during its removal. An
  /// animation whose view is in the new tree follows that view from now on.
  /// One whose view is not there ends.
  ///
  /// The value animations of the body's sites that a live site took over
  /// were handed back by the frame head, which is where a site's body can
  /// still run again (``continueRemovalValueSites``). The ones left belong
  /// to sites the new tree does not have, and end here.
  private func returnRemovalBodyAnimations(
    of body: RemovalBodyState,
    to frame: AnimationTransitionBodyInsertion.Frame
  ) {
    endRemovalValueAnimations(of: body)
    guard !activeAnimations.isEmpty, !body.ownedIdentities.isEmpty else { return }
    for key in Array(activeAnimations.keys) where body.ownedIdentities.contains(key.identity) {
      guard case .property = key.scope else { continue }
      if frame.snapshots[key.identity] != nil {
        activeAnimations[key]?.ownerViewNodeID = frame.nodeIDs[key.identity]
        activeAnimations[key]?.resolvedIdentity = key.identity
      } else if let entry = activeAnimations.removeValue(forKey: key) {
        releaseBatch(entry.batchID, logicalAlreadyReleased: entry.isLogicallyReleased)
      }
    }
  }

  /// The `.didDisappear` bodies evaluated for one frame, by the identity of
  /// the body's registration, with the answers each was evaluated with. A
  /// body with several roots has a removal for each root, and one evaluation
  /// of the body serves every one of them that is given the same answers.
  private typealias RemovalBodyEvaluations = [Identity: (
    answers: [AnimationKey: AnyAnimatable], tree: TransitionPhaseTree
  )]

  /// Evaluates the working tree of a removal body again when what its sites
  /// present has changed since the tree was last evaluated, and returns
  /// whether it did.
  ///
  /// The body is evaluated at most once for a frame, with this frame's
  /// sample of each value animation the removal owns that is in flight. A
  /// site with none evaluates with the data the `.didDisappear` phase gives
  /// it. So the body is evaluated on every frame that moves one of its
  /// sites, once more when the last of them has ended, and then no more. A
  /// body with no `Animatable` view or modifier is never evaluated here.
  @discardableResult
  private func refreshRemovalWorkingTree(
    _ body: inout RemovalBodyState,
    of entry: RemovalEntry,
    at timestamp: MonotonicInstant,
    evaluations: inout RemovalBodyEvaluations
  ) -> Bool {
    guard !body.valueSites.isEmpty, body.valueResolveInstant != timestamp,
      let registration = entry.transition.bodyRegistration
    else { return false }
    var presented: [AnimationKey: AnyAnimatable] = [:]
    for key in body.valueSites.keys where activeAnimations[key] != nil {
      if let sample = valueSites.samples[key] {
        presented[key] = sample
      }
    }
    let answers = body.normalizedValueAnswers(presented)
    guard answers != body.valueAnswers else { return false }
    let tree: TransitionPhaseTree
    if let evaluated = evaluations[registration.identity], evaluated.answers == answers {
      tree = evaluated.tree
    } else {
      tree = AnimationTransitionBodyRemoval.evaluateWorkingTree(
        of: body, registration: registration, answers: answers)
      evaluations[registration.identity] = (answers, tree)
    }
    AnimationTransitionBodyRemoval.refreshWorkingTree(
      of: &body,
      from: tree,
      registration: registration,
      frozenResolved: entry.snapshot,
      answers: answers,
      at: timestamp)
    return true
  }

  package var preFrameHeadOffscreenPropertyAnimationRedrawIdentities: Set<Identity>? {
    guard !isFrameHeadTransactionActive else { return nil }
    guard !activeAnimations.isEmpty else { return nil }
    guard removingNodes.isEmpty else { return nil }
    guard pendingEmptyBatchCompletions.isEmpty else { return nil }
    guard transitionsByNodeID.isEmpty,
      previousTransitionsByNodeID.isEmpty,
      pendingTransitionsByNodeID.isEmpty
    else {
      return nil
    }
    guard
      activeAnimations.values.allSatisfy({ animation in
        if case .property = animation.kind {
          return true
        }
        return false
      })
    else {
      return nil
    }

    return Set(activeAnimations.keys.map(\.identity))
  }

  /// Advances a deadline-only off-screen property-animation tick without
  /// resolving a new frame head. This deliberately handles only the state that
  /// ``preFrameHeadOffscreenPropertyAnimationRedrawIdentities`` proves safe:
  /// in-tree property animations with no active transition/removal/placed-level
  /// overlay bookkeeping.
  @discardableResult
  package func advancePreFrameHeadOffscreenPropertyAnimationTick(
    at timestamp: MonotonicInstant
  ) -> AnimationTickResult {
    guard preFrameHeadOffscreenPropertyAnimationRedrawIdentities != nil else {
      preconditionFailure("Pre-frame-head off-screen animation tick is not eligible.")
    }

    lastFrameHeadCompletionCount = 0

    var keysToRemove: [AnimationKey] = []
    var completedBatches: [CompletedBatchRelease] = []
    var logicallyCompletedBatches: [AnimationBatchID] = []
    var completedAnimationBoxes: Set<AnimationBox> = []
    var redrawIdentities: Set<Identity> = []
    var latestDeadline: MonotonicInstant = timestamp
    var hasPendingWork = false

    for (key, animation) in activeAnimations {
      guard case .property = animation.kind else {
        preconditionFailure("Pre-frame-head off-screen tick only supports property animations.")
      }
      switch advancePropertyAnimationStep(
        key: key,
        animation: animation,
        at: timestamp,
        keysToRemove: &keysToRemove,
        completedBatches: &completedBatches,
        logicallyCompletedBatches: &logicallyCompletedBatches,
        completedAnimationBoxes: &completedAnimationBoxes,
        redrawIdentities: &redrawIdentities
      ) {
      case .unregistered, .completed:
        break
      case .progressed:
        latestDeadline = timestamp.advanced(by: frameInterval)
        hasPendingWork = true
      }
    }

    for key in keysToRemove {
      activeAnimations.removeValue(forKey: key)
    }
    for batchID in logicallyCompletedBatches {
      releaseLogicalBatch(batchID)
    }
    for release in completedBatches {
      releaseBatch(release.batchID, logicalAlreadyReleased: release.logicalAlreadyReleased)
    }
    // The eligibility gate guarantees `removingNodes` is empty off-screen, so
    // the shared prune's removal-overlay scan is a no-op here (F178: before
    // the shared step, curves completing during elided ticks leaked their
    // ledger entries — the off-screen path had no prune at all).
    pruneCompletedAnimationRegistrations(completedAnimationBoxes)

    let result = AnimationTickResult(
      hasPendingWork: hasPendingWork,
      nextDeadline: hasPendingWork ? latestDeadline : nil,
      redrawIdentities: redrawIdentities
    )
    lastTickResult = result
    return result
  }

  private enum PropertyAnimationStepResult {
    case unregistered
    case completed
    case progressed(Double)
  }

  /// One shared property-curve evaluation step for the main tick and the
  /// pre-frame-head off-screen tick (F178): registration lookup, curve
  /// evaluation, custom-state write-back, and completion bookkeeping —
  /// including the `completedAnimationBoxes` feed the registration-ledger
  /// prune consumes. Interpolated-value application stays caller-side: the
  /// off-screen tick has no visible tree to write into.
  private func advancePropertyAnimationStep(
    key: AnimationKey,
    animation: ActiveAnimation,
    at timestamp: MonotonicInstant,
    keysToRemove: inout [AnimationKey],
    completedBatches: inout [CompletedBatchRelease],
    logicallyCompletedBatches: inout [AnimationBatchID],
    completedAnimationBoxes: inout Set<AnimationBox>,
    redrawIdentities: inout Set<Identity>
  ) -> PropertyAnimationStepResult {
    let release = animation.batchID.map {
      CompletedBatchRelease(batchID: $0, logicalAlreadyReleased: animation.isLogicallyReleased)
    }
    guard let anim = registeredAnimations[animation.animationBox] else {
      keysToRemove.append(key)
      if let release { completedBatches.append(release) }
      return .unregistered
    }

    let elapsed = animation.startTime.duration(to: timestamp)
    var state = animation.customState
    let evaluated = anim.evaluate(
      elapsed: elapsed,
      state: &state,
      initialVelocity: animation.initialVelocity
    )
    // Store the updated custom state back on the active animation so the
    // next tick carries user bookkeeping forward.
    activeAnimations[key]?.customState = state

    guard let progress = evaluated else {
      keysToRemove.append(key)
      completedAnimationBoxes.insert(animation.animationBox)
      if let release { completedBatches.append(release) }
      redrawIdentities.insert(key.identity)
      return .completed
    }

    // Logical-completion latch: an `Animation.logicallyComplete(after:)`
    // curve reports its batch's `.logicallyComplete` barrier at that instant
    // while the curve keeps ticking toward the `.removed` barrier.
    if let logicalDuration = anim.logicalDuration,
      let batchID = animation.batchID,
      !animation.isLogicallyReleased,
      elapsed >= logicalDuration
    {
      activeAnimations[key]?.isLogicallyReleased = true
      logicallyCompletedBatches.append(batchID)
    }

    redrawIdentities.insert(key.identity)
    return .progressed(progress)
  }

  /// A batch retain to drop at the end of a tick, with whether its logical
  /// half was already released by the latch above.
  private struct CompletedBatchRelease {
    var batchID: AnimationBatchID
    var logicalAlreadyReleased: Bool
  }

  /// Prune registration-ledger entries for curves whose consumers just completed
  /// and whose box no longer backs any live consumer (009). The box→animation
  /// ledger is otherwise append-only, so a run of unique finite curves grows it
  /// without bound. A box can back several active slots and any in-flight
  /// removal overlay, so drop it only once its LAST live reference is gone: a
  /// still-running or `.repeatForever` animation keeps its box in
  /// `activeAnimations` (its curve never returns `nil`, so it is never in
  /// `completedAnimationBoxes`) and is never pruned. Dropping a box a live
  /// animation still needs would break the retarget / velocity / merge
  /// handoff and the placed-overlay lookups that key on `registeredAnimations`.
  private func pruneCompletedAnimationRegistrations(
    _ completedAnimationBoxes: Set<AnimationBox>
  ) {
    guard !completedAnimationBoxes.isEmpty else {
      return
    }
    var liveBoxes = Set<AnimationBox>()
    for animation in activeAnimations.values {
      liveBoxes.insert(animation.animationBox)
    }
    for entry in removingNodes.values {
      if let box = entry.animationBox {
        liveBoxes.insert(box)
      }
    }
    for box in completedAnimationBoxes where !liveBoxes.contains(box) {
      registeredAnimations.removeValue(forKey: box)
    }
  }

  /// Occupancy reading for the profiling memory signal. Computed, so it stays
  /// outside the checkpoint totality contract.
  package var memoryMetricSnapshot: MemoryMetricSnapshot {
    MemoryMetricSnapshot(
      name: "AnimationController.activeAnimations",
      count: activeAnimations.count,
      detail: [
        "registered": registeredAnimations.count,
        "completions": completions.count,
        "unclaimedCompletionBatches": unclaimedCompletionBatchIDs.count,
        "batchRefCounts": batchRefCounts.count,
        "pendingEmptyBatches": pendingEmptyBatchCompletions.count,
      ]
    )
  }

  /// Registrations without a live retainer or a scheduled empty-batch drain.
  /// These can be legitimate between authoring and resolve; a batch that stays
  /// here after its home frame is the orphan-completion diagnostic.
  private var unclaimedCompletionBatchIDs: Set<AnimationBatchID> {
    Set(
      completions.keys.filter {
        batchRefCounts[$0] == nil && pendingEmptyBatchCompletions[$0] == nil
      })
  }

  /// Whether the *live* controller still holds animation work that needs another
  /// frame to drain (active animations / removals) or to fire a pending
  /// `withAnimation` completion. Used to keep the run loop's animation pump alive
  /// across SKIPPED / elided async frames: a cancelled-before-start /
  /// dropped-completed frame abandons its draft without committing, so — unlike
  /// the committed path — it never reschedules the next deadline. If the skipped
  /// frame was the one draining an animation, the live controller keeps that
  /// animation active but no deadline is armed, the run loop idles, and the
  /// deferred completion (e.g. a `PhaseAnimator` loop's per-phase completion)
  /// never fires until an unrelated event wakes the loop.
  ///
  /// Every term names work: an animation in flight (`activeAnimations`), a
  /// removal overlay (`removingNodes`), a completion that waits for its time
  /// (`pendingEmptyBatchCompletions`) and a completion that waits for its
  /// frame head to finish (`deferredFrameHeadCompletions`). The first three
  /// are also the gate of ``applyInterpolations(to:at:surfaceSize:)``, which
  /// returns at once unless one of them is non-empty. Not every entry ends
  /// in that tick: a placed-level animation and a removal the placed pass
  /// owns end in ``placedAnimationOverlaySnapshot(for:at:surfaceSize:adoption:)``,
  /// and a value animation ends in ``beginValueSiteFrame(at:currentIdentity:)``.
  ///
  /// The `.transition()` registration maps are not among them. A registration
  /// says what an insertion or a removal of its view will play. It is not
  /// work: the insertion that plays puts its animations in `activeAnimations`
  /// (``enqueueInsertionAnimation``, ``startInsertionValueSites``), and the
  /// removal that plays puts its overlay in `removingNodes`
  /// (``planRemovalOverlay``). A view at rest under a transition therefore
  /// keeps no frame armed, and the run loop sleeps until the scheduler gets
  /// its next request: an input, a state write from a task, a signal, or a
  /// deadline some other part of the runtime armed, such as a gesture's.
  package var requiresContinuedAnimationFrames: Bool {
    if !activeAnimations.isEmpty
      || !pendingEmptyBatchCompletions.isEmpty
      || !deferredFrameHeadCompletions.isEmpty
      || !removingNodes.isEmpty
    {
      return true
    }
    // Reaching here, every mechanism that could FIRE a `withAnimation`
    // completion is empty: `releaseBatch` needs an active animation to count its
    // batch refcount down to zero, and the empty-batch / frame-head completion
    // paths are likewise empty. So any `completionClosures` still registered are
    // ORPHANED — their carrier animation was removed (e.g. the owning subtree was
    // torn down when its tab was switched away) without the batch refcount
    // reaching zero, so nothing will ever fire them. Keeping the pump alive for
    // them spun forever: each deadline tick elides the off-screen removed subtree
    // (no pixels), and elision skips the resolve-time prune that would release
    // the batch — a self-sustaining off-screen elision storm that pegs the CPU
    // and stalls the new tab's first paint (the "slow / momentarily blank tab
    // switch"). The orphaned closure's awaiter is already resolved (its owning
    // `.task` was cancelled with the tab), so the loop must quiesce here; the
    // closure is never fired (doing so would double-resume a finished
    // continuation) — it is dropped by the next resolve-time prune.
    return false
  }

  /// The animation tick cadence (matches the run loop's 33 ms frame interval).
  package var animationFrameInterval: Duration {
    frameInterval
  }

  package var frameDropEligibilityBlockers: Set<FrameDropEligibility.Blocker> {
    var blockers: Set<FrameDropEligibility.Blocker> = []
    if lastFrameHeadCompletionCount > 0 || !completions.isEmpty
      || !pendingEmptyBatchCompletions.isEmpty || !deferredFrameHeadCompletions.isEmpty
    {
      blockers.insert(.animationCompletion)
    }
    if !transitionsByNodeID.isEmpty || !previousTransitionsByNodeID.isEmpty
      || !pendingTransitionsByNodeID.isEmpty || !removingNodes.isEmpty
      || activeAnimations.keys.contains(where: { key in
        if case .property = key.scope {
          return false
        }
        return true
      })
    {
      blockers.insert(.animationTransition)
    }
    return blockers
  }

  /// Called by the View layer at the start of resolve so the controller
  /// can collect up-to-date `.transition()` registrations.
  ///
  /// The PREVIOUS frame's registrations are preserved so removal
  /// detection can still find transitions for views whose branches are
  /// gone.  Registrations for identities whose subtrees are not
  /// re-evaluated this frame survive in `transitionsByNodeID` via a
  /// merge in ``finishTransitionCollection()``; stale entries for
  /// identities that leave the tree are pruned at the end of
  /// ``processResolvedTree(_:transaction:timestamp:)``.
  package func beginTransitionCollection() {
    transitions.beginCollection()
    // The collection lasts as long as the frame head's resolve, which is
    // also when a site resolves through the evaluation of its owner node.
    valueSites.beginHeadResolve()
    // What the head of an earlier frame decided for its insertions is not
    // this frame's.
    if !bodyInsertions.isEmpty {
      bodyInsertions.reset()
    }
  }

  /// Finishes the frame's `.transition()` collection.
  ///
  /// `reEvaluatedNodeIDs` is the set of ViewNodeIDs whose declarations were
  /// freshly re-evaluated this frame (the renderer threads
  /// ``ViewGraph/evaluatedNodeIDsThisFrame``). `nil` means "every live node was
  /// re-evaluated" (a full evaluation, and the shape a direct test drives),
  /// which prunes any registration not re-collected this frame.
  ///
  /// `isLiveNode` says whether a graph node is still in the graph (the
  /// renderer asks its view graph). A registration another node declared
  /// goes when that node has left. `nil` means it is not known, and no
  /// registration is dropped for it.
  package func finishTransitionCollection(
    reEvaluatedNodeIDs: Set<ViewNodeID>? = nil,
    isLiveNode: ((ViewNodeID) -> Bool)? = nil
  ) {
    transitions.mergePendingRegistrations(
      reEvaluatedNodeIDs: reEvaluatedNodeIDs, isLiveNode: isLiveNode)
    valueSites.finishHeadResolve(reEvaluatedNodeIDs: reEvaluatedNodeIDs)
  }

  /// Registers a concrete animation so the controller can re-hydrate it
  /// later from a box carried in a ``TransactionSnapshot``.
  @discardableResult
  package func register(_ animation: Animation) -> AnimationBox {
    let box = animation.animationBox
    registeredAnimations[box] = animation
    return box
  }

  /// `true` when this frame's ``processResolvedTree(_:transaction:timestamp:)``
  /// is provably a no-op and may be skipped (F66). The caller must have
  /// established that the canonical resolved tree is animation-process
  /// equivalent to the one last processed (a fully-reused resolve — zero
  /// nodes computed);
  /// this gate adds the controller-state half of the proof:
  ///
  /// - the transaction opens no animation batch, so no animation can start
  ///   and no stranded-batch drain is owed for it;
  /// - the controller may hold active animations or removal overlays, because
  ///   their deadline-only advancement is owned by `applyInterpolations` and
  ///   the placed-overlay pass rather than authored snapshot diffing;
  /// - a previous processed tree exists (baselines are recorded).
  ///
  /// Under those conditions the identity diff is empty, matched-geometry
  /// plans are empty (the key→identity maps are unchanged), the transition
  /// prune is a no-op (already pruned against the same live set), and the
  /// baseline stores would rewrite animation-equivalent data — so skipping the
  /// full-tree walk changes nothing. `noteSkippedResolvedTreeProcessing`
  /// DEBUG-asserts that premise against the exact resolved fields consumed by
  /// this controller. Transaction snapshots are intentionally excluded: with
  /// no changed animatable snapshot and no new root animation batch, changing
  /// inherited transaction intent cannot enqueue work.
  package func canSkipResolvedTreeProcessing(
    transactionPlan: FrameAnimationTransactionPlan,
    graphAnimationInputToken: UInt64? = nil
  ) -> Bool {
    // `isContinuous` is deliberately not consulted: continuity is
    // resolve-side metadata with no animation intent, so a
    // continuity-only transaction cannot enqueue controller work and
    // must not defeat the skip (plan 2026-08-04-002 §5.5).
    previousTreeRoot != nil
      // A registration or a site record that waits for this frame's tree to
      // say whether its view is still there has to see that tree.
      && transitions.unconfirmedNodeIDs.isEmpty
      && valueSites.unresolvedKeys.isEmpty
      && !transactionPlan.hasExplicitTransactions
      && transactionPlan.base.animationRequest.animationBoxIfAny == nil
      && transactionPlan.base.animationBatchID == nil
      && !transactionPlan.base.tracksVelocity
      && (graphAnimationInputToken == nil
        || graphAnimationInputToken == previousFrame.graphAnimationInputToken)
  }

  private func settleReducedMotion(
    reducedIdentities: Set<Identity>,
    currentIdentities: Set<Identity>,
    transactions: [Identity: TransactionSnapshot],
    timestamp: MonotonicInstant
  ) {
    guard !reducedIdentities.isEmpty else { return }
    func isReduced(_ identity: Identity) -> Bool {
      var candidate: Identity? = identity
      while let current = candidate {
        if currentIdentities.contains(current) { return reducedIdentities.contains(current) }
        // A departing .id may live outside its structural parent's identity
        // prefix. Follow the actual previous tree, not string ancestry.
        candidate =
          previousParentByIdentity[current]
          ?? previousFrame.realizedPresentationOwners[current]
      }
      return false
    }
    var finishedBoxes: Set<AnimationBox> = []
    for key in Array(activeAnimations.keys) {
      // A value animation is not ended here. Its site ends it when it
      // resolves under the policy, and presents its target in the same
      // step (`presentedValue`, `settlesAnimationInFlight`). Removing the
      // entry here would leave the body at the sample it last ran with, and
      // nothing would evaluate it again.
      guard !key.isValue else { continue }
      guard let entry = activeAnimations[key], isReduced(entry.resolvedIdentity ?? key.identity)
      else { continue }
      activeAnimations.removeValue(forKey: key)
      slotVelocitySamplers.removeValue(forKey: key)
      finishedBoxes.insert(entry.animationBox)
      releaseBatch(entry.batchID, logicalAlreadyReleased: entry.isLogicallyReleased)
    }
    for nodeID in Array(removingNodes.keys) {
      guard let entry = removingNodes[nodeID],
        isReduced(entry.identity) || entry.parentIdentity.map(isReduced) == true
          || entry.snapshot.environmentSnapshot.style.renderingReduceMotion
      else { continue }
      removingNodes.removeValue(forKey: nodeID)
      if let box = entry.animationBox { finishedBoxes.insert(box) }
      // The values of a transition body end with the removal that owns them.
      // Their views are in no tree the walk above can reach.
      if let body = entry.body {
        finishedBoxes.formUnion(endRemovalBodyAnimations(of: body))
      }
      releaseBatch(entry.completionBatchID, logicalAlreadyReleased: entry.isLogicallyComplete)
    }
    pruneCompletedAnimationRegistrations(finishedBoxes)
    for identity in reducedIdentities {
      guard let batchID = transactions[identity]?.animationBatchID,
        batchRefCounts[batchID] == nil, completions[batchID] != nil
      else { continue }
      pendingEmptyBatchCompletions[batchID] = timestamp
    }
  }

  /// Direct-test convenience for a frame with one base transaction and no
  /// identity-scoped scheduler segments.
  package func canSkipResolvedTreeProcessing(
    transaction: TransactionSnapshot
  ) -> Bool {
    canSkipResolvedTreeProcessing(
      transactionPlan: FrameAnimationTransactionPlan(base: transaction)
    )
  }

  /// Number of frames whose resolved-tree processing was skipped by the
  /// F66 gate. Test hook: pins that the gate actually fires on fully-reused
  /// frames (a silently dead gate would pass every behavior test).
  package private(set) var resolvedTreeProcessingSkipCount = 0

  /// The skip-path counterpart of ``processResolvedTree``'s per-frame
  /// resets: clears the head completion count (nothing can fire on a skipped
  /// frame), refreshes the retained removal-capture root without walking it,
  /// and pins the caller's animation-process-equivalence premise in DEBUG.
  package func noteSkippedResolvedTreeProcessing(resolved: ResolvedNode) {
    lastFrameHeadCompletionCount = 0
    lastResolvedTreeProcessedNodeCount = 0
    resolvedTreeProcessingSkipCount += 1
    if !bodyInsertions.isEmpty {
      bodyInsertions.reset()
    }
    #if DEBUG
      if let previousTreeRoot,
        let divergence = Self.debugFirstAnimationProcessDivergence(
          previousTreeRoot,
          resolved,
          path: "root"
        )
      {
        assertionFailure(
          """
          processResolvedTree skipped for a resolved tree that differs in \
          animation-processing inputs — the zero-computed-nodes premise is \
          unsound here. First divergence: \(divergence)
          """
        )
      }
    #endif
    previousTreeRoot = resolved
  }

  #if DEBUG
    /// Names the first divergence in the exact resolved-tree inputs consumed
    /// by `processResolvedTree`: identity topology, owner node routing,
    /// animatable snapshots, and matched-geometry registration. Transaction
    /// snapshots are not baselines and cannot matter when the animatable
    /// snapshot is unchanged.
    private static func debugFirstAnimationProcessDivergence(
      _ lhs: ResolvedNode,
      _ rhs: ResolvedNode,
      path: String
    ) -> String? {
      if lhs.identity != rhs.identity {
        // Name the node shapes too: an identity divergence at one position is
        // usually a wrapper level present on one evaluation path and absent on
        // the other (plan 2026-08-25-003 P3), which the kinds and child counts
        // show at a glance.
        return
          "\(path): identity prev=\(lhs.identity.path) current=\(rhs.identity.path) "
          + "(prev \(lhs.kind) x\(lhs.children.count) children"
          + "\(lhs.children.first.map { " first=\($0.kind)@\($0.identity.path)" } ?? ""); "
          + "current \(rhs.kind) x\(rhs.children.count) children"
          + "\(rhs.children.first.map { " first=\($0.kind)@\($0.identity.path)" } ?? ""))"
      }
      if lhs.viewNodeID != rhs.viewNodeID {
        let lhsStamp = lhs.viewNodeID.map { "\($0.rawValue)" } ?? "nil"
        let rhsStamp = rhs.viewNodeID.map { "\($0.rawValue)" } ?? "nil"
        return "\(path): viewNodeID prev=\(lhsStamp) current=\(rhsStamp)"
      }
      if AnimatableSnapshot.extract(from: lhs).values
        != AnimatableSnapshot.extract(from: rhs).values
      {
        return "\(path): animatableSnapshot"
      }
      if lhs.environmentSnapshot.style.renderingReduceMotion
        != rhs.environmentSnapshot.style.renderingReduceMotion
      {
        return "\(path): reduceMotion"
      }
      if lhs.matchedGeometry != rhs.matchedGeometry { return "\(path): matchedGeometry" }
      if lhs.children.count != rhs.children.count { return "\(path): children.count" }
      for (index, (l, r)) in zip(lhs.children, rhs.children).enumerated() {
        if let divergence = debugFirstAnimationProcessDivergence(
          l,
          r,
          path: "\(path)[\(index)]<\(l.identity.path)>"
        ) {
          return divergence
        }
      }
      return nil
    }

    /// Walks two resolved trees in lockstep and names the first node path +
    /// field where `==` diverges — the F66 skip-premise assert's forensic
    /// payload, so a premise break names its divergent subtree instead of
    /// requiring a live reproduction to localize.
    package static func debugFirstDivergence(
      _ lhs: ResolvedNode,
      _ rhs: ResolvedNode,
      path: String
    ) -> String {
      if lhs.identity != rhs.identity {
        return "\(path): identity \(lhs.identity.path) vs \(rhs.identity.path)"
      }
      if lhs.structuralPath != rhs.structuralPath { return "\(path): structuralPath" }
      if lhs.structuralEdgeRole != rhs.structuralEdgeRole { return "\(path): structuralEdgeRole" }
      if lhs.entityIdentity != rhs.entityIdentity { return "\(path): entityIdentity" }
      if lhs.entityStructuralPath != rhs.entityStructuralPath {
        return "\(path): entityStructuralPath"
      }
      if lhs.declarationOwnerEdge != rhs.declarationOwnerEdge {
        return "\(path): declarationOwnerEdge"
      }
      if lhs.kind != rhs.kind { return "\(path): kind \(lhs.kind) vs \(rhs.kind)" }
      if !ResolvedNode.typeDiscriminatorsCompatible(lhs.typeDiscriminator, rhs.typeDiscriminator) {
        return "\(path): typeDiscriminator"
      }
      if lhs.environmentSnapshot != rhs.environmentSnapshot {
        return "\(path): environmentSnapshot"
      }
      if lhs.transactionSnapshot != rhs.transactionSnapshot {
        return "\(path): transactionSnapshot"
      }
      if lhs.layoutBehavior != rhs.layoutBehavior { return "\(path): layoutBehavior" }
      if lhs.layoutMetadata != rhs.layoutMetadata { return "\(path): layoutMetadata" }
      if lhs.layoutRealizedContent?.equivalenceSignature
        != rhs.layoutRealizedContent?.equivalenceSignature
      {
        return "\(path): layoutRealizedContent"
      }
      if lhs.drawMetadata != rhs.drawMetadata { return "\(path): drawMetadata" }
      if lhs.drawEffects != rhs.drawEffects { return "\(path): drawEffects" }
      if lhs.surfaceComposition != rhs.surfaceComposition { return "\(path): surfaceComposition" }
      if lhs.semanticMetadata != rhs.semanticMetadata { return "\(path): semanticMetadata" }
      if lhs.lifecycleMetadata != rhs.lifecycleMetadata { return "\(path): lifecycleMetadata" }
      if lhs.drawPayload != rhs.drawPayload { return "\(path): drawPayload" }
      if lhs.intrinsicSize != rhs.intrinsicSize { return "\(path): intrinsicSize" }
      if lhs.indexedChildSource?.measurementSignature
        != rhs.indexedChildSource?.measurementSignature
      {
        return "\(path): indexedChildSource"
      }
      if lhs.preferenceValues != rhs.preferenceValues { return "\(path): preferenceValues" }
      if lhs.supportsRetainedReuse != rhs.supportsRetainedReuse {
        return "\(path): supportsRetainedReuse"
      }
      if lhs.matchedGeometry != rhs.matchedGeometry { return "\(path): matchedGeometry" }
      if lhs.isTransient != rhs.isTransient { return "\(path): isTransient" }
      if lhs.children.count != rhs.children.count {
        return "\(path): children.count \(lhs.children.count) vs \(rhs.children.count)"
      }
      for (index, (l, r)) in zip(lhs.children, rhs.children).enumerated() where l != r {
        return debugFirstDivergence(l, r, path: "\(path)[\(index)]<\(l.identity.path)>")
      }
      return "\(path): (equal?)"
    }
  #endif

  /// Called after resolve, before measure.  Compares the new resolved
  /// tree to the previous snapshot and starts or retargets animations
  /// for changed properties.
  package func processResolvedTree(
    _ node: ResolvedNode,
    transactionPlan: FrameAnimationTransactionPlan,
    timestamp: MonotonicInstant,
    graphAnimationInputToken: UInt64? = nil
  ) {
    let transaction = transactionPlan.base
    lastFrameHeadCompletionCount = 0
    lastResolvedTreeProcessedNodeCount = 0
    // If the incoming transaction carries an animation box, make sure
    // the controller has the concrete Animation registered. In normal
    // flow the View-layer `withAnimation`/`.animation(_:value:)` sink
    // already registered it at withAnimation-time, but a `withAnimation`
    // dispatched outside the run loop's installed registration-sink scope
    // (an event handler driven directly, not through `RunLoop.run()`)
    // threads the box onto the transaction without ever registering the
    // concrete curve. The box itself carries that curve, so recover and
    // register it here: an `.animate(box)` request means "animate with
    // this animation", and an unregistered box would otherwise be purged
    // on the next tick (its `evaluate` finds no registration), silently
    // dropping the requested animation.
    for frameTransaction in transactionPlan.transactions {
      if case .animate(let box) = frameTransaction.animationRequest,
        registeredAnimations[box] == nil,
        let animation = box.unwrap(as: Animation.self)
      {
        registeredAnimations[box] = animation
      }
    }

    var newSnapshots: [Identity: AnimatableSnapshot] = [:]
    var newParentByIdentity: [Identity: Identity] = [:]
    var newChildIndexByIdentity: [Identity: Int] = [:]
    var newMatchedConfigsByIdentity: [Identity: MatchedGeometryConfig] = [:]
    var newNodeIDByIdentity: [Identity: ViewNodeID] = [:]
    var newTransactionsByIdentity: [Identity: TransactionSnapshot] = [:]
    var reducedMotionIdentities: Set<Identity> = []
    var newLiveNodeIDs: Set<ViewNodeID> = []
    let activeKeysByOwnerNodeID = Dictionary(
      grouping: activeAnimations.compactMap { key, animation in
        animation.ownerViewNodeID.map { ($0, key) }
      },
      by: \.0
    ).mapValues { entries in entries.map(\.1) }
    processNode(
      node,
      parentIdentity: nil,
      childIndex: 0,
      transaction: transaction,
      scopeOuterTransaction: nil,
      transactionPlan: transactionPlan,
      timestamp: timestamp,
      snapshotAccumulator: &newSnapshots,
      parentAccumulator: &newParentByIdentity,
      childIndexAccumulator: &newChildIndexByIdentity,
      matchedKeyAccumulator: &newMatchedConfigsByIdentity,
      nodeIDAccumulator: &newNodeIDByIdentity,
      transactionAccumulator: &newTransactionsByIdentity,
      reducedMotionAccumulator: &reducedMotionIdentities,
      liveNodeIDAccumulator: &newLiveNodeIDs,
      activeKeysByOwnerNodeID: activeKeysByOwnerNodeID
    )

    // Bring the registrations in line with the committed tree: re-home the
    // ones whose node id was aliased away by single-child subtree
    // re-stamping onto the node that carries their identity, and drop the
    // ones whose node now emits another view than the one they were made
    // for. See ``TransitionRegistry/reconcile(liveNodeIDs:nodeIDByIdentity:)``.
    transitions.reconcile(liveNodeIDs: newLiveNodeIDs, nodeIDByIdentity: newNodeIDByIdentity)

    // Detect insertions and removals by diffing identity sets.  Skip
    // identities that are already mid-removal: they exist in the
    // injected overlay but not in the live tree, so they should not be
    // re-inserted as "new".
    let resolvedDiff = AnimationResolvedIdentityDiff.make(
      newSnapshots: newSnapshots,
      previousIdentities: previousIdentities,
      removingIdentities: removingIdentitySet
    )
    let newIdentities = resolvedDiff.newIdentities
    let insertedIdentities = resolvedDiff.insertedIdentities
    // Removal detection keys on ViewNodeID occurrences, not Identity. A node
    // that departed the live tree is one whose ViewNodeID was live last frame
    // and is not live now — this catches a departed occurrence of a still-live
    // duplicate `.id` (Identity survives, one occurrence left) that pure
    // Identity-set subtraction misses, and it does *not* flag a reparented node
    // (same ViewNodeID under a new parent Identity) whose ViewNodeID is still
    // live, so a stable entity changing parents produces no false removal.
    let departedNodeIDs = previousLiveNodeIDs.subtracting(newLiveNodeIDs)

    // A same-identity reinsertion supersedes that identity's in-flight
    // removal overlay: the live node owns the visual from this frame on, so
    // the frozen exit snapshot must not keep compositing beside it. (The
    // diff above already treats mid-removal identities as departed, so the
    // reinsertion still fires its own insertion transition when one is
    // registered.)
    var reinsertionOpacities: [Identity: Double] = [:]
    // The body channel of each superseded removal, by the removal's identity.
    // Its animations stay in flight until the insertion below takes them.
    var returnedRemovalBodies: [Identity: RemovalBodyState] = [:]
    if !removingNodes.isEmpty {
      let supersededRemovals = removingNodes.filter { _, entry in
        newIdentities.contains(entry.identity)
      }
      for viewNodeID in supersededRemovals.keys {
        if let entry = removingNodes.removeValue(forKey: viewNodeID) {
          if let target = entry.transition.removalModifiers().opacity,
            let box = entry.animationBox, let animation = registeredAnimations[box]
          {
            var state = entry.customState
            let progress =
              animation.evaluate(
                elapsed: entry.startTime.duration(to: timestamp), state: &state) ?? 1
            reinsertionOpacities[entry.identity] =
              entry.startOpacity + (target - entry.startOpacity) * progress
          }
          if let body = entry.body {
            returnedRemovalBodies[entry.identity] = body
          }
          releaseBatch(
            entry.completionBatchID,
            logicalAlreadyReleased: entry.isLogicallyComplete
          )
        }
      }
    }

    // Matched-geometry detection.  A match fires when the current
    // frame's (identity, key) mapping differs from the previous
    // frame's — regardless of whether either identity is newly
    // inserted.  Both "swap via reorder" and "swap via if/else"
    // cases are handled by comparing previous vs new key→identity
    // maps.  Record which live identity received each matched key so
    // the counterpart's exit overlay can travel toward it.
    let matchedGeometryPlans = AnimationResolvedTreeDiffing.matchedGeometryPlans(
      newMatchedConfigsByIdentity: newMatchedConfigsByIdentity,
      previousMatchedKeyIdentities: previousMatchedKeyIdentities,
      previousMatchedGeometryBounds: previousMatchedGeometryBounds,
      transactionForIdentity: { identity in
        newTransactionsByIdentity[identity]
          ?? transactionPlan.transaction(for: identity)
      }
    )
    let matchedDestinationsByKey = matchedGeometryPlans.destinationIdentityByKey
    for plan in matchedGeometryPlans.animations {
      let matchedKey = AnimationKey(
        identity: plan.identity, scope: .matchedGeometry
      )
      if let existing = activeAnimations[matchedKey] {
        releaseBatch(existing.batchID, logicalAlreadyReleased: existing.isLogicallyReleased)
      }
      retainBatch(plan.batchID)
      activeAnimations[matchedKey] = ActiveAnimation(
        kind: .matchedGeometry(
          fromBounds: plan.fromBounds,
          properties: plan.properties,
          anchor: plan.anchor
        ),
        animationBox: plan.animationBox,
        startTime: timestamp,
        batchID: plan.batchID
      )
    }

    // Process insertions: kick off willAppear -> identity animations.
    // A matched-geometry swap does not suppress the arriving instance's
    // transition: the match owns its geometry (a placed-level translate and
    // resize) and the transition owns opacity, offset, and scale, and the two
    // compose — `.transition(.opacity)` fades the arriving instance in
    // along the matched path while the departing instance's exit overlay
    // travels the same path (`planRemovalOverlay`), the cross-fade SwiftUI
    // shows when a view in its removal transition is positioned onto the
    // new source.
    //
    // Skip structural first-appearances: when an identity's
    // parent was also just inserted, the whole subtree appeared
    // because a container was mounted (e.g. tab switch), NOT because
    // a conditional toggled inside withAnimation.  Playing insertion
    // transitions for these would cause spurious fade-ins whenever a
    // PhaseAnimator or other continuous animation shares the frame
    // transaction.  This matches SwiftUI, which only fires
    // .transition() when the view's conditional presence changes.
    //
    // A transition with a body also animates the slots its `.willAppear`
    // body and the live tree hold different values for. One evaluation of
    // that phase serves every root a body emitted this frame.
    //
    // Which insertions qualify is decided by one helper,
    // ``qualifiedInsertion(of:among:in:registry:transactionPlan:)``. The
    // frame head runs it too, on the frame that inserts a body with an
    // `Animatable` view or modifier in it
    // (``prepareTransitionBodyInsertions``), and what the head decided for
    // the body channel is read here instead of being decided a second time.
    var bodyInsertionFrame: AnimationTransitionBodyInsertion.Frame?
    var bodyInsertionOrigins: [Identity: AnimationTransitionBodyInsertion.Origin] = [:]
    let insertionCensus = InsertionCensus(
      root: node,
      identities: newIdentities,
      parents: newParentByIdentity,
      nodeIDs: newNodeIDByIdentity,
      liveNodeIDs: newLiveNodeIDs,
      transactions: newTransactionsByIdentity
    )
    for identity in insertedIdentities {
      guard
        let insertion = qualifiedInsertion(
          of: identity,
          among: insertedIdentities,
          in: insertionCensus,
          registry: transitions,
          transactionPlan: transactionPlan)
      else { continue }
      let transition = insertion.transition
      var insertionTransaction = insertion.transaction
      // The body channel. The `.willAppear` body is evaluated only when the
      // insertion can play: with no curve it snaps, as the effects do.
      var bodyChanges: [AnimationTransitionBodyInsertion.SlotChange] = []
      if let registration = transition.bodyRegistration {
        let decision =
          bodyInsertions.decisions[identity]
          ?? bodyInsertionDecision(
            for: insertion,
            parents: newParentByIdentity,
            returnedRemovalIdentities: returnedRemovalBodies.keys)
        // The data of the body's sites animates under the transaction the
        // decision was made with. The slots take the same one.
        insertionTransaction = decision.transaction
        if decision.plays {
          let frame =
            bodyInsertionFrame
            ?? AnimationTransitionBodyInsertion.Frame(
              root: node,
              snapshots: newSnapshots,
              nodeIDs: newNodeIDByIdentity,
              parents: newParentByIdentity,
              transactions: newTransactionsByIdentity
            )
          bodyInsertionFrame = frame
          if let returnedIdentity = decision.returnedRemovalIdentity,
            let returned = returnedRemovalBodies.removeValue(forKey: returnedIdentity)
          {
            // The view came back while its removal was in flight. It continues
            // from what the removal shows, not from the `.willAppear` body: a
            // value still in flight is retargeted from its sample with its
            // velocity, and a settled one starts at its `.didDisappear` value.
            returnRemovalBodyAnimations(of: returned, to: frame)
            bodyChanges = AnimationTransitionBodyRemoval.reinsertionChanges(
              from: returned, insertedIdentity: identity, in: frame)
          } else {
            let origin: AnimationTransitionBodyInsertion.Origin
            if let evaluated = bodyInsertionOrigins[registration.identity] {
              origin = evaluated
            } else {
              // The head evaluated this phase already when the body has an
              // `Animatable` view or modifier whose data starts there.
              origin = AnimationTransitionBodyInsertion.origin(
                of: registration, in: frame,
                willAppearRoots: bodyInsertions.willAppearRoots[registration.identity])
              if let issue = origin.phaseOnlyIssue {
                // The tail of this frame drains the queue into its issue channel.
                ImperativeRuntimeIssueQueue.record(issue)
              }
              bodyInsertionOrigins[registration.identity] = origin
            }
            bodyChanges = AnimationTransitionBodyInsertion.changes(
              from: origin, insertedIdentity: identity, in: frame)
          }
        }
      }
      enqueueInsertionAnimation(
        identity: identity,
        viewNodeID: insertion.viewNodeID,
        transition: transition,
        snapshot: newSnapshots[identity] ?? .init(),
        reinsertionOpacity: reinsertionOpacities[identity],
        bodyChanges: bodyChanges,
        transaction: insertionTransaction,
        timestamp: timestamp
      )
    }
    // The head's decisions were for this frame's insertions.
    if !bodyInsertions.isEmpty {
      bodyInsertions.reset()
    }

    // A removal body whose view came back without replaying its transition
    // (no curve, or an insertion the rules above skip) ends here: its values
    // stop, and the view shows its identity body.
    for body in returnedRemovalBodies.values {
      endRemovalBodyAnimations(of: body)
    }

    // What the sites of each departing transition body showed when the
    // removal of the root that holds them took them over, for the removals
    // of the body's other roots.
    var plannedRemovalSites: [AnimationKey: AnimationTransitionBodyRemoval.LiveSite] = [:]

    // Process removals: look up the full subtree and position from the
    // previous frame so the animation controller can re-inject them as
    // non-semantic overlays each tick until the exit animation
    // completes.
    //
    // The transition is registered against the leaf identity that the
    // `.transition()` modifier's child resolved to, but that leaf may
    // be wrapped by layout modifiers (e.g. `.padding(1)`) which
    // themselves have distinct identities and disappear at the same
    // time.  Walk up the previous parent chain until we find an
    // ancestor that is still in the new tree — that's the insertion
    // point — and capture the deepest disappearing ancestor as the
    // subtree to inject.  This way the entire wrapped unit fades out.
    //
    // Both channels below find the views with a transition that left on this
    // frame. They are collected first and planned afterwards, because what
    // one of them plays depends on the others: a view inside another
    // departing view with a transition is part of that view's removal and
    // plans none of its own (``departingTransitionRoots(of:)``).
    var removalCandidates: [RemovalCandidate] = []
    if let previousRoot = previousTreeRoot {
      for removedNodeID in departedNodeIDs {
        // O(1) dictionary guards run before the O(tree) previous-frame node
        // search: bulk teardown departs many nodes at once, and most carry no
        // transition registration and are not already animating out.
        //
        // Removal look-up uses the PREVIOUS frame's registrations: the
        // disappearing view's `.transition()` modifier isn't evaluated in
        // the current frame (its branch is gone), so `transitionsByNodeID`
        // no longer contains an entry for it.  The previous frame captured
        // the registration while the view was still present.
        guard removingNodes[removedNodeID] == nil,
          let transition = previousTransitionsByNodeID[removedNodeID],
          let previousNode = AnimationTreeQueries.findResolvedNode(
            in: previousRoot,
            viewNodeID: removedNodeID
          )
        else { continue }
        removalCandidates.append(
          RemovalCandidate(
            nodeID: removedNodeID, identity: previousNode.identity, transition: transition,
            channel: .departedNode))
      }

      // Second removal channel: adopted-slot conditional removals. Branch flips
      // inside a structural slot ADOPT the slot's graph node for the incoming
      // occupant, so the departing transition child's ViewNodeID stays live and
      // the occurrence diff above cannot see it leave. The previous frame's
      // registration map records exactly which identity the transition was
      // authored for — if that identity left the identity set while its node
      // survived, the conditional presence changed and the exit must play.
      // A node re-registered THIS frame is a surviving transition node
      // (reparent or value update), never a conditional removal, and real node
      // departures already ran through the occurrence channel above.
      for (nodeID, registeredIdentity) in previousTransitionIdentitiesByNodeID {
        guard removingNodes[nodeID] == nil,
          !departedNodeIDs.contains(nodeID),
          !newIdentities.contains(registeredIdentity),
          previousIdentities.contains(registeredIdentity),
          !removingIdentitySet.contains(registeredIdentity),
          transitionIdentitiesByNodeID[nodeID] == nil,
          let transition = previousTransitionsByNodeID[nodeID],
          AnimationTreeQueries.findResolvedNode(
            in: previousRoot,
            identity: registeredIdentity
          ) != nil
        else { continue }
        removalCandidates.append(
          RemovalCandidate(
            nodeID: nodeID, identity: registeredIdentity, transition: transition,
            channel: .adoptedSlot))
      }

      for candidate in departingTransitionRoots(of: removalCandidates) {
        // A removal planned earlier in this loop can have taken the node or
        // the identity of a later candidate.
        guard removingNodes[candidate.nodeID] == nil,
          candidate.channel == .departedNode || !removingIdentitySet.contains(candidate.identity)
        else { continue }
        planRemovalOverlay(
          removedNodeID: candidate.nodeID,
          identity: candidate.identity,
          transition: candidate.transition,
          previousRoot: previousRoot,
          newIdentities: newIdentities,
          newLiveNodeIDs: newLiveNodeIDs,
          matchedDestinationsByKey: matchedDestinationsByKey,
          transactionPlan: transactionPlan,
          timestamp: timestamp,
          plannedSites: &plannedRemovalSites
        )
      }
    }

    // Unmarked presence boundaries use opacity. Select the topmost departed
    // subtree once: synthesizing a registration on every node would multiply
    // the fade and make a bulk departure search the old tree for every leaf.
    // Explicit transitions anywhere within that boundary own its behavior,
    // including `.identity`, which intentionally suppresses the default.
    if let previousRoot = previousTreeRoot,
      transactionPlan.transactions.contains(where: { $0.animationRequest.animationBoxIfAny != nil })
    {
      var pending = [previousRoot]
      while let previousNode = pending.popLast() {
        if !newIdentities.contains(previousNode.identity),
          let parent = previousParentByIdentity[previousNode.identity],
          newIdentities.contains(parent)
        {
          let subtreeIdentities = AnimationTreeQueries.collectIdentities(in: previousNode)
          let hasExplicitTransition = previousTransitionIdentitiesByNodeID.values.contains {
            subtreeIdentities.contains($0)
          }
          if !hasExplicitTransition,
            let nodeID = previousNode.viewNodeID,
            removingNodes[nodeID] == nil,
            previousNode.entityIdentity == nil || !newLiveNodeIDs.contains(nodeID)
          {
            planRemovalOverlay(
              removedNodeID: nodeID, identity: previousNode.identity,
              transition: .opacity, previousRoot: previousRoot,
              newIdentities: newIdentities,
              newLiveNodeIDs: newLiveNodeIDs,
              matchedDestinationsByKey: matchedDestinationsByKey,
              transactionPlan: transactionPlan, timestamp: timestamp,
              plannedSites: &plannedRemovalSites)
          }
          continue
        }
        pending.append(contentsOf: previousNode.children)
      }
    }

    // The removals of one body last together while its sites animate.
    shareRemovalValueSiteLifetimes(plannedAt: timestamp)

    // Prune transition registrations for nodes that are no longer
    // in the live tree. Their registration was already copied into
    // previousTransitionsByNodeID at the start of this frame, so any
    // removal that needed it has already found it. Pruning prevents
    // unbounded growth of the map.
    transitions.pruneDepartedNodes(liveNodeIDs: newLiveNodeIDs)

    // Reclaim animations whose identities left the live tree WITHOUT a
    // registered transition (tab switch, bare `if`) — the resolve-time prune
    // the quiesce logic in `requiresContinuedAnimationFrames` promises. The
    // removal loop above only reaches identities with a
    // `previousTransitionsByNodeID` entry; an untransitioned removal skipped
    // everything, stranding `activeAnimations` entries (a removed
    // `.repeatForever` re-armed the 33 ms pump for the rest of the session)
    // and batch refcounts that could never reach zero (their completion
    // closures pinned `.animationCompletion` into the frame-drop blockers
    // permanently). Identities mid-exit-overlay are exempt: their entries
    // were superseded when the removal was planned, and the overlay ticks
    // through `removingNodes`, not `activeAnimations`. Orphaned completions
    // are dropped, never fired — their awaiters died with the subtree.
    let exitOverlayIdentities = removingIdentitySet
    // The values of a transition body in its removal are still animating,
    // for the removal that owns them.
    let removalBodyOwners = removalBodyOwners
    // A value animation belongs to the view at its site. That view's
    // identity can be absent from the tree while its node is in it, and its
    // node can stay in the tree after the view has gone (see
    // ``ValueSiteState/isLive(_:identities:liveNodeIDs:)``).
    let valueSiteIsLive = { [valueSites] (key: AnimationKey) -> Bool in
      valueSites.isLive(key, identities: newIdentities, liveNodeIDs: newLiveNodeIDs)
    }
    // So is the data of that body's `Animatable` views and modifiers, by
    // key: such a site need not resolve at an identity the removal froze.
    let removalOwnedValueKeys = removalOwnedValueKeys
    let departedKeys = activeAnimations.keys.filter { key in
      !newIdentities.contains(key.identity)
        && !exitOverlayIdentities.contains(key.identity)
        && removalBodyOwners[key.identity] == nil
        && !(key.isValue && (valueSiteIsLive(key) || removalOwnedValueKeys.contains(key)))
        && !(previousFrame.realizedPresentationTargets[key] != nil
          && previousFrame.realizedPresentationOwners[key.identity].map {
            newIdentities.contains($0)
          }
            == true)
    }
    var departedBatchCounts: [AnimationBatchID: Int] = [:]
    for key in departedKeys {
      if let batchID = activeAnimations[key]?.batchID {
        departedBatchCounts[batchID, default: 0] += 1
      }
    }
    // Decide against the whole prune, not dictionary iteration order: only
    // retainers that actually survive this frame can own these completions.
    let survivingBatches = Set(
      departedBatchCounts.compactMap { batchID, count in
        (batchRefCounts[batchID] ?? 0) > count ? batchID : nil
      })
    for key in departedKeys {
      guard let entry = activeAnimations.removeValue(forKey: key) else { continue }
      releaseBatch(
        entry.batchID,
        logicalAlreadyReleased: entry.isLogicallyReleased,
        firingCompletion: entry.batchID.map { survivingBatches.contains($0) } ?? false
      )
    }
    if !slotVelocitySamplers.isEmpty {
      slotVelocitySamplers = slotVelocitySamplers.filter { newIdentities.contains($0.key.identity) }
    }
    // The target an `Animatable` view or modifier last resolved with belongs
    // to the view at that site. One that left takes its record with it, so
    // a view that later appears there starts from its own value and not
    // from an old one, and is a new site to the frame head.
    if !valueSites.targets.isEmpty {
      let liveTargets = valueSites.targets.filter { valueSiteIsLive($0.key) }
      if liveTargets.count != valueSites.targets.count {
        valueSites.targets = liveTargets
      }
      if !valueSites.ownerNodeIDs.isEmpty {
        valueSites.ownerNodeIDs = valueSites.ownerNodeIDs.filter { liveTargets[$0.key] != nil }
      }
      if !valueSites.lateKeys.isEmpty {
        valueSites.lateKeys = valueSites.lateKeys.filter { liveTargets[$0] != nil }
      }
    } else if !valueSites.lateKeys.isEmpty {
      valueSites.lateKeys.removeAll(keepingCapacity: true)
    }
    if !valueSites.unresolvedKeys.isEmpty {
      valueSites.unresolvedKeys.removeAll(keepingCapacity: true)
    }

    // A policy change is meaningful even when the authored target value did
    // not change. End every affected channel (including frozen exits) before
    // interpolation, releasing each completion retainer exactly once.
    settleReducedMotion(
      reducedIdentities: reducedMotionIdentities,
      currentIdentities: newIdentities,
      transactions: newTransactionsByIdentity,
      timestamp: timestamp)

    previousSnapshots = newSnapshots
    previousIdentities = newIdentities
    previousLiveNodeIDs = newLiveNodeIDs
    previousTreeRoot = node
    previousParentByIdentity = newParentByIdentity
    previousChildIndexByIdentity = newChildIndexByIdentity
    previousFrame.graphAnimationInputToken = graphAnimationInputToken

    // Drain stranded completions.  Any batch that has a registered
    // completion closure but no live ref count (no property, no
    // removal, no insertion, no matched-geometry retained it) will
    // otherwise leak forever — and any `withAnimation` caller that
    // await-ed on its completion (like ``PhaseAnimator``) would hang.
    // Schedule a drain for each such batch here; the drain fires
    // after the animation's nominal duration in ``applyInterpolations``.
    for frameTransaction in transactionPlan.transactions
    where frameTransaction.animationBatchID != nil {
      scheduleStrandedBatchDrains(
        transaction: frameTransaction,
        timestamp: timestamp
      )
    }
  }

  /// Direct-test convenience for a frame with one base transaction and no
  /// identity-scoped scheduler segments.
  package func processResolvedTree(
    _ node: ResolvedNode,
    transaction: TransactionSnapshot,
    timestamp: MonotonicInstant,
    graphAnimationInputToken: UInt64? = nil
  ) {
    processResolvedTree(
      node,
      transactionPlan: FrameAnimationTransactionPlan(base: transaction),
      timestamp: timestamp,
      graphAnimationInputToken: graphAnimationInputToken
    )
  }

  // MARK: - Insertion qualification

  /// The tables of a resolved tree that deciding its insertions reads.
  ///
  /// The injection stage fills them while it diffs the tree. The frame head
  /// needs them earlier, before the tree is final, and takes a census of the
  /// tree for that (``insertionCensus(of:transactionPlan:)``).
  private struct InsertionCensus {
    var root: ResolvedNode
    var identities: Set<Identity> = []
    var parents: [Identity: Identity] = [:]
    var nodeIDs: [Identity: ViewNodeID] = [:]
    var liveNodeIDs: Set<ViewNodeID> = []
    /// The effective transaction of each node.
    var transactions: [Identity: TransactionSnapshot] = [:]
  }

  /// Walks `root` as ``processResolvedTree`` walks it and records what
  /// deciding its insertions reads. It starts no animation and changes
  /// nothing: the effective transaction of each node comes from the helper
  /// the diffing walk uses.
  private func insertionCensus(
    of root: ResolvedNode,
    transactionPlan: FrameAnimationTransactionPlan
  ) -> InsertionCensus {
    var census = InsertionCensus(root: root)
    func visit(
      _ node: ResolvedNode,
      parentIdentity: Identity?,
      transaction: TransactionSnapshot,
      scopeOuterTransaction: TransactionSnapshot?
    ) {
      let effective = nodeTransactions(
        of: node,
        inherited: transaction,
        scopeOuterTransaction: scopeOuterTransaction,
        transactionPlan: transactionPlan
      ).effective
      census.identities.insert(node.identity)
      if let parentIdentity {
        census.parents[node.identity] = parentIdentity
      }
      if let viewNodeID = node.viewNodeID {
        census.nodeIDs[node.identity] = viewNodeID
        census.liveNodeIDs.insert(viewNodeID)
      }
      census.transactions[node.identity] = effective
      let childScopeOuterTransaction =
        node.transactionSnapshot.scopeRole == .scopeRoot ? effective : scopeOuterTransaction
      for child in node.children {
        visit(
          child,
          parentIdentity: node.identity,
          transaction: effective,
          scopeOuterTransaction: childScopeOuterTransaction)
      }
    }
    visit(
      root, parentIdentity: nil, transaction: transactionPlan.base, scopeOuterTransaction: nil)
    return census
  }

  /// An inserted identity whose insertion plays a transition.
  private struct QualifiedInsertion {
    var identity: Identity
    var viewNodeID: ViewNodeID
    var transition: AnyTransition
    /// The transaction the insertion animates under.
    var transaction: TransactionSnapshot
  }

  /// Decides whether `identity`, which is new in the tree of `census`, is an
  /// insertion that plays a transition, and which transition.
  ///
  /// This is the one place that decides it. The injection stage calls it for
  /// every inserted identity. The frame head calls it on the frame that
  /// inserts a transition body with an `Animatable` view or modifier in it,
  /// with a census of the tree and a copy of the registration maps brought
  /// to the state the injection stage will see them in.
  private func qualifiedInsertion(
    of identity: Identity,
    among insertedIdentities: Set<Identity>,
    in census: InsertionCensus,
    registry: TransitionRegistry,
    transactionPlan: FrameAnimationTransactionPlan
  ) -> QualifiedInsertion? {
    // Structural first-appearance guard: if the parent identity is
    // also freshly inserted, this view appeared as part of a bulk
    // mount, not a conditional toggle.
    if let parent = census.parents[identity],
      insertedIdentities.contains(parent)
    {
      return nil
    }
    guard let viewNodeID = census.nodeIDs[identity] else { return nil }
    var authoredTransition = registry.byNodeID[viewNodeID]
    if authoredTransition == nil,
      var wrapped = AnimationTreeQueries.findResolvedSubtree(in: census.root, identity: identity)
    {
      // Layout wrappers can own the presence boundary while the authored
      // transition is registered on their single content child. Carry that
      // child's choice (including identity) to the whole wrapped unit,
      // matching the removal path's wrapper capture.
      while wrapped.children.count == 1, authoredTransition == nil {
        wrapped = wrapped.children[0]
        if let wrappedNodeID = wrapped.viewNodeID {
          authoredTransition = registry.byNodeID[wrappedNodeID]
        }
      }
    }
    if authoredTransition == nil {
      guard previousTreeRoot != nil, census.parents[identity] != nil else { return nil }
    }
    let transition = authoredTransition ?? .opacity
    // Reparent suppression: a newly-inserted Identity whose ViewNodeID was
    // live last frame AND carried a transition registration last frame is a
    // transition-marked node that changed parents (same ViewNodeID, new
    // Identity), not a conditional first-appearance. SwiftUI fires
    // `.transition()` only when a view's conditional presence changes, so a
    // surviving-but-reparented node must not play an insertion transition.
    //
    // The previous-registration conjunct matters: branch flips inside a
    // structural slot ADOPT the slot's graph node for the new occupant
    // (that adoption is what keeps slot state stable through
    // conditionals), so a conditionally-inserted transition child can
    // surface with a ViewNodeID that was live last frame under the OTHER
    // branch's occupant. That occupant carried no transition registration —
    // a genuinely reparented transition node did.
    if previousLiveNodeIDs.contains(viewNodeID),
      registry.previousByNodeID[viewNodeID] != nil
    {
      return nil
    }
    return QualifiedInsertion(
      identity: identity,
      viewNodeID: viewNodeID,
      transition: transition,
      transaction: census.transactions[identity] ?? transactionPlan.transaction(for: identity)
    )
  }

  /// Decides the body channel of a qualified insertion: whether it has a
  /// curve, and whether it continues a removal the view came back from.
  ///
  /// `returnedRemovalIdentities` are the removals with a body that this
  /// frame's tree supersedes and that no insertion has taken yet.
  private func bodyInsertionDecision(
    for insertion: QualifiedInsertion,
    parents: [Identity: Identity],
    returnedRemovalIdentities: some Sequence<Identity>
  ) -> AnimationTransitionBodyInsertion.Decision {
    let plays = Self.transitionPlays(
      override: insertion.transition.insertionAnimation,
      request: insertion.transaction.animationRequest)
    let returned =
      plays
      ? returnedRemovalIdentities.first { removalIdentity in
        AnimationTransitionBodyInsertion.isInside(
          removalIdentity, subtreeOf: insertion.identity, parents: parents)
      } : nil
    return AnimationTransitionBodyInsertion.Decision(
      transaction: insertion.transaction, plays: plays, returnedRemovalIdentity: returned)
  }

  // MARK: - Animatable views and modifiers of an inserted transition body

  /// Whether the frame being prepared may be inserting a transition body
  /// that has an `Animatable` view or modifier in it: some site resolved for
  /// the first time this frame, and a transition with a body was registered
  /// this frame for an identity that had none on the frame before.
  ///
  /// The frame head asks after it has resolved, and runs
  /// ``prepareTransitionBodyInsertions(in:transactionPlan:reEvaluatedNodeIDs:isLiveNode:currentIdentity:)``
  /// when this is `true`. On every other frame the check is two emptiness
  /// tests.
  package var hasFreshTransitionBodySites: Bool {
    guard !valueSites.freshKeys.isEmpty, !pendingTransitionsByNodeID.isEmpty else {
      return false
    }
    var registeredLastFrame: Set<Identity>?
    for (viewNodeID, transition) in pendingTransitionsByNodeID
    where transition.bodyRegistration != nil {
      guard let identity = pendingTransitionIdentitiesByNodeID[viewNodeID] else { continue }
      let registered = registeredLastFrame ?? Set(previousTransitionIdentitiesByNodeID.values)
      registeredLastFrame = registered
      if !registered.contains(identity) {
        return true
      }
    }
    return false
  }

  /// The number of insertions the frame head has decided the body channel
  /// of and the injection stage has not read yet. Test hook.
  package var pendingTransitionBodyInsertionDecisionCount: Int {
    bodyInsertions.decisions.count
  }

  /// Starts the animations of the `Animatable` views and modifiers of the
  /// transition bodies this frame inserts, and returns the identities whose
  /// bodies have to run again before the frame is final.
  ///
  /// The frame head calls this after its resolve, when
  /// ``hasFreshTransitionBodySites`` holds, with the tree as resolved so
  /// far. Such a site has just resolved with the data of the identity phase:
  /// the injection stage, which qualifies insertions, runs after the tree is
  /// final. So the insertions are qualified here first, by the helper the
  /// injection stage uses, on a census of the tree and a copy of the
  /// registration maps as that stage will see them. For each body that
  /// plays:
  ///
  /// - the `.willAppear` phase is evaluated in the scratch scope with a sink
  ///   that records what the phase wrote for each site: its origin. Each
  ///   live site of the body starts an animation from that origin to the
  ///   data it resolved with;
  /// - a view that came back during its removal continues each site from
  ///   what the removal shows instead, with its velocity.
  ///
  /// The caller marks the returned identities dirty and evaluates them
  /// again, so the first frame presents the origins. The tree is then what
  /// the `.willAppear` body produces wherever a site drives it, and the
  /// slot channel finds nothing to animate there.
  ///
  /// What is decided here is recorded (``TransitionBodyInsertionRecords``).
  /// The injection stage reads it and does not decide again, and it takes
  /// the evaluated `.willAppear` phase for the slot channel.
  ///
  /// - Parameters:
  ///   - reEvaluatedNodeIDs: the nodes whose declarations ran this frame, as
  ///     for ``finishTransitionCollection(reEvaluatedNodeIDs:isLiveNode:)``.
  ///   - isLiveNode: whether a graph node is still in the graph, as for
  ///     ``finishTransitionCollection(reEvaluatedNodeIDs:isLiveNode:)``.
  ///   - currentIdentity: which identity a graph node is indexed at now, as
  ///     for ``beginValueSiteFrame(at:currentIdentity:)``.
  package func prepareTransitionBodyInsertions(
    in node: ResolvedNode,
    transactionPlan: FrameAnimationTransactionPlan,
    reEvaluatedNodeIDs: Set<ViewNodeID>? = nil,
    isLiveNode: ((ViewNodeID) -> Bool)? = nil,
    currentIdentity: (ViewNodeID) -> Identity? = { _ in nil }
  ) -> Set<Identity> {
    guard hasFreshTransitionBodySites, let timestamp = valueSites.frameInstant else {
      return []
    }
    let census = insertionCensus(of: node, transactionPlan: transactionPlan)
    // The registration maps as the injection stage will read them: this
    // frame's registrations merged in, and the result brought in line with
    // the tree. The controller's own maps stay as they are until the frame's
    // collection ends.
    var registry = transitions
    registry.mergePendingRegistrations(
      reEvaluatedNodeIDs: reEvaluatedNodeIDs, isLiveNode: isLiveNode)
    registry.reconcile(liveNodeIDs: census.liveNodeIDs, nodeIDByIdentity: census.nodeIDs)
    let insertedIdentities = census.identities.subtracting(previousIdentities)
    // The removals with a body that this frame's tree supersedes.
    var returnedRemovals: [Identity: ViewNodeID] = [:]
    for (viewNodeID, entry) in removingNodes
    where entry.body != nil && census.identities.contains(entry.identity) {
      returnedRemovals[entry.identity] = viewNodeID
    }

    // Decide every insertion first. What each one starts from must not
    // depend on the order the inserted identities are visited in. The
    // insertions are kept by body: a body with several roots has one for
    // each root that arrives, and which of them a site animates under is a
    // property of the site (``TransitionBodySiteHolders``).
    var bodies: [Identity: InsertedBody] = [:]
    for identity in insertedIdentities {
      guard
        let insertion = qualifiedInsertion(
          of: identity,
          among: insertedIdentities,
          in: census,
          registry: registry,
          transactionPlan: transactionPlan),
        let registration = insertion.transition.bodyRegistration
      else { continue }
      let decision = bodyInsertionDecision(
        for: insertion,
        parents: census.parents,
        returnedRemovalIdentities: returnedRemovals.keys)
      bodyInsertions.decisions[identity] = decision
      let returnedRemoval =
        decision.plays
        ? decision.returnedRemovalIdentity.flatMap { returnedRemovals.removeValue(forKey: $0) }
        : nil
      bodies[registration.identity, default: InsertedBody(registration: registration)]
        .roots.append(
          InsertedBody.Root(
            insertion: insertion, plays: decision.plays, returnedRemoval: returnedRemoval))
    }

    var owners: Set<Identity> = []
    // The views that came back during their removal continue from what the
    // removal shows on this frame. The slot channel of such an insertion
    // starts from the removal's working tree, so bring the tree of every
    // superseded removal to this frame's samples first, while the removals
    // still own the animations those samples are of.
    let returning = bodies.values.flatMap(\.roots).filter { $0.returnedRemoval != nil }
    if !returning.isEmpty {
      var evaluations: RemovalBodyEvaluations = [:]
      for viewNodeID in returning.compactMap(\.returnedRemoval) + returnedRemovals.values {
        guard let entry = removingNodes[viewNodeID], var body = entry.body else { continue }
        if refreshRemovalWorkingTree(&body, of: entry, at: timestamp, evaluations: &evaluations) {
          removingNodes[viewNodeID]?.body = body
        }
      }
      for root in returning {
        guard let removalNodeID = root.returnedRemoval else { continue }
        owners.formUnion(
          continueRemovalValueSites(
            ofRemoval: removalNodeID,
            under: root.insertion,
            in: census,
            at: timestamp,
            currentIdentity: currentIdentity))
      }
    }
    // The others start from the `.willAppear` phase. One evaluation serves
    // every root a body emitted.
    for body in bodies.values
    where body.roots.contains(where: { $0.plays && $0.returnedRemoval == nil }) {
      owners.formUnion(
        startInsertionValueSites(of: body, in: census, currentIdentity: currentIdentity))
    }
    return owners
  }

  /// The insertions of one transition body on the frame being prepared: one
  /// for each root of the body that arrives.
  private struct InsertedBody {
    struct Root {
      var insertion: QualifiedInsertion
      /// Whether the insertion has a curve.
      var plays: Bool
      /// The removal this insertion interrupts, when the view came back
      /// while that removal was in flight and the insertion plays.
      var returnedRemoval: ViewNodeID?
    }

    var registration: TransitionBodyRegistration
    var roots: [Root] = []
  }

  /// Evaluates the `.willAppear` phase of an inserted body and starts the
  /// animation of each of its live sites from the data that phase wrote for
  /// it. Returns the owners of the sites that started.
  ///
  /// Each site animates under the insertion of the root that holds it
  /// (``TransitionBodySiteHolders``): under that insertion's transaction
  /// when it plays, and not at all when it does not, whatever the body's
  /// other roots do.
  private func startInsertionValueSites(
    of body: InsertedBody,
    in census: InsertionCensus,
    currentIdentity: (ViewNodeID) -> Identity?
  ) -> Set<Identity> {
    let registration = body.registration
    let sink = TransitionBodyValueSink()
    let willAppear = registration.resolve(phase: .willAppear, valueSink: sink)
    // The slot channel of the injection stage takes this evaluation. Its
    // roots get the stamps of the modifiers outside the transition here,
    // where the registration and the tree are of one evaluation: the owners
    // of the sites run again before the injection stage sees the tree.
    bodyInsertions.willAppearRoots[registration.identity] =
      AnimationTransitionBodyInsertion.willAppearRoots(
        of: registration, evaluated: willAppear, root: census.root, parents: census.parents)
    // The insertion each root of the body arrives through: the one whose
    // inserted subtree the root is in. A root that was already there has
    // none. A body with one insertion whose root has another identity in
    // this phase than on screen arrives through that insertion.
    let holders = TransitionBodySiteHolders(roots: willAppear.roots)
    let insertionByRoot: [Int?] = willAppear.roots.map { root in
      body.roots.firstIndex { candidate in
        AnimationTransitionBodyInsertion.isInside(
          root.identity, subtreeOf: candidate.insertion.identity, parents: census.parents)
      } ?? (body.roots.count == 1 && !census.identities.contains(root.identity) ? 0 : nil)
    }
    var owners: Set<Identity> = []
    var animationBoxes: [Int: AnimationBox] = [:]
    for key in sink.sites {
      // Only a site that resolved for the first time this frame is a site of
      // the body being inserted. It resolved with the data of the identity
      // phase, which is its target. A site that already has an animation
      // took it over from a removal on this frame and continues from there.
      // One that a removal still owns belongs to a view that removal is
      // drawing: the live site keeps its own data. And a site the tree does
      // not anchor (neither its identity nor the node that evaluates it is
      // stamped there) loses its record when this frame is processed: it
      // gets its destination data at once, and the slots its body writes
      // animate in its place.
      guard valueSites.freshKeys.contains(key),
        activeAnimations[key] == nil,
        !removalOwnsValue(at: key),
        valueSites.isLive(key, identities: census.identities, liveNodeIDs: census.liveNodeIDs),
        let target = valueSites.targets[key],
        let origin = sink.phaseData[key],
        origin.wrapsSameType(as: target),
        origin != target,
        case .value(let ordinal) = key.scope,
        let holder = holders.holderIndex(ofSiteAt: key.identity),
        let rootIndex = insertionByRoot[holder]
      else { continue }
      let root = body.roots[rootIndex]
      // A root that came back during its removal continues the sites of
      // that removal and starts no other.
      guard root.plays, root.returnedRemoval == nil else { continue }
      // The curve of the root's transition, picked once and only when a
      // site has something to animate: a curve nothing uses would stay
      // registered.
      let box =
        animationBoxes[rootIndex]
        ?? transitionAnimationBox(
          override: root.insertion.transition.insertionAnimation,
          request: root.insertion.transaction.animationRequest,
          hasEffect: true)
      guard let box else { continue }
      animationBoxes[rootIndex] = box
      if beginValueAnimation(
        at: AnimatableValueSite(identity: key.identity, ordinal: ordinal),
        from: origin,
        to: target,
        animationBox: box,
        batchID: root.insertion.transaction.animationBatchID)
      {
        owners.insert(valueSites.ownerNodeIDs[key].flatMap(currentIdentity) ?? key.identity)
      }
    }
    return owners
  }

  /// Hands the value animations of a removal body to the live sites of the
  /// view that came back during that removal. Each such site continues from
  /// what the removal shows on this frame: the sample of the animation in
  /// flight, with its velocity, or the data of the `.didDisappear` phase
  /// when the removal's animation of the site has ended. Returns the owners
  /// of the sites that animate.
  ///
  /// A site of a body with several roots is owned by the removal of the
  /// root that holds it, so it is handed over under the insertion of that
  /// same root.
  private func continueRemovalValueSites(
    ofRemoval removalNodeID: ViewNodeID,
    under insertion: QualifiedInsertion,
    in census: InsertionCensus,
    at timestamp: MonotonicInstant,
    currentIdentity: (ViewNodeID) -> Identity?
  ) -> Set<Identity> {
    guard let sites = removingNodes[removalNodeID]?.body?.valueSites, !sites.isEmpty else {
      return []
    }
    var owners: Set<Identity> = []
    var animationBox: AnimationBox?
    for (key, removalTarget) in sites {
      // A live site resolved at this key on this frame: the view is back.
      guard valueSites.freshKeys.contains(key), let target = valueSites.targets[key] else {
        continue
      }
      let shown =
        (activeAnimations[key] != nil ? valueSites.samples[key] : nil) ?? removalTarget
      // From here on the animation at the key is the live site's.
      releaseRemovalOwnership(ofValueAt: key)
      // A site the tree does not anchor keeps no record past this frame
      // (see ``startInsertionValueSites``): it shows its own data.
      guard shown.wrapsSameType(as: target), shown != target,
        valueSites.isLive(key, identities: census.identities, liveNodeIDs: census.liveNodeIDs)
      else {
        endValueAnimation(at: key)
        continue
      }
      let box =
        animationBox
        ?? transitionAnimationBox(
          override: insertion.transition.insertionAnimation,
          request: insertion.transaction.animationRequest,
          hasEffect: true)
      guard let box else {
        endValueAnimation(at: key)
        continue
      }
      animationBox = box
      retargetValueAnimation(
        at: key,
        restingOrigin: shown,
        to: target,
        animationBox: box,
        batchID: insertion.transaction.animationBatchID,
        at: timestamp)
      if activeAnimations[key] != nil {
        owners.insert(valueSites.ownerNodeIDs[key].flatMap(currentIdentity) ?? key.identity)
      }
    }
    return owners
  }

  /// Records a delayed completion firing when the current resolve
  /// pass opens a batch that never gets retained.  Called at the end
  /// of ``processResolvedTree`` once every retain path has had a
  /// chance to bump ``batchRefCounts``.
  ///
  /// Only acts on the batch carried by the incoming transaction —
  /// that is, the batch *this* `withAnimation` scope just opened.
  /// Completions for other batches (e.g. registered but not yet
  /// brought through a resolve pass) are left alone so they can be
  /// handled by their own home frame.
  ///
  /// The drain delay matches the animation's nominal wall-clock
  /// duration, so callers that asked for a 500 ms animation still
  /// observe a 500 ms delay before their completion fires — even
  /// when the body changed nothing the controller can interpolate.
  /// An animation with ``RepeatBehavior/forever`` has no logical
  /// completion time and is skipped entirely, matching SwiftUI's
  /// behavior of never firing `withAnimation` completions for
  /// `.repeatForever` scopes.
  private func scheduleStrandedBatchDrains(
    transaction: TransactionSnapshot,
    timestamp: MonotonicInstant
  ) {
    let decision = AnimationCompletionScheduling.strandedBatchDecision(
      for: transaction,
      timestamp: timestamp,
      registeredAnimations: registeredAnimations,
      batchRefCounts: batchRefCounts,
      completions: completions,
      pendingEmptyBatchCompletions: pendingEmptyBatchCompletions
    )

    switch decision {
    case .ignore:
      return
    case .schedule(let batchID, let deadline):
      pendingEmptyBatchCompletions[batchID] = deadline
    case .dropCompletion(let batchID):
      _ = takeCompletions(for: batchID)
    }
  }

  private func enqueueInsertionAnimation(
    identity: Identity,
    viewNodeID: ViewNodeID,
    transition: AnyTransition,
    snapshot: AnimatableSnapshot,
    reinsertionOpacity: Double? = nil,
    bodyChanges: [AnimationTransitionBodyInsertion.SlotChange] = [],
    transaction: TransactionSnapshot,
    timestamp: MonotonicInstant
  ) {
    let modifiers = transition.insertionModifiers()
    guard
      let box = transitionAnimationBox(
        override: transition.insertionAnimation,
        request: transaction.animationRequest,
        // A body that changes a slot between its phases is an effect to
        // play. A body with nothing to interpolate is not: it leaves no curve
        // in the registration ledger.
        hasEffect: modifiers != .identity || !bodyChanges.isEmpty
      )
    else {
      // No animation intent — snap to identity immediately.
      return
    }
    // The animations retain the surrounding transaction's batch whichever
    // curve they play, so its completion waits for the transition.
    let batchID = transaction.animationBatchID
    // Enqueue an animation for each modifier effect the transition
    // declares.  From values are derived from the modifiers (offset
    // shift, reduced opacity); to values are identity.  If an animation
    // for the same (identity, property) is already mid-flight — e.g.
    // an interrupted removal — sample its currently displayed value
    // and use that as the new `from`, so the insertion starts from
    // whatever is on screen instead of snapping back to the declared
    // `willAppear` value.
    if let startOpacity = modifiers.opacity {
      let target = snapshot.opacity ?? 1.0
      let key = AnimationKey(identity: identity, slot: .opacity)
      let effectiveFrom: AnyAnimatable =
        sampleCurrentValue(for: key, at: timestamp)
        ?? reinsertionOpacity.map(AnyAnimatable.init)
        ?? AnyAnimatable(startOpacity)
      if let existing = activeAnimations[key] {
        releaseBatch(existing.batchID, logicalAlreadyReleased: existing.isLogicallyReleased)
      }
      retainBatch(batchID)
      activeAnimations[key] = ActiveAnimation(
        kind: .property(
          from: effectiveFrom,
          to: AnyAnimatable(target)
        ),
        animationBox: box,
        ownerViewNodeID: viewNodeID,
        resolvedIdentity: identity,
        startTime: timestamp,
        batchID: batchID
      )
    }
    // Insertion offsets route through a placed-level scope rather
    // than the property path, because applyValue can't translate
    // intrinsic-layout leaves like Text (LayoutEngine's .offset
    // variant requires `resolved.children.first`).  The placed-level
    // path walks the post-layout tree and translates matching
    // bounds directly.
    if modifiers.hasOffsetEffect {
      var offsetModifiers = modifiers
      offsetModifiers.opacity = nil
      offsetModifiers.scale = nil
      let offsetKey = AnimationKey(identity: identity, scope: .insertionOffset)
      if let existing = activeAnimations[offsetKey] {
        releaseBatch(existing.batchID, logicalAlreadyReleased: existing.isLogicallyReleased)
      }
      retainBatch(batchID)
      activeAnimations[offsetKey] = ActiveAnimation(
        kind: .insertionOffset(from: offsetModifiers),
        animationBox: box,
        startTime: timestamp,
        batchID: batchID
      )
    }
    // Like offsets, transition scale is a post-layout visual transform: it
    // changes the rendered bounds around an anchor without participating in
    // measurement or moving siblings.
    if let scale = modifiers.scale {
      let scaleKey = AnimationKey(identity: identity, scope: .insertionScale)
      if let existing = activeAnimations[scaleKey] {
        releaseBatch(existing.batchID, logicalAlreadyReleased: existing.isLogicallyReleased)
      }
      retainBatch(batchID)
      activeAnimations[scaleKey] = ActiveAnimation(
        kind: .insertionScale(from: scale),
        animationBox: box,
        startTime: timestamp,
        batchID: batchID
      )
    }
    // The body channel. Each node the `.willAppear` body shares with the
    // live tree animates the slots that differ, from the body's values to
    // the live ones, as ordinary property animations: keyed by identity and
    // slot, retaining the batch, and retargeted from the displayed value
    // when one is already in flight at the key. The first sample, on this
    // frame, is the `.willAppear` value.
    for change in bodyChanges {
      var previous = change.previous
      var current = change.current
      if modifiers.opacity != nil, change.identity == identity {
        // The effect channel owns the opacity of the inserted view itself,
        // which it starts at the declared value (zero for every built-in).
        // Opacities multiply, so that start is also the product's.
        previous[.opacity] = nil
        current[.opacity] = nil
      }
      diffAndEnqueue(
        identity: change.identity,
        viewNodeID: change.viewNodeID,
        previous: previous,
        current: current,
        request: .animate(box),
        batchID: batchID,
        tracksVelocity: false,
        timestamp: timestamp
      )
    }
  }

  /// A view with a transition that left the tree on the frame being
  /// processed.
  private struct RemovalCandidate {
    enum Channel { case departedNode, adoptedSlot }

    var nodeID: ViewNodeID
    /// The identity the transition is registered for.
    var identity: Identity
    var transition: AnyTransition
    var channel: Channel
  }

  /// The candidates that plan a removal, in the order they are planned.
  ///
  /// One removal is planned for each departing subtree. A view with a
  /// transition that lies inside another departing view with a transition
  /// did not leave by itself: its presence inside that view did not change,
  /// and it goes with it. It plans no removal, as a view that appears
  /// together with its container plays no insertion. Planned, it would draw
  /// the same frozen subtree a second time and end the animations the outer
  /// removal had just started for its body (STUI-1576).
  ///
  /// The order is that of the identities, so a frame plans its removals in
  /// the same order in every run. The candidates arrive in the order of a
  /// set of node ids, which differs from one tree to the next.
  private func departingTransitionRoots(
    of candidates: [RemovalCandidate]
  ) -> [RemovalCandidate] {
    guard candidates.count > 1 else { return candidates }
    let departing = Set(candidates.map(\.identity))
    return
      candidates
      .filter { candidate in
        var ancestor = previousParentByIdentity[candidate.identity]
        while let current = ancestor {
          if departing.contains(current) { return false }
          ancestor = previousParentByIdentity[current]
        }
        return true
      }
      .sorted { lhs, rhs in
        // The departed-node channel first, as before; then by identity.
        if lhs.channel != rhs.channel { return lhs.channel == .departedNode }
        return lhs.identity < rhs.identity
      }
  }

  /// Plans one removal overlay: resolves the injection point, captures the
  /// departing subtree and its frozen placed bounds, supersedes in-flight
  /// animations on the injected identities, and records the `RemovalEntry`.
  /// Shared by both removal-detection channels — departed ViewNodeID
  /// occurrences and adopted-slot conditional removals (a registered identity
  /// leaving the identity set while its slot node survives).
  ///
  /// A transition with a registered body also plays that body
  /// (``AnimationTransitionBodyRemoval``): the entry carries the
  /// `.didDisappear` body, and the views of that body which were on screen
  /// animate from the value they show. Those animations go through the slot
  /// path, so one still in flight from the insertion is retargeted from its
  /// sample with its velocity instead of being superseded. The body plays
  /// only when the removal has a curve and a frozen placed snapshot to draw
  /// it in; otherwise the removal is what its effects alone make it.
  private func planRemovalOverlay(
    removedNodeID: ViewNodeID,
    identity: Identity,
    transition: AnyTransition,
    previousRoot: ResolvedNode,
    newIdentities: Set<Identity>,
    newLiveNodeIDs: Set<ViewNodeID>,
    matchedDestinationsByKey: [MatchedGeometryKey: Identity],
    transactionPlan: FrameAnimationTransactionPlan,
    timestamp: MonotonicInstant,
    plannedSites: inout [AnimationKey: AnimationTransitionBodyRemoval.LiveSite]
  ) {
    let effects = transition.removalModifiers()
    let registration = transition.bodyRegistration
    guard effects != .identity || registration != nil else { return }
    // Whether a live view still resolves the site at `key` in the new tree.
    let siteIsLive = { [valueSites] (key: AnimationKey) -> Bool in
      valueSites.isLive(key, identities: newIdentities, liveNodeIDs: newLiveNodeIDs)
    }
    // A body whose removal does not play leaves at once. Its insertion may
    // still be in flight. End that here, as the removal of an effect ends an
    // insertion below: the completions the insertion retained fire now. Left
    // to the departed-identity prune they would be dropped, which is right
    // only for a view that had no transition.
    func snapBody() {
      if registration != nil {
        supersedeAnimations(
          inDepartingSubtreeAt: identity, previousRoot: previousRoot, siteIsLive: siteIsLive)
      }
    }
    // A transition whose own animation is `nil` snaps: it plans no overlay,
    // exactly as an identity transition plans none.
    if transition.removalAnimation == .explicit(nil) {
      snapBody()
      return
    }
    let removalTransaction = transactionForDepartedIdentity(
      identity,
      transactionPlan: transactionPlan
    )
    // Whether the removal has a curve. A body with none snaps, as an identity
    // transition does.
    let plays = Self.transitionPlays(
      override: transition.removalAnimation,
      request: removalTransaction.animationRequest)
    if effects == .identity, !plays {
      snapBody()
      return
    }
    // Resolve the injection point: the deepest disappearing ancestor (the
    // subtree to inject) and the first surviving ancestor it attaches to.
    // See `AnimationTransitionRemovalPlanning` for the walk-up rules.
    let injectionPoint = AnimationTransitionRemovalPlanning.injectionPoint(
      for: identity,
      previousRoot: previousRoot,
      previousParentByIdentity: previousParentByIdentity,
      newIdentities: newIdentities
    )
    let injectionTarget = injectionPoint.target

    // injectionParent must be a surviving identity in the new tree.
    // If the walk-up stopped at a multi-child container, it may still be a
    // removed identity — skip.
    guard let injectionParent = injectionPoint.parent,
      newIdentities.contains(injectionParent),
      let subtree = AnimationTreeQueries.findResolvedSubtree(
        in: previousRoot,
        identity: injectionTarget
      )
    else {
      if effects == .identity { snapBody() }
      return
    }

    // A departing matched-geometry instance whose key swapped to a live
    // counterpart this frame keeps its exit transition: the overlay travels
    // to the counterpart's rect while the transition plays (sampled by
    // `PlacedAnimationOverlaySampling`), so the pair coincides and
    // cross-fades. The matched node may sit below the registered identity,
    // so the injected subtree is searched rather than the registered node.
    let matchedTravel = AnimationTreeQueries.firstMatchedGeometry(in: subtree) { config in
      matchedDestinationsByKey[config.key] != nil
    }.flatMap { found in
      matchedDestinationsByKey[found.config.key].map { destination in
        MatchedRemovalTravel(
          matchedIdentity: found.identity,
          destinationIdentity: destination,
          properties: found.config.properties,
          anchor: found.config.anchor
        )
      }
    }

    // If a previous placed tree is cached, look up the frozen
    // placed subtree for the same identity so the overlay can be
    // injected post-layout (draw-only, no layout-shift).
    // The baseline is un-adopted; a departing co-present non-source was drawn
    // at its source's rect, so its frozen clone takes last frame's adoption
    // offset and the exit overlay starts where the node was drawn.
    let placedSnapshot: PlacedNode?
    if let previousPlacedRoot,
      let frozen = AnimationTreeQueries.findPlacedSubtree(
        in: previousPlacedRoot,
        identity: injectionTarget
      )
    {
      placedSnapshot =
        previousAdoptionOffsets.isEmpty
        ? frozen
        : translatePlacedNodesByIdentity(
          tree: frozen, offsets: previousAdoptionOffsets, offsetsAreAbsolute: true)
    } else {
      placedSnapshot = nil
    }

    // The body channel. It needs a curve and the frozen placed snapshot: the
    // resolved-level fallback lays the overlay out with the live tree and
    // cannot host a body.
    var bodyPlan: AnimationTransitionBodyRemoval.Plan?
    if let registration, plays, let placedSnapshot {
      switch AnimationTransitionBodyRemoval.plan(
        of: registration,
        rootIdentity: identity,
        frozenResolved: subtree,
        frozenPlaced: placedSnapshot,
        previousSnapshots: previousSnapshots,
        hasEffectChannel: effects != .identity,
        effectOwnsRootOpacity: effects.opacity != nil,
        liveSites: liveSiteData(planned: plannedSites, isLive: siteIsLive),
        timestamp: timestamp
      ) {
      case .plays(let plan):
        bodyPlan = plan
        plannedSites.merge(plan.liveSites) { first, _ in first }
        for issue in plan.issues {
          // The tail of this frame drains the queue into its issue channel.
          ImperativeRuntimeIssueQueue.record(issue)
        }
      case .unavailable(let issue):
        ImperativeRuntimeIssueQueue.record(issue)
      }
    }
    if effects == .identity, bodyPlan == nil {
      // Nothing to play: no effect, and no body that can be drawn.
      snapBody()
      return
    }
    let bodyIdentities = bodyPlan?.state.ownedIdentities ?? []
    let styledContentIdentities = Set((bodyPlan?.state.contentStyles ?? [:]).keys)
    let bodyValueSites = bodyPlan?.state.valueSites ?? [:]
    // Whether the body channel keeps the animation at `key`. On a view of
    // the body that is every slot but one: the opacity of the departing view
    // itself belongs to the effect channel when the effects fade the view.
    // On a view of the frozen content it is the two inherited styles the body
    // can set; the content's own animations end here as they always did. The
    // data of an `Animatable` view or modifier of the body is kept by site:
    // the removal goes on evaluating the body with it.
    func bodyKeeps(_ key: AnimationKey) -> Bool {
      if key.isValue {
        return bodyValueSites[key] != nil
      }
      guard case .property(let slot) = key.scope, bodyIdentities.contains(key.identity) else {
        return false
      }
      if styledContentIdentities.contains(key.identity) {
        return slot == .foregroundShapeStyle || slot == .tintShapeStyle
      }
      return !(slot == .opacity && key.identity == identity && effects.opacity != nil)
    }

    // Before clearing the injected subtree's active animations, peek
    // at any mid-flight opacity animation on the transition's
    // registered identity (or anywhere in the subtree) so the
    // removal can start from the displayed value instead of
    // snapping back to 1.0.  Must run before the filter below. An opacity
    // the body channel keeps is not an effect to carry: it continues on its
    // own key.
    let departing = DepartingViews(subtree)
    let injectedIdentities = departing.identities
    var initialOpacity: Double = 1.0
    let keyOnTarget = AnimationKey(identity: identity, slot: .opacity)
    if !bodyKeeps(keyOnTarget), let existing = activeAnimations[keyOnTarget],
      let sampled = sample(existing, at: timestamp),
      let value = sampled.unwrap(as: Double.self)
    {
      initialOpacity = value
    } else {
      for sid in injectedIdentities {
        let k = AnimationKey(identity: sid, slot: .opacity)
        if !bodyKeeps(k), let existing = activeAnimations[k],
          let sampled = sample(existing, at: timestamp),
          let value = sampled.unwrap(as: Double.self)
        {
          initialOpacity = value
          break
        }
      }
    }

    var initialScale: TransitionScaleEffect?
    let scaleKey = AnimationKey(identity: identity, scope: .insertionScale)
    if let entry = activeAnimations[scaleKey],
      case .insertionScale(let from) = entry.kind,
      let animation = registeredAnimations[entry.animationBox]
    {
      var state = entry.customState
      if let progress = animation.evaluate(
        elapsed: entry.startTime.duration(to: timestamp), state: &state)
      {
        initialScale = TransitionScaleEffect(
          scale: from.scale + (1.0 - from.scale) * progress, anchor: from.anchor)
      }
    }

    // Supersede any in-flight animations on identities that are being
    // re-injected from the removed subtree.  The unified activeAnimations
    // map means this filter is scope-agnostic: property animations,
    // insertion-offset animations, insertion-scale animations, and
    // matched-geometry animations are all swept together. Any withAnimation
    // completion closures ref-
    // counted by these entries fire immediately here (via releaseBatch
    // below), rather than at each animation's natural curve completion —
    // matching SwiftUI's interrupt semantics where a removal supersedes
    // any in-progress insertion or matched-geometry transition.
    //
    // Pre-Phase-4, insertion-offset and matched-geometry animations
    // lived in separate side-channel maps and were not touched by this
    // filter, so they would tick to natural completion (or be purged
    // later by the placed-overlay loop's "registration missing" path)
    // even after the exit animation started.
    //
    // The animations the body channel keeps are spared: the removal
    // retargets them below.
    let completionBatchID = removalTransaction.animationBatchID.flatMap { batchID in
      completions[batchID] == nil ? nil : batchID
    }
    retainBatch(completionBatchID)

    let supersededEntries = activeAnimations.filter {
      animation(at: $0.key, belongsTo: departing, siteIsLive: siteIsLive) && !bodyKeeps($0.key)
    }
    if !supersededEntries.isEmpty {
      activeAnimations = activeAnimations.filter { supersededEntries[$0.key] == nil }
    }
    for (key, entry) in supersededEntries {
      if key.isValue {
        valueSites.samples.removeValue(forKey: key)
      }
      releaseBatch(entry.batchID, logicalAlreadyReleased: entry.isLogicallyReleased)
    }

    let animationBox = transitionAnimationBox(
      override: transition.removalAnimation,
      request: removalTransaction.animationRequest,
      hasEffect: true
    )
    var bodyState: RemovalBodyState?
    if let bodyPlan, let animationBox {
      var state = bodyPlan.state
      // Each view of the body that was on screen animates the slots that
      // differ, from the value it shows to its value in the `.didDisappear`
      // phase, as ordinary property animations under the removal's curve. An
      // animation already in flight at a key is retargeted from its sample,
      // with the velocity projection. One whose target does not change is
      // left to finish.
      for change in bodyPlan.changes {
        diffAndEnqueue(
          identity: change.identity,
          viewNodeID: nil,
          previous: change.previous,
          current: change.current,
          request: .animate(animationBox),
          batchID: removalTransaction.animationBatchID,
          tracksVelocity: false,
          timestamp: timestamp
        )
      }
      // Each `Animatable` view or modifier of the body animates its data
      // from what the live site presents on this frame to the data the
      // `.didDisappear` phase gives it. An animation in flight at the site
      // is continued from its sample with its velocity, and one that is
      // already going to that data is left to finish. From here on the
      // site belongs to the removal: no live view resolves at it, so its
      // record goes, and the removal evaluates its body with the samples.
      for (key, target) in state.valueSites {
        if let origin = bodyPlan.liveSites[key]?.presented, origin.wrapsSameType(as: target) {
          let inFlightTarget = activeAnimations[key]?.kind.endpoints?.to
          if inFlightTarget.map({ $0 != target }) ?? (origin != target) {
            retargetValueAnimation(
              at: key,
              restingOrigin: origin,
              to: target,
              animationBox: animationBox,
              batchID: removalTransaction.animationBatchID,
              at: timestamp)
          }
        } else {
          // Nothing to animate from: the site is in this phase only, or a
          // view of another type was there.
          endValueAnimation(at: key)
        }
        valueSites.targets.removeValue(forKey: key)
        valueSites.ownerNodeIDs.removeValue(forKey: key)
        slotVelocitySamplers.removeValue(forKey: key)
      }
      // The nodes those animations were applied to are gone. From here on
      // their samples go to the removal's working tree, by identity, and the
      // samples of its sites to the evaluation of its body. The ones that
      // start now are the removal's own, and it lasts as long as they do.
      for key in Array(activeAnimations.keys) where bodyKeeps(key) {
        activeAnimations[key]?.ownerViewNodeID = nil
        activeAnimations[key]?.resolvedIdentity = nil
        if activeAnimations[key]?.startTime == timestamp {
          state.drivingKeys.insert(key)
        }
      }
      bodyState = state
    }

    removingNodes[removedNodeID] = RemovalEntry(
      identity: identity,
      snapshot: subtree,
      parentIdentity: injectionParent,
      childIndex: previousChildIndexByIdentity[injectionTarget] ?? 0,
      transition: transition,
      animationBox: animationBox,
      startTime: timestamp,
      startOpacity: initialOpacity,
      startScale: initialScale,
      completionBatchID: completionBatchID,
      placedSnapshot: placedSnapshot,
      matchedTravel: matchedTravel,
      body: bodyState
    )
  }

  /// The views of a subtree that left the tree, as the animation maps name
  /// them: by identity, and by the graph node that evaluated them.
  private struct DepartingViews {
    var identities: Set<Identity> = []
    var nodeIDs: Set<ViewNodeID> = []

    init(_ subtree: ResolvedNode) {
      var pending = [subtree]
      while let node = pending.popLast() {
        identities.insert(node.identity)
        if let viewNodeID = node.viewNodeID {
          nodeIDs.insert(viewNodeID)
        }
        pending.append(contentsOf: node.children)
      }
    }
  }

  /// Whether the animation at `key` is an animation of a view of
  /// `departing`.
  ///
  /// Every animation is keyed at the identity of its view, and that covers
  /// all but one case. The data of an `Animatable` view or modifier animates
  /// at the identity the view resolves at, which need not be an identity of
  /// the tree (see ``ValueSiteState/ownerNodeIDs``). Such an animation
  /// belongs to the departing views when the node that evaluated its site is
  /// one of theirs and no live view resolves the site any more. The second
  /// condition matters where a node outlives its view: a slot keeps its node
  /// for the next occupant, whose sites are that node's too.
  private func animation(
    at key: AnimationKey,
    belongsTo departing: DepartingViews,
    siteIsLive: (AnimationKey) -> Bool
  ) -> Bool {
    if departing.identities.contains(key.identity) {
      return true
    }
    guard key.isValue, let ownerNodeID = valueSites.ownerNodeIDs[key],
      departing.nodeIDs.contains(ownerNodeID)
    else { return false }
    return !siteIsLive(key)
  }

  /// Ends every animation in flight on the subtree that departed at
  /// `identity`, releasing the batches they retained so their completions
  /// fire.
  private func supersedeAnimations(
    inDepartingSubtreeAt identity: Identity,
    previousRoot: ResolvedNode,
    siteIsLive: (AnimationKey) -> Bool
  ) {
    guard !activeAnimations.isEmpty,
      let subtree = AnimationTreeQueries.findResolvedSubtree(in: previousRoot, identity: identity)
    else { return }
    let departing = DepartingViews(subtree)
    let superseded = activeAnimations.filter {
      animation(at: $0.key, belongsTo: departing, siteIsLive: siteIsLive)
    }
    guard !superseded.isEmpty else { return }
    activeAnimations = activeAnimations.filter { superseded[$0.key] == nil }
    for (key, entry) in superseded {
      if key.isValue {
        valueSites.samples.removeValue(forKey: key)
      }
      releaseBatch(entry.batchID, logicalAlreadyReleased: entry.isLogicallyReleased)
    }
  }

  /// Picks the curve one direction of a transition plays, or `nil` when it
  /// snaps.
  ///
  /// A transition with no animation of its own takes the transaction's curve,
  /// as before. A transition's own animation replaces the transaction's and
  /// also plays when the transaction carries none; its `nil` snaps. A
  /// disabled request (`withAnimation(nil)`, reduced motion, stable output)
  /// snaps whatever the transition carries. The override's curve is
  /// registered here because no `withAnimation` scope delivered it, and only
  /// when the direction has an effect to play it: a curve nothing uses would
  /// stay in the registration ledger, which is pruned as its users complete.
  private func transitionAnimationBox(
    override: TransitionAnimationOverride,
    request: AnimationRequest,
    hasEffect: Bool
  ) -> AnimationBox? {
    switch override {
    case .inherit:
      return request.animationBoxIfAny
    case .explicit(nil):
      return nil
    case .explicit(let animation?):
      if request == .disabled || !hasEffect { return nil }
      return register(animation)
    }
  }

  /// Whether ``transitionAnimationBox(override:request:hasEffect:)`` would
  /// pick a curve for a direction that has an effect. It registers nothing,
  /// so the body channel can ask before it evaluates a phase.
  private static func transitionPlays(
    override: TransitionAnimationOverride,
    request: AnimationRequest
  ) -> Bool {
    switch override {
    case .inherit:
      request.animationBoxIfAny != nil
    case .explicit(nil):
      false
    case .explicit(.some):
      request != .disabled
    }
  }

  /// Selects animation intent for a node that no longer exists in the current
  /// resolved tree. Authored `.id` can rebase a child's public identity outside
  /// its structural parent's identity path, so identity ancestry alone cannot
  /// associate that departed child with the segment that caused its removal.
  /// Walk the retained structural parent chain until a claimed identity is
  /// found; live insertion/property paths instead carry their selected
  /// transaction directly on the newly resolved node.
  private func transactionForDepartedIdentity(
    _ identity: Identity,
    transactionPlan: FrameAnimationTransactionPlan
  ) -> TransactionSnapshot {
    var candidate: Identity? = identity
    while let current = candidate {
      if transactionPlan.segment(for: current) != nil {
        return transactionPlan.transaction(for: current)
      }
      candidate = previousParentByIdentity[current]
    }
    return transactionPlan.base
  }

  /// Returns the currently interpolated value of the animation at
  /// `key` if one is in flight, or nil if the slot is empty.  Used by
  /// the insertion path to retarget from the displayed value when a
  /// mid-flight animation gets interrupted by an opposite toggle.
  private func sampleCurrentValue(
    for key: AnimationKey,
    at timestamp: MonotonicInstant
  ) -> AnyAnimatable? {
    guard let existing = activeAnimations[key] else { return nil }
    return sample(existing, at: timestamp)
  }

  private func processNode(
    _ node: ResolvedNode,
    parentIdentity: Identity?,
    childIndex: Int,
    transaction: TransactionSnapshot,
    scopeOuterTransaction: TransactionSnapshot?,
    transactionPlan: FrameAnimationTransactionPlan,
    timestamp: MonotonicInstant,
    snapshotAccumulator: inout [Identity: AnimatableSnapshot],
    parentAccumulator: inout [Identity: Identity],
    childIndexAccumulator: inout [Identity: Int],
    matchedKeyAccumulator: inout [Identity: MatchedGeometryConfig],
    nodeIDAccumulator: inout [Identity: ViewNodeID],
    transactionAccumulator: inout [Identity: TransactionSnapshot],
    reducedMotionAccumulator: inout Set<Identity>,
    liveNodeIDAccumulator: inout Set<ViewNodeID>,
    activeKeysByOwnerNodeID: [ViewNodeID: [AnimationKey]]
  ) {
    lastResolvedTreeProcessedNodeCount += 1
    if let viewNodeID = node.viewNodeID,
      let activeKeys = activeKeysByOwnerNodeID[viewNodeID]
    {
      for key in activeKeys {
        activeAnimations[key]?.resolvedIdentity = node.identity
      }
    }
    var snapshot = AnimatableSnapshot.extract(from: node)
    let previous = previousSnapshots[node.identity]

    // The transactions this node resolves under
    // (``nodeTransactions(of:inherited:scopeOuterTransaction:transactionPlan:)``).
    let resolvedTransactions = nodeTransactions(
      of: node,
      inherited: transaction,
      scopeOuterTransaction: scopeOuterTransaction,
      transactionPlan: transactionPlan)
    let frameSegment = resolvedTransactions.frameSegment
    let transaction = resolvedTransactions.inherited
    let effectiveTransaction = resolvedTransactions.effective
    let reducesMotion = resolvedTransactions.reducesMotion
    if reducesMotion {
      reducedMotionAccumulator.insert(node.identity)
    }
    var styleIntents: [AnimatableSlot: ScopedStyleAnimationIntent] = [:]
    if !reducesMotion, !effectiveTransaction.customValues.isEmpty {
      for (slot, key) in [
        (
          AnimatableSlot.foregroundShapeStyle,
          ObjectIdentifier(ScopedForegroundStyleAnimationKey.self)
        ),
        (AnimatableSlot.tintShapeStyle, ObjectIdentifier(ScopedTintStyleAnimationKey.self)),
      ] {
        guard
          let intent = effectiveTransaction.customValues[key]?.unwrap(
            as: ScopedStyleAnimationIntent.self), intent.isScoped
        else { continue }
        if node.drawPayload == .none {
          // Scoped environment writes pass through nonpainting wrappers.
          // Exclude their slots as well as their intents: falling back to the
          // node's transaction would still animate a wrapper inside the scope.
          snapshot[slot] = nil
        } else if slot != .foregroundShapeStyle
          || node.drawMetadata.baseStyle.foregroundStyle == nil
        {
          styleIntents[slot] = intent
        }
      }
    }
    // `clipShape` and `opacity` merge into the content's node; when a
    // modifier's scope differs from the node's own it recorded it (STUI-1319,
    // STUI-1325), so that slot animates under the transaction where the
    // modifier was applied.
    if !node.transactionSnapshot.customValues.isEmpty {
      for (scopedSlot, key) in Self.drawMetadataScopeKeys {
        guard
          let scope = node.transactionSnapshot.customValues[key]?.unwrap(
            as: ScopedStyleAnimationIntent.self)
        else { continue }
        // The slots the scope governs on this node: the one it names and,
        // for a clip, the data of each mask of an `Animatable` shape, which
        // is a clip as well.
        var slots: [AnimatableSlot] = []
        if snapshot[scopedSlot] != nil || previous?[scopedSlot] != nil {
          slots.append(scopedSlot)
        }
        if scopedSlot == .clipShapePaths {
          var maskSlots = Set(snapshot.values.keys.filter(\.isClipShapeData))
          if let previous {
            maskSlots.formUnion(previous.values.keys.filter(\.isClipShapeData))
          }
          slots.append(contentsOf: maskSlots)
        }
        guard !slots.isEmpty else { continue }
        var scopeSnapshot = node.transactionSnapshot
        scopeSnapshot.animationRequest = scope.request
        scopeSnapshot.animationBatchID = scope.batchID
        let scopeTransaction = Self.effectiveTransaction(
          of: scopeSnapshot, frameSegment: frameSegment, inherited: transaction)
        // A scope that inherits nothing must not fall back to the node's own
        // request; `.disabled` snaps exactly as `.inherit` does.
        let request =
          reducesMotion || scopeTransaction.animationRequest == .inherit
          ? AnimationRequest.disabled : scopeTransaction.animationRequest
        let intent = ScopedStyleAnimationIntent(
          isScoped: true, request: request, batchID: scopeTransaction.animationBatchID)
        for slot in slots {
          styleIntents[slot] = intent
        }
      }
    }
    if let previous {
      diffAndEnqueue(
        identity: node.identity,
        viewNodeID: node.viewNodeID,
        previous: previous,
        current: snapshot,
        request: effectiveTransaction.animationRequest,
        batchID: effectiveTransaction.animationBatchID,
        tracksVelocity: effectiveTransaction.tracksVelocity,
        styleIntents: styleIntents,
        timestamp: timestamp
      )
    }
    // First time we see an identity: no animation, just record the snapshot.

    snapshotAccumulator[node.identity] = snapshot
    if let parentIdentity {
      parentAccumulator[node.identity] = parentIdentity
    }
    childIndexAccumulator[node.identity] = childIndex
    if let config = node.matchedGeometry {
      matchedKeyAccumulator[node.identity] = config
    }
    if let viewNodeID = node.viewNodeID {
      nodeIDAccumulator[node.identity] = viewNodeID
      liveNodeIDAccumulator.insert(viewNodeID)
    }
    transactionAccumulator[node.identity] = effectiveTransaction

    let childScopeOuterTransaction =
      node.transactionSnapshot.scopeRole == .scopeRoot
      ? effectiveTransaction
      : scopeOuterTransaction
    for (index, child) in node.children.enumerated() {
      processNode(
        child,
        parentIdentity: node.identity,
        childIndex: index,
        transaction: effectiveTransaction,
        scopeOuterTransaction: childScopeOuterTransaction,
        transactionPlan: transactionPlan,
        timestamp: timestamp,
        snapshotAccumulator: &snapshotAccumulator,
        parentAccumulator: &parentAccumulator,
        childIndexAccumulator: &childIndexAccumulator,
        matchedKeyAccumulator: &matchedKeyAccumulator,
        nodeIDAccumulator: &nodeIDAccumulator,
        transactionAccumulator: &transactionAccumulator,
        reducedMotionAccumulator: &reducedMotionAccumulator,
        liveNodeIDAccumulator: &liveNodeIDAccumulator,
        activeKeysByOwnerNodeID: activeKeysByOwnerNodeID
      )
    }
  }

  /// The transactions one node of the frame's tree resolves under.
  private struct NodeTransactions {
    /// The frame-selected segment that covers the node, if any.
    var frameSegment: AnimationInvalidationSegment?
    /// What the node inherits: its parent's effective transaction, the
    /// transaction outside its scope, or the frame's base transaction.
    var inherited: TransactionSnapshot
    /// The node's own effective transaction. Disabled under reduced motion.
    var effective: TransactionSnapshot
    var reducesMotion: Bool
  }

  /// Determines the transactions of `node`, given what its parent passes
  /// down. The walk that diffs the tree and the walk that only takes its
  /// census (``insertionCensus(of:transactionPlan:)``) both call this, so a
  /// node has one effective transaction whoever asks.
  ///
  /// A resolved node normally already carries its frame-selected segment.
  /// Consulting the plan here also covers controller-direct inputs and
  /// departed/reused transaction snapshots.
  ///
  /// A scoped modifier's placeholder (`restoresOuter`) inherits from the
  /// nearest scope root's effective transaction — the transaction outside
  /// the scope — instead of from its scoped resolved parent.
  ///
  /// The owner of a value animation that ticked this frame is a third case.
  /// Its body ran for the tick, and an ancestor that was resolved on an
  /// earlier frame still carries that frame's request in its snapshot. The
  /// owner must not inherit it: every sample would then start a property
  /// animation on whatever the body produced, on top of the value
  /// animation. It takes what its own resolve had: its stamp, the segment
  /// that covers it, or the frame's base transaction.
  private func nodeTransactions(
    of node: ResolvedNode,
    inherited transaction: TransactionSnapshot,
    scopeOuterTransaction: TransactionSnapshot?,
    transactionPlan: FrameAnimationTransactionPlan
  ) -> NodeTransactions {
    let frameSegment = transactionPlan.segment(for: node.identity)
    let isTickedValueOwner =
      !valueSites.tickedOwners.isEmpty && valueSites.tickedOwners.contains(node.identity)
    let inherited =
      node.transactionSnapshot.scopeRole == .restoresOuter
      ? (scopeOuterTransaction ?? transaction)
      : isTickedValueOwner ? transactionPlan.base : transaction
    var effective = Self.effectiveTransaction(
      of: node.transactionSnapshot, frameSegment: frameSegment, inherited: inherited)
    let reducesMotion = node.environmentSnapshot.style.renderingReduceMotion
    if reducesMotion {
      effective.animationRequest = .disabled
    }
    return NodeTransactions(
      frameSegment: frameSegment,
      inherited: inherited,
      effective: effective,
      reducesMotion: reducesMotion
    )
  }

  /// The slots a merged draw-metadata modifier can scope to its own
  /// transaction, with the key it records that scope under.
  private static let drawMetadataScopeKeys: [(AnimatableSlot, ObjectIdentifier)] = [
    (.clipShapePaths, ObjectIdentifier(ClipShapeAnimationScopeKey.self)),
    (.opacity, ObjectIdentifier(OpacityAnimationScopeKey.self)),
  ]

  /// `snapshot` with an `.inherit` request resolved the way a node's is: from
  /// the frame-selected segment when one covers the node, else from the
  /// inherited (parent or scope-outer) transaction. Metadata fields
  /// (`isContinuous`, custom key values) inherit with the request; the
  /// snapshot's own resolve-stamped values win per key.
  private static func effectiveTransaction(
    of snapshot: TransactionSnapshot,
    frameSegment: AnimationInvalidationSegment?,
    inherited transaction: TransactionSnapshot
  ) -> TransactionSnapshot {
    var effective = snapshot
    if effective.animationRequest == .inherit {
      if let frameSegment {
        effective.animationRequest = frameSegment.animationRequest
        effective.animationBatchID = frameSegment.animationBatchID
        effective.isContinuous =
          effective.isContinuous || frameSegment.isContinuous
        effective.tracksVelocity =
          effective.tracksVelocity || frameSegment.tracksVelocity
        effective.customValues = frameSegment.customValues.merging(
          effective.customValues
        ) { _, node in node }
      } else {
        effective.animationRequest = transaction.animationRequest
        effective.animationBatchID = transaction.animationBatchID
        effective.isContinuous =
          effective.isContinuous || transaction.isContinuous
        effective.tracksVelocity =
          effective.tracksVelocity || transaction.tracksVelocity
        effective.customValues = transaction.customValues.merging(
          effective.customValues
        ) { _, node in node }
      }
    } else if effective.animationBatchID == nil {
      let isFrameSegmentBoundary =
        frameSegment.map { segment in
          segment.animationRequest == effective.animationRequest
            && segment.animationBatchID == nil
        } ?? false
      if !isFrameSegmentBoundary {
        effective.animationBatchID = transaction.animationBatchID
      }
    }
    return effective
  }

  private func diffAndEnqueue(
    identity: Identity,
    viewNodeID: ViewNodeID?,
    previous: AnimatableSnapshot,
    current: AnimatableSnapshot,
    request: AnimationRequest,
    batchID: AnimationBatchID?,
    tracksVelocity: Bool,
    styleIntents: [AnimatableSlot: ScopedStyleAnimationIntent] = [:],
    timestamp: MonotonicInstant
  ) {
    // Union of slot keys from both snapshots — a slot that appears
    // in only one snapshot is a "one side nil" change and snaps.
    var slots = Set(previous.values.keys)
    slots.formUnion(current.values.keys)

    for slot in slots {
      let intent = styleIntents[slot]
      enqueueSlotChangeIfNeeded(
        identity: identity,
        viewNodeID: viewNodeID,
        slot: slot,
        previous: previous[slot],
        current: current[slot],
        request: intent.map { $0.request == .inherit ? request : $0.request } ?? request,
        batchID: intent?.batchID ?? batchID,
        tracksVelocity: tracksVelocity,
        timestamp: timestamp
      )
    }
  }

  private func enqueueSlotChangeIfNeeded(
    identity: Identity,
    viewNodeID: ViewNodeID?,
    slot: AnimatableSlot,
    previous: AnyAnimatable?,
    current: AnyAnimatable?,
    request: AnimationRequest,
    batchID: AnimationBatchID?,
    tracksVelocity: Bool,
    timestamp: MonotonicInstant
  ) {
    // No change → nothing to do, except for the data of an `Animatable`
    // shape whose animation is in flight. This is the path of nearly every
    // slot of every frame, so it builds no key.
    guard previous != current else {
      if slot.holdsShapeData, let current {
        refreshShapeDataDestination(
          at: AnimationKey(identity: identity, slot: slot), with: current)
      }
      return
    }

    let key = AnimationKey(identity: identity, slot: slot)

    // A slot appearing or disappearing breaks value continuity even when
    // its view identity survives. No older velocity can bridge that gap.
    if previous == nil || current == nil {
      slotVelocitySamplers.removeValue(forKey: key)
    }

    switch request {
    case .inherit, .disabled:
      if let superseded = activeAnimations.removeValue(forKey: key) {
        releaseBatch(superseded.batchID, logicalAlreadyReleased: superseded.isLogicallyReleased)
      }
      // A `tracksVelocity` write is sampled into the slot's velocity ring
      // so a later spring on this slot can start with that velocity.
      // Two or more writes are needed before a release can carry velocity.
      if tracksVelocity, AnimationVelocityConfiguration.isEnabled, let current {
        var sampler = slotVelocitySamplers[key] ?? SlotVelocitySampler()
        sampler.record(current, at: timestamp)
        slotVelocitySamplers[key] = sampler
      }

    case .animate(let box):
      guard let previous, let current else {
        // One side nil — cannot interpolate, snap.
        if let superseded = activeAnimations.removeValue(forKey: key) {
          releaseBatch(superseded.batchID, logicalAlreadyReleased: superseded.isLogicallyReleased)
        }
        return
      }

      // Retarget: if an animation already exists, sample its current
      // value and use it as the new `from` — matches the existing
      // mid-flight retarget behavior.
      let effectiveFrom: AnyAnimatable
      var carriedCustomState = AnimationState()
      var initialVelocity: Double?
      if let existing = activeAnimations[key],
        let sampled = sampleAdvancingCustomState(existing, at: timestamp)
      {
        effectiveFrom = sampled.value
        (carriedCustomState, initialVelocity) = retargetHandoff(
          from: existing,
          sampledState: sampled.state,
          origin: effectiveFrom,
          target: current,
          incomingBox: box,
          at: timestamp
        )
        releaseBatch(existing.batchID, logicalAlreadyReleased: existing.isLogicallyReleased)
      } else {
        effectiveFrom = previous
        initialVelocity = sampledReleaseVelocity(
          at: key, from: previous, to: current, at: timestamp)
      }
      slotVelocitySamplers.removeValue(forKey: key)

      retainBatch(batchID)
      activeAnimations[key] = ActiveAnimation(
        kind: .property(from: effectiveFrom, to: current),
        animationBox: box,
        ownerViewNodeID: viewNodeID,
        startTime: timestamp,
        customState: carriedCustomState,
        batchID: batchID,
        initialVelocity: initialVelocity
      )
    }
  }

  /// Gives the animation of an `Animatable` shape's data, in flight at
  /// `key`, the shape the view now holds.
  ///
  /// The slot's value is the shape's data together with the way back from
  /// data to geometry, which is the shape itself. Two values with equal data
  /// are equal, so a change to a field of the shape that its
  /// `animatableData` does not cover is no change of the slot, and starts
  /// nothing. An animation in flight draws each sample through the shape of
  /// its destination, though, and that is the shape as it was when the
  /// animation started. So when the view resolves again with the same data,
  /// the destination takes the value just resolved: every sample from this
  /// frame on is drawn by the shape as it is now, and the data, the curve
  /// and the timing of the animation are untouched (STUI-1577).
  ///
  /// An animation heading for other data is left alone. The view's data
  /// then changed as well, and the slot change that follows retargets it.
  private func refreshShapeDataDestination(at key: AnimationKey, with current: AnyAnimatable) {
    guard let existing = activeAnimations[key],
      case .property(let from, let to) = existing.kind,
      to == current
    else { return }
    activeAnimations[key]?.kind = .property(from: from, to: current)
  }

  /// What an animation that interrupts `existing` takes over from it: the
  /// custom state to carry and the velocity to start with. Shared by the
  /// property slots and by the data of `Animatable` views and modifiers.
  ///
  /// `sampledState` is `existing`'s custom state after its evaluation at
  /// `timestamp`. `origin` is the value that evaluation gave, where the
  /// replacement starts, and `target` is where it goes.
  private func retargetHandoff(
    from existing: ActiveAnimation,
    sampledState: AnimationState,
    origin: AnyAnimatable,
    target: AnyAnimatable,
    incomingBox: AnimationBox,
    at timestamp: MonotonicInstant
  ) -> (customState: AnimationState, initialVelocity: Double?) {
    var carriedCustomState = AnimationState()
    var initialVelocity: Double?
    let outgoing = registeredAnimations[existing.animationBox]
    let incoming = registeredAnimations[incomingBox]
    let elapsed = existing.startTime.duration(to: timestamp)
    if outgoing?.isCustomCurve == true || incoming?.isCustomCurve == true {
      // Custom-curve retarget handoff.  Carry the sample-advanced custom
      // state into the replacement so a retargeting custom curve keeps
      // its per-key bookkeeping instead of resetting to an empty buffer
      // (011); query the outgoing curve's velocity hook (013); consult
      // the incoming curve's merge policy against the previously
      // registered animation (012).
      carriedCustomState = sampledState
      _ = outgoing?.velocity(elapsed: elapsed, state: sampledState)
      if let incoming, let outgoing {
        _ = incoming.shouldMerge(
          previous: outgoing,
          elapsed: elapsed,
          state: &carriedCustomState
        )
      }
    } else if AnimationVelocityConfiguration.isEnabled,
      let ends = existing.kind.endpoints,
      let outgoing,
      let progressVelocity = outgoing.velocity(
        elapsed: elapsed,
        state: sampledState,
        initialVelocity: existing.initialVelocity
      ),
      let projection = AnyAnimatable.progressProjection(
        of: (from: ends.from, to: ends.to),
        onto: (from: origin, to: target)
      )
    {
      // Built-in retarget continuity (T4): the outgoing curve's progress
      // velocity along its own axis, re-expressed along the new segment's
      // axis so the replacement spring continues instead of restarting
      // at rest. Clamped to zero when the new axis is degenerate.
      let seeded = progressVelocity * projection
      initialVelocity = seeded.isFinite && abs(seeded) > 1e-6 ? seeded : nil
    }
    return (carriedCustomState, initialVelocity)
  }

  /// The velocity the preceding `tracksVelocity` writes at `key` release
  /// into an animation that starts from rest there, or `nil`.
  private func sampledReleaseVelocity(
    at key: AnimationKey,
    from origin: AnyAnimatable,
    to target: AnyAnimatable,
    at timestamp: MonotonicInstant
  ) -> Double? {
    guard AnimationVelocityConfiguration.isEnabled,
      let sampler = slotVelocitySamplers[key],
      let sampled = sampler.progressVelocity(from: origin, to: target, at: timestamp),
      abs(sampled) > 1e-6
    else {
      return nil
    }
    return sampled
  }

  // MARK: - Animatable views and modifiers

  /// Begins the frame at `timestamp` for the data of `Animatable` views and
  /// modifiers, before the frame resolves.
  ///
  /// Each value animation in flight is evaluated here, once, and its sample
  /// is kept for the frame: the owner's body reads it when it resolves (the
  /// `presentedValue` entry below). The
  /// returned identities are the owners. The caller adds them to the frame's
  /// invalidation set, so only those bodies run again and the frame tail
  /// treats them as changed. An animation that ends here has no sample left
  /// and is still returned once, so its body runs at the target.
  ///
  /// With no animation in flight this stores the instant and returns.
  ///
  /// `currentIdentity` answers which identity a graph node is indexed at
  /// now. An owner is named by that identity when its node has one: a view
  /// whose body root is a conditional is indexed at its branch.
  package func beginValueSiteFrame(
    at timestamp: MonotonicInstant,
    currentIdentity: (ViewNodeID) -> Identity? = { _ in nil }
  ) -> Set<Identity> {
    valueSites.frameInstant = timestamp
    // What each animation presented on the frame before this one is what
    // its site's body last ran with.
    if !valueSites.samples.isEmpty || !valueSites.previousSamples.isEmpty {
      valueSites.previousSamples = valueSites.samples
      valueSites.samples = [:]
    }
    if !valueSites.tickedOwners.isEmpty {
      valueSites.tickedOwners.removeAll(keepingCapacity: true)
    }
    if !valueSites.freshKeys.isEmpty {
      valueSites.freshKeys.removeAll(keepingCapacity: true)
    }
    guard !activeAnimations.isEmpty else {
      return []
    }
    // A removal that plays a transition body owns the value animations of
    // that body's sites. They are sampled here like every other, and the
    // removal evaluates its body with the samples before the frame tail. No
    // live view reads them: the view at such a site left the graph when the
    // removal began, so there is no owner to run again.
    let removalOwnedKeys = removalOwnedValueKeys
    var owners: Set<Identity> = []
    var sampledAnimation = false
    var keysToRemove: [AnimationKey] = []
    var completedBatches: [CompletedBatchRelease] = []
    var logicallyCompletedBatches: [AnimationBatchID] = []
    var completedAnimationBoxes: Set<AnimationBox> = []
    // The shared step reports what it would redraw. A value animation
    // redraws through its owner's invalidation instead.
    var unusedRedrawIdentities: Set<Identity> = []
    for (key, animation) in activeAnimations {
      guard case .value(let from, let to) = animation.kind else { continue }
      sampledAnimation = true
      if !removalOwnedKeys.contains(key) {
        owners.insert(valueSites.ownerNodeIDs[key].flatMap(currentIdentity) ?? key.identity)
      }
      switch advancePropertyAnimationStep(
        key: key,
        animation: animation,
        at: timestamp,
        keysToRemove: &keysToRemove,
        completedBatches: &completedBatches,
        logicallyCompletedBatches: &logicallyCompletedBatches,
        completedAnimationBoxes: &completedAnimationBoxes,
        redrawIdentities: &unusedRedrawIdentities
      ) {
      case .unregistered, .completed:
        // No sample: the site resolves with its target.
        break
      case .progressed(let progress):
        valueSites.samples[key] = AnimationPropertyValueApplication.interpolate(
          from: from, to: to, progress: progress)
      }
    }
    guard sampledAnimation else {
      return []
    }
    for key in keysToRemove {
      activeAnimations.removeValue(forKey: key)
    }
    for batchID in logicallyCompletedBatches {
      releaseLogicalBatch(batchID)
    }
    for release in completedBatches {
      releaseBatch(release.batchID, logicalAlreadyReleased: release.logicalAlreadyReleased)
    }
    pruneCompletedAnimationRegistrations(completedAnimationBoxes)
    valueSites.tickedOwners = owners
    return owners
  }

  /// The data the site at `key` evaluates its body with on this frame, given
  /// the data the author wrote for it (`target`) and the animation request
  /// of the transaction it resolves under.
  ///
  /// - The site's first resolve records the target and returns it.
  /// - An unchanged target returns this frame's sample while the animation
  ///   toward it is in flight, and the target otherwise. The read changes
  ///   nothing, so every resolve of the site in one frame agrees.
  /// - A target that changed under `.animate` starts an animation from the
  ///   old target, or retargets the one in flight from this frame's sample
  ///   with its velocity. Both return where the animation starts: the body's
  ///   output on a start frame is what it was, so no property animation
  ///   starts beside the value animation.
  /// - A target that changed under `.inherit` or `.disabled` (no animated
  ///   transaction, `withAnimation(nil)`, a disabled transaction, reduced
  ///   motion, the stable-output policy) ends any animation and returns the
  ///   target.
  /// - With `settlesAnimationInFlight`, an unchanged target ends the
  ///   animation toward it and returns the target. The site resolves under
  ///   reduced motion or the stable-output policy, which turned on while the
  ///   animation ran. The animation has to end here, where the body is being
  ///   evaluated: ended anywhere else, the body would keep the sample it last
  ///   ran with. A transaction that only disables animations does not do
  ///   this. It says how a change is applied, and nothing changed.
  package func presentedValue(
    for target: AnyAnimatable,
    at key: AnimationKey,
    request: AnimationRequest,
    batchID: AnimationBatchID?,
    tracksVelocity: Bool = false,
    settlesAnimationInFlight: Bool = false
  ) -> AnyAnimatable {
    guard let previousTarget = valueSites.targets[key],
      previousTarget.wrapsSameType(as: target)
    else {
      // Nothing to animate from: the site's first resolve, or a value of
      // another type where a different view used to be.
      valueSites.targets[key] = target
      valueSites.freshKeys.insert(key)
      endValueAnimation(at: key)
      slotVelocitySamplers.removeValue(forKey: key)
      return target
    }
    guard previousTarget != target else {
      guard activeAnimations[key] != nil else { return target }
      if settlesAnimationInFlight {
        endValueAnimation(at: key)
        return target
      }
      return valueSites.samples[key] ?? target
    }
    valueSites.targets[key] = target

    guard case .animate(let box) = request, let timestamp = valueSites.frameInstant else {
      endValueAnimation(at: key)
      // A `tracksVelocity` write is sampled, as a slot's is, so a spring
      // that later starts here continues the motion of the writes.
      if tracksVelocity, AnimationVelocityConfiguration.isEnabled,
        let timestamp = valueSites.frameInstant
      {
        var sampler = slotVelocitySamplers[key] ?? SlotVelocitySampler()
        sampler.record(target, at: timestamp)
        slotVelocitySamplers[key] = sampler
      }
      return target
    }
    return retargetValueAnimation(
      at: key,
      restingOrigin: previousTarget,
      to: target,
      animationBox: box,
      batchID: batchID,
      at: timestamp
    )
  }

  /// Moves the site at `key` toward `target` under the curve of `box`, in
  /// place of whatever animation the site has, and returns the value the
  /// new animation starts at.
  ///
  /// An animation in flight is continued: the new one starts at this frame's
  /// sample of it, with its velocity. With none in flight it starts at
  /// `restingOrigin`, with the velocity of preceding `tracksVelocity` writes
  /// when there are any. Every path that redirects a site goes through
  /// here: a live site whose target changed, a removal that takes a site
  /// over, and a view that comes back during its removal.
  @discardableResult
  private func retargetValueAnimation(
    at key: AnimationKey,
    restingOrigin: AnyAnimatable,
    to target: AnyAnimatable,
    animationBox box: AnimationBox,
    batchID: AnimationBatchID?,
    at timestamp: MonotonicInstant
  ) -> AnyAnimatable {
    // The transaction can carry a curve no sink registered (see
    // ``processResolvedTree``, which recovers it too, but after resolve).
    if registeredAnimations[box] == nil, let animation = box.unwrap(as: Animation.self) {
      registeredAnimations[box] = animation
    }

    let origin: AnyAnimatable
    var carriedCustomState = AnimationState()
    var initialVelocity: Double?
    if let existing = activeAnimations.removeValue(forKey: key) {
      // This frame's sample is the head's one evaluation of the curve in
      // flight, and the custom state it advanced is already stored.
      origin = valueSites.samples[key] ?? existing.kind.endpoints?.to ?? restingOrigin
      (carriedCustomState, initialVelocity) = retargetHandoff(
        from: existing,
        sampledState: existing.customState,
        origin: origin,
        target: target,
        incomingBox: box,
        at: timestamp
      )
      releaseBatch(existing.batchID, logicalAlreadyReleased: existing.isLogicallyReleased)
    } else {
      origin = restingOrigin
      initialVelocity = sampledReleaseVelocity(
        at: key, from: restingOrigin, to: target, at: timestamp)
    }
    slotVelocitySamplers.removeValue(forKey: key)
    return startValueAnimation(
      at: key,
      from: origin,
      to: target,
      animationBox: box,
      batchID: batchID,
      customState: carriedCustomState,
      initialVelocity: initialVelocity,
      at: timestamp
    )
  }

  /// Starts the value animation of `site` from `origin` toward `target` on
  /// the frame being prepared, in place of whatever the site had.
  ///
  /// This is the way to animate a site from a value its body never resolved
  /// with: a view inserted under a transition starts from the data of
  /// another phase. The site's next resolve with `target` reads the origin
  /// as this frame's sample. Returns `false`, and starts nothing, when no
  /// frame has begun or the curve is not registered.
  @discardableResult
  package func beginValueAnimation(
    at site: AnimatableValueSite,
    from origin: AnyAnimatable,
    to target: AnyAnimatable,
    animationBox box: AnimationBox,
    batchID: AnimationBatchID?
  ) -> Bool {
    let key = AnimationKey(site: site)
    guard let timestamp = valueSites.frameInstant, origin.wrapsSameType(as: target) else {
      return false
    }
    if registeredAnimations[box] == nil, let animation = box.unwrap(as: Animation.self) {
      registeredAnimations[box] = animation
    }
    guard registeredAnimations[box] != nil else {
      return false
    }
    valueSites.targets[key] = target
    endValueAnimation(at: key)
    slotVelocitySamplers.removeValue(forKey: key)
    startValueAnimation(
      at: key,
      from: origin,
      to: target,
      animationBox: box,
      batchID: batchID,
      customState: AnimationState(),
      initialVelocity: nil,
      at: timestamp
    )
    return true
  }

  /// The boxed form of `data` that the value-animation entry points take.
  package static func boxedAnimatableData<Data: VectorArithmetic>(_ data: Data) -> AnyAnimatable {
    AnyAnimatable(AnimatableDataBox(data))
  }

  /// The data this frame's resolve of `site` presents while its animation is
  /// in flight, or `nil` when none is. Test hook.
  package func valueAnimationSample(at site: AnimatableValueSite) -> AnyAnimatable? {
    let key = AnimationKey(site: site)
    guard activeAnimations[key] != nil else { return nil }
    return valueSites.samples[key]
  }

  /// The velocity the value animation of `site` was released with, in
  /// progress units per second, or `nil` when it started at rest or none is
  /// in flight. Test hook.
  package func valueAnimationInitialVelocity(at site: AnimatableValueSite) -> Double? {
    activeAnimations[AnimationKey(site: site)]?.initialVelocity
  }

  /// Puts a new value animation at `key` and returns its first value. The
  /// curve is evaluated once, at its start, as a property animation's is on
  /// the frame that creates it: a curve with no extent is over at once, and
  /// the site then resolves with its target.
  @discardableResult
  private func startValueAnimation(
    at key: AnimationKey,
    from origin: AnyAnimatable,
    to target: AnyAnimatable,
    animationBox box: AnimationBox,
    batchID: AnimationBatchID?,
    customState: AnimationState,
    initialVelocity: Double?,
    at timestamp: MonotonicInstant
  ) -> AnyAnimatable {
    guard let animation = registeredAnimations[box] else {
      valueSites.samples.removeValue(forKey: key)
      return target
    }
    var state = customState
    guard
      let progress = animation.evaluate(
        elapsed: .zero, state: &state, initialVelocity: initialVelocity)
    else {
      valueSites.samples.removeValue(forKey: key)
      return target
    }
    retainBatch(batchID)
    activeAnimations[key] = ActiveAnimation(
      kind: .value(from: origin, to: target),
      animationBox: box,
      startTime: timestamp,
      customState: state,
      batchID: batchID,
      initialVelocity: initialVelocity
    )
    let sample = AnimationPropertyValueApplication.interpolate(
      from: origin, to: target, progress: progress)
    valueSites.samples[key] = sample
    return sample
  }

  /// Ends the value animation at `key`, if one is in flight, releasing the
  /// batch it retained so its completion can fire.
  private func endValueAnimation(at key: AnimationKey) {
    valueSites.samples.removeValue(forKey: key)
    guard let entry = activeAnimations.removeValue(forKey: key) else { return }
    releaseBatch(entry.batchID, logicalAlreadyReleased: entry.isLogicallyReleased)
  }

  /// The number of slots currently holding `tracksVelocity` samples. Test hook.
  package var velocitySamplerCount: Int {
    slotVelocitySamplers.count
  }

  /// The velocity the property animation on `slot` was released with, in
  /// progress units per second, or `nil` when it started at rest or there
  /// is no such animation. Test hook.
  package func initialVelocity(forIdentity identity: Identity, slot: AnimatableSlot) -> Double? {
    activeAnimations[AnimationKey(identity: identity, slot: slot)]?.initialVelocity
  }

  /// Diffs presentation values realized outside the head's resolved tree.
  /// The frame draft owns their targets and curves until commit; layout keeps
  /// destination values while this pass returns the current painted samples.
  package func processRealizedPresentation(
    in placed: PlacedNode,
    transactionPlan: FrameAnimationTransactionPlan,
    at timestamp: MonotonicInstant, surfaceSize: CellSize? = nil
  ) -> (
    textRolls: [Identity: TextRollValue], tintStyles: [Identity: AnyShapeStyle],
    placements: [Identity: CellPlacementContext]
  ) {
    var targets: [AnimationKey: AnyAnimatable] = [:]
    var owners: [Identity: Identity] = [:]
    var samples: [AnimationKey: AnyAnimatable] = [:]
    var baselineTints: [Identity: AnyShapeStyle] = [:]
    var pending: [(PlacedNode, Identity?, CellPlacementParent?)] = [(placed, nil, nil)]
    while let (node, inheritedOwner, parent) = pending.popLast() {
      guard !node.isTransient else { continue }
      let isResolved = previousIdentities.contains(node.identity)
      let owner = isResolved ? node.identity : inheritedOwner
      let space = CellPlacementParent(
        identity: node.identity, nodeID: node.viewNodeID,
        origin: node.bounds.origin)
      pending.append(contentsOf: node.children.map { ($0, owner, space) })
      var values: [AnimatableSlot: AnyAnimatable] = [:]
      if node.drawEffects.hasPlacement {
        values[.cellPlacement] = AnyAnimatable(
          CellPlacementValue(
            parent: parent?.identity, parentID: parent?.nodeID, site: node.viewNodeID,
            viewport: surfaceSize ?? placed.bounds.size,
            current: node.bounds.relative(to: parent?.origin ?? .zero)))
      }
      if case .text(let text) = node.drawPayload,
        let transition = node.drawMetadata.contentTransition
      {
        values[.textRoll] = AnyAnimatable(TextRollValue(text: text, transition: transition))
      }
      if node.drawPayload != .none,
        let tint = AnimatableSnapshot.extractAnimatableShapeStyle(
          from: node.environmentSnapshot.style.tintStyle)
      {
        values[.tintShapeStyle] = tint
        baselineTints[node.identity] = node.environmentSnapshot.style.tintStyle
      }
      for (slot, target) in values {
        let key = AnimationKey(identity: node.identity, slot: slot)
        if isResolved && slot != .cellPlacement {
          // Retained eager placement can carry an earlier head sample.
          let byNode = node.viewNodeID.flatMap {
            currentResolvedPresentationProjection.interpolatedByNodeID[$0]?[slot]
          }
          samples[key] =
            byNode
            ?? currentResolvedPresentationProjection.interpolatedByIdentity[node.identity]?[slot]
            ?? previousSnapshots[node.identity]?[slot]
          continue
        }
        targets[key] = target
        owners[node.identity] = owner
        samples[key] = target
        var transaction = node.presentationAnimationTransaction ?? .init()
        let frameTransaction = transactionPlan.transaction(for: node.identity)
        if transaction.animationRequest == .inherit {
          transaction.animationRequest = frameTransaction.animationRequest
          transaction.animationBatchID = frameTransaction.animationBatchID
        }
        if slot == .tintShapeStyle,
          let intent = transaction.customValues[ObjectIdentifier(ScopedTintStyleAnimationKey.self)]?
            .unwrap(as: ScopedStyleAnimationIntent.self), intent.isScoped
        {
          if intent.request != .inherit { transaction.animationRequest = intent.request }
          transaction.animationBatchID = intent.batchID ?? transaction.animationBatchID
        }
        if node.environmentSnapshot.style.renderingReduceMotion {
          transaction.animationRequest = .disabled
          if let entry = activeAnimations.removeValue(forKey: key) {
            releaseBatch(entry.batchID, logicalAlreadyReleased: entry.isLogicallyReleased)
          }
        }
        if case .animate(let box) = transaction.animationRequest,
          registeredAnimations[box] == nil, let animation = box.unwrap(as: Animation.self)
        {
          registeredAnimations[box] = animation
        }
        var previous = previousFrame.realizedPresentationTargets[key]
        if slot == .cellPlacement,
          let old = previous?.unwrap(as: CellPlacementValue.self),
          let new = target.unwrap(as: CellPlacementValue.self), !old.sharesSpace(with: new)
        {
          previous = nil
        }
        enqueueSlotChangeIfNeeded(
          identity: node.identity, viewNodeID: node.viewNodeID, slot: slot,
          previous: previous, current: target,
          request: transaction.animationRequest, batchID: transaction.animationBatchID,
          tracksVelocity: transaction.tracksVelocity, timestamp: timestamp)
      }
    }

    // Leaving the realized window releases both the curve and its completion
    // ownership. Re-entry starts at the current model, without an offscreen sample.
    var completedBoxes: Set<AnimationBox> = []
    for key in previousFrame.realizedPresentationTargets.keys where targets[key] == nil {
      if let entry = activeAnimations.removeValue(forKey: key) {
        completedBoxes.insert(entry.animationBox)
        releaseBatch(entry.batchID, logicalAlreadyReleased: entry.isLogicallyReleased)
      }
    }
    previousFrame.realizedPresentationTargets = targets
    previousFrame.realizedPresentationOwners = owners

    var keysToRemove: [AnimationKey] = []
    var completedBatches: [CompletedBatchRelease] = []
    var logicallyCompletedBatches: [AnimationBatchID] = []
    var redraw: Set<Identity> = []
    for key in targets.keys {
      guard let entry = activeAnimations[key], case .property(let from, let to) = entry.kind else {
        continue
      }
      switch advancePropertyAnimationStep(
        key: key, animation: entry, at: timestamp, keysToRemove: &keysToRemove,
        completedBatches: &completedBatches, logicallyCompletedBatches: &logicallyCompletedBatches,
        completedAnimationBoxes: &completedBoxes, redrawIdentities: &redraw)
      {
      case .unregistered, .completed:
        break
      case .progressed(let progress):
        samples[key] = AnimationPropertyValueApplication.interpolate(
          from: from, to: to, progress: progress)
      }
    }
    for key in keysToRemove { activeAnimations.removeValue(forKey: key) }
    for batchID in logicallyCompletedBatches { releaseLogicalBatch(batchID) }
    for release in completedBatches {
      releaseBatch(release.batchID, logicalAlreadyReleased: release.logicalAlreadyReleased)
    }
    pruneCompletedAnimationRegistrations(completedBoxes)
    lastTickResult.redrawIdentities.formUnion(redraw)
    if targets.keys.contains(where: { activeAnimations[$0] != nil }) {
      lastTickResult.hasPendingWork = true
      let next = timestamp.advanced(by: frameInterval)
      lastTickResult.nextDeadline = min(lastTickResult.nextDeadline ?? next, next)
    } else if activeAnimations.isEmpty && removingNodes.isEmpty
      && pendingEmptyBatchCompletions.isEmpty
    {
      lastTickResult.hasPendingWork = false
      lastTickResult.nextDeadline = nil
    }
    var rolls: [Identity: TextRollValue] = [:]
    var tints: [Identity: AnyShapeStyle] = [:]
    var placements: [Identity: CellPlacementContext] = [:]
    for (key, sample) in samples {
      if key.scope == .property(.cellPlacement) {
        if let value = sample.unwrap(as: CellPlacementValue.self), let prior = value.previous {
          placements[key.identity] = .init(
            previousFrame: prior, currentFrame: value.current,
            progress: value.animatableData)
        }
      } else if key.scope == .property(.textRoll) {
        rolls[key.identity] = sample.unwrap(as: TextRollValue.self)
      } else if let tint = AnimationPropertyValueApplication.unwrapShapeStyle(sample),
        tint != baselineTints[key.identity]
      {
        tints[key.identity] = tint
      }
    }
    return (rolls, tints, placements)
  }

  private func retainBatch(_ batchID: AnimationBatchID?) {
    guard let batchID else { return }
    pendingEmptyBatchCompletions.removeValue(forKey: batchID)
    batchRefCounts[batchID, default: 0] += 1
    batchLogicalRefCounts[batchID, default: 0] += 1
  }

  /// Drops one logical retain. When the last logical retainer lets go, the
  /// batch's `.logicallyComplete` registrations fire (or are dropped, on the
  /// departed-identity prune's arm); its `.removed` registrations wait for
  /// ``releaseBatch(_:logicalAlreadyReleased:firingCompletion:)``.
  private func releaseLogicalBatch(
    _ batchID: AnimationBatchID?,
    firingCompletion: Bool = true
  ) {
    guard let batchID, let count = batchLogicalRefCounts[batchID] else { return }
    if count <= 1 {
      batchLogicalRefCounts.removeValue(forKey: batchID)
      let closures = takeCompletions(for: batchID, barrier: .logicallyComplete)
      if firingCompletion {
        for closure in closures {
          fireOrDeferCompletion(closure)
        }
      }
    } else {
      batchLogicalRefCounts[batchID] = count - 1
    }
  }

  /// `firingCompletion: false` is the departed-identity prune's arm: when the
  /// LAST retainer of a batch left the live tree untransitioned, its
  /// completion's awaiter died with the owning subtree, so the closure is
  /// dropped rather than fired (firing would double-resume a finished
  /// continuation — see ``requiresContinuedAnimationFrames``). If a live
  /// animation in the same batch releases last instead, the completion fires
  /// normally through the default arm.
  ///
  /// `logicalAlreadyReleased: true` is for a retainer that passed its logical
  /// barrier earlier (a latched `logicallyComplete(after:)` curve, an exit
  /// overlay whose curve already ended) so the logical count is not
  /// decremented twice; every other release drops both halves, logical
  /// first, so a batch that ends in one step fires its `.logicallyComplete`
  /// registrations before its `.removed` ones.
  private func releaseBatch(
    _ batchID: AnimationBatchID?,
    logicalAlreadyReleased: Bool = false,
    firingCompletion: Bool = true
  ) {
    guard let batchID, let count = batchRefCounts[batchID] else { return }
    if !logicalAlreadyReleased {
      releaseLogicalBatch(batchID, firingCompletion: firingCompletion)
    }
    let newCount = count - 1
    if newCount <= 0 {
      batchRefCounts.removeValue(forKey: batchID)
      batchLogicalRefCounts.removeValue(forKey: batchID)
      let closures = takeCompletions(for: batchID)
      if firingCompletion {
        for closure in closures {
          fireOrDeferCompletion(closure)
        }
      }
    } else {
      batchRefCounts[batchID] = newCount
    }
  }

  /// Removes and returns the batch's registrations at `barrier`, or every
  /// registration when `barrier` is `nil`; a batch whose list empties leaves
  /// the ledger so pending-work checks see only live completions.
  private func takeCompletions(
    for batchID: AnimationBatchID,
    barrier: AnimationCompletionBarrier? = nil
  ) -> [@MainActor @Sendable () -> Void] {
    guard let registrations = completions[batchID] else { return [] }
    let taken = registrations.filter { barrier == nil || $0.barrier == barrier }
    let remaining = registrations.filter { barrier != nil && $0.barrier != barrier }
    if remaining.isEmpty {
      completions.removeValue(forKey: batchID)
    } else {
      completions[batchID] = remaining
    }
    return taken.map(\.closure)
  }

  private func fireOrDeferCompletion(_ completion: @escaping @MainActor @Sendable () -> Void) {
    guard isFrameHeadTransactionActive else {
      lastFrameHeadCompletionCount += 1
      completion()
      return
    }
    deferredFrameHeadCompletions.append(completion)
  }

  /// Applies interpolated values to the resolved tree for the given
  /// timestamp.  Returns a tick result describing scheduling needs.
  package func applyInterpolations(
    to tree: inout ResolvedNode,
    at timestamp: MonotonicInstant,
    surfaceSize: CellSize? = nil
  ) -> AnimationTickResult {
    guard
      !activeAnimations.isEmpty
        || !removingNodes.isEmpty
        || !pendingEmptyBatchCompletions.isEmpty
    else {
      currentResolvedPresentationProjection = .init()
      lastTickResult = AnimationTickResult()
      lastPropertyInterpolationVisitedNodeCount = 0
      return lastTickResult
    }

    var keysToRemove: [AnimationKey] = []
    var redrawIdentities: Set<Identity> = []
    var latestDeadline: MonotonicInstant = timestamp
    var hasPendingWork = false

    // Build interpolated value maps for the fast tree walk. Property animations
    // that captured their owning entity (`ownerViewNodeID`) are keyed by
    // `ViewNodeID` so they follow the entity across an identity-changing move
    // (G10a); the rest fall back to the registration `Identity`.
    var interpolatedByNodeID: [ViewNodeID: [AnimatableSlot: AnyAnimatable]] = [:]
    var interpolatedIdentityByNodeID: [ViewNodeID: Identity] = [:]
    var interpolatedByIdentity: [Identity: [AnimatableSlot: AnyAnimatable]] = [:]

    // Record the batches that completed animations belong to so we can
    // release their ref counts in a second pass (after this iteration
    // closes).  Releasing during the iteration would mutate
    // activeAnimations and invalidate the dictionary traversal.
    var completedBatches: [CompletedBatchRelease] = []
    var logicallyCompletedBatches: [AnimationBatchID] = []

    // Boxes of property animations that ran to completion this tick. After the
    // active/removal maps are finalized below, each such box whose LAST live
    // reference is gone is dropped from the append-only registration ledger so
    // it stays bounded across a run of unique finite curves (009).
    var completedAnimationBoxes: Set<AnimationBox> = []

    // The property animations a removal's transition body owns are sampled
    // here like any other, once per frame. Their views are not in `tree`:
    // the samples go to the removal, which draws its body with them before
    // the frame tail.
    let removalBodyOwners = removalBodyOwners
    var removalBodySamples: [ViewNodeID: [Identity: [AnimatableSlot: AnyAnimatable]]] = [:]

    // Walk every active animation regardless of scope.  Property
    // scopes are sampled here and write into ``interpolated`` for
    // application by ``applyInterpolatedValues`` below.  Placed-level
    // scopes (insertion offset/scale, matched geometry) only need the run
    // loop to keep ticking on this pass — their actual evaluation +
    // translation runs inside ``applyPlacedOverlays``, and we must
    // not double-evaluate stateful CustomAnimation curves here.
    for (key, animation) in activeAnimations {
      switch animation.kind {
      case .property(let from, let to):
        if let owner = removalBodyOwners[key.identity] {
          let slot = AnimationPropertyValueApplication.propertySlot(for: key)
          switch advancePropertyAnimationStep(
            key: key,
            animation: animation,
            at: timestamp,
            keysToRemove: &keysToRemove,
            completedBatches: &completedBatches,
            logicallyCompletedBatches: &logicallyCompletedBatches,
            completedAnimationBoxes: &completedAnimationBoxes,
            redrawIdentities: &redrawIdentities
          ) {
          case .unregistered:
            break
          case .completed:
            removalBodySamples[owner, default: [:]][key.identity, default: [:]][slot] =
              AnimationPropertyValueApplication.presentationValue(of: to, for: slot)
          case .progressed(let progress):
            removalBodySamples[owner, default: [:]][key.identity, default: [:]][slot] =
              AnimationPropertyValueApplication.presentationValue(
                of: AnimationPropertyValueApplication.interpolate(
                  from: from, to: to, progress: progress),
                for: slot)
            latestDeadline = timestamp.advanced(by: frameInterval)
            hasPendingWork = true
          }
          continue
        }
        if previousFrame.realizedPresentationTargets[key] != nil {
          // The tail owns this curve's single evaluation after row realization.
          hasPendingWork = true
          latestDeadline = timestamp.advanced(by: frameInterval)
          redrawIdentities.insert(key.identity)
          continue
        }
        let slot = AnimationPropertyValueApplication.propertySlot(for: key)
        switch advancePropertyAnimationStep(
          key: key,
          animation: animation,
          at: timestamp,
          keysToRemove: &keysToRemove,
          completedBatches: &completedBatches,
          logicallyCompletedBatches: &logicallyCompletedBatches,
          completedAnimationBoxes: &completedAnimationBoxes,
          redrawIdentities: &redrawIdentities
        ) {
        case .unregistered:
          continue
        case .completed:
          // Animation complete — snap to final value; the step purged it.
          let value = AnimationPropertyValueApplication.presentationValue(of: to, for: slot)
          if let ownerViewNodeID = animation.ownerViewNodeID {
            interpolatedByNodeID[ownerViewNodeID, default: [:]][slot] = value
            interpolatedIdentityByNodeID[ownerViewNodeID] =
              animation.resolvedIdentity ?? key.identity
          } else {
            interpolatedByIdentity[key.identity, default: [:]][slot] = value
          }
          continue
        case .progressed(let progress):
          // The data of an `Animatable` shape becomes geometry here, on the
          // main actor, once for this sample.
          let value = AnimationPropertyValueApplication.presentationValue(
            of: AnimationPropertyValueApplication.interpolate(
              from: from,
              to: to,
              progress: progress
            ),
            for: slot)
          if let ownerViewNodeID = animation.ownerViewNodeID {
            interpolatedByNodeID[ownerViewNodeID, default: [:]][slot] = value
            interpolatedIdentityByNodeID[ownerViewNodeID] =
              animation.resolvedIdentity ?? key.identity
          } else {
            interpolatedByIdentity[key.identity, default: [:]][slot] = value
          }
          latestDeadline = timestamp.advanced(by: frameInterval)
          hasPendingWork = true
        }

      case .insertionOffset, .insertionScale, .matchedGeometry:
        // Placed-level scopes don't read or write the resolved tree
        // here.  Their kind payload only mutates the placed tree
        // inside ``applyPlacedOverlays``, which advances the
        // animation's custom state and releases the entry on
        // completion.  This pass simply marks the loop as having
        // pending work so the scheduler keeps ticking.  Don't call
        // ``evaluate(elapsed:state:)`` on the registered Animation
        // here — that would double-evaluate stateful CustomAnimation
        // curves once per frame (this loop + applyPlacedOverlays).
        hasPendingWork = true
        if latestDeadline == timestamp {
          latestDeadline = timestamp.advanced(by: frameInterval)
        }
        redrawIdentities.insert(key.identity)

      case .value:
        // The frame head sampled this curve before resolve
        // (``beginValueSiteFrame(at:)``), and the owner's body has run with
        // the sample. Nothing is written here and nothing is evaluated a
        // second time. The owner is in the frame's invalidation set, so no
        // redraw identity is reported for it. Only the next tick is asked
        // for.
        hasPendingWork = true
        if latestDeadline == timestamp {
          latestDeadline = timestamp.advanced(by: frameInterval)
        }
      }
    }

    // Remove completed animations.
    for key in keysToRemove {
      activeAnimations.removeValue(forKey: key)
    }
    // Release the batch references for everything that completed.
    // ``releaseBatch`` fires the matching completion closures when the
    // ref counts hit zero; latched logical completions release first.
    for batchID in logicallyCompletedBatches {
      releaseLogicalBatch(batchID)
    }
    for release in completedBatches {
      releaseBatch(release.batchID, logicalAlreadyReleased: release.logicalAlreadyReleased)
    }

    // Each removal that plays a body takes this frame's samples. A slot
    // without one shows the value of the removal's working tree.
    for viewNodeID in Array(removingNodes.keys) where removingNodes[viewNodeID]?.body != nil {
      removingNodes[viewNodeID]?.body?.samples = removalBodySamples[viewNodeID] ?? [:]
    }

    // Process removal entries: compute interpolated transition modifiers
    // and prepare them for injection back into the tree.
    var removalsToPurge: [ViewNodeID] = []
    var injectionsByParent: [Identity: [(childIndex: Int, snapshot: ResolvedNode)]] = [:]

    for (viewNodeID, entry) in removingNodes {
      // The placed overlay pass alone samples a removal with a placed snapshot,
      // a parent, and a registered curve. Sampling here too would advance a
      // stateful CustomAnimation twice per frame. Keep ticking until that pass
      // latches logical completion, then purge on the following head tick.
      // Mirror `sampleRemovalOverlays`' ownership guards so removals without a
      // snapshot, parent, or registered curve drain through the fallback below.
      if entry.placedSnapshot != nil,
        entry.parentIdentity != nil,
        let box = entry.animationBox,
        registeredAnimations[box] != nil
      {
        if entry.isLogicallyComplete {
          // The placed pass ended this overlay's curve on the previous
          // committed turn and held its final visual for that turn. Purging
          // here, at the head, fires the `.removed` barrier on this frame
          // whether or not a placed pass follows (elided frames run none).
          removingNodes.removeValue(forKey: viewNodeID)
          completedAnimationBoxes.insert(box)
          if let body = entry.body {
            completedAnimationBoxes.formUnion(endRemovalBodyAnimations(of: body))
          }
          releaseBatch(entry.completionBatchID, logicalAlreadyReleased: true)
          redrawIdentities.insert(entry.identity)
          continue
        }
        redrawIdentities.insert(entry.identity)
        latestDeadline = timestamp.advanced(by: frameInterval)
        hasPendingWork = true
        continue
      }

      let modifiers: TransitionModifiers
      var animationComplete = false

      if let box = entry.animationBox, let anim = registeredAnimations[box] {
        let elapsed = entry.startTime.duration(to: timestamp)
        var state = entry.customState
        let evaluated = anim.evaluate(elapsed: elapsed, state: &state)
        // Write the updated custom state back so the next tick of
        // the exit transition carries user bookkeeping forward
        // (matches the active-animation tick loop pattern).
        removingNodes[viewNodeID]?.customState = state
        if let progress = evaluated {
          // Interpolate from the entry's captured starting opacity
          // (normally 1.0 = identity, but may be lower if this
          // removal interrupted a mid-flight insertion) toward the
          // removal modifiers.  Progress 0 == starting state,
          // progress 1 == fully removed.
          // Resolved-level fallback: no placed rect exists for the departing
          // subtree yet, so the surface is the only basis available (the
          // documented fallback on `resolvedOffset(edgeBasis:)`).
          modifiers = AnimationTransitionOverlay.interpolatedRemovalModifiers(
            from: entry.startOpacity,
            startScale: entry.startScale,
            to: entry.transition.removalModifiers(),
            progress: progress,
            edgeBasis: surfaceSize
          )
        } else {
          animationComplete = true
          modifiers = entry.transition.removalModifiers()
        }
      } else {
        // No animation intent carried through — snap.
        animationComplete = true
        modifiers = .identity
      }

      if animationComplete {
        // Placed-pass-owned removals already continued above. A snapshot alone
        // must not hold an instantaneous exit (including withAnimation(nil)):
        // no registered curve will advance it, so release its barriers here.
        if entry.completionBatchID == nil || entry.isLogicallyComplete {
          removalsToPurge.append(viewNodeID)
        } else {
          removingNodes[viewNodeID]?.isLogicallyComplete = true
          releaseLogicalBatch(entry.completionBatchID)
          latestDeadline = timestamp.advanced(by: frameInterval)
          hasPendingWork = true
        }
        redrawIdentities.insert(entry.identity)
        continue
      }

      // When a placed snapshot was captured in the previous frame
      // we inject the overlay at the PLACED level (after layout)
      // via ``applyPlacedOverlays`` — skip resolved-level injection
      // here so the overlay doesn't run through measure/place.  This
      // closes the VStack layout-shift gap.
      if entry.placedSnapshot == nil {
        // Resolved-level fallback path (no cached placed tree).
        // Clone the subtree and apply the interpolated transition
        // modifiers recursively so leaf views (text, etc.) pick up
        // the fading opacity even if the transition was applied
        // higher up in the subtree.  Mark every node in the cloned
        // overlay as transient so the semantic extractor, focus
        // tracker, and lifecycle coordinator skip them.
        let subtreeCopy = AnimationTransitionOverlay.resolvedRemovalSnapshot(
          from: entry.snapshot,
          applying: modifiers
        )
        if let parentId = entry.parentIdentity {
          injectionsByParent[parentId, default: []].append(
            (childIndex: entry.childIndex, snapshot: subtreeCopy)
          )
        }
      }
      redrawIdentities.insert(entry.identity)
      latestDeadline = timestamp.advanced(by: frameInterval)
      hasPendingWork = true
    }

    for viewNodeID in removalsToPurge {
      if let entry = removingNodes.removeValue(forKey: viewNodeID) {
        if let box = entry.animationBox { completedAnimationBoxes.insert(box) }
        releaseBatch(
          entry.completionBatchID,
          logicalAlreadyReleased: entry.isLogicallyComplete
        )
      }
    }

    pruneCompletedAnimationRegistrations(completedAnimationBoxes)

    currentResolvedPresentationProjection = ResolvedPresentationProjection(
      interpolatedByNodeID: interpolatedByNodeID,
      interpolatedIdentityByNodeID: interpolatedIdentityByNodeID,
      interpolatedByIdentity: interpolatedByIdentity,
      parentByIdentity: previousParentByIdentity,
      childIndexByIdentity: previousChildIndexByIdentity,
      removalInjectionsByParent: injectionsByParent
    )

    // Apply interpolated values for in-tree animations.
    var appliedIdentities: Set<Identity> = []
    var interpolationVisitedNodeCount = 0
    tree = AnimationPropertyValueApplication.applyInterpolatedValues(
      tree: tree,
      interpolatedByNodeID: interpolatedByNodeID,
      interpolatedIdentityByNodeID: interpolatedIdentityByNodeID,
      interpolatedByIdentity: interpolatedByIdentity,
      parentByIdentity: previousParentByIdentity,
      childIndexByIdentity: previousChildIndexByIdentity,
      visitedNodeCount: &interpolationVisitedNodeCount,
      appliedIdentities: &appliedIdentities
    )
    lastPropertyInterpolationVisitedNodeCount = interpolationVisitedNodeCount
    // A node-id-keyed animation lands on the entity's *current* identity, which
    // can differ from the registration `Identity` after a move; redraw the
    // identities actually written so the moved view repaints (G10a).
    redrawIdentities.formUnion(appliedIdentities)

    // Inject removal overlays at their previous parent/index.
    if !injectionsByParent.isEmpty {
      tree = AnimationTransitionOverlay.injectResolvedRemovals(
        into: tree,
        injectionsByParent: injectionsByParent
      )
    }

    // Drain stranded `withAnimation` completions whose target time
    // has elapsed.  Any batch whose resolve pass found no animatable
    // property to retain was parked here by
    // ``scheduleStrandedBatchDrains``; we fire its completion once
    // the wall-clock has caught up to the animation's nominal
    // duration.  The closure is removed in a single pass so the same
    // drain can't double-fire across subsequent ticks.
    if !pendingEmptyBatchCompletions.isEmpty {
      let pendingDrain = AnimationCompletionScheduling.partitionPendingDrains(
        pendingEmptyBatchCompletions,
        at: timestamp
      )
      if let deadline = pendingDrain.nextDeadline {
        hasPendingWork = true
        if latestDeadline == timestamp || deadline < latestDeadline {
          latestDeadline = deadline
        }
      }
      for batchID in pendingDrain.drainedBatchIDs {
        pendingEmptyBatchCompletions.removeValue(forKey: batchID)
        for closure in takeCompletions(for: batchID) {
          fireOrDeferCompletion(closure)
        }
      }
    }

    let result = AnimationTickResult(
      hasPendingWork: hasPendingWork,
      nextDeadline: hasPendingWork ? latestDeadline : nil,
      redrawIdentities: redrawIdentities
    )
    lastTickResult = result
    return result
  }

  /// Re-applies the resolved presentation sampled by the most recent tick to a
  /// freshly reconciled canonical tree. This does not sample time, advance
  /// custom animation state, mutate active-animation bookkeeping, or dispatch
  /// completions.
  @discardableResult
  package func reapplyCurrentResolvedPresentation(
    to tree: inout ResolvedNode
  ) -> Set<Identity> {
    let projection = currentResolvedPresentationProjection
    var visitedNodeCount = 0
    var appliedIdentities: Set<Identity> = []
    tree = AnimationPropertyValueApplication.applyInterpolatedValues(
      tree: tree,
      interpolatedByNodeID: projection.interpolatedByNodeID,
      interpolatedIdentityByNodeID: projection.interpolatedIdentityByNodeID,
      interpolatedByIdentity: projection.interpolatedByIdentity,
      parentByIdentity: projection.parentByIdentity,
      childIndexByIdentity: projection.childIndexByIdentity,
      visitedNodeCount: &visitedNodeCount,
      appliedIdentities: &appliedIdentities
    )
    if !projection.removalInjectionsByParent.isEmpty {
      tree = AnimationTransitionOverlay.injectResolvedRemovals(
        into: tree,
        injectionsByParent: projection.removalInjectionsByParent
      )
    }
    return appliedIdentities
  }

  /// Samples the current interpolated value of a property-scoped
  /// animation at `timestamp`, discarding the advanced custom state.
  /// Returns `nil` for non-property kinds — the placed-level scopes
  /// (insertion offset/scale, matched geometry) produce placed transforms
  /// rather than ``AnyAnimatable`` values and don't participate in the
  /// property retarget path.
  ///
  /// The insertion path (``sampleCurrentValue(for:at:)``) releases the
  /// existing animation immediately after sampling, so it has no use for
  /// the advanced state.  The property retarget path calls
  /// ``sampleAdvancingCustomState(_:at:)`` directly to keep it.
  private func sample(
    _ animation: ActiveAnimation,
    at timestamp: MonotonicInstant
  ) -> AnyAnimatable? {
    sampleAdvancingCustomState(animation, at: timestamp)?.value
  }

  /// Samples the current interpolated value like ``sample(_:at:)`` but
  /// also returns the custom ``AnimationState`` advanced by the sampling
  /// `evaluate` call.  The retarget path carries that advanced state into
  /// the replacement animation so a stateful ``CustomAnimation`` keeps its
  /// per-key bookkeeping instead of resetting to `.init()` (011).  Returns
  /// `nil` for non-property kinds or an unregistered box, matching
  /// ``sample(_:at:)``.
  private func sampleAdvancingCustomState(
    _ animation: ActiveAnimation,
    at timestamp: MonotonicInstant
  ) -> (value: AnyAnimatable, state: AnimationState)? {
    guard case .property(let from, let to) = animation.kind else {
      return nil
    }
    guard let anim = registeredAnimations[animation.animationBox] else {
      return nil
    }
    let elapsed = animation.startTime.duration(to: timestamp)
    var state = animation.customState
    guard
      let progress = anim.evaluate(
        elapsed: elapsed,
        state: &state,
        initialVelocity: animation.initialVelocity
      )
    else {
      return (to, state)
    }
    let value = AnimationPropertyValueApplication.interpolate(
      from: from,
      to: to,
      progress: progress
    )
    return (value, state)
  }

  /// Resets all per-identity state.  Used when the renderer is disposed
  /// or the view tree is completely reset.
  ///
  /// Clears every stored field so no stale state leaks across a reset —
  /// leaving `removingNodes` or `previousTreeRoot` alive would cause
  /// the next tick after reset to try to re-inject a subtree from a
  /// previous-generation tree.
  package func reset() {
    previousFrame.reset()
    transitions.reset()
    batchCompletion.reset()
    completionLedger.reset()
    valueSites.reset()
    bodyInsertions.reset()
    frameHead.reset()
    activeAnimations.removeAll(keepingCapacity: true)
    removingNodes.removeAll(keepingCapacity: true)
    currentResolvedPresentationProjection = .init()
    lastTickResult = .init()
    resolvedTreeProcessingSkipCount = 0
    lastResolvedTreeProcessedNodeCount = 0
    lastPropertyInterpolationVisitedNodeCount = 0
    resetEpoch &+= 1
  }
}

@MainActor
package final class AnimationFrameDraft {
  private let liveController: AnimationController
  package let controller: AnimationController
  private let transactionCheckpoint: AnimationController.Checkpoint
  private let capturedResetEpoch: Int
  private var didCommit = false
  private var didDiscard = false

  fileprivate init(liveController: AnimationController) {
    let draftController = AnimationController(
      restoring: liveController.makeCheckpoint()
    )
    self.liveController = liveController
    controller = draftController
    transactionCheckpoint = draftController.beginFrameHeadTransaction()
    capturedResetEpoch = liveController.resetEpoch
  }

  package var frameDropEligibilityBlockers: Set<FrameDropEligibility.Blocker> {
    controller.frameDropEligibilityBlockers
  }

  package func commit() {
    precondition(!didCommit && !didDiscard)
    let completions = controller.finishFrameHeadTransaction(transactionCheckpoint)
    didCommit = true
    guard liveController.resetEpoch == capturedResetEpoch else {
      // The live controller was reset after this draft began. Publishing the
      // draft's pre-reset state would resurrect it, so the reset dominates:
      // abandon the draft (mirroring discard()) and drop its deferred
      // completions rather than firing them into a torn-down frame.
      return
    }
    liveController.publishCommittedState(
      from: controller,
      preservingConcurrentRegistrationsSince: transactionCheckpoint
    )
    liveController.dispatchOrDeferCommittedCompletions(completions)
  }

  package func discard() {
    precondition(!didCommit && !didDiscard)
    didDiscard = true
  }
}

extension AnimationController: AnimationRegistrationSink {
  package func registerAnimationBox(
    _ box: AnimationBox,
    payload: any Sendable
  ) {
    if let animation = payload as? Animation {
      registeredAnimations[box] = animation
    }
  }
}

extension AnimationController: AnimationCompletionSink {
  package func finishEmptyCompletionScope(batchID: AnimationBatchID) {
    let closures = takeCompletions(for: batchID)
    if isFrameHeadTransactionActive {
      deferredFrameHeadCompletions.append(contentsOf: closures)
    } else {
      dispatchOrDeferCommittedCompletions(closures)
    }
  }

  /// Parks the completions of batches the scheduler's latest-wins
  /// coalescing displaced before the frame drained (F117). A superseded
  /// batch's animations never retain it — its state writes rode the frame
  /// under the WINNING batch's ID — so without this park nothing would ever
  /// fire its `withAnimation` completion, and a live awaiter would hang.
  /// Parking with an immediate deadline fires it on the next tick, matching
  /// the semantics of a batch whose animations were superseded before they
  /// ran.
  package func parkSupersededBatchCompletions(
    _ batchIDs: [AnimationBatchID],
    at now: MonotonicInstant
  ) {
    for batchID in batchIDs {
      guard completions[batchID] != nil,
        batchRefCounts[batchID] == nil,
        pendingEmptyBatchCompletions[batchID] == nil
      else { continue }
      pendingEmptyBatchCompletions[batchID] = now
    }
  }

  package func registerCompletion(
    batchID: AnimationBatchID,
    barrier: AnimationCompletionBarrier = .logicallyComplete,
    closure: @escaping @MainActor @Sendable () -> Void
  ) {
    // Append the registration; it fires when the batch's matching ref count
    // hits zero (`.logicallyComplete` on the logical count, `.removed` on the
    // removed count). A batch keeps every registration made for it, so
    // `Transaction.addAnimationCompletion` can add several with their own
    // barriers and overlapping scopes that share a batch all fire.
    completions[batchID, default: []].append(
      AnimationCompletionRegistration(barrier: barrier, closure: closure)
    )
  }
}

extension AnimationController: AnimatableValueSink {
  /// The resolver's entry: boxes the site's data so it interpolates like
  /// every other animated value, and unboxes what the site presents.
  package func presentedAnimatableData<Data: VectorArithmetic>(
    for target: Data,
    at site: AnimatableValueSite,
    ownerNodeID: ViewNodeID?,
    transaction: TransactionSnapshot,
    reducesMotion: Bool
  ) -> Data {
    let key = AnimationKey(site: site)
    if let ownerNodeID {
      if valueSites.ownerNodeIDs[key] != ownerNodeID {
        valueSites.ownerNodeIDs[key] = ownerNodeID
      }
    } else if valueSites.ownerNodeIDs[key] != nil {
      valueSites.ownerNodeIDs.removeValue(forKey: key)
    }
    valueSites.noteResolve(of: key)
    if removalOwnsValue(at: key) {
      // A removal is still drawing the view that was at this site, and owns
      // the animation at the key. A view that resolves here now came back
      // during that removal. It evaluates with its own data and leaves the
      // animation alone. The frame head hands the animation to it when the
      // insertion plays (``continueRemovalValueSites``), and the body then
      // runs again from what the removal shows. If the insertion does not
      // play, the animation ends with the removal.
      valueSites.targets[key] = AnyAnimatable(AnimatableDataBox(target))
      valueSites.freshKeys.insert(key)
      return target
    }
    let presented = presentedValue(
      for: AnyAnimatable(AnimatableDataBox(target)),
      at: key,
      request: reducesMotion ? .disabled : transaction.animationRequest,
      batchID: transaction.animationBatchID,
      tracksVelocity: transaction.tracksVelocity,
      settlesAnimationInFlight: reducesMotion
    )
    return presented.unwrap(as: AnimatableDataBox<Data>.self)?.animatableData ?? target
  }
}

extension AnimationController: TransitionRegistrationSink {
  package func registerTransition(
    for identity: Identity,
    transition: any Sendable
  ) {
    registerTransition(for: identity, viewNodeID: nil, transition: transition)
  }

  package func registerTransition(
    for identity: Identity,
    viewNodeID: ViewNodeID?,
    transition: any Sendable
  ) {
    registerTransition(
      for: identity, viewNodeID: viewNodeID, declaringNodeID: nil, transition: transition)
  }

  package func registerTransition(
    for identity: Identity,
    viewNodeID: ViewNodeID?,
    declaringNodeID: ViewNodeID?,
    transition: any Sendable
  ) {
    guard let viewNodeID else { return }
    if let anyTransition = transition as? AnyTransition {
      transitions.registerPending(
        anyTransition, for: identity, viewNodeID: viewNodeID, declaringNodeID: declaringNodeID)
    }
  }
}
