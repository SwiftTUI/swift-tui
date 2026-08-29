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
  /// baseline slot (``AnimationPlacedTreeCapture/adoptionOffsets``).
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
    let result = PlacedAnimationOverlaySampling.sample(
      removingNodes: removingNodes,
      activeAnimations: activeAnimations,
      registeredAnimations: registeredAnimations,
      tree: tree,
      timestamp: timestamp,
      surfaceSize: surfaceSize,
      adoption: adoption
    )

    for (viewNodeID, state) in result.removalCustomStates {
      removingNodes[viewNodeID]?.customState = state
    }
    for (key, state) in result.activeAnimationCustomStates {
      activeAnimations[key]?.customState = state
    }
    for key in result.completedAnimationKeys {
      if let entry = activeAnimations.removeValue(forKey: key) {
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
        continue
      }
      if !entry.isLogicallyComplete {
        entry.isLogicallyComplete = true
        releaseLogicalBatch(entry.completionBatchID)
        removingNodes[viewNodeID] = entry
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
      case .property:
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

  private var removingIdentitySet: Set<Identity> {
    Set(removingNodes.values.map(\.identity))
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

  /// Prune registration-ledger entries for property curves that just completed
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
        "batchRefCounts": batchRefCounts.count,
        "pendingEmptyBatches": pendingEmptyBatchCompletions.count,
      ]
    )
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
  package var requiresContinuedAnimationFrames: Bool {
    if !activeAnimations.isEmpty
      || !pendingEmptyBatchCompletions.isEmpty
      || !deferredFrameHeadCompletions.isEmpty
      || !removingNodes.isEmpty
      || !transitionsByNodeID.isEmpty
      || !previousTransitionsByNodeID.isEmpty
      || !pendingTransitionsByNodeID.isEmpty
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
    previousTransitionsByNodeID = transitionsByNodeID
    previousTransitionIdentitiesByNodeID = transitionIdentitiesByNodeID
    pendingTransitionsByNodeID.removeAll(keepingCapacity: true)
    pendingTransitionIdentitiesByNodeID.removeAll(keepingCapacity: true)
  }

  /// Finishes the frame's `.transition()` collection.
  ///
  /// `reEvaluatedNodeIDs` is the set of ViewNodeIDs whose declarations were
  /// freshly re-evaluated this frame (the renderer threads
  /// ``ViewGraph/evaluatedNodeIDsThisFrame``). `nil` means "every live node was
  /// re-evaluated" (a full evaluation, and the shape a direct test drives),
  /// which prunes any registration not re-collected this frame.
  package func finishTransitionCollection(reEvaluatedNodeIDs: Set<ViewNodeID>? = nil) {
    // Merge newly registered transitions into the existing map so
    // that registrations for non-re-evaluated subtrees survive
    // across selective-evaluation frames.  Without this, a
    // PhaseAnimator-only tick would wipe every other subtree's
    // transition and the next removal couldn't find it.
    for (viewNodeID, transition) in pendingTransitionsByNodeID {
      transitionsByNodeID[viewNodeID] = transition
      transitionIdentitiesByNodeID[viewNodeID] =
        pendingTransitionIdentitiesByNodeID[viewNodeID]
    }

    // Prune registrations whose owner node was re-evaluated this frame but
    // declared no `.transition()` (its pending entry is absent). A live node
    // that drops its transition modifier — while keeping its ViewNodeID — would
    // otherwise retain the stale registration and mis-animate a *later*
    // removal. A node that was reused (not in `reEvaluatedNodeIDs`) is left
    // alone: the merge above preserved its registration and it did not re-run
    // its declaration this frame. `nil` treats the whole current map as
    // re-evaluated (full evaluation), so every un-re-collected entry is dropped.
    let staleNodeIDs: [ViewNodeID]
    if let reEvaluatedNodeIDs {
      staleNodeIDs = reEvaluatedNodeIDs.filter { pendingTransitionsByNodeID[$0] == nil }
    } else {
      staleNodeIDs = transitionsByNodeID.keys.filter { pendingTransitionsByNodeID[$0] == nil }
    }
    for viewNodeID in staleNodeIDs {
      transitionsByNodeID.removeValue(forKey: viewNodeID)
      transitionIdentitiesByNodeID.removeValue(forKey: viewNodeID)
    }
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
      && !transactionPlan.hasExplicitTransactions
      && transactionPlan.base.animationRequest.animationBoxIfAny == nil
      && transactionPlan.base.animationBatchID == nil
      && !transactionPlan.base.tracksVelocity
      && (graphAnimationInputToken == nil
        || graphAnimationInputToken == previousFrame.graphAnimationInputToken)
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
      liveNodeIDAccumulator: &newLiveNodeIDs,
      activeKeysByOwnerNodeID: activeKeysByOwnerNodeID
    )

    // Re-home registrations whose node id was aliased away by single-child
    // subtree re-stamping: a node-backed conditional branch child registers
    // under its own mint, but a one-element chain level absorbs its output
    // and the committed tree carries the absorber's stamp. Every channel
    // below — the occurrence diff, the insertion lookup, the adopted-slot
    // removal channel, and the live-node prune — keys on committed stamps,
    // so a registration left keyed to the aliased-away mint is invisible to
    // all of them: insertions never fire and branch-flip removals plan no
    // exit overlay. Moving it onto the stamp-owning id restores the
    // host-keyed registration the value-only fallback used to produce.
    for (nodeID, identity) in transitionIdentitiesByNodeID
    where !newLiveNodeIDs.contains(nodeID) {
      guard let liveNodeID = newNodeIDByIdentity[identity],
        liveNodeID != nodeID,
        transitionIdentitiesByNodeID[liveNodeID] == nil,
        let transition = transitionsByNodeID[nodeID]
      else { continue }
      transitionsByNodeID[liveNodeID] = transition
      transitionIdentitiesByNodeID[liveNodeID] = identity
      transitionsByNodeID.removeValue(forKey: nodeID)
      transitionIdentitiesByNodeID.removeValue(forKey: nodeID)
    }

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
    if !removingNodes.isEmpty {
      let supersededRemovals = removingNodes.filter { _, entry in
        newIdentities.contains(entry.identity)
      }
      for viewNodeID in supersededRemovals.keys {
        if let entry = removingNodes.removeValue(forKey: viewNodeID) {
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
    for identity in insertedIdentities {
      // Structural first-appearance guard: if the parent identity is
      // also freshly inserted, this view appeared as part of a bulk
      // mount, not a conditional toggle.
      if let parent = newParentByIdentity[identity],
        insertedIdentities.contains(parent)
      {
        continue
      }
      guard let viewNodeID = newNodeIDByIdentity[identity],
        let transition = transitionsByNodeID[viewNodeID]
      else { continue }
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
        previousTransitionsByNodeID[viewNodeID] != nil
      {
        continue
      }
      enqueueInsertionAnimation(
        identity: identity,
        viewNodeID: viewNodeID,
        transition: transition,
        snapshot: newSnapshots[identity] ?? .init(),
        transaction: newTransactionsByIdentity[identity]
          ?? transactionPlan.transaction(for: identity),
        timestamp: timestamp
      )
    }

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
        let previousRoot = previousTreeRoot,
        let previousNode = AnimationTreeQueries.findResolvedNode(
          in: previousRoot,
          viewNodeID: removedNodeID
        )
      else { continue }
      planRemovalOverlay(
        removedNodeID: removedNodeID,
        identity: previousNode.identity,
        transition: transition,
        previousRoot: previousRoot,
        newIdentities: newIdentities,
        matchedDestinationsByKey: matchedDestinationsByKey,
        transactionPlan: transactionPlan,
        timestamp: timestamp
      )
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
        let previousRoot = previousTreeRoot,
        AnimationTreeQueries.findResolvedNode(
          in: previousRoot,
          identity: registeredIdentity
        ) != nil
      else { continue }
      planRemovalOverlay(
        removedNodeID: nodeID,
        identity: registeredIdentity,
        transition: transition,
        previousRoot: previousRoot,
        newIdentities: newIdentities,
        matchedDestinationsByKey: matchedDestinationsByKey,
        transactionPlan: transactionPlan,
        timestamp: timestamp
      )
    }

    // Prune transition registrations for nodes that are no longer
    // in the live tree. Their registration was already copied into
    // previousTransitionsByNodeID at the start of this frame, so any
    // removal that needed it has already found it. Pruning prevents
    // unbounded growth of the map.
    transitionsByNodeID = transitionsByNodeID.filter { viewNodeID, _ in
      newLiveNodeIDs.contains(viewNodeID)
    }
    transitionIdentitiesByNodeID = transitionIdentitiesByNodeID.filter { viewNodeID, _ in
      newLiveNodeIDs.contains(viewNodeID)
    }

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
    let departedKeys = activeAnimations.keys.filter { key in
      !newIdentities.contains(key.identity)
        && !exitOverlayIdentities.contains(key.identity)
    }
    for key in departedKeys {
      guard let entry = activeAnimations.removeValue(forKey: key) else { continue }
      releaseBatch(
        entry.batchID,
        logicalAlreadyReleased: entry.isLogicallyReleased,
        firingCompletion: false
      )
    }
    if !slotVelocitySamplers.isEmpty {
      slotVelocitySamplers = slotVelocitySamplers.filter { newIdentities.contains($0.key.identity) }
    }

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
    transaction: TransactionSnapshot,
    timestamp: MonotonicInstant
  ) {
    let modifiers = transition.insertionModifiers()
    guard case .animate(let box) = transaction.animationRequest else {
      // No animation intent — snap to identity immediately.
      return
    }
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
      let offsetModifiers = TransitionModifiers(
        offsetX: modifiers.offsetX,
        offsetY: modifiers.offsetY,
        moveEdge: modifiers.moveEdge
      )
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
  }

  /// Plans one removal overlay: resolves the injection point, captures the
  /// departing subtree and its frozen placed bounds, supersedes in-flight
  /// animations on the injected identities, and records the `RemovalEntry`.
  /// Shared by both removal-detection channels — departed ViewNodeID
  /// occurrences and adopted-slot conditional removals (a registered identity
  /// leaving the identity set while its slot node survives).
  private func planRemovalOverlay(
    removedNodeID: ViewNodeID,
    identity: Identity,
    transition: AnyTransition,
    previousRoot: ResolvedNode,
    newIdentities: Set<Identity>,
    matchedDestinationsByKey: [MatchedGeometryKey: Identity],
    transactionPlan: FrameAnimationTransactionPlan,
    timestamp: MonotonicInstant
  ) {
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
    else { return }

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

    // Before clearing the injected subtree's active animations, peek
    // at any mid-flight opacity animation on the transition's
    // registered identity (or anywhere in the subtree) so the
    // removal can start from the displayed value instead of
    // snapping back to 1.0.  Must run before the filter below.
    let injectedIdentities = AnimationTreeQueries.collectIdentities(in: subtree)
    var initialOpacity: Double = 1.0
    let keyOnTarget = AnimationKey(identity: identity, slot: .opacity)
    if let existing = activeAnimations[keyOnTarget],
      let sampled = sample(existing, at: timestamp),
      let value = sampled.unwrap(as: Double.self)
    {
      initialOpacity = value
    } else {
      for sid in injectedIdentities {
        let k = AnimationKey(identity: sid, slot: .opacity)
        if let existing = activeAnimations[k],
          let sampled = sample(existing, at: timestamp),
          let value = sampled.unwrap(as: Double.self)
        {
          initialOpacity = value
          break
        }
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
    let removalTransaction = transactionForDepartedIdentity(
      identity,
      transactionPlan: transactionPlan
    )
    let completionBatchID = removalTransaction.animationBatchID.flatMap { batchID in
      completions[batchID] == nil ? nil : batchID
    }
    retainBatch(completionBatchID)

    let supersededEntries = activeAnimations.filter {
      injectedIdentities.contains($0.key.identity)
    }
    activeAnimations = activeAnimations.filter {
      !injectedIdentities.contains($0.key.identity)
    }
    for (_, entry) in supersededEntries {
      releaseBatch(entry.batchID, logicalAlreadyReleased: entry.isLogicallyReleased)
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
        : translatePlacedNodesByIdentity(tree: frozen, offsets: previousAdoptionOffsets)
    } else {
      placedSnapshot = nil
    }

    removingNodes[removedNodeID] = RemovalEntry(
      identity: identity,
      snapshot: subtree,
      parentIdentity: injectionParent,
      childIndex: previousChildIndexByIdentity[injectionTarget] ?? 0,
      transition: transition,
      animationBox: removalTransaction.animationRequest.animationBoxIfAny,
      startTime: timestamp,
      startOpacity: initialOpacity,
      completionBatchID: completionBatchID,
      placedSnapshot: placedSnapshot,
      matchedTravel: matchedTravel
    )
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
    let snapshot = AnimatableSnapshot.extract(from: node)
    let previous = previousSnapshots[node.identity]

    // Determine the effective transaction. A resolved node normally already
    // carries its frame-selected segment. Consulting the plan here also covers
    // controller-direct inputs and departed/reused transaction snapshots.
    //
    // A scoped modifier's placeholder (`restoresOuter`) inherits from the
    // nearest scope root's effective transaction — the transaction outside
    // the scope — instead of from its scoped resolved parent.
    let frameSegment = transactionPlan.segment(for: node.identity)
    let transaction =
      node.transactionSnapshot.scopeRole == .restoresOuter
      ? (scopeOuterTransaction ?? transaction)
      : transaction
    var effectiveTransaction = node.transactionSnapshot
    if effectiveTransaction.animationRequest == .inherit {
      // Metadata fields (`isContinuous`, custom key values) inherit with
      // the request; the node's own resolve-stamped values win per key.
      if let frameSegment {
        effectiveTransaction.animationRequest = frameSegment.animationRequest
        effectiveTransaction.animationBatchID = frameSegment.animationBatchID
        effectiveTransaction.isContinuous =
          effectiveTransaction.isContinuous || frameSegment.isContinuous
        effectiveTransaction.tracksVelocity =
          effectiveTransaction.tracksVelocity || frameSegment.tracksVelocity
        effectiveTransaction.customValues = frameSegment.customValues.merging(
          effectiveTransaction.customValues
        ) { _, node in node }
      } else {
        effectiveTransaction.animationRequest = transaction.animationRequest
        effectiveTransaction.animationBatchID = transaction.animationBatchID
        effectiveTransaction.isContinuous =
          effectiveTransaction.isContinuous || transaction.isContinuous
        effectiveTransaction.tracksVelocity =
          effectiveTransaction.tracksVelocity || transaction.tracksVelocity
        effectiveTransaction.customValues = transaction.customValues.merging(
          effectiveTransaction.customValues
        ) { _, node in node }
      }
    } else if effectiveTransaction.animationBatchID == nil {
      let isFrameSegmentBoundary =
        frameSegment.map { segment in
          segment.animationRequest == effectiveTransaction.animationRequest
            && segment.animationBatchID == nil
        } ?? false
      if !isFrameSegmentBoundary {
        effectiveTransaction.animationBatchID = transaction.animationBatchID
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
        liveNodeIDAccumulator: &liveNodeIDAccumulator,
        activeKeysByOwnerNodeID: activeKeysByOwnerNodeID
      )
    }
  }

  private func diffAndEnqueue(
    identity: Identity,
    viewNodeID: ViewNodeID?,
    previous: AnimatableSnapshot,
    current: AnimatableSnapshot,
    request: AnimationRequest,
    batchID: AnimationBatchID?,
    tracksVelocity: Bool,
    timestamp: MonotonicInstant
  ) {
    // Union of slot keys from both snapshots — a slot that appears
    // in only one snapshot is a "one side nil" change and snaps.
    var slots = Set(previous.values.keys)
    slots.formUnion(current.values.keys)

    for slot in slots {
      enqueueSlotChangeIfNeeded(
        identity: identity,
        viewNodeID: viewNodeID,
        slot: slot,
        previous: previous[slot],
        current: current[slot],
        request: request,
        batchID: batchID,
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
    // No change → nothing to do.
    guard previous != current else { return }

    let key = AnimationKey(identity: identity, slot: slot)

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
      let velocityChannelEnabled = AnimationVelocityConfiguration.isEnabled
      if let existing = activeAnimations[key],
        let sampled = sampleAdvancingCustomState(existing, at: timestamp)
      {
        effectiveFrom = sampled.value
        let outgoing = registeredAnimations[existing.animationBox]
        let incoming = registeredAnimations[box]
        let elapsed = existing.startTime.duration(to: timestamp)
        if outgoing?.isCustomCurve == true || incoming?.isCustomCurve == true {
          // Custom-curve retarget handoff.  Carry the sample-advanced custom
          // state into the replacement so a retargeting custom curve keeps
          // its per-key bookkeeping instead of resetting to an empty buffer
          // (011); query the outgoing curve's velocity hook (013); consult
          // the incoming curve's merge policy against the previously
          // registered animation (012).
          carriedCustomState = sampled.state
          _ = outgoing?.velocity(elapsed: elapsed, state: sampled.state)
          if let incoming, let outgoing {
            _ = incoming.shouldMerge(
              previous: outgoing,
              elapsed: elapsed,
              state: &carriedCustomState
            )
          }
        } else if velocityChannelEnabled,
          case .property(let oldFrom, let oldTo) = existing.kind,
          let outgoing,
          let progressVelocity = outgoing.velocity(
            elapsed: elapsed,
            state: sampled.state,
            initialVelocity: existing.initialVelocity
          ),
          let projection = AnyAnimatable.progressProjection(
            of: (from: oldFrom, to: oldTo),
            onto: (from: effectiveFrom, to: current)
          )
        {
          // Built-in retarget continuity (T4): the outgoing curve's progress
          // velocity along its own axis, re-expressed along the new segment's
          // axis so the replacement spring continues instead of restarting
          // at rest. Clamped to zero when the new axis is degenerate.
          let seeded = progressVelocity * projection
          initialVelocity = seeded.isFinite && abs(seeded) > 1e-6 ? seeded : nil
        }
        releaseBatch(existing.batchID, logicalAlreadyReleased: existing.isLogicallyReleased)
      } else {
        effectiveFrom = previous
        if velocityChannelEnabled,
          let sampler = slotVelocitySamplers[key],
          let sampled = sampler.progressVelocity(from: previous, to: current, at: timestamp),
          abs(sampled) > 1e-6
        {
          // The preceding `tracksVelocity` writes release into this spring.
          initialVelocity = sampled
        }
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

  private func retainBatch(_ batchID: AnimationBatchID?) {
    guard let batchID else { return }
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
          if let ownerViewNodeID = animation.ownerViewNodeID {
            interpolatedByNodeID[ownerViewNodeID, default: [:]][slot] = to
            interpolatedIdentityByNodeID[ownerViewNodeID] =
              animation.resolvedIdentity ?? key.identity
          } else {
            interpolatedByIdentity[key.identity, default: [:]][slot] = to
          }
          continue
        case .progressed(let progress):
          let value = AnimationPropertyValueApplication.interpolate(
            from: from,
            to: to,
            progress: progress
          )
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

    // Process removal entries: compute interpolated transition modifiers
    // and prepare them for injection back into the tree.
    var removalsToPurge: [ViewNodeID] = []
    var injectionsByParent: [Identity: [(childIndex: Int, snapshot: ResolvedNode)]] = [:]

    for (viewNodeID, entry) in removingNodes {
      // A placed-level removal (a captured `placedSnapshot`) whose curve is
      // registered is evaluated, custom-state-advanced, overlaid, and purged
      // solely by the placed overlay pass (`sampleRemovalOverlays`). Evaluating
      // the curve here too double-samples a stateful `CustomAnimation` once per
      // frame — the resolved tick and the placed overlay would each call
      // `evaluate` (016). Mirror the insertion-offset / insertion-scale /
      // matched-geometry placed scopes handled in the active-animation loop
      // above: keep the frame
      // ticking so the scheduler reaches the placed pass, but do not evaluate,
      // advance custom state, build modifiers, or purge here — the placed pass
      // owns the single evaluation and the completion/purge. The condition
      // mirrors `sampleRemovalOverlays`' ownership guards exactly, so removals
      // it does not own (no placed snapshot, no parent, or no registered curve)
      // still fall through to the resolved handling below.
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
        // A cached placed snapshot is still a live exit overlay. Its sampling
        // pass owns both the logical endpoint and the later removal barrier;
        // resolving must not advance the same entry first and collapse the two
        // criteria inside one committed frame.
        if entry.placedSnapshot != nil {
          redrawIdentities.insert(entry.identity)
          latestDeadline = timestamp.advanced(by: frameInterval)
          hasPendingWork = true
          continue
        }
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
    guard let viewNodeID else { return }
    if let anyTransition = transition as? AnyTransition {
      pendingTransitionsByNodeID[viewNodeID] = anyTransition
      pendingTransitionIdentitiesByNodeID[viewNodeID] = identity
    }
  }
}
