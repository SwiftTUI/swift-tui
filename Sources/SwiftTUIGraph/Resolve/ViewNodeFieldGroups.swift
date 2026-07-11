// Cohesive value-typed field groups for ViewNode's reconciliation state.
//
// Each group clusters a set of stored properties that share a purpose and a
// checkpoint lifetime. ViewNode stores one instance of each group and exposes
// every original field as a computed accessor that forwards into its group, so
// the reconciliation body reads and writes the fields by their original names
// while makeCheckpoint/restoreCheckpoint move whole groups by value.
//
// Grouping collapses the four hand-maintained mirrors of each field (the stored
// declaration, ViewNode.Checkpoint, makeCheckpoint, restoreCheckpoint) into a
// single whole-struct copy: a field added to a group is checkpointed and
// restored automatically, so it cannot silently fall out of rollback.
// ViewGraphCheckpointTotalityTests keeps the group fields and the flat debug
// snapshot in lockstep.
//
// This mirrors the ViewGraph decomposition in ViewGraphFieldGroups.swift and
// continues the consolidation begun in Item 6 (which folded ~14 scattered
// render mirrors into the single `committed: ResolvedNode`). Decomposition is
// staged one group per change; FrameState is the first.

extension ViewNode {
  /// Per-frame bookkeeping that `prepareForFrame` resets at the start of each
  /// frame and the reconciler updates as it visits the node: presence/visit
  /// flags, the previous frame's children identities and lifecycle metadata, the
  /// body state-slot counts, and the prepared/visited frame stamps. None of it
  /// is committed render state — it is the working set for one frame's pass.
  package struct FrameState {
    package var wasPresentAtFrameStart: Bool = false
    package var wasVisitedThisFrame: Bool = false
    package var previousChildrenIdentities: [Identity] = []
    package var previousLifecycleMetadata: LifecycleMetadata = .init()
    package var bodyStateSlotCount: Int? = nil
    package var currentBodyStateSlotCount: Int = 0
    package var preparedFrameID: UInt64 = 0
    package var visitedFrameID: UInt64 = 0
    // Modifier-ordinal minting for the current body pass; reset alongside the
    // counts above in prepareForFrame/beginEvaluation, so same frame-local
    // lifecycle.
    package var nextChangeModifierOrdinal: Int = 0
    package var nextNavigationDestinationModifierOrdinal: Int = 0
    package var nextTaskModifierOrdinal: Int = 0
    package var nextValueAnimationModifierOrdinal: Int = 0
    // The frame in which this node was freshly minted after `nodeForIdentity`
    // evicted a different-entity occupant from its identity slot. Frame-scoped
    // by comparison against `preparedFrameID` (the `visitedFrameID` pattern)
    // because the mint happens *before* the fresh node's first
    // `prepareForFrame`, which would wipe a plain Bool.
    package var entityDisplacedOccupantFrameID: UInt64 = 0
  }

  /// Internal node bookkeeping that persists across frames (unlike
  /// ``FrameState``): the evaluation/registration nesting depths, the monotonic
  /// registration mutation-generation counter, and the two lifecycle flags
  /// (has-this-node-ever-committed and suppress-structural-lifecycle). None of
  /// it is render state.
  ///
  /// The checkpoint mutation generation deliberately lives *outside* this group
  /// (as a plain stored property on ``ViewNode``): it is tracker metadata about
  /// mutations, not state — restores bump it rather than write it back, keeping
  /// it monotonic so generation equality always implies state equality.
  package struct EvaluationState {
    package var registrationCaptureDepth: Int = 0
    package var runtimeRegistrationMutationGeneration: UInt64 = 0
    package var evaluationDepth: Int = 0
    package var hasCommittedPresence: Bool = false
    package var suppressesStructuralLifecycle: Bool = false
    /// Child slot identities this control declared focus-presentation-inert:
    /// a promise that the values the control hands each slot cannot vary with
    /// the control's own focus/press presentation (a `TabView`'s content slot
    /// derives from the authored tabs and the selection only). The run loop's
    /// focus/press retained-reuse suppression skips descendant matching below
    /// a declared slot — but only when the scope member is the declaring
    /// control itself: a cascade from any other ancestor may change the
    /// authored inputs the promise is conditioned on, so it keeps full-cone
    /// suppression. Insert-only per resolve; departs with the node.
    package var focusPresentationInertSlotIdentities: Set<Identity> = []
    /// Child slot identities this control declared focus-presentation
    /// *value-verified*: unlike an inert slot, the values the control hands
    /// the slot MAY vary with its own focus/press presentation (a `TabView`'s
    /// strip items carry an `isFocused` flag) — but they carry every
    /// focus-derived input, so an `Equatable`-equal value proves the subtree's
    /// output is unchanged. Descendants below one are exempt from the
    /// focus-member dirty-queue walk and from the *memoized* (value-verified)
    /// reuse denial only; value-blind Layer-A reuse stays denied, so a slot
    /// whose value flipped fails the memo compare and recomputes fresh. The
    /// member==declarer pairing applies exactly as for inert slots.
    /// Insert-only per resolve; departs with the node.
    package var focusPresentationValueVerifiedSlotIdentities: Set<Identity> = []
  }

  /// Reuse/freshness gating consumed by the reconciler's skip fast-paths:
  /// whether the node needs re-evaluation, whether its committed-children
  /// snapshot still reflects the live descendants, and whether an island-seam
  /// descendant was dirtied (which denies retained reuse).
  package struct ReuseState {
    package var isDirty: Bool = true
    package var isCommittedSnapshotFresh: Bool = false
    package var hasStaleIslandDescendant: Bool = false
  }

  /// The node's retained per-node state that survives across frames: its `@State`
  /// slots, recorded dependency edges, lifecycle phase, registered handlers, and
  /// the pending change-handler IDs awaiting dispatch. These are small per-node
  /// collections; like the analogous `ViewGraph` field groups they are reached
  /// through plain get/set forwarders, so an in-place mutation copies only the
  /// small per-node collection.
  ///
  /// `@MainActor`-isolated because `NodeHandlers` carries main-actor handler
  /// closures (matching the enclosing `ViewNode`); the other groups stay
  /// nonisolated.
  @MainActor
  package struct PersistentState {
    package var stateSlots: [Int: AnyStateSlot] = [:]
    package var dependencies: DependencySet = .init()
    package var lifecycleState: NodeLifecycleState = .alive
    package var registeredHandlers: NodeHandlers = .init()
    package var pendingChangeHandlerIDs: [String] = []
  }
}
