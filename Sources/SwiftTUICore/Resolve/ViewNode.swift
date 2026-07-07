@MainActor
package final class ViewNode {
  package let viewNodeID: ViewNodeID
  package let identity: Identity
  package weak var invalidator: (any Invalidating)? {
    didSet { recordCheckpointMutation() }
  }
  package weak var ownerGraph: ViewGraph? {
    didSet { recordCheckpointMutation() }
  }
  package weak var parent: ViewNode? {
    didSet { recordCheckpointMutation() }
  }
  /// The node whose body resolution evaluated this node, captured at
  /// outermost `beginEvaluation`. Bridges island seams in the upward
  /// invalidation walks: capture-hosted content (scoped content payloads, AnyView
  /// shells, `.id`-re-rooted subtrees) is reachable from its host only
  /// through body resolution, not `parent` links, so a dirty island could
  /// not reach its host spine and the spine was wrongly retained-reused
  /// over it (the divergent-identity orphaning bug). Past the seam the walk
  /// sets `hasStaleIslandDescendant` (reuse denial) rather than clearing
  /// snapshot freshness — see `invalidateCachedSnapshots(startingAt:)`.
  /// Never cleared when a frontier evaluator re-runs outside an enclosing
  /// resolution (`ViewNodeContext.current == nil` there); weak, so a
  /// vanished host degrades to the old walk-stops-here behavior.
  package private(set) weak var evaluationHost: ViewNode? {
    didSet { recordCheckpointMutation() }
  }

  /// Reuse/freshness gating, grouped so checkpoint/restore move it as a unit
  /// (see ``ReuseState`` in ViewNodeFieldGroups.swift). The three flags below
  /// are computed forwarders preserving their names and visibility.
  private var reuseState = ReuseState() {
    didSet { recordCheckpointMutation() }
  }

  /// Set when a node behind an island seam below this node was dirtied or
  /// re-applied; consumed only by `canReuse`, so retained reuse cannot skip
  /// the body re-resolve that re-captures the island content by value.
  /// Cleared by `apply(resolved:children:)` (the body re-run that produced
  /// the apply re-resolved everything below, islands included). Kept
  /// separate from `isCommittedSnapshotFresh` deliberately: freshness
  /// drives `snapshot()`'s rebuild-from-live-children, which cannot span an
  /// island seam — clearing it above a seam truncates the rebuilt tree.
  package private(set) var hasStaleIslandDescendant: Bool {
    get { reuseState.hasStaleIslandDescendant }
    set { reuseState.hasStaleIslandDescendant = newValue }
  }

  /// The most-recently-committed `ResolvedNode` for this node.
  ///
  /// This is the single source of truth for the per-node render-tree
  /// state that used to live in ~14 scattered mirror fields (`kind`,
  /// `layoutBehavior`, `drawMetadata`, and so on).  Those accessors still
  /// exist as computed properties that forward to `committed`, so
  /// external readers see the same API they did before Item 6.
  ///
  /// Two invariants to be aware of:
  ///
  /// 1. `committed.children` holds the child `ResolvedNode`s passed to
  ///    the most recent `apply(resolved:children:)`.  It may go stale
  ///    between commits — if a descendant is re-applied, the parent's
  ///    `committed.children` is not automatically updated.
  ///    `isCommittedSnapshotFresh` tracks that.
  /// 2. `committed.identity` plays the role of the old
  ///    `resolvedIdentity` field: it's the identity the resolved tree
  ///    was built with, which may differ from `self.identity` when a
  ///    registration alias remaps identity during resolve.
  package private(set) var committed: ResolvedNode {
    didSet { recordCheckpointMutation() }
  }

  /// Whether `committed.children` still reflects the current state of
  /// descendant `ViewNode`s.
  ///
  /// Flipped `false` when any descendant is dirtied or re-applied (via
  /// `invalidateCachedSnapshotUpward` / `invalidateAncestorCachedSnapshots`).
  /// Flipped `true` by `apply(resolved:children:)` and by successful
  /// `snapshot()` rebuilds.
  ///
  /// Also doubles as the "have I been committed at least once" flag —
  /// `init` leaves it `false` until the first `apply`, so `canReuse`
  /// correctly refuses to reuse an untouched node.
  private var isCommittedSnapshotFresh: Bool {
    get { reuseState.isCommittedSnapshotFresh }
    set { reuseState.isCommittedSnapshotFresh = newValue }
  }

  package private(set) var children: [ViewNode] {
    didSet { recordCheckpointMutation() }
  }

  /// Retained per-node state, grouped so checkpoint/restore move it as a unit
  /// (see ``PersistentState`` in ViewNodeFieldGroups.swift). The five fields are
  /// computed forwarders preserving their names and `package private(set)`.
  private var persistentState = PersistentState() {
    didSet { recordCheckpointMutation() }
  }

  package private(set) var stateSlots: [Int: AnyStateSlot] {
    get { persistentState.stateSlots }
    set { persistentState.stateSlots = newValue }
  }
  package private(set) var dependencies: DependencySet {
    get { persistentState.dependencies }
    set { persistentState.dependencies = newValue }
  }
  package private(set) var lifecycleState: NodeLifecycleState {
    get { persistentState.lifecycleState }
    set { persistentState.lifecycleState = newValue }
  }
  package private(set) var registeredHandlers: NodeHandlers {
    get { persistentState.registeredHandlers }
    set { persistentState.registeredHandlers = newValue }
  }

  package var isDirty: Bool {
    get { reuseState.isDirty }
    set { reuseState.isDirty = newValue }
  }

  /// Per-frame working set, grouped into a value sub-struct so checkpoint and
  /// restore move it as a unit (see ``FrameState`` in ViewNodeFieldGroups.swift).
  /// The eight fields below are computed forwarders preserving their original
  /// names and visibility; the reconciler is unchanged.
  private var frameState = FrameState() {
    didSet { recordCheckpointMutation() }
  }

  package var wasPresentAtFrameStart: Bool {
    get { frameState.wasPresentAtFrameStart }
    set { frameState.wasPresentAtFrameStart = newValue }
  }
  package var entityDisplacedOccupantFrameID: UInt64 {
    get { frameState.entityDisplacedOccupantFrameID }
    set { frameState.entityDisplacedOccupantFrameID = newValue }
  }
  /// True when this node was freshly minted this frame after its identity
  /// slot's prior occupant was displaced by a different entity (an explicit-id
  /// value churn). The churn-detection predicate in `ExactIdentityModifier`
  /// keys on `wasPresentAtFrameStart`-style rebinding, which a displacement
  /// mint never satisfies — this is the graph-side signal that replaces it.
  package var hasEntityDisplacedOccupantThisFrame: Bool {
    frameState.entityDisplacedOccupantFrameID != 0
      && frameState.entityDisplacedOccupantFrameID == frameState.preparedFrameID
  }

  /// Whether this node is currently inside a `beginEvaluation` /
  /// `finishEvaluation` pair (its body resolution is on the stack).
  package var isEvaluating: Bool {
    evaluationDepth > 0
  }
  package var wasVisitedThisFrame: Bool {
    get { frameState.wasVisitedThisFrame }
    set { frameState.wasVisitedThisFrame = newValue }
  }
  package var previousChildrenIdentities: [Identity] {
    get { frameState.previousChildrenIdentities }
    set { frameState.previousChildrenIdentities = newValue }
  }
  package var previousLifecycleMetadata: LifecycleMetadata {
    get { frameState.previousLifecycleMetadata }
    set { frameState.previousLifecycleMetadata = newValue }
  }
  package var bodyStateSlotCount: Int? {
    get { frameState.bodyStateSlotCount }
    set { frameState.bodyStateSlotCount = newValue }
  }
  package var currentBodyStateSlotCount: Int {
    get { frameState.currentBodyStateSlotCount }
    set { frameState.currentBodyStateSlotCount = newValue }
  }
  package private(set) var pendingChangeHandlerIDs: [String] {
    get { persistentState.pendingChangeHandlerIDs }
    set { persistentState.pendingChangeHandlerIDs = newValue }
  }

  private let dependencyTracker: DependencyTracker
  /// Cross-frame internal bookkeeping, grouped so checkpoint/restore move it as
  /// a unit (see ``EvaluationState`` in ViewNodeFieldGroups.swift). The five
  /// fields below are computed forwarders preserving their original names.
  private var evaluationState = EvaluationState() {
    didSet { recordCheckpointMutation() }
  }

  private var registrationCaptureDepth: Int {
    get { evaluationState.registrationCaptureDepth }
    set { evaluationState.registrationCaptureDepth = newValue }
  }
  private var runtimeRegistrationMutationGeneration: UInt64 {
    get { evaluationState.runtimeRegistrationMutationGeneration }
    set { evaluationState.runtimeRegistrationMutationGeneration = newValue }
  }
  private var evaluationDepth: Int {
    get { evaluationState.evaluationDepth }
    set { evaluationState.evaluationDepth = newValue }
  }
  private var hasCommittedPresence: Bool {
    get { evaluationState.hasCommittedPresence }
    set { evaluationState.hasCommittedPresence = newValue }
  }
  private var suppressesStructuralLifecycle: Bool {
    get { evaluationState.suppressesStructuralLifecycle }
    set { evaluationState.suppressesStructuralLifecycle = newValue }
  }
  package var focusPresentationInertSlotIdentities: Set<Identity> {
    evaluationState.focusPresentationInertSlotIdentities
  }
  package var focusPresentationValueVerifiedSlotIdentities: Set<Identity> {
    evaluationState.focusPresentationValueVerifiedSlotIdentities
  }
  private var nextChangeModifierOrdinal: Int {
    get { frameState.nextChangeModifierOrdinal }
    set { frameState.nextChangeModifierOrdinal = newValue }
  }
  private var nextNavigationDestinationModifierOrdinal: Int {
    get { frameState.nextNavigationDestinationModifierOrdinal }
    set { frameState.nextNavigationDestinationModifierOrdinal = newValue }
  }
  private var nextTaskModifierOrdinal: Int {
    get { frameState.nextTaskModifierOrdinal }
    set { frameState.nextTaskModifierOrdinal = newValue }
  }
  private var preparedFrameID: UInt64 {
    get { frameState.preparedFrameID }
    set { frameState.preparedFrameID = newValue }
  }
  private var visitedFrameID: UInt64 {
    get { frameState.visitedFrameID }
    set { frameState.visitedFrameID = newValue }
  }
  private var evaluator: (@MainActor () -> Void)? {
    didSet { recordCheckpointMutation() }
  }

  /// Checkpoint-mutation tracker metadata, deliberately a plain stored property
  /// outside every observed field group: the `didSet` observers above bump it,
  /// so placing it inside an observed group would recurse, and it must stay
  /// monotonic — ``restoreCheckpoint(_:)`` never writes it back (the group
  /// assignments a restore performs bump it instead). Monotonicity is what
  /// makes "generation equal ⇒ state equal" hold across any window, which the
  /// delta-checkpoint machinery (and the F29 checkpoint store) relies on.
  private var checkpointMutationGeneration: UInt64 = 0

  package init(
    viewNodeID: ViewNodeID,
    identity: Identity
  ) {
    self.viewNodeID = viewNodeID
    self.identity = identity
    committed = ResolvedNode(
      identity: identity,
      kind: .view("EmptyView")
    )
    children = []
    // PersistentState() defaults stateSlots=[:], dependencies=.init(),
    // lifecycleState=.alive, registeredHandlers=.init(),
    // pendingChangeHandlerIDs=[]; ReuseState() defaults isDirty=true (freshness
    // flags false); FrameState() defaults the per-frame working set to its
    // empty/zero values.
    dependencyTracker = .init()
    // registrationCaptureDepth/runtimeRegistrationMutationGeneration/
    // evaluationDepth default to 0 and hasCommittedPresence/
    // suppressesStructuralLifecycle to false via EvaluationState()'s defaults.
    evaluator = nil
  }

  /// Bumps the checkpoint-mutation generation. Recording is structural: the
  /// `didSet` observers on every stored mutable property call this, so a field
  /// write cannot forget to record. The only remaining explicit calls cover
  /// mutations of the reference-typed `dependencyTracker`, which property
  /// observation cannot see (`recordStateReadDependency`,
  /// `recordEnvironmentRead`, `recordObservableRead`,
  /// `recordFocusComparisonTargets`).
  private func recordCheckpointMutation() {
    checkpointMutationGeneration &+= 1
  }

  /// The explicit recording seam for mutations of the reference-typed
  /// `dependencyTracker`: it is the one mutable member property observation
  /// cannot see (a `let` class), so its mutation entry points
  /// (`recordStateReadDependency`, `recordEnvironmentRead`,
  /// `recordObservableRead`, `recordFocusComparisonTargets`) call this by
  /// hand. Every other checkpoint-covered mutation records structurally via
  /// the stored-property `didSet` observers.
  private func recordDependencyTrackerMutation() {
    checkpointMutationGeneration &+= 1
  }

  package var currentCheckpointMutationGeneration: UInt64 {
    checkpointMutationGeneration
  }

  package convenience init(
    identity: Identity
  ) {
    self.init(
      viewNodeID: ViewNodeID(rawValue: 0),
      identity: identity
    )
  }

  package func prepareForFrame(
    _ frameID: UInt64
  ) {
    guard preparedFrameID != frameID else {
      return
    }
    wasPresentAtFrameStart = hasCommittedPresence
    wasVisitedThisFrame = false
    previousChildrenIdentities = children.map(\.identity)
    previousLifecycleMetadata = lifecycleMetadata
    currentBodyStateSlotCount = 0
    pendingChangeHandlerIDs.removeAll(keepingCapacity: true)
    nextChangeModifierOrdinal = 0
    nextNavigationDestinationModifierOrdinal = 0
    nextTaskModifierOrdinal = 0
    preparedFrameID = frameID
  }

  package func beginEvaluation(
    frameID: UInt64,
    invalidator: (any Invalidating)?,
    suppressesStructuralLifecycle: Bool = false
  ) {
    prepareForFrame(frameID)
    self.suppressesStructuralLifecycle = suppressesStructuralLifecycle
    if evaluationDepth == 0 {
      self.invalidator = invalidator
      if let host = ViewNodeContext.current, host !== self {
        evaluationHost = host
      }
      wasVisitedThisFrame = true
      visitedFrameID = frameID
      isDirty = false
      currentBodyStateSlotCount = 0
      nextChangeModifierOrdinal = 0
      nextNavigationDestinationModifierOrdinal = 0
      nextTaskModifierOrdinal = 0
      _ = dependencyTracker.reset()
    }
    evaluationDepth += 1
  }

  package func beginReuse(
    frameID: UInt64,
    invalidator: (any Invalidating)?
  ) {
    prepareForFrame(frameID)
    self.invalidator = invalidator
    // Re-bind to the host evaluating this reuse, exactly as `beginEvaluation`
    // does for a recompute. A subtree reused across a capture-host re-resolve
    // otherwise keeps a stale `evaluationHost` — possibly a retired node —
    // orphaning the island-invalidation walk that reaches capture-hosted
    // content only through this link.
    if let host = ViewNodeContext.current, host !== self {
      evaluationHost = host
    }
    wasVisitedThisFrame = true
    visitedFrameID = frameID
    isDirty = false
  }

  package func finishEvaluation(
    accessedStateSlots: Int
  ) -> Bool {
    bodyStateSlotCount = max(bodyStateSlotCount ?? 0, accessedStateSlots)
    evaluationDepth = max(0, evaluationDepth - 1)
    guard evaluationDepth == 0 else {
      return false
    }

    dependencies = dependencyTracker.reset()
    return true
  }

  package func hasStateSlot(
    ordinal: Int
  ) -> Bool {
    stateSlots[ordinal] != nil
  }

  package func stateSlot<Value>(
    ordinal: Int,
    seed: @autoclosure () -> Value
  ) -> Value {
    let readKey = StateSlotKey(owner: viewNodeID, ordinal: ordinal)
    if let reader = ViewNodeContext.current {
      // Reader-attributed: the dependency belongs to the node actually
      // evaluating this read (which may be a descendant consuming a projected
      // binding), not the slot owner. A genuine self-read records on self
      // (reader == self == owner), exactly as before.
      reader.recordStateReadDependency(readKey)
    } else {
      // No evaluating reader in scope (a read outside resolve): record on self.
      dependencyTracker.recordStateRead(readKey)
    }

    return primedStateSlot(ordinal: ordinal, seed: seed())
  }

  /// Slot access without read attribution. Runtime plumbing that must reach
  /// the storage without becoming a recorded reader uses this — the
  /// `@FocusState` location's storage resolution and its prime touch: a body
  /// that merely *projects* a binding hosts the slot but presents nothing
  /// derived from it, and attributing that touch as a read would put the
  /// owner in every runtime flip's invalidation set, re-broadening the
  /// reader-attributed cone to the owner's whole subtree.
  package func primedStateSlot<Value>(
    ordinal: Int,
    seed: @autoclosure () -> Value
  ) -> Value {
    var slot = stateSlots[ordinal] ?? .init()
    slot.initializeIfNeeded(with: seed())
    stateSlots[ordinal] = slot

    guard slot.stores(Value.self) else {
      let slotTypes = stateSlots.keys.sorted().map { index in
        "\(index):\(stateSlots[index]?.storedTypeDescription ?? "missing")"
      }.joined(separator: ", ")
      fatalError(
        "State slot type mismatch on node \(identity) ordinal \(ordinal). Expected \(Value.self), found \(slot.storedTypeDescription). Slots: [\(slotTypes)]"
      )
    }

    return slot.value(as: Value.self)
  }

  /// Records a state-read dependency on *this* node's tracker. Used by
  /// reader-attributed reads so the dependency lands on the evaluating reader
  /// rather than the slot owner (see ``ReaderAttributionConfiguration``).
  package func recordStateReadDependency(
    _ key: StateSlotKey
  ) {
    recordDependencyTrackerMutation()
    dependencyTracker.recordStateRead(key)
  }

  package func setStateSlot<Value>(
    ordinal: Int,
    value: Value,
    invalidationIdentity: Identity? = nil,
    certifiedInvalidationIdentities: Set<Identity>? = nil
  ) {
    var slot = stateSlots[ordinal] ?? .init()
    let didChange = slot.set(value)
    stateSlots[ordinal] = slot
    if didChange {
      let key = StateSlotKey(owner: viewNodeID, ordinal: ordinal)
      ownerGraph?.queueDirtyForStateChange(key)
      let invalidationIdentities = stateChangeInvalidationIdentities(
        for: key,
        explicit: invalidationIdentity,
        certified: certifiedInvalidationIdentities
      )
      InvalidationSourceTrace.note("state-write", invalidationIdentities)
      let animationRequest = AnimationContextStorage.currentRequest
      let batchID = AnimationContextStorage.currentBatchID
      if animationRequest != .inherit || batchID != nil,
        let animationAware = invalidator as? any AnimationAwareInvalidating
      {
        animationAware.requestInvalidation(
          of: invalidationIdentities,
          animation: animationRequest,
          batchID: batchID
        )
      } else {
        invalidator?.requestInvalidation(of: invalidationIdentities)
      }
    }
  }

  /// The identities to invalidate for a state-slot write: the genuine readers
  /// recorded for this slot, so a disjoint subtree (such as a sheet/palette
  /// background that only *projects* the binding) is spared — completing the
  /// read-side attribution in ``stateSlot(ordinal:seed:)``. Without this, the
  /// owner identity would be invalidated and `conflictsWithInvalidation` would
  /// block the whole background as an ancestor, defeating reader attribution on
  /// open. Falls back to the owner identity when no readers were recorded
  /// (deferred / conditional reads, or no owning graph) so a change is never
  /// dropped.
  ///
  /// `certified`, when provided, replaces reader attribution entirely: the
  /// caller certifies that these identities cover every subtree whose
  /// resolved output can differ because of this write, *beyond the owner's
  /// own re-evaluation* (which rides `queueDirtyForStateChange` regardless).
  /// This narrows a self-read presentation slot whose reading owner is a
  /// near-root container — reader attribution would conflict-deny the
  /// owner's whole descendant cone — down to the chrome the write actually
  /// changes (`TabView`'s stored strip-focus index). It applies only when
  /// every certified identity reaches live graph work at or below itself; a
  /// tree that never materialized them (a custom style that does not stamp
  /// the route identities) keeps the reader-attributed broad cone, because
  /// certified identities with no live subtree would deny no reuse while the
  /// queue boundary remapped them onto an ancestor.
  private func stateChangeInvalidationIdentities(
    for key: StateSlotKey,
    explicit: Identity?,
    certified: Set<Identity>? = nil
  ) -> Set<Identity> {
    let ownerIdentity = explicit ?? identity
    guard let ownerGraph else {
      return [ownerIdentity]
    }
    let readers = ownerGraph.stateDependentIdentities(for: key)
    if let certified, !certified.isEmpty,
      // Certification covers subtrees beyond the owner's own re-run. A
      // reader on any OTHER node needs its own invalidation, which the
      // certified set cannot promise to include — interior-hosting seams can
      // store the slot on an ancestor evaluator's node while the control's
      // body records the read on its own node — so foreign readers keep
      // reader attribution.
      readers.subtracting([identity]).isEmpty,
      ownerGraph.allIdentitiesReachLiveSubtrees(certified)
    {
      return certified
    }
    return readers.isEmpty ? [ownerIdentity] : readers
  }

  /// Stores a value in a state slot without triggering invalidation or
  /// dirtying the graph.  Used by ``ValueAnimationModifier`` to remember
  /// the previous watched value during resolve without causing a
  /// re-resolve cycle.
  package func setStateSlotSilently<Value>(
    ordinal: Int,
    value: Value
  ) {
    var slot = stateSlots[ordinal] ?? .init()
    _ = slot.set(value)
    stateSlots[ordinal] = slot
  }

  package func stateSlotStorage(
    ordinal: Int
  ) -> AnyStateSlot? {
    stateSlots[ordinal]
  }

  package func restoreStateSlot(
    ordinal: Int,
    slot: AnyStateSlot
  ) {
    stateSlots[ordinal] = slot
  }

  package func resetStateSlots() {
    stateSlots.removeAll(keepingCapacity: false)
  }

  package func markDirty() {
    let wasDirty = isDirty
    isDirty = true
    if !wasDirty {
      invalidateCachedSnapshotUpward()
    }
  }

  package func setEvaluator(
    _ evaluator: @escaping @MainActor () -> Void
  ) {
    self.evaluator = evaluator
  }

  package func evaluate() {
    evaluator?()
  }

  package var hasEvaluator: Bool {
    evaluator != nil
  }

  package var isAtOutermostEvaluationDepth: Bool {
    evaluationDepth == 1
  }

  /// Withdraws the committed subtree's runtime-ID stamp claim so the next
  /// apply takes the slow restamping path. Entity routing calls this when it
  /// adopts this node across identities: the committed value's positional
  /// stamp pairing is no longer verified against the node's next live
  /// children.
  package func withdrawCommittedStampClaim() {
    committed.markSubtreeRuntimeNodeIDsUnstamped()
  }

  package func recordEnvironmentRead(
    _ key: ObjectIdentifier
  ) {
    recordDependencyTrackerMutation()
    dependencyTracker.recordEnvironmentRead(key)
  }

  package func recordObservableRead(
    _ key: ObjectIdentifier
  ) {
    recordDependencyTrackerMutation()
    dependencyTracker.recordObservableRead(key)
  }

  package func recordFocusComparisonTargets(
    _ targets: Set<Identity>
  ) {
    recordDependencyTrackerMutation()
    dependencyTracker.recordFocusComparisonTargets(targets)
  }

  package func requestInvalidation() {
    InvalidationSourceTrace.note("node-request", [identity])
    ownerGraph?.queueDirty([identity])
    invalidator?.requestInvalidation(of: [identity])
  }

  /// Reader-attributed invalidation for a runtime-applied state-slot change
  /// (a `@FocusState` flip applied by focus-sync's binding re-derive). The
  /// invalidated set is the receiving `.focused()` registration identity
  /// (`registrationScope` — its re-resolve refreshes the registry's captured
  /// `isSelected`/`hasPendingRequest`, and the ancestor-chain conflict
  /// denial reaches the hosting node that re-runs it) plus the slot's
  /// recorded genuine value readers (a body that read the value recomputes).
  /// The owner's whole identity cone — which blanketed every sibling of the
  /// bound control — is used only as a fallback when neither exists, so a
  /// change is never dropped.
  package func invalidateStateSlotReadersForRuntimeChange(
    ordinal: Int,
    registrationScope: Identity?
  ) {
    let key = StateSlotKey(owner: viewNodeID, ordinal: ordinal)
    var invalidationIdentities =
      ownerGraph?.stateDependentIdentities(for: key) ?? []
    if let registrationScope {
      invalidationIdentities.insert(registrationScope)
    }
    if invalidationIdentities.isEmpty {
      invalidationIdentities = [identity]
    }
    InvalidationSourceTrace.note("runtime-state-flip", invalidationIdentities)
    ownerGraph?.queueDirty(invalidationIdentities)
    invalidator?.requestInvalidation(of: invalidationIdentities)
  }

  package func setLifecycleState(
    _ lifecycleState: NodeLifecycleState
  ) {
    self.lifecycleState = lifecycleState
  }

  package func claimChangeModifierOrdinal() -> Int {
    defer {
      nextChangeModifierOrdinal += 1
    }
    return nextChangeModifierOrdinal
  }

  package func claimNavigationDestinationModifierOrdinal() -> Int {
    defer {
      nextNavigationDestinationModifierOrdinal += 1
    }
    return nextNavigationDestinationModifierOrdinal
  }

  package func claimTaskModifierOrdinal() -> Int {
    defer {
      nextTaskModifierOrdinal += 1
    }
    return nextTaskModifierOrdinal
  }

  package func queueChangeHandler(
    _ handlerID: String
  ) {
    guard !pendingChangeHandlerIDs.contains(handlerID) else {
      return
    }
    pendingChangeHandlerIDs.append(handlerID)
  }

  package func apply(
    resolved: ResolvedNode,
    children: [ViewNode]
  ) {
    refreshChildResolvedMetadata(
      from: resolved.children,
      children: children
    )
    let resolved = resolvedWithRuntimeNodeIDs(
      resolved,
      children: children
    )
    // Reuse fast path: an unchanged reused subtree hands back exactly the nodes
    // already attached, in the same order (recordReusedSubtree resolves each child
    // via nodeForIdentity). The detach and re-parent loops below are then no-ops
    // and the identity Set is pure O(children) overhead, so refresh the committed
    // snapshot and bail. Structural changes (reorder/add/remove) fail the check and
    // take the full reconciliation path.
    if childrenReferToSameNodes(as: children) {
      committed = resolved
      isCommittedSnapshotFresh = true
      hasStaleIslandDescendant = false
      invalidateAncestorCachedSnapshots()
      return
    }

    let newChildrenByIdentity = Set(children.map(\.identity))
    for child in self.children
    where !newChildrenByIdentity.contains(child.identity) && child.parent === self {
      child.parent = nil
    }

    committed = resolved
    isCommittedSnapshotFresh = true
    hasStaleIslandDescendant = false
    self.children = children
    for child in children {
      guard child !== self else {
        continue
      }
      child.parent = self
    }
    invalidateAncestorCachedSnapshots()
  }

  package func applyRetainedSnapshot(
    _ snapshot: ResolvedNode
  ) {
    var snapshot = snapshot
    snapshot.viewNodeID = viewNodeID
    snapshot.recomputeSubtreeRuntimeNodeIDsStamped()
    committed = snapshot
    isCommittedSnapshotFresh = true
    invalidateAncestorCachedSnapshots()
  }

  private func refreshChildResolvedMetadata(
    from resolvedChildren: [ResolvedNode],
    children: [ViewNode]
  ) {
    guard resolvedChildren.count == children.count else {
      return
    }

    for (resolvedChild, child) in zip(resolvedChildren, children) {
      child.refreshResolvedMetadata(from: resolvedChild)
    }
  }

  package func refreshResolvedMetadata(
    from resolved: ResolvedNode
  ) {
    committed.structuralPath = resolved.structuralPath
    committed.structuralEdgeRole = resolved.structuralEdgeRole
    committed.entityIdentity = resolved.entityIdentity
    committed.entityStructuralPath = resolved.entityStructuralPath
    committed.declarationOwnerEdge = resolved.declarationOwnerEdge
    committed.typeDiscriminator = resolved.typeDiscriminator
  }

  private func childrenReferToSameNodes(
    as candidate: [ViewNode]
  ) -> Bool {
    guard candidate.count == children.count else {
      return false
    }
    for index in candidate.indices where candidate[index] !== children[index] {
      return false
    }
    return true
  }

  private func resolvedWithRuntimeNodeIDs(
    _ resolved: ResolvedNode,
    children: [ViewNode]
  ) -> ResolvedNode {
    // Fast path: a subtree value whose stamps are already complete and whose
    // root carries this node's ID was produced from committed snapshots
    // (retained reuse hands back `node.snapshot()`, child evaluations return
    // their freshly committed roots), so every descendant stamp is already
    // the one this walk would write.  Skipping the recursion keeps a fresh
    // ancestor's apply O(direct children) instead of O(subtree) struct
    // copies over large reused regions.  The flag is trustworthy because the
    // count-guard-unmet branch below withdraws it whenever child stamps were
    // spliced in unverified (Group splices, capture-host injections).  The
    // remaining seam where a stale interior could hide under a matching root
    // is the known divergent-resolvedIdentity capture-host orphaning bug
    // (reuse-host guard work tracks it); the debug assertion below trips
    // loudly if any such value reaches a skip.
    if resolved.subtreeRuntimeNodeIDsStamped, resolved.viewNodeID == viewNodeID {
      #if DEBUG
        assertResolvedStampsCoherent(resolved, children: children)
      #else
        // Release: run the same read-only oracle only on sampled frames when the
        // soundness probe is opted in. Off by default → a single Bool read.
        if SoundnessProbeConfiguration.isSampledFrame,
          let violation = resolvedStampsCoherenceViolation(resolved, children: children)
        {
          SoundnessProbeConfiguration.recordStampCoherenceViolation(violation)
        }
      #endif
      return resolved
    }
    var resolved = resolved
    resolved.viewNodeID = viewNodeID
    if resolved.children.count == children.count {
      let stampedChildren = zip(resolved.children, children).map { childResolved, childNode in
        // Transparent-chain fixed point: this node absorbed a node-less chain
        // level (`.frame` wrapper -> `.id` -> primitive), so the positional
        // pairing lands back on the absorber itself. The absorbed level's
        // value takes the absorber's stamp, but the values BELOW it belong to
        // the chain's interior nodes and arrived stamped by those nodes' own
        // applies. Recursing the self-pairing would clobber every deeper
        // stamp with the absorber's ID — the committed value tree would then
        // claim the interior head is the absorber, and teardown's value
        // descent could never reach the interior node again (it re-enters the
        // absorber and strands the head as a churn orphan).
        if childNode === self {
          var absorbed = childResolved
          absorbed.viewNodeID = viewNodeID
          absorbed.recomputeSubtreeRuntimeNodeIDsStamped()
          return absorbed
        }
        return childNode.resolvedWithRuntimeNodeIDs(
          childResolved,
          children: childNode.children
        )
      }
      resolved.setChildrenPreservingDerivedState(stampedChildren)
      resolved.recomputeSubtreeRuntimeNodeIDsStamped()
    } else {
      // Count guard unmet (Group splices, passthrough bodies, capture-host
      // injections like the toolbar reconcile): the walk could not pair this
      // value's children with this node's live children, so the child stamps
      // are unverified and may belong to other live nodes.  Claiming subtree
      // completeness here let a later apply fast-path over foreign stamps
      // (the gallery tab-switch stamp-coherence crash), so withdraw the
      // claim and leave this subtree to the slow restamping path.
      resolved.markSubtreeRuntimeNodeIDsUnstamped()
    }
    return resolved
  }

  /// Debug-only coherence check for the stamping fast path: every value
  /// stamp in the skipped subtree must equal the positionally paired live
  /// node's ID wherever the pairing is defined (count-aligned levels), i.e.
  /// exactly what the full walk would have written.
  private func assertResolvedStampsCoherent(
    _ resolved: ResolvedNode,
    children: [ViewNode]
  ) {
    #if DEBUG
      if let violation = resolvedStampsCoherenceViolation(resolved, children: children) {
        assertionFailure(violation)
      }
    #endif
  }

  /// Read-only stamp-coherence check shared by the DEBUG assertion and the
  /// release-sampled soundness probe (``SoundnessProbeConfiguration``). Returns
  /// a divergence description, or `nil` when the skipped subtree's stamps match
  /// what the full restamping walk would write. Tolerates count mismatch (Group
  /// splices / capture-host injections) by stopping descent — exactly like the
  /// full walk withdraws its completeness claim — so it never false-positives on
  /// an intentionally unverified seam.
  package func resolvedStampsCoherenceViolation(
    _ resolved: ResolvedNode,
    children: [ViewNode]
  ) -> String? {
    guard resolved.viewNodeID == viewNodeID else {
      return
        "stamp skip: value stamp \(String(describing: resolved.viewNodeID)) "
        + "diverges from live node \(viewNodeID) at \(identity)"
    }
    guard resolved.children.count == children.count else {
      return nil
    }
    for (childResolved, childNode) in zip(resolved.children, children) {
      // Mirror the stamping walk's transparent-chain fixed point: a
      // self-paired child value carries the absorber's stamp, and the values
      // below it belong to the chain's interior nodes — the full walk does
      // not restamp past the self-pairing, so the checker must not demand
      // absorber stamps there either.
      if childNode === self {
        if childResolved.viewNodeID != viewNodeID {
          return
            "stamp skip: absorbed chain value stamp "
            + "\(String(describing: childResolved.viewNodeID)) diverges from absorber "
            + "\(viewNodeID) at \(identity)"
        }
        continue
      }
      if let violation = childNode.resolvedStampsCoherenceViolation(
        childResolved,
        children: childNode.children
      ) {
        return violation
      }
    }
    return nil
  }

  /// The view value this node was last resolved with, kept to compare against
  /// the next frame's value via ``MemoValueComparator`` for memoized-body reuse.
  /// Populated only when ``MemoReuseConfiguration`` is enabled (or the sampled
  /// ``MemoSkipTrace`` diagnostics are observing this frame); `nil` otherwise,
  /// so it costs nothing when both features are off. Checkpointed so an aborted
  /// frame does not leave a stale value that would mis-compare on the next frame.
  package var memoViewValue: Any? {
    didSet { recordCheckpointMutation() }
  }

  /// Whether this node would pass the retained-reuse guards *except* for the
  /// dirty / invalidation-intersection veto — the conjuncts that make a memoized
  /// skip safe (present, snapshot-fresh, island-fresh, reuse support, equal
  /// environment, reuse-equivalent transaction). ANDed with view-value equality
  /// and a deps-clean check by the memo gate.
  package func canMemoReuse(
    environment: EnvironmentSnapshot,
    transaction: TransactionSnapshot
  ) -> Bool {
    wasPresentAtFrameStart
      && isCommittedSnapshotFresh
      && !hasStaleIslandDescendant
      && committed.supportsRetainedReuse
      && committed.environmentSnapshot == environment
      && committed.transactionSnapshot.isReuseEquivalent(to: transaction)
  }

  /// Whether the node recorded no `@State`/`@Observable`/`@Environment` reads
  /// when it was last resolved — the strictest memo-reuse subset whose output is
  /// a pure function of its view value and environment.
  ///
  /// This indexes only *explicitly attributed* reads. An `@Observable` model read
  /// directly (not via a `Bindable` projection) is tracked by
  /// `withObservationTracking`, not recorded here — so it can report `true` while
  /// still depending on observable state. That case is covered by the `!isDirty`
  /// conjunct the memo gate ANDs alongside this one (an observable mutation dirties
  /// the node before the next frame). Any future memo path MUST keep that `!isDirty`
  /// co-guard; this property alone is not a complete dependency oracle.
  package var hasNoRecordedDependencies: Bool {
    dependencies.stateSlotReads.isEmpty
      && dependencies.observableReads.isEmpty
      && dependencies.environmentReads.isEmpty
  }

  /// Whether the node's recorded dependencies are all *covered by the memo
  /// gate's other conjuncts* — i.e. it recorded no `@State` slot reads, no
  /// `@Observable` reads, and no `@Environment` read of an *uncovered* key.
  ///
  /// `@Environment` reads of keys carried by `environmentSnapshot` ARE allowed:
  /// the gate's `committed.environmentSnapshot == environment` conjunct (in
  /// ``canMemoReuse(environment:transaction:)``) already verifies the whole
  /// snapshot is unchanged, so those reads necessarily return the same value.
  /// This widens reuse to the layout containers (`VStack`/`HStack`/…) that read
  /// layout environment — exactly the boundaries where reusing a whole subtree
  /// pays.
  ///
  /// `uncoveredEnvironmentKeys` names the environment keys deliberately *excluded*
  /// from `environmentSnapshot` equality — the focus/press runtime side-fields
  /// (`focusedIdentity`/`pressedIdentity`), which change every focus move and
  /// would otherwise env-mismatch the whole tree. A read of one is NOT verified
  /// by the snapshot, so it disqualifies the node: focus/press correctness is
  /// enforced by the run loop's retained-reuse suppression scope, which the gate
  /// sits behind in the live path but which the one-shot renderer does not
  /// compute — so a focus reader must never be memo-reused on view-value +
  /// snapshot equality alone.
  ///
  /// `@State` slot reads and `@Observable` reads stay excluded outright: neither
  /// is covered by the environment snapshot. (`!isDirty` catches an observable
  /// mutation, but state-value equality is not yet checked — a further widening.)
  package func hasNoMemoUncoveredDependencies(
    uncoveredEnvironmentKeys: Set<ObjectIdentifier>
  ) -> Bool {
    dependencies.stateSlotReads.isEmpty
      && dependencies.observableReads.isEmpty
      && dependencies.environmentReads.isDisjoint(with: uncoveredEnvironmentKeys)
  }

  package func canReuse(
    frameID: UInt64,
    environment: EnvironmentSnapshot,
    transaction: TransactionSnapshot
  ) -> Bool {
    prepareForFrame(frameID)
    return wasPresentAtFrameStart
      && !wasVisitedThisFrame
      && !isDirty
      && isCommittedSnapshotFresh
      && !hasStaleIslandDescendant
      && committed.supportsRetainedReuse
      && committed.environmentSnapshot == environment
      // Compare resolve-time transaction *intent* (animation request + batch),
      // not the full snapshot: the per-frame `debugSignature` (the frame's cause
      // summary) otherwise changes every frame and defeats retained reuse for
      // subtrees disjoint from the invalidation. See `TransactionSnapshot.isReuseEquivalent`.
      && committed.transactionSnapshot.isReuseEquivalent(to: transaction)
  }

  /// Diagnostic mirror of ``canReuse(frameID:environment:transaction:)``:
  /// returns the first failing condition as a label, or `nil` if `canReuse`
  /// would succeed (so the caller can attribute the denial to invalidation
  /// intersection instead). For `env-mismatch` it records the specific differing
  /// environment keys into ``ReuseDenialTrace``. Used only when the trace is on.
  package func canReuseDenialReason(
    frameID: UInt64,
    environment: EnvironmentSnapshot,
    transaction: TransactionSnapshot
  ) -> String? {
    prepareForFrame(frameID)
    if !wasPresentAtFrameStart { return "not-present" }
    if wasVisitedThisFrame { return "visited" }
    if isDirty { return "dirty" }
    if !isCommittedSnapshotFresh { return "stale-snapshot" }
    if hasStaleIslandDescendant { return "stale-island-descendant" }
    if !committed.supportsRetainedReuse { return "no-retained-support" }
    if committed.environmentSnapshot != environment {
      recordEnvironmentSnapshotDiff(committed.environmentSnapshot, environment)
      return "env-mismatch"
    }
    if !committed.transactionSnapshot.isReuseEquivalent(to: transaction) {
      return "transaction"
    }
    return nil
  }

  private func recordEnvironmentSnapshotDiff(
    _ committed: EnvironmentSnapshot,
    _ current: EnvironmentSnapshot
  ) {
    guard ReuseDenialTrace.isEnabled else { return }
    if committed.debugSignature != current.debugSignature {
      ReuseDenialTrace.recordEnvironmentKeyDiff("debugSignature")
    }
    if committed.style != current.style {
      ReuseDenialTrace.recordEnvironmentKeyDiff("style")
    }
    let committedValues = committed.values
    let currentValues = current.values
    for key in Set(committedValues.keys).union(currentValues.keys)
    where committedValues[key] != currentValues[key] {
      ReuseDenialTrace.recordEnvironmentKeyDiff("val:\(key)")
    }
  }

  package var hasDirtyAncestor: Bool {
    var current = parent
    var visited: Set<ObjectIdentifier> = []

    while let node = current {
      let nodeID = ObjectIdentifier(node)
      guard visited.insert(nodeID).inserted else {
        return false
      }
      if node.isDirty {
        return true
      }
      current = node.parent
    }

    return false
  }

  package func beginRegistrationCapture() {
    if registrationCaptureDepth == 0 {
      registeredHandlers.reset()
      recordRuntimeRegistrationMutation()
    }
    registrationCaptureDepth += 1
  }

  package func endRegistrationCapture() {
    registrationCaptureDepth = max(0, registrationCaptureDepth - 1)
  }

  package func recordActionRegistration(
    identity: Identity,
    handler: @escaping LocalActionRegistry.Handler,
    followUpInvalidationIdentity: Identity?
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordAction(
      identity: identity,
      handler: handler,
      followUpInvalidationIdentity: followUpInvalidationIdentity
    )
  }

  package func recordActionRegistration(
    identity: Identity,
    handler: @escaping LocalActionRegistry.Handler,
    followUpInvalidationIdentity: Identity?,
    owner: RuntimeRegistrationOwnerKey
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordAction(
      identity: identity,
      handler: handler,
      followUpInvalidationIdentity: followUpInvalidationIdentity,
      owner: owner
    )
  }

  package func recordKeyHandlerRegistration(
    identity: Identity,
    handler: @escaping LocalKeyHandlerRegistry.Handler
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordKeyHandler(
      identity: identity,
      handler: handler
    )
  }

  package func recordKeyPressHandlerRegistration(
    identity: Identity,
    ordinal: UInt64,
    handler: @escaping LocalKeyHandlerRegistry.KeyPressHandler
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordKeyPressHandler(
      identity: identity,
      ordinal: ordinal,
      handler: handler
    )
  }

  package func recordPasteHandlerRegistration(
    identity: Identity,
    ordinal: UInt64,
    handler: @escaping LocalKeyHandlerRegistry.PasteHandler
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordPasteHandler(
      identity: identity,
      ordinal: ordinal,
      handler: handler
    )
  }

  package func recordTerminationHandlerRegistration(
    identity: Identity,
    handler: @escaping LocalTerminationRegistry.Handler
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordTerminationHandler(
      identity: identity,
      handler: handler
    )
  }

  package func recordPointerHandlerRegistration(
    routeID: RouteID,
    handler: @escaping LocalPointerHandlerRegistry.Handler
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordPointerHandler(
      routeID: routeID,
      handler: handler
    )
  }

  package func recordPointerHoverHandlerRegistration(
    routeID: RouteID,
    handler: @escaping LocalPointerHandlerRegistry.HoverHandler
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordPointerHoverHandler(
      routeID: routeID,
      handler: handler
    )
  }

  package func recordGestureRegistration(
    identity: Identity,
    recognizer: AnyGestureRecognizer
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordGesture(
      identity: identity,
      recognizer: recognizer
    )
  }

  package func gestureRegistration(
    for identity: Identity
  ) -> AnyGestureRecognizer? {
    registeredHandlers.gesture.recognizers[identity]
  }

  package func recordGestureStateBinding(
    identity: Identity,
    binding: AnyGestureStateBinding
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordGestureStateBinding(
      identity: identity,
      binding: binding
    )
  }

  // The focus-family recorders stamp `ownerIdentity` with the recording
  // node's identity: focus snapshots can be published at identities DETACHED
  // from every structural root (an exact `.id(_:)`), and the commit's
  // `removeSubtrees` needs the owner to clear them before the scoped restore
  // re-appends this node's snapshots — identity-prefix matching alone leaves
  // detached entries stacking one copy per scoped commit (the F04
  // registration-publication oracle's live=3 vs rebuilt=1 finding).

  package func recordDefaultFocus(
    _ registration: DefaultFocusScopeRegistrationSnapshot
  ) {
    var registration = registration
    registration.ownerIdentity = registration.ownerIdentity ?? identity
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordDefaultFocus(registration)
  }

  package func recordDefaultFocus(
    _ registration: DefaultFocusCandidateRegistrationSnapshot
  ) {
    var registration = registration
    registration.ownerIdentity = registration.ownerIdentity ?? identity
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordDefaultFocus(registration)
  }

  package func recordFocusBindingRegistration(
    _ registration: FocusBindingRegistrationSnapshot
  ) {
    var registration = registration
    registration.ownerIdentity = registration.ownerIdentity ?? identity
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordFocusBinding(registration)
  }

  package func recordFocusedValuesRegistration(
    _ registration: FocusedValuesRegistrationSnapshot
  ) {
    var registration = registration
    registration.ownerIdentity = registration.ownerIdentity ?? identity
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordFocusedValues(registration)
  }

  package func recordScrollPositionRegistration(
    _ registration: ScrollPositionRegistrationSnapshot
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordScrollPosition(registration)
  }

  package func recordLifecycleAppearRegistration(
    _ registration: LifecycleHandlerRegistration
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordLifecycleAppear(
      registration
    )
  }

  package func recordLifecycleDisappearRegistration(
    _ registration: LifecycleHandlerRegistration
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordLifecycleDisappear(
      registration
    )
  }

  package func recordLifecycleChangeRegistration(
    _ registration: LifecycleHandlerRegistration
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordLifecycleChange(
      registration
    )
  }

  package func recordTaskRegistration(
    identity: Identity,
    registration: TaskRegistration
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordTask(
      identity: identity,
      registration: registration
    )
  }

  package func recordPreferenceObservationRegistration(
    _ registration: PreferenceObservationRegistrationSnapshot
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordPreferenceObservation(registration)
  }

  package func recordCommandRegistration(
    _ registration: CommandRegistrySnapshot
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordCommand(registration)
  }

  package func recordDropDestinationRegistration(
    _ registration: DropDestinationRegistrySnapshot
  ) {
    recordRuntimeRegistrationMutation()
    registeredHandlers.recordDropDestination(registration)
  }

  private func recordRuntimeRegistrationMutation() {
    runtimeRegistrationMutationGeneration &+= 1
  }

  package func runtimeRegistrationFingerprintEntry()
    -> RuntimeRegistrationNodeFingerprint?
  {
    guard registeredHandlers.hasRuntimeRegistrations else {
      return nil
    }
    return RuntimeRegistrationNodeFingerprint(
      viewNodeID: viewNodeID,
      subtreeRoot: identity,
      resolvedIdentity: resolvedIdentity,
      mutationGeneration: runtimeRegistrationMutationGeneration
    )
  }

  package func restoreRuntimeRegistrations(
    into registrations: RuntimeRegistrationSet
  ) {
    var traversedNodes: Set<ObjectIdentifier> = []
    restoreRuntimeRegistrations(
      into: registrations,
      traversedNodes: &traversedNodes
    )
  }

  /// Adopts a departing node's recorded runtime registrations. Called when an
  /// absorbed shadowed interior mint is reclaimed while this node's committed
  /// value carries the interior's output (the chain-collapse stamp fixed
  /// point): registration bookkeeping must follow the value, or publication
  /// rebuilds drop the interior's handlers and its committed tasks never
  /// start ("no task registration at commit").
  package func adoptRuntimeRegistrations(from departing: ViewNode) {
    guard departing.registeredHandlers.hasRuntimeRegistrations else {
      return
    }
    recordRuntimeRegistrationMutation()
    registeredHandlers.absorbAdopted(departing.registeredHandlers)
  }

  package func restoreOwnRuntimeRegistrations(
    into registrations: RuntimeRegistrationSet
  ) {
    // Handler-less nodes (the bulk of a reused layout/text subtree) restore
    // nothing, so skip the per-registry `restore(from:)` work — which allocates
    // a Set + a filtered pointer-handler copy and touches ~18 registries — when
    // there is provably nothing to restore. `hasRuntimeRegistrations` is the
    // exact disjunction of the families `restore(from:)` reads, so this is a
    // behavior-preserving no-op skip (mirrors the guard at
    // `runtimeRegistrationFingerprintEntry()`).
    guard registeredHandlers.hasRuntimeRegistrations else {
      return
    }
    // `visitedFrameID` is the restore's recency. Two live nodes can hold
    // captured hover registrations for the same owner-agnostic route when an
    // evaluation-topology change re-captures the handler on a different node:
    // the abandoned node keeps a shadowed copy but is never re-visited, so the
    // hover registry uses this stamp to let the fresher capture evict it.
    registrations.restore(from: registeredHandlers, recency: visitedFrameID)
  }

  package func restoreOwnEffectRegistrations(
    into registrations: RuntimeRegistrationSet
  ) {
    // Effect-less nodes (the bulk of the live tree) restore nothing; each
    // effect registry's `restore` is already a no-op for empty handlers, so
    // this skip is behavior-preserving (mirrors the guard in
    // `restoreOwnRuntimeRegistrations`).
    guard registeredHandlers.hasEffectRegistrations else {
      return
    }
    registrations.restoreEffectRegistrations(from: registeredHandlers)
  }

  private func restoreRuntimeRegistrations(
    into registrations: RuntimeRegistrationSet,
    traversedNodes: inout Set<ObjectIdentifier>
  ) {
    let nodeID = ObjectIdentifier(self)
    guard traversedNodes.insert(nodeID).inserted else {
      return
    }

    restoreOwnRuntimeRegistrations(
      into: registrations
    )

    for child in children {
      child.restoreRuntimeRegistrations(
        into: registrations,
        traversedNodes: &traversedNodes
      )
    }
  }

  package func rebuildRuntimeRegistrations(
    into registrations: RuntimeRegistrationSet
  ) {
    registrations.resetAll()

    restoreRuntimeRegistrations(
      into: registrations
    )
  }

  /// Whether this node has a cached resolved snapshot available for reuse.
  package var hasCachedSnapshot: Bool {
    isCommittedSnapshotFresh
  }

  package func snapshot() -> ResolvedNode {
    if isCommittedSnapshotFresh {
      return committed
    }
    var entered: Set<ObjectIdentifier> = []
    return snapshotRebuilding(entered: &entered)
  }

  private func snapshotRebuilding(
    entered: inout Set<ObjectIdentifier>
  ) -> ResolvedNode {
    if isCommittedSnapshotFresh {
      return committed
    }
    // Rebuild the whole-subtree snapshot by recursively pulling each
    // child ViewNode's current snapshot.  The `didSet` on
    // `ResolvedNode.children` then recomputes preferenceValues,
    // subtreeNodeCount, and supportsRetainedReuse from the new children.
    // `apply` tolerates a node re-appearing inside its own `children`
    // (an entity-routed wrapper collapse leaves the slot node aliased into
    // its own resolved subtree; the parent pointer is never wired), so the
    // rebuild tracks entered nodes and hands back the committed value on
    // re-entry instead of recursing forever.
    guard entered.insert(ObjectIdentifier(self)).inserted else {
      return committed
    }
    var rebuilt = committed
    rebuilt.children = children.map { $0.snapshotRebuilding(entered: &entered) }
    committed = rebuilt
    isCommittedSnapshotFresh = true
    return committed
  }

  private func invalidateCachedSnapshotUpward() {
    invalidateCachedSnapshots(startingAt: self)
  }

  private func invalidateAncestorCachedSnapshots() {
    if let parent {
      invalidateCachedSnapshots(startingAt: parent)
    } else if let evaluationHost {
      invalidateCachedSnapshots(startingAt: evaluationHost, crossedIslandSeam: true)
    }
  }

  /// Walks ancestors propagating "a descendant changed" with split signals.
  ///
  /// Along live `parent` links the walk clears `isCommittedSnapshotFresh`,
  /// whose `snapshot()` rebuild reconstructs the committed mirror from live
  /// children. The moment the walk crosses an island seam (a node reachable
  /// only via `evaluationHost` — capture-hosted content has no parent link to
  /// its host), it switches to setting `hasStaleIslandDescendant` instead and
  /// never touches freshness again: a host's live children do NOT mirror its
  /// committed value across the seam, so clearing its freshness would make
  /// `snapshot()`'s rebuild graft a structurally truncated tree (live
  /// children only) and launder it as fresh — erasing the island interior
  /// from the frame. `hasStaleIslandDescendant` is consumed only by
  /// `canReuse`, denying retained reuse until the host's body re-resolve
  /// re-captures the island by value; `apply` clears it.
  private func invalidateCachedSnapshots(
    startingAt start: ViewNode,
    crossedIslandSeam: Bool = false
  ) {
    var current: ViewNode? = start
    var crossedIslandSeam = crossedIslandSeam
    var visited: Set<ObjectIdentifier> = []

    while let node = current {
      let nodeID = ObjectIdentifier(node)
      guard visited.insert(nodeID).inserted else {
        return
      }
      if crossedIslandSeam {
        node.hasStaleIslandDescendant = true
      } else {
        node.isCommittedSnapshotFresh = false
      }
      if let parent = node.parent {
        current = parent
      } else {
        current = node.evaluationHost
        crossedIslandSeam = crossedIslandSeam || current != nil
      }
    }
  }

  package var participatesInStructuralLifecycle: Bool {
    guard !suppressesStructuralLifecycle else {
      return false
    }
    var ancestor = parent
    while let current = ancestor {
      if current.committed.indexedChildSource != nil {
        return false
      }
      ancestor = current.parent
    }
    return true
  }

  package func isDescendant(
    of ancestor: ViewNode
  ) -> Bool {
    var current = parent
    var visited: Set<ObjectIdentifier> = []

    while let node = current {
      let nodeID = ObjectIdentifier(node)
      guard visited.insert(nodeID).inserted else {
        return false
      }
      if node === ancestor {
        return true
      }
      current = node.parent
    }

    return false
  }

  package func isPrepared(
    for frameID: UInt64
  ) -> Bool {
    preparedFrameID == frameID
  }

  package func visitedThisFrame(
    _ frameID: UInt64
  ) -> Bool {
    prepareForFrame(frameID)
    return visitedFrameID == frameID
  }

  /// The visited-frame stamp used as a registration's recency: the hover
  /// registry uses it to let a re-captured handler evict a never-re-visited
  /// node's stale, shadowed copy of the same owner-agnostic route. See
  /// `restoreOwnRuntimeRegistrations`.
  package var runtimeRegistrationRecency: UInt64 {
    visitedFrameID
  }

  package func setCommittedPresence(
    _ hasCommittedPresence: Bool
  ) {
    self.hasCommittedPresence = hasCommittedPresence
  }

  package func setSuppressesStructuralLifecycle(
    _ suppressesStructuralLifecycle: Bool
  ) {
    self.suppressesStructuralLifecycle = suppressesStructuralLifecycle
  }

  /// Declares one focus-presentation-inert child slot on this control's node —
  /// see ``EvaluationState/focusPresentationInertSlotIdentities`` for the
  /// promise this records. Idempotent; the equal-value guard keeps repeated
  /// per-resolve declarations from bumping the checkpoint generation.
  package func declareFocusPresentationInertSlot(_ slotIdentity: Identity) {
    guard
      !evaluationState.focusPresentationInertSlotIdentities.contains(slotIdentity)
    else {
      return
    }
    evaluationState.focusPresentationInertSlotIdentities.insert(slotIdentity)
  }

  /// Declares one focus-presentation value-verified child slot on this
  /// control's node — see
  /// ``EvaluationState/focusPresentationValueVerifiedSlotIdentities`` for the
  /// promise this records. Idempotent; the equal-value guard keeps repeated
  /// per-resolve declarations from bumping the checkpoint generation.
  package func declareFocusPresentationValueVerifiedSlot(_ slotIdentity: Identity) {
    guard
      !evaluationState.focusPresentationValueVerifiedSlotIdentities.contains(slotIdentity)
    else {
      return
    }
    evaluationState.focusPresentationValueVerifiedSlotIdentities.insert(slotIdentity)
  }
}

