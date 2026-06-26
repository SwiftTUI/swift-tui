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
  }

  /// Internal node bookkeeping that persists across frames (unlike
  /// ``FrameState``): the evaluation/registration nesting depths, the monotonic
  /// mutation-generation counters that gate registration and checkpoint reuse,
  /// and the two lifecycle flags (has-this-node-ever-committed and
  /// suppress-structural-lifecycle). None of it is render state.
  package struct EvaluationState {
    package var registrationCaptureDepth: Int = 0
    package var runtimeRegistrationMutationGeneration: UInt64 = 0
    package var checkpointMutationGeneration: UInt64 = 0
    package var evaluationDepth: Int = 0
    package var hasCommittedPresence: Bool = false
    package var suppressesStructuralLifecycle: Bool = false
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
}
