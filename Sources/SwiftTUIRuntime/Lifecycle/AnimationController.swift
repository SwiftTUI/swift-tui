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
  package private(set) var lastTickResult: AnimationTickResult = .init()

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

  /// Completion closures registered by ``withAnimation`` overloads.
  /// The controller fires and removes the entry once every animation
  /// (and every removal overlay) tagged with the batch ID has drained.
  private var completionClosures: [AnimationBatchID: @Sendable () -> Void] {
    get { completionLedger.completionClosures }
    set { completionLedger.completionClosures = newValue }
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
  private var deferredFrameHeadCompletions: [@Sendable () -> Void] {
    get { frameHead.deferredCompletions }
    set { frameHead.deferredCompletions = newValue }
  }
  private var lastFrameHeadCompletionCount: Int {
    get { frameHead.lastCompletionCount }
    set { frameHead.lastCompletionCount = newValue }
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
    for completion in completions {
      completion()
    }
  }

  fileprivate func finishFrameHeadTransaction(
    _ checkpoint: Checkpoint
  ) -> [@Sendable () -> Void] {
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
      lastTickResult: lastTickResult
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
    lastTickResult = checkpoint.lastTickResult
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
  package func capturePlacedTree(_ placed: PlacedNode) {
    let capture = AnimationPlacedTreeCapture.capture(placed)
    previousPlacedRoot = capture.root
    previousMatchedGeometryBounds = capture.matchedBounds
    previousMatchedKeyIdentities = capture.matchedIdentities
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
      registeredAnimationCount: registeredAnimations.count,
      completionClosureBatchIDs: Set(completionClosures.keys),
      batchRefCounts: batchRefCounts,
      pendingEmptyBatchCompletions: pendingEmptyBatchCompletions,
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

  /// Runs the placed-level animation pass after layout: injects any
  /// pending removal overlays and translates any active insertion
  /// offsets.  Called between place and semantics in the render
  /// pipeline.
  ///
  /// Overlays injected this way never flow through measure or place,
  /// so sibling layout is not disturbed when the removed view lived
  /// inside a VStack or other flow container.  They carry the
  /// transient flag, so semantics/focus/lifecycle skip them.
  ///
  /// Insertion offsets translate the bounds of in-tree placed nodes
  /// by an interpolated delta so `.transition(.move(edge:))` and
  /// friends work on intrinsic-layout leaves (where `applyValue`
  /// can't rewrite the layoutBehavior).
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
  package func placedAnimationOverlaySnapshot(
    for tree: PlacedNode,
    at timestamp: MonotonicInstant,
    surfaceSize: CellSize? = nil
  ) -> PlacedAnimationOverlaySnapshot {
    let result = PlacedAnimationOverlaySampling.sample(
      removingNodes: removingNodes,
      activeAnimations: activeAnimations,
      registeredAnimations: registeredAnimations,
      tree: tree,
      timestamp: timestamp,
      surfaceSize: surfaceSize
    )

    for (viewNodeID, state) in result.removalCustomStates {
      removingNodes[viewNodeID]?.customState = state
    }
    for (key, state) in result.activeAnimationCustomStates {
      activeAnimations[key]?.customState = state
    }
    for key in result.completedAnimationKeys {
      if let entry = activeAnimations.removeValue(forKey: key) {
        releaseBatch(entry.batchID)
      }
    }

    return result.snapshot
  }

  /// Number of insertion-offset animations currently in flight.
  /// Test hook so integration tests can pin the enqueue path
  /// without exposing the entire private map.
  package var activeInsertionOffsetCount: Int {
    activeAnimations.keys.lazy.filter { $0.scope == .insertionOffset }.count
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

  package var activePropertyAnimationIdentities: Set<Identity> {
    activeAnimations.keys.reduce(into: Set<Identity>()) { partial, key in
      if case .property = key.scope {
        partial.insert(key.identity)
      }
    }
  }

  private var removingIdentitySet: Set<Identity> {
    Set(removingNodes.values.map(\.identity))
  }

  /// The identities of every pending animation work item that needs
  /// retained-reuse suppression: active animations of any scope (property,
  /// insertion offset, matched geometry) plus in-flight removal transitions.
  ///
  /// Stranded empty-batch completion drains deliberately contribute NOTHING
  /// here: a pending drain is a controller-internal deadline that fires in
  /// `applyInterpolations` (the frame head runs on every frame shape,
  /// including elided and dropped frames), touches no tree state, and
  /// re-registers nothing — so no subtree needs to recompute for it.
  /// Classifying drains as identity-agnostic previously made the run loop
  /// fall back to FULL retained-reuse suppression plus forced root
  /// evaluation for the batch's entire nominal duration, so a tab-switch
  /// transition's empty `withAnimation` batch recomputed the whole tree on
  /// every frame of the switch burst (the multi-hundred-node `suppressed=`
  /// runs in the reuse trace, and the recompute latency behind the Life-tab
  /// presentation starvation).
  ///
  /// `nil` is reserved for pending work the controller genuinely cannot
  /// attribute (no such class exists today); the run loop keeps the
  /// full-suppression fallback for it.
  package var attributablePendingAnimationIdentities: Set<Identity>? {
    var identities = Set(activeAnimations.keys.map(\.identity))
    identities.formUnion(removingIdentitySet)
    return identities
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
    var completedBatches: [AnimationBatchID] = []
    var redrawIdentities: Set<Identity> = []
    var latestDeadline: MonotonicInstant = timestamp
    var hasPendingWork = false

    for (key, animation) in activeAnimations {
      guard case .property = animation.kind else {
        preconditionFailure("Pre-frame-head off-screen tick only supports property animations.")
      }
      guard let anim = registeredAnimations[animation.animationBox] else {
        keysToRemove.append(key)
        if let batchID = animation.batchID { completedBatches.append(batchID) }
        continue
      }

      let elapsed = animation.startTime.duration(to: timestamp)
      var state = animation.customState
      let evaluated = anim.evaluate(elapsed: elapsed, state: &state)
      activeAnimations[key]?.customState = state

      guard evaluated != nil else {
        keysToRemove.append(key)
        if let batchID = animation.batchID { completedBatches.append(batchID) }
        redrawIdentities.insert(key.identity)
        continue
      }

      redrawIdentities.insert(key.identity)
      latestDeadline = timestamp.advanced(by: frameInterval)
      hasPendingWork = true
    }

    for key in keysToRemove {
      activeAnimations.removeValue(forKey: key)
    }
    for batchID in completedBatches {
      releaseBatch(batchID)
    }

    let result = AnimationTickResult(
      hasPendingWork: hasPendingWork,
      nextDeadline: hasPendingWork ? latestDeadline : nil,
      redrawIdentities: redrawIdentities
    )
    lastTickResult = result
    return result
  }

  /// Occupancy reading for the profiling memory signal. Computed, so it stays
  /// outside the checkpoint totality contract.
  package var memoryMetricSnapshot: MemoryMetricSnapshot {
    MemoryMetricSnapshot(
      name: "AnimationController.activeAnimations",
      count: activeAnimations.count,
      detail: [
        "registered": registeredAnimations.count,
        "completions": completionClosures.count,
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
    if lastFrameHeadCompletionCount > 0 || !completionClosures.isEmpty
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

  package func finishTransitionCollection() {
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
  /// established that the canonical resolved tree is value-identical to the
  /// one last processed (a fully-reused resolve — zero nodes computed);
  /// this gate adds the controller-state half of the proof:
  ///
  /// - the transaction opens no animation batch, so no animation can start
  ///   and no stranded-batch drain is owed for it;
  /// - no active animations exist to retarget, supersede, or expire;
  /// - no removal overlays are pending;
  /// - a previous processed tree exists (baselines are recorded).
  ///
  /// Under those conditions the identity diff is empty, matched-geometry
  /// plans are empty (the key→identity maps are unchanged), the transition
  /// prune is a no-op (already pruned against the same live set), and the
  /// baseline stores would rewrite value-identical data — so skipping the
  /// full-tree walk changes nothing. `noteSkippedResolvedTreeProcessing`
  /// DEBUG-asserts the value-identity premise.
  package func canSkipResolvedTreeProcessing(
    transaction: TransactionSnapshot
  ) -> Bool {
    previousTreeRoot != nil
      && transaction.animationRequest.animationBoxIfAny == nil
      && activeAnimations.isEmpty
      && removingNodes.isEmpty
  }

  /// Number of frames whose resolved-tree processing was skipped by the
  /// F66 gate. Test hook: pins that the gate actually fires on fully-reused
  /// frames (a silently dead gate would pass every behavior test).
  package private(set) var resolvedTreeProcessingSkipCount = 0

  /// The skip-path counterpart of ``processResolvedTree``'s per-frame
  /// resets: clears the head completion count (nothing can fire on a
  /// skipped frame) and pins the caller's value-identity premise in DEBUG.
  package func noteSkippedResolvedTreeProcessing(resolved: ResolvedNode) {
    lastFrameHeadCompletionCount = 0
    resolvedTreeProcessingSkipCount += 1
    #if DEBUG
      if previousTreeRoot != resolved {
        assertionFailure(
          """
          processResolvedTree skipped for a resolved tree that differs from \
          the last processed one — the zero-computed-nodes premise does not \
          imply value identity here. First divergence: \
          \(previousTreeRoot.map {
            Self.debugFirstDivergence($0, resolved, path: "root")
          } ?? "no previous tree was processed")
          """
        )
      }
    #endif
  }

  #if DEBUG
    /// Walks two resolved trees in lockstep and names the first node path +
    /// field where `==` diverges — the F66 skip-premise assert's forensic
    /// payload, so a premise break names its divergent subtree instead of
    /// requiring a live reproduction to localize.
    package static func debugFirstDivergence(
      _ lhs: ResolvedNode,
      _ rhs: ResolvedNode,
      path: String
    ) -> String {
      if lhs.identity != rhs.identity { return "\(path): identity \(lhs.identity.path) vs \(rhs.identity.path)" }
      if lhs.structuralPath != rhs.structuralPath { return "\(path): structuralPath" }
      if lhs.structuralEdgeRole != rhs.structuralEdgeRole { return "\(path): structuralEdgeRole" }
      if lhs.entityIdentity != rhs.entityIdentity { return "\(path): entityIdentity" }
      if lhs.entityStructuralPath != rhs.entityStructuralPath { return "\(path): entityStructuralPath" }
      if lhs.declarationOwnerEdge != rhs.declarationOwnerEdge { return "\(path): declarationOwnerEdge" }
      if lhs.kind != rhs.kind { return "\(path): kind \(lhs.kind) vs \(rhs.kind)" }
      if !ResolvedNode.typeDiscriminatorsCompatible(lhs.typeDiscriminator, rhs.typeDiscriminator) {
        return "\(path): typeDiscriminator"
      }
      if lhs.environmentSnapshot != rhs.environmentSnapshot { return "\(path): environmentSnapshot" }
      if lhs.transactionSnapshot != rhs.transactionSnapshot { return "\(path): transactionSnapshot" }
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
      if lhs.supportsRetainedReuse != rhs.supportsRetainedReuse { return "\(path): supportsRetainedReuse" }
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
    transaction: TransactionSnapshot,
    timestamp: MonotonicInstant
  ) {
    lastFrameHeadCompletionCount = 0
    // If the incoming transaction carries an animation box, make sure
    // the controller has the concrete Animation registered.  In normal
    // flow ``DefaultRenderer.register(animation:)`` already registered
    // it at withAnimation-time, but guard here in case the caller
    // constructed the transaction directly.
    if case .animate(let box) = transaction.animationRequest,
      registeredAnimations[box] == nil
    {
      // Box without registration — tick sampling will no-op for this
      // batch but the controller will still record snapshots so
      // future changes can animate.
    }

    var newSnapshots: [Identity: AnimatableSnapshot] = [:]
    var newParentByIdentity: [Identity: Identity] = [:]
    var newChildIndexByIdentity: [Identity: Int] = [:]
    var newMatchedKeysByIdentity: [Identity: MatchedGeometryKey] = [:]
    var newNodeIDByIdentity: [Identity: ViewNodeID] = [:]
    var newLiveNodeIDs: Set<ViewNodeID> = []
    processNode(
      node,
      parentIdentity: nil,
      childIndex: 0,
      transaction: transaction,
      timestamp: timestamp,
      snapshotAccumulator: &newSnapshots,
      parentAccumulator: &newParentByIdentity,
      childIndexAccumulator: &newChildIndexByIdentity,
      matchedKeyAccumulator: &newMatchedKeysByIdentity,
      nodeIDAccumulator: &newNodeIDByIdentity,
      liveNodeIDAccumulator: &newLiveNodeIDs
    )

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
    let removedIdentities = resolvedDiff.removedIdentities

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
        removingNodes.removeValue(forKey: viewNodeID)
      }
    }

    // Matched-geometry detection.  A match fires when the current
    // frame's (identity, key) mapping differs from the previous
    // frame's — regardless of whether either identity is newly
    // inserted.  Both "swap via reorder" and "swap via if/else"
    // cases are handled by comparing previous vs new key→identity
    // maps.  Collect the set of keys that matched so the
    // counterpart removal/transition can be skipped.
    let matchedGeometryPlans = AnimationResolvedTreeDiffing.matchedGeometryPlans(
      newMatchedKeysByIdentity: newMatchedKeysByIdentity,
      previousMatchedKeyIdentities: previousMatchedKeyIdentities,
      previousMatchedGeometryBounds: previousMatchedGeometryBounds,
      transaction: transaction
    )
    let matchedKeysConsumedByMatch = matchedGeometryPlans.consumedKeys
    for plan in matchedGeometryPlans.animations {
      let matchedKey = AnimationKey(
        identity: plan.identity, scope: .matchedGeometry
      )
      if let existing = activeAnimations[matchedKey] {
        releaseBatch(existing.batchID)
      }
      retainBatch(plan.batchID)
      activeAnimations[matchedKey] = ActiveAnimation(
        kind: .matchedGeometry(fromBounds: plan.fromBounds),
        animationBox: plan.animationBox,
        startTime: timestamp,
        batchID: plan.batchID
      )
    }

    // Process insertions: kick off willAppear -> identity animations.
    // Skip insertions that are part of a matched-geometry swap —
    // those use the matched-geometry pathway and shouldn't fire a
    // redundant willAppear transition.
    //
    // Also skip structural first-appearances: when an identity's
    // parent was also just inserted, the whole subtree appeared
    // because a container was mounted (e.g. tab switch), NOT because
    // a conditional toggled inside withAnimation.  Playing insertion
    // transitions for these would cause spurious fade-ins whenever a
    // PhaseAnimator or other continuous animation shares the frame
    // transaction.  This matches SwiftUI, which only fires
    // .transition() when the view's conditional presence changes.
    for identity in insertedIdentities {
      if let key = newMatchedKeysByIdentity[identity],
        matchedKeysConsumedByMatch.contains(key)
      {
        continue
      }
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
      enqueueInsertionAnimation(
        identity: identity,
        transition: transition,
        snapshot: newSnapshots[identity] ?? .init(),
        transaction: transaction,
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
    for identity in removedIdentities {
      guard let previousRoot = previousTreeRoot,
        let previousNode = AnimationTreeQueries.findResolvedNode(
          in: previousRoot,
          identity: identity
        ),
        let removedNodeID = previousNode.viewNodeID,
        removingNodes[removedNodeID] == nil
      else { continue }

      // If the removed identity's matched-geometry key was
      // consumed by a match on this frame, the counterpart insertion
      // already owns the visual transition.  Skip the removal
      // overlay so the old view just disappears.
      if let removedConfig = previousNode.matchedGeometry,
        matchedKeysConsumedByMatch.contains(removedConfig.key)
      {
        continue
      }
      // Removal look-up uses the PREVIOUS frame's registrations: the
      // disappearing view's `.transition()` modifier isn't evaluated in
      // the current frame (its branch is gone), so `transitionsByNodeID`
      // no longer contains an entry for it.  The previous frame captured
      // the registration while the view was still present.
      guard let transition = previousTransitionsByNodeID[removedNodeID] else {
        continue
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
      else { continue }

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
      // insertion-offset animations, and matched-geometry animations are
      // all swept together.  Any withAnimation completion closures ref-
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
      let supersededEntries = activeAnimations.filter {
        injectedIdentities.contains($0.key.identity)
      }
      activeAnimations = activeAnimations.filter {
        !injectedIdentities.contains($0.key.identity)
      }
      for (_, entry) in supersededEntries {
        releaseBatch(entry.batchID)
      }

      // If a previous placed tree is cached, look up the frozen
      // placed subtree for the same identity so the overlay can be
      // injected post-layout (draw-only, no layout-shift).
      let placedSnapshot: PlacedNode?
      if let previousPlacedRoot {
        placedSnapshot = AnimationTreeQueries.findPlacedSubtree(
          in: previousPlacedRoot,
          identity: injectionTarget
        )
      } else {
        placedSnapshot = nil
      }

      removingNodes[removedNodeID] = RemovalEntry(
        identity: identity,
        snapshot: subtree,
        parentIdentity: injectionParent,
        childIndex: previousChildIndexByIdentity[injectionTarget] ?? 0,
        transition: transition,
        animationBox: transaction.animationRequest.animationBoxIfAny,
        startTime: timestamp,
        startOpacity: initialOpacity,
        placedSnapshot: placedSnapshot
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
      releaseBatch(entry.batchID, firingCompletion: false)
    }

    previousSnapshots = newSnapshots
    previousIdentities = newIdentities
    previousTreeRoot = node
    previousParentByIdentity = newParentByIdentity
    previousChildIndexByIdentity = newChildIndexByIdentity

    // Drain stranded completions.  Any batch that has a registered
    // completion closure but no live ref count (no property, no
    // removal, no insertion, no matched-geometry retained it) will
    // otherwise leak forever — and any `withAnimation` caller that
    // await-ed on its completion (like ``PhaseAnimator``) would hang.
    // Schedule a drain for each such batch here; the drain fires
    // after the animation's nominal duration in ``applyInterpolations``.
    scheduleStrandedBatchDrains(
      transaction: transaction,
      timestamp: timestamp
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
      completionClosures: completionClosures,
      pendingEmptyBatchCompletions: pendingEmptyBatchCompletions
    )

    switch decision {
    case .ignore:
      return
    case .schedule(let batchID, let deadline):
      pendingEmptyBatchCompletions[batchID] = deadline
    case .dropCompletion(let batchID):
      completionClosures.removeValue(forKey: batchID)
    }
  }

  private func enqueueInsertionAnimation(
    identity: Identity,
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
      if let existing = activeAnimations[key] { releaseBatch(existing.batchID) }
      retainBatch(batchID)
      activeAnimations[key] = ActiveAnimation(
        kind: .property(
          from: effectiveFrom,
          to: AnyAnimatable(target)
        ),
        animationBox: box,
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
        releaseBatch(existing.batchID)
      }
      retainBatch(batchID)
      activeAnimations[offsetKey] = ActiveAnimation(
        kind: .insertionOffset(from: offsetModifiers),
        animationBox: box,
        startTime: timestamp,
        batchID: batchID
      )
    }
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
    timestamp: MonotonicInstant,
    snapshotAccumulator: inout [Identity: AnimatableSnapshot],
    parentAccumulator: inout [Identity: Identity],
    childIndexAccumulator: inout [Identity: Int],
    matchedKeyAccumulator: inout [Identity: MatchedGeometryKey],
    nodeIDAccumulator: inout [Identity: ViewNodeID],
    liveNodeIDAccumulator: inout Set<ViewNodeID>
  ) {
    let snapshot = AnimatableSnapshot.extract(from: node)
    let previous = previousSnapshots[node.identity]

    // Determine the effective animation request: child transactions
    // override parent; otherwise inherit.
    let effectiveRequest = effectiveAnimationRequest(
      node: node,
      parent: transaction
    )

    if let previous {
      // A child transaction's .animate overrides inherit the parent's
      // batch ID when its own is nil; that way `.animation(_:value:)`
      // subtree overrides don't lose the `withAnimation` completion
      // association.
      let effectiveBatchID =
        node.transactionSnapshot.animationBatchID ?? transaction.animationBatchID
      diffAndEnqueue(
        identity: node.identity,
        viewNodeID: node.viewNodeID,
        previous: previous,
        current: snapshot,
        request: effectiveRequest,
        batchID: effectiveBatchID,
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
      matchedKeyAccumulator[node.identity] = config.key
    }
    if let viewNodeID = node.viewNodeID {
      nodeIDAccumulator[node.identity] = viewNodeID
      liveNodeIDAccumulator.insert(viewNodeID)
    }

    for (index, child) in node.children.enumerated() {
      processNode(
        child,
        parentIdentity: node.identity,
        childIndex: index,
        transaction: transaction,
        timestamp: timestamp,
        snapshotAccumulator: &snapshotAccumulator,
        parentAccumulator: &parentAccumulator,
        childIndexAccumulator: &childIndexAccumulator,
        matchedKeyAccumulator: &matchedKeyAccumulator,
        nodeIDAccumulator: &nodeIDAccumulator,
        liveNodeIDAccumulator: &liveNodeIDAccumulator
      )
    }
  }

  private func effectiveAnimationRequest(
    node: ResolvedNode,
    parent: TransactionSnapshot
  ) -> AnimationRequest {
    // Node's transaction snapshot carries the most-specific intent.
    switch node.transactionSnapshot.animationRequest {
    case .inherit:
      return parent.animationRequest
    case .disabled, .animate:
      return node.transactionSnapshot.animationRequest
    }
  }

  private func diffAndEnqueue(
    identity: Identity,
    viewNodeID: ViewNodeID?,
    previous: AnimatableSnapshot,
    current: AnimatableSnapshot,
    request: AnimationRequest,
    batchID: AnimationBatchID?,
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
    timestamp: MonotonicInstant
  ) {
    // No change → nothing to do.
    guard previous != current else { return }

    let key = AnimationKey(identity: identity, slot: slot)

    switch request {
    case .inherit, .disabled:
      if let superseded = activeAnimations.removeValue(forKey: key) {
        releaseBatch(superseded.batchID)
      }

    case .animate(let box):
      guard let previous, let current else {
        // One side nil — cannot interpolate, snap.
        if let superseded = activeAnimations.removeValue(forKey: key) {
          releaseBatch(superseded.batchID)
        }
        return
      }

      // Retarget: if an animation already exists, sample its current
      // value and use it as the new `from` — matches the existing
      // mid-flight retarget behavior.
      let effectiveFrom: AnyAnimatable
      if let existing = activeAnimations[key],
        let sampled = sample(existing, at: timestamp)
      {
        effectiveFrom = sampled
        releaseBatch(existing.batchID)
      } else {
        effectiveFrom = previous
      }

      retainBatch(batchID)
      activeAnimations[key] = ActiveAnimation(
        kind: .property(from: effectiveFrom, to: current),
        animationBox: box,
        ownerViewNodeID: viewNodeID,
        startTime: timestamp,
        batchID: batchID
      )
    }
  }

  private func retainBatch(_ batchID: AnimationBatchID?) {
    guard let batchID else { return }
    batchRefCounts[batchID, default: 0] += 1
  }

  /// `firingCompletion: false` is the departed-identity prune's arm: when the
  /// LAST retainer of a batch left the live tree untransitioned, its
  /// completion's awaiter died with the owning subtree, so the closure is
  /// dropped rather than fired (firing would double-resume a finished
  /// continuation — see ``requiresContinuedAnimationFrames``). If a live
  /// animation in the same batch releases last instead, the completion fires
  /// normally through the default arm.
  private func releaseBatch(
    _ batchID: AnimationBatchID?,
    firingCompletion: Bool = true
  ) {
    guard let batchID, let count = batchRefCounts[batchID] else { return }
    let newCount = count - 1
    if newCount <= 0 {
      batchRefCounts.removeValue(forKey: batchID)
      if let closure = completionClosures.removeValue(forKey: batchID),
        firingCompletion
      {
        fireOrDeferCompletion(closure)
      }
    } else {
      batchRefCounts[batchID] = newCount
    }
  }

  private func fireOrDeferCompletion(_ completion: @escaping @Sendable () -> Void) {
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
      lastTickResult = AnimationTickResult()
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
    var interpolatedByIdentity: [Identity: [AnimatableSlot: AnyAnimatable]] = [:]

    // Record the batches that completed animations belong to so we can
    // release their ref counts in a second pass (after this iteration
    // closes).  Releasing during the iteration would mutate
    // activeAnimations and invalidate the dictionary traversal.
    var completedBatches: [AnimationBatchID] = []

    // Walk every active animation regardless of scope.  Property
    // scopes are sampled here and write into ``interpolated`` for
    // application by ``applyInterpolatedValues`` below.  Placed-level
    // scopes (insertion offset, matched geometry) only need the run
    // loop to keep ticking on this pass — their actual evaluation +
    // translation runs inside ``applyPlacedOverlays``, and we must
    // not double-evaluate stateful CustomAnimation curves here.
    for (key, animation) in activeAnimations {
      switch animation.kind {
      case .property(let from, let to):
        guard let anim = registeredAnimations[animation.animationBox] else {
          keysToRemove.append(key)
          if let batchID = animation.batchID { completedBatches.append(batchID) }
          continue
        }
        let elapsed = animation.startTime.duration(to: timestamp)
        var state = animation.customState
        let evaluated = anim.evaluate(elapsed: elapsed, state: &state)
        // Store the updated custom state back on the active animation
        // so the next tick carries user bookkeeping forward.
        activeAnimations[key]?.customState = state

        let slot = AnimationPropertyValueApplication.propertySlot(for: key)
        guard let progress = evaluated else {
          // Animation complete — snap to final value and purge.
          if let ownerViewNodeID = animation.ownerViewNodeID {
            interpolatedByNodeID[ownerViewNodeID, default: [:]][slot] = to
          } else {
            interpolatedByIdentity[key.identity, default: [:]][slot] = to
          }
          keysToRemove.append(key)
          if let batchID = animation.batchID { completedBatches.append(batchID) }
          redrawIdentities.insert(key.identity)
          continue
        }
        let value = AnimationPropertyValueApplication.interpolate(
          from: from,
          to: to,
          progress: progress
        )
        if let ownerViewNodeID = animation.ownerViewNodeID {
          interpolatedByNodeID[ownerViewNodeID, default: [:]][slot] = value
        } else {
          interpolatedByIdentity[key.identity, default: [:]][slot] = value
        }
        redrawIdentities.insert(key.identity)
        latestDeadline = timestamp.advanced(by: frameInterval)
        hasPendingWork = true

      case .insertionOffset, .matchedGeometry:
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
    // ``releaseBatch`` fires the matching completion closure when the
    // ref count hits zero.
    for batchID in completedBatches {
      releaseBatch(batchID)
    }

    // Process removal entries: compute interpolated transition modifiers
    // and prepare them for injection back into the tree.
    var removalsToPurge: [ViewNodeID] = []
    var injectionsByParent: [Identity: [(childIndex: Int, snapshot: ResolvedNode)]] = [:]

    for (viewNodeID, entry) in removingNodes {
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
          modifiers = AnimationTransitionOverlay.interpolatedRemovalModifiers(
            from: entry.startOpacity,
            to: entry.transition.removalModifiers(),
            progress: progress,
            surfaceSize: surfaceSize
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
        removalsToPurge.append(viewNodeID)
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
      removingNodes.removeValue(forKey: viewNodeID)
    }

    // Apply interpolated values for in-tree animations.
    var appliedIdentities: Set<Identity> = []
    tree = AnimationPropertyValueApplication.applyInterpolatedValues(
      tree: tree,
      interpolatedByNodeID: interpolatedByNodeID,
      interpolatedByIdentity: interpolatedByIdentity,
      appliedIdentities: &appliedIdentities
    )
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
        if let closure = completionClosures.removeValue(forKey: batchID) {
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

  /// Samples the current interpolated value of a property-scoped
  /// animation at `timestamp`.  Returns `nil` for non-property kinds —
  /// the placed-level scopes (insertion offset, matched geometry)
  /// produce translation deltas rather than ``AnyAnimatable`` values
  /// and don't participate in the property retarget path.
  ///
  /// The custom-state writeback is intentionally discarded: the only
  /// caller (``sampleCurrentValue(for:at:)`` from the retarget /
  /// insertion paths) immediately releases the existing animation
  /// after sampling, so the advanced state would be thrown away on
  /// the next line anyway.  If a future caller needs to keep the
  /// animation alive after sampling, this helper should be split.
  private func sample(
    _ animation: ActiveAnimation,
    at timestamp: MonotonicInstant
  ) -> AnyAnimatable? {
    guard case .property(let from, let to) = animation.kind else {
      return nil
    }
    guard let anim = registeredAnimations[animation.animationBox] else {
      return nil
    }
    let elapsed = animation.startTime.duration(to: timestamp)
    var state = animation.customState
    guard let progress = anim.evaluate(elapsed: elapsed, state: &state) else {
      return to
    }
    return AnimationPropertyValueApplication.interpolate(
      from: from,
      to: to,
      progress: progress
    )
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
    lastTickResult = .init()
  }
}

@MainActor
package final class AnimationFrameDraft {
  private let liveController: AnimationController
  package let controller: AnimationController
  private let transactionCheckpoint: AnimationController.Checkpoint
  private var didCommit = false
  private var didDiscard = false

  fileprivate init(liveController: AnimationController) {
    let draftController = AnimationController(
      restoring: liveController.makeCheckpoint()
    )
    self.liveController = liveController
    controller = draftController
    transactionCheckpoint = draftController.beginFrameHeadTransaction()
  }

  package var frameDropEligibilityBlockers: Set<FrameDropEligibility.Blocker> {
    controller.frameDropEligibilityBlockers
  }

  package func commit() {
    precondition(!didCommit && !didDiscard)
    let completions = controller.finishFrameHeadTransaction(transactionCheckpoint)
    liveController.publishCommittedState(
      from: controller,
      preservingConcurrentRegistrationsSince: transactionCheckpoint
    )
    didCommit = true
    for completion in completions {
      completion()
    }
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
      guard completionClosures[batchID] != nil,
        batchRefCounts[batchID] == nil,
        pendingEmptyBatchCompletions[batchID] == nil
      else { continue }
      pendingEmptyBatchCompletions[batchID] = now
    }
  }

  package func registerCompletion(
    batchID: AnimationBatchID,
    closure: @escaping @Sendable () -> Void
  ) {
    // Store the closure; it fires when the batch's ref count hits zero
    // in ``releaseBatch``.  Registering a second closure for the same
    // batch ID replaces the first, matching SwiftUI's last-writer-wins
    // behavior when overlapping ``withAnimation`` calls collide.
    completionClosures[batchID] = closure
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