extension ViewNode {
  package struct Checkpoint {
    package var viewNodeID: ViewNodeID
    // The four upward references mirror the live properties' `weak` storage.
    // This matters once images persist in the F29 ``NodeCheckpointImageStore``:
    // a strong `ownerGraph`/`invalidator` here would form a permanent retain
    // cycle (graph → store → image → graph / run loop), where the live graph's
    // ownership shape has strong edges pointing downward only. Weak images
    // also restore what the live weak property would actually hold — a
    // referent that died since capture reads nil either way.
    package weak var invalidator: (any Invalidating)?
    package weak var ownerGraph: ViewGraph?
    package weak var parent: ViewNode?
    package weak var evaluationHost: ViewNode?
    package var committed: ResolvedNode
    package var reuseState: ReuseState
    package var children: [ViewNode]
    package var persistentState: PersistentState
    package var frameState: FrameState
    package var dependencyTracker: DependencyTracker.Checkpoint
    package var evaluationState: EvaluationState
    package var evaluator: (@MainActor () -> Void)?
    package var memoViewValue: Any?
    /// Capture metadata, not restored state: the node's checkpoint-mutation
    /// generation at the moment this image was taken. ``restoreCheckpoint(_:)``
    /// never writes it back — live generations are monotonic (every restore
    /// bumps them via the stored-property observers), which is what keeps
    /// "generation equal ⇒ state equal" sound across restore cycles.
    package var checkpointMutationGeneration: UInt64
  }

  package func makeCheckpoint() -> Checkpoint {
    Checkpoint(
      viewNodeID: viewNodeID,
      invalidator: invalidator,
      ownerGraph: ownerGraph,
      parent: parent,
      evaluationHost: evaluationHost,
      committed: committed,
      reuseState: reuseState,
      children: children,
      persistentState: persistentState,
      frameState: frameState,
      dependencyTracker: dependencyTracker.makeCheckpoint(),
      evaluationState: evaluationState,
      evaluator: evaluator,
      memoViewValue: memoViewValue,
      checkpointMutationGeneration: checkpointMutationGeneration
    )
  }

  package func restoreCheckpoint(_ checkpoint: Checkpoint) {
    precondition(
      checkpoint.viewNodeID == viewNodeID,
      "Cannot restore checkpoint for \(checkpoint.viewNodeID) onto \(viewNodeID)."
    )
    invalidator = checkpoint.invalidator
    ownerGraph = checkpoint.ownerGraph
    parent = checkpoint.parent
    evaluationHost = checkpoint.evaluationHost
    committed = checkpoint.committed
    reuseState = checkpoint.reuseState
    children = checkpoint.children
    persistentState = checkpoint.persistentState
    frameState = checkpoint.frameState
    dependencyTracker.restoreCheckpoint(checkpoint.dependencyTracker)
    evaluationState = checkpoint.evaluationState
    evaluator = checkpoint.evaluator
    memoViewValue = checkpoint.memoViewValue
  }
}

extension ViewNode {
  package func debugTotalStateSnapshot() -> DebugTotalStateSnapshot {
    DebugTotalStateSnapshot(
      viewNodeID: viewNodeID,
      invalidatorInstalled: invalidator != nil,
      ownerGraphInstalled: ownerGraph != nil,
      parentIdentity: parent?.identity,
      committed: committed,
      isCommittedSnapshotFresh: isCommittedSnapshotFresh,
      hasStaleIslandDescendant: hasStaleIslandDescendant,
      children: children.map(\.identity),
      stateSlots: stateSlots.map { ordinal, slot in
        DebugTotalStateSnapshot.StateSlotSnapshot(
          ordinal: ordinal,
          storedTypeDescription: slot.storedTypeDescription
        )
      }.sorted { lhs, rhs in lhs.ordinal < rhs.ordinal },
      dependencies: dependencies,
      lifecycleState: lifecycleState,
      registeredHandlers: registeredHandlers.debugTotalStateSnapshot(),
      isDirty: isDirty,
      wasPresentAtFrameStart: wasPresentAtFrameStart,
      wasVisitedThisFrame: wasVisitedThisFrame,
      previousChildrenIdentities: previousChildrenIdentities,
      previousLifecycleMetadata: previousLifecycleMetadata,
      bodyStateSlotCount: bodyStateSlotCount,
      currentBodyStateSlotCount: currentBodyStateSlotCount,
      pendingChangeHandlerIDs: pendingChangeHandlerIDs,
      dependencyTracker: dependencyTracker.currentDependencies,
      registrationCaptureDepth: registrationCaptureDepth,
      runtimeRegistrationMutationGeneration: runtimeRegistrationMutationGeneration,
      evaluationDepth: evaluationDepth,
      hasCommittedPresence: hasCommittedPresence,
      suppressesStructuralLifecycle: suppressesStructuralLifecycle,
      focusPresentationInertSlotIdentities: focusPresentationInertSlotIdentities,
      focusPresentationValueVerifiedSlotIdentities: focusPresentationValueVerifiedSlotIdentities,
      nextChangeModifierOrdinal: nextChangeModifierOrdinal,
      nextNavigationDestinationModifierOrdinal: nextNavigationDestinationModifierOrdinal,
      // nextTaskModifierOrdinal was checkpointed but historically omitted from
      // this debug mirror; grouping it into FrameState surfaced the gap and the
      // totality guard now requires it here.
      nextTaskModifierOrdinal: nextTaskModifierOrdinal,
      preparedFrameID: preparedFrameID,
      visitedFrameID: visitedFrameID,
      entityDisplacedOccupantFrameID: entityDisplacedOccupantFrameID,
      evaluatorInstalled: evaluator != nil
    )
  }
}
